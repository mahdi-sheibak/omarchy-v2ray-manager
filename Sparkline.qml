import QtQuick
import qs.Commons

// Latency / metric sparkline.
// Draws a thin line through numeric samples (oldest first).
// Nulls/undefined draw as gaps. Uses dim color so it never shouts.
Canvas {
  id: root
  property var values: []
  property color lineColor: Color.foreground
  property real minSpan: 10          // floor for y-scaling (avoid jitter amplification)
  property int sparkW: 34
  property int sparkH: 14
  property bool symmetrical: false  // if true, scale 0..max around a center line

  width: sparkW
  height: sparkH
  antialiasing: true
  visible: values.length >= 2

  onValuesChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    var v = values
    if (!Array.isArray(v) || v.length < 2) return

    var s = v.filter(function(x) { return x !== null && x !== undefined })
    if (s.length < 2) return

    var min = Math.min.apply(null, s)
    var max = Math.max.apply(null, s)
    var span = max - min
    if (span < root.minSpan) span = root.minSpan
    if (span <= 0) span = 1

    var pad = 2
    var n = v.length
    var step = (width - pad * 2) / (n - 1)

    ctx.strokeStyle = root.lineColor
    ctx.lineWidth = 1
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.beginPath()

    var started = false
    for (var i = 0; i < n; i++) {
      var val = v[i]
      if (val === null || val === undefined) { started = false; continue }
      var x = pad + i * step
      var frac = (val - min) / span
      frac = Math.max(0, Math.min(1, frac))
      var y = height - pad - frac * (height - pad * 2)
      if (!started) { ctx.moveTo(x, y); started = true }
      else ctx.lineTo(x, y)
    }
    ctx.stroke()
  }

  Component.onCompleted: requestPaint()
}
