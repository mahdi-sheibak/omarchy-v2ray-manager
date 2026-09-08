import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var settings: ({})
  property bool installed: false
  property bool running: false
  property string mode: "proxy"
  property var active: null
  property var profiles: []
  property var pings: ({})
  property var pingHistory: ({})   // id -> [ms|null, ...] sparkline data
  property string pingTarget: ""
  property string exitIp: ""
  property var geo: null           // {cc, flag, country, city} when running
  property string actionStatus: ""
  property string lastError: ""
  property string backend: "sing-box"
  property bool xrayAvailable: false
  // Group filter: "" shows all profiles, otherwise filters to that group
  property string selectedGroup: ""
  // Subscription metadata keyed by group name: {url, updated_at, added}
  property var subscriptions: ({})
  property int refreshIntervalSec: 30
  // Auto-refetch subscriptions every N minutes (0 = disabled)
  property int subscriptionRefetchMin: 360
  // Auto-reconnect on consecutive health-check failures
  property bool autoReconnect: true

  readonly property bool busy: whichProcess.running || statusProcess.running || actionProcess.running || pingProcess.running || healthCheckProcess.running || qrProcess.running || _queueRunning
  readonly property string cli: "omarchy-v2ray"

  // Read a single value from this widget's inline shell.json entry, with
  // a fallback for missing/null values.
  function setting(key, fallback) {
    var v = settings ? settings[key] : undefined
    return (v === undefined || v === null) ? fallback : v
  }

  // Wire manifest-declared settings to live properties.
  onSettingsChanged: {
    var r = parseInt(setting("refreshIntervalSec", 30), 10)
    if (isFinite(r) && r >= 5) refreshIntervalSec = r
    var sub = parseInt(setting("subscriptionRefetchMin", 360), 10)
    if (isFinite(sub) && sub >= 0) subscriptionRefetchMin = sub
    var ar = setting("autoReconnect", true)
    if (typeof ar === "boolean") autoReconnect = ar
    else if (typeof ar === "string") autoReconnect = ar === "true"
  }

  // Kill-timer guards: pkexec can hang ~120s with no dialog when no polkit
  // agent is running (known pitfall on this box). Without this, one hung
  // call leaves `busy` true forever and every control goes dead.
  // One timer per process — a shared timer breaks when two overlap.
  property bool _timedOut: false
  Timer {
    id: wdStatus
    interval: 15000
    onTriggered: root._timeoutKill(statusProcess, 15, "status")
  }
  Timer {
    id: wdAction
    interval: 45000
    onTriggered: root._timeoutKill(actionProcess, 45, "action")
  }
  Timer {
    id: wdPing
    interval: 90000
    onTriggered: root._timeoutKill(pingProcess, 90, "ping")
  }

  function _timeoutKill(p, secs, kind) {
    if (!p || !p.running) return
    p.kill()
    if (kind !== "status") {
      _timedOut = true
      lastError = "Command timed out after " + secs + "s — is the polkit agent running?"
      actionStatus = ""
      pingTarget = ""
      _actionQueue = []
      _queueRunning = false
    }
  }

  // Distinct group names, kept in sync from applyStatus() so the Repeater
  // always reflects the current set (readonly var bindings on reassigned
  // arrays can fail to re-trigger in QuickShell).
  property var groups: []

  // Profiles visible under the current group filter
  readonly property var visibleProfiles: {
    if (selectedGroup === "") return profiles
    var out = []
    for (var i = 0; i < profiles.length; i++) {
      if (String(profiles[i].group || "") === selectedGroup) out.push(profiles[i])
    }
    return out
  }

  Component.onCompleted: {
    whichProcess.command = ["which", cli]
    whichProcess.running = true
  }

  // If refresh() is called while a status poll is already in flight, retry
  // as soon as it finishes instead of waiting for the next 30s tick.
  property bool _refreshPending: false
  function refresh() {
    if (!installed) return
    if (statusProcess.running) { _refreshPending = true; return }
    statusProcess.command = [cli, "status"]
    statusProcess.running = true
  }

  function selectedId() {
    if (active && active.id) return String(active.id)
    if (profiles.length > 0) return String(profiles[0].id)
    return ""
  }

  function connectProfile(id) {
    var target = id || selectedId()
    if (target === "") {
      lastError = "No profiles yet. Paste a share link below."
      return
    }
    act(["connect", target])
  }

  // "Fastest" pseudo-profile: CLI pings candidates and connects to the best.
  // Respects the group filter via --group. Tracked so the row can show a
  // spinner and so the queue can route it through the right process slot.
  property bool connectingFastest: false
  function connectFastest() {
    if (profiles.length === 0) {
      lastError = "No profiles yet. Paste a share link below."
      return
    }
    var args = ["connect", "best"]
    if (selectedGroup !== "") args.push("--group", selectedGroup)
    connectingFastest = true
    enqueue(args, "Finding fastest profile…")
  }

  function setGroupFilter(name) {
    selectedGroup = String(name || "")
  }

  // Create a group from the current ungrouped profiles, or delete an
  // existing group (un-grouping its members).  Routed through the action
  // queue so the next status poll reflects the new state in order.
  function createGroup(name) {
    var n = String(name || "").trim()
    if (n === "") { lastError = "Group name cannot be empty"; return }
    enqueue(["group", "create", n], "Creating group…")
  }

  function deleteGroup(name) {
    var n = String(name || "").trim()
    if (n === "") return
    enqueue(["group", "delete", n], "Deleting group…")
  }

  function addSubscription(url, name) {
    var u = String(url || "").trim()
    if (u === "") { lastError = "Subscription URL cannot be empty"; return }
    var cmd = ["subscription", "add", u]
    if (name) cmd.push("--group", name)
    enqueue(cmd, "Adding subscription…")
  }

  function updateSubscription(name) {
    var n = String(name || "").trim()
    if (n === "") return
    enqueue(["subscription", "update", n], "Refetching…")
  }

  function removeSubscription(name) {
    var n = String(name || "").trim()
    if (n === "") return
    enqueue(["subscription", "remove", n], "Removing subscription…")
  }

  function refetchAllSubscriptions() {
    // Immediate background refetch (not queued) — used by the manual button
    if (root._refetching || subRefetchProcess.running) return
    root._refetching = true
    subRefetchProcess.command = [cli, "subscription", "refetch-all"]
    subRefetchProcess.running = true
  }

  function disconnect() { act(["disconnect"]) }

  function toggle() {
    if (running) disconnect()
    else connectProfile("")
  }

  function setMode(m) {
    if (m === mode && !running) return
    act(["mode", m])
  }

  // Sequential action queue. Fixes the setBackend race: previously
  // disconnect() -> act(backend) -> callLater(connect) all fired while a
  // single shared actionProcess was still busy, so act() silently no-oped
  // and the user ended up disconnected on the old backend.
  property var _actionQueue: []
  property bool _queueRunning: false

  function enqueue(args, label) {
    _actionQueue.push({ args: args, label: label || "" })
    _drainQueue()
  }

  function _drainQueue() {
    if (_queueRunning || _actionQueue.length === 0) return
    var job = _actionQueue.shift()
    _queueRunning = true
    lastError = ""
    actionStatus = job.label !== "" ? job.label : "Working…"
    actionProcess.command = [cli].concat(job.args)
    actionProcess.running = true
  }

  function setBackend(b) {
    if (b === backend) return
    if (running) {
      // disconnect -> switch -> reconnect, strictly in order
      enqueue(["disconnect"], "Switching backend…")
      enqueue(["backend", b], "Switching backend…")
      enqueue(["connect"], "Reconnecting…")
    } else {
      enqueue(["backend", b])
    }
  }

  function removeProfile(id) {
    // Disconnect first if removing the active profile, otherwise the bar
    // keeps showing connected on a now-deleted profile (bug #4).
    if (active && String(active.id) === String(id || "")) {
      enqueue(["disconnect"], "Disconnecting…")
      enqueue(["remove", id])
    } else {
      enqueue(["remove", id])
    }
  }

  function importLinks(text) {
    var t = String(text || "").trim()
    if (t === "") return
    lastError = ""
    // Land new profiles in the currently selected group (if any).
    // Routed through the action queue so the result handler updates
    // state in order — previously this ran outside the queue, and after
    // a successful import the list only updated on the next 30s status
    // poll, making it look like the selected group was ignored.
    var cmd = ["import", t]
    if (selectedGroup !== "") { cmd.push("--group", selectedGroup) }
    enqueue(cmd, "Importing…")
  }

  function pingProfile(id) {
    if (pingProcess.running) return
    // When called from "Test all" button with no arg, respect the group filter
    var target = id || (selectedGroup !== "" ? ("group:" + selectedGroup) : "all")
    lastError = ""
    actionStatus = "Testing…"
    pingTarget = target
    pingProcess.command = [cli, "ping", target]
    pingProcess.running = true
  }

  function pingResult(id) {
    var r = pings[String(id)]
    return r && typeof r === "object" ? r : null
  }

  function act(args) {
    // All actions flow through the sequential queue so nothing is ever
    // silently dropped while another action is in flight.
    enqueue(args)
  }

  function applyStatus(text) {
    var d
    try { d = JSON.parse(String(text || "")) } catch (e) { return }
    installed = true
    running = d.running === true
    mode = String(d.mode || "proxy")
    backend = String(d.backend || "sing-box")
    xrayAvailable = d.xray_installed === true
    active = d.active || null
    var newProfiles = Array.isArray(d.profiles) ? d.profiles : []
    profiles = newProfiles
    // Use the groups list the CLI computes (persisted + profile tags) so
    // empty groups still appear.  A readonly binding on `profiles` can
    // fail to re-trigger in QuickShell, so set it explicitly here.
    groups = Array.isArray(d.groups) ? d.groups : []
    subscriptions = (d.subscription_groups && typeof d.subscription_groups === "object") ? d.subscription_groups : ({})
    pings = d.pings && typeof d.pings === "object" ? d.pings : {}
    pingHistory = d.ping_history && typeof d.ping_history === "object" ? d.ping_history : {}
    exitIp = String(d.exit_ip || "")
    geo = d.geo && d.geo.cc ? d.geo : null
    // Preserve the action result message ("Imported 1 profile", "Connected
    // · …" etc.) — only clear a stale "Working…" / status-only placeholder.
    // The message is meant to linger a couple of seconds so the user sees
    // the outcome of their action, not get swallowed by the next status poll.
    if (actionStatus === "Working…" || actionStatus === "") actionStatus = ""
  }

  function applyActionResult(text, stderrText, code) {
    _queueRunning = false
    connectingFastest = false
    busyHandled()
    if (_timedOut) {
      // Watchdog killed this process and already showed a timeout error;
      // don't let the dead process's empty stdout overwrite it.
      _timedOut = false
      refresh()
      return
    }
    var d = null
    try { d = JSON.parse(String(text || "")) } catch (e) {}
    if (!d || d.ok !== true) {
      var msg = d && d.error ? String(d.error) : (stderrText || "command failed")
      lastError = String(msg).replace(/\x1b\[[0-9;]*m/g, "").trim()
      actionStatus = ""
      _actionQueue = []   // a failed step invalidates the rest of the chain
      refresh()
      return
    }
    lastError = ""
    if (d.added !== undefined) {
      var n = d.added.length
      if (n > 0) {
        actionStatus = "Imported " + n + " profile" + (n > 1 ? "s" : "")
      } else if (d.duplicates && d.duplicates.length > 0) {
        var dup = d.duplicates[0]
        var extra = d.duplicates.length > 1
          ? " (+" + (d.duplicates.length - 1) + " more)" : ""
        actionStatus = "Already saved · " + dup.name
          + (dup.group ? " · group " + dup.group : "") + extra
      } else if (d.invalid && d.invalid.length > 0) {
        actionStatus = "Could not parse link"
      } else {
        actionStatus = "Nothing new to import"
      }
    } else if (d.connected !== undefined) {
      root.actionStatus = "Connected · " + d.connected
      if (d.verified === false) {
        root.lastError = "Tunnel is up but no traffic flows — this profile looks down. Test with 󰓅 or pick another."
      }
    } else if (d.disconnected !== undefined) {
      actionStatus = "Disconnected"
    } else if (d.mode !== undefined) {
      actionStatus = "Mode: " + d.mode
    } else if (d.removed !== undefined) {
      actionStatus = "Profile removed"
    } else if (d.subscription_added !== undefined) {
      var na = d.added ? d.added.length : 0
      actionStatus = "Subscription · " + d.subscription_added + " · " + na + " configs"
    } else if (d.subscription_updated !== undefined) {
      actionStatus = "Refetched · " + d.subscription_updated + " · " + (d.added || 0) + " configs"
    } else if (d.subscription_removed !== undefined) {
      actionStatus = "Removed subscription · " + d.subscription_removed
    } else {
      actionStatus = ""
    }
    refresh()
    _drainQueue()
  }

  function busyHandled() {}

  Timer {
    interval: Math.max(5, root.refreshIntervalSec) * 1000
    repeat: true
    running: root.installed
    onTriggered: root.refresh()
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refresh()
      else root.lastError = "omarchy-v2ray CLI not found in PATH"
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onRunningChanged: (running) ? wdStatus.restart() : wdStatus.stop()
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(statusStdout.text)
      else {
        // Surface failures instead of silently keeping stale data
        if (!root.installed) root.lastError = "status check failed"
        else root.lastError = "status check failed (exit " + exitCode + ") — showing last known state"
      }
      // A refresh() was requested while this poll was in flight — fire now
      if (root._refreshPending) { root._refreshPending = false; root.refresh() }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onRunningChanged: (running) ? wdAction.restart() : wdAction.stop()
    onExited: function(exitCode) {
      root.applyActionResult(actionStdout.text, actionStderr.text, exitCode)
    }
  }

  Process {
    id: pingProcess
    running: false
    command: []
    stdout: StdioCollector { id: pingStdout; waitForEnd: true }
    stderr: StdioCollector { id: pingStderr; waitForEnd: true }
    onRunningChanged: (running) ? wdPing.restart() : wdPing.stop()
    onExited: function(exitCode) {
      root.pingTarget = ""
      var d = null
      try { d = JSON.parse(String(pingStdout.text || "")) } catch (e) {}
      if (!d || d.ok !== true || !d.results) {
        root.actionStatus = ""
        root.lastError = String(pingStderr.text || "ping failed").replace(/\x1b\[[0-9;]*m/g, "").trim()
        return
      }
      var merged = {}
      for (var k in root.pings) merged[k] = root.pings[k]
      var okCount = 0
      var failCount = 0
      for (var k2 in d.results) {
        merged[k2] = d.results[k2]
        if (d.results[k2].ms !== null && d.results[k2].ms !== undefined) okCount++
        else failCount++
      }
      root.pings = merged
      root.lastError = ""
      root.actionStatus = failCount > 0
        ? ("Tested: " + okCount + " ok, " + failCount + " unreachable")
        : ("Tested: " + okCount + " ok")
      // The CLI reorders profiles by latency after a full/group test.
      // Reload status so the panel reflects the new order immediately
      // instead of waiting for the next 30 s poll.
      root.refresh()
    }
  }

  // ── Auto-reconnect health check ────────────────────────────────────────
  // True end-to-end probe via ipify through the tunnel.  The old local-TCP
  // probe (`/dev/tcp/127.0.0.1/2080`) falsely passed when the upstream server
  // was dead, because sing-box/xray keep the inbound port open regardless.
  // This curl call takes 2-5 s; the 60 s interval keeps it tolerable.
  property bool _hcActive: false        // prevents overlapping checks
  property int _consecutiveFails: 0     // 2 consecutive fails → auto-reconnect

  Timer {
    id: healthCheckTimer
    interval: 60000                     // every 60 s
    repeat: true
    running: root.installed && root.running && root.autoReconnect
    // Reset probe state whenever we drop out of connected
    onRunningChanged: if (!running) { root._hcActive = false; root._consecutiveFails = 0 }
    onTriggered: {
      if (!root.autoReconnect) return
      if (_hcActive || actionProcess.running || pingProcess.running) return
      _hcActive = true
      healthCheckProcess.command = [cli, "status"]
      healthCheckProcess.running = true
    }
  }

  Process {
    id: healthCheckProcess
    running: false
    command: []
    stdout: StdioCollector { id: hcStdout; waitForEnd: true }
    onExited: function(exitCode) {
      _hcActive = false
      // If CLI status itself fails, treat as failure.
      if (exitCode !== 0 || !hcStdout.text) {
        _consecutiveFails++
        if (root.autoReconnect && _consecutiveFails >= 2 && !actionProcess.running) {
          var pid = active ? String(active.id) : selectedId()
          lastError = "Connection lost — reconnecting…"
          actionStatus = ""
          enqueue(["disconnect"], "Health check failed — reconnecting…")
          if (pid) enqueue(["connect", pid], "Reconnecting…")
        }
        return
      }
      // The key check: does the status report a live exit IP?
      // If `running` is true in the CLI but `exit_ip` is empty the
      // upstream tunnel has silently died (the CLI still sees the systemd
      // unit as "active" but no traffic can flow).
      var exitIpOk = false
      try {
        var d = JSON.parse(hcStdout.text)
        exitIpOk = d.running === true && String(d.exit_ip || "") !== ""
      } catch (e) {}
      if (exitIpOk) {
        _consecutiveFails = 0
      } else {
        _consecutiveFails++
        if (root.autoReconnect && _consecutiveFails >= 2 && !actionProcess.running) {
          var pid2 = active ? String(active.id) : selectedId()
          lastError = "Tunnel unresponsive — reconnecting…"
          actionStatus = ""
          enqueue(["disconnect"], "Tunnel unresponsive — reconnecting…")
          if (pid2) enqueue(["connect", pid2], "Reconnecting…")
        }
      }
    }
  }

  // ── QR Code ────────────────────────────────────────────────────────────
  property string qrImagePath: ""
  property string qrProfileId: ""

  // ── Auto-refetch subscriptions ───────────────────────────────────────
  // Runs `subscription refetch-all` on a background timer, completely
  // independent of the action queue so it never blocks user actions.
  property bool _refetching: false

  Timer {
    id: subRefetchTimer
    interval: Math.max(1, root.subscriptionRefetchMin) * 60000
    repeat: true
    running: root.installed && root.subscriptionRefetchMin > 0
    onTriggered: {
      if (root._refetching || root.actionProcess.running || root.pingProcess.running) return
      root._refetching = true
      subRefetchProcess.command = [cli, "subscription", "refetch-all"]
      subRefetchProcess.running = true
    }
  }

  Process {
    id: subRefetchProcess
    running: false
    command: []
    stdout: StdioCollector { id: subRefetchStdout; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root._refetching = false
      if (exitCode !== 0) return
      // Just reload state so the profile list and subscription timestamps update
      root.refresh()
    }
  }

  function showQR(profileId) {
    qrProfileId = profileId
    qrImagePath = ""
    qrProcess.command = ["omarchy-v2ray", "qr", profileId]
    qrProcess.running = true
  }

  function hideQR() {
    qrProfileId = ""
    qrImagePath = ""
  }

  Process {
    id: qrProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) {
        qrImagePath = String(qrStdout.text).trim()
      }
    }
    stdout: StdioCollector { id: qrStdout; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  // Sparkline: resolve the last N latencies for a profile ID.
  // Returns an array of numbers (ms) and nulls (failed), oldest first.
  function sparklineData(profileId) {
    var h = pingHistory[String(profileId)]
    if (!h || !Array.isArray(h)) return []
    return h
  }
}
