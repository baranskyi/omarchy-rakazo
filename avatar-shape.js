.pragma library

// Port of Rakazo's avatar geometry so bar faces match the app exactly:
// identitySeed/organicPath follow packages/core/src/avatar-shape.ts and
// adjustColor follows packages/ui-web/src/bot-avatar.tsx (Rakazo @ ef63e35).
// tests/test_avatar_shape.qml compares the output with the TypeScript original.

var _templates = null

function identitySeed(identity) {
  var text = String(identity === undefined || identity === null ? "" : identity)
  var hash = 0
  for (var i = 0; i < text.length; i++) {
    hash = (hash << 5) - hash + text.charCodeAt(i)
    hash |= 0
  }
  return Math.abs(hash)
}

function ring(count, radiusAt) {
  var points = []
  for (var i = 0; i < count; i++) {
    var angle = (i / count) * Math.PI * 2
    points.push(radiusAt(angle))
  }
  return points
}

function templates() {
  if (_templates)
    return _templates
  _templates = [
    [[-43, 22], [-51, 16], [-53, 6], [-49, -4], [-40, -12], [-30, -13], [-27, -24], [-18, -34],
     [-6, -36], [4, -32], [12, -42], [25, -45], [37, -38], [43, -27], [42, -17], [51, -11],
     [56, 0], [54, 12], [46, 20], [30, 24], [0, 25], [-29, 25]],
    [[0, -52], [12, -35], [28, -17], [39, 2], [42, 21], [34, 38], [19, 49], [0, 52], [-19, 49],
     [-34, 38], [-42, 21], [-39, 2], [-28, -17], [-12, -35]],
    [[-42, -23], [-27, -40], [-7, -46], [14, -40], [33, -27], [46, -8], [46, 14], [35, 34],
     [14, 46], [-8, 46], [-29, 38], [-43, 21], [-48, 0]],
    ring(40, function(angle) {
      var radius = 44 + Math.cos(angle * 5) * 5
      return [Math.cos(angle) * radius, Math.sin(angle) * radius]
    }),
    ring(36, function(angle) {
      var radius = 43 + Math.cos(angle * 6) * 7
      return [Math.cos(angle) * radius, Math.sin(angle) * radius]
    }),
    ring(32, function(angle) {
      var x = Math.cos(angle)
      var y = Math.sin(angle)
      return [Math.sign(x) * Math.sqrt(Math.abs(x)) * 46, Math.sign(y) * Math.sqrt(Math.abs(y)) * 43]
    }),
    [[0, 48], [-14, 36], [-32, 20], [-45, 0], [-43, -20], [-29, -36], [-10, -39], [0, -27],
     [10, -39], [29, -36], [43, -20], [45, 0], [32, 20], [14, 36]],
    [[-48, 35], [-38, 22], [-34, -8], [-27, -31], [-12, -44], [0, -48], [12, -44], [27, -31],
     [34, -8], [38, 22], [48, 35], [26, 42], [0, 44], [-26, 42]],
    [[-45, -19], [-28, -38], [-4, -46], [22, -41], [42, -25], [49, -2], [42, 23], [22, 42],
     [-4, 47], [-29, 38], [-46, 18], [-50, 0]],
    [[-50, 0], [-45, -20], [-30, -38], [0, -48], [30, -38], [45, -20], [50, 0], [35, 10],
     [18, 12], [16, 38], [0, 46], [-16, 38], [-18, 12], [-35, 10]]
  ]
  return _templates
}

function round2(value) {
  return Math.round(value * 100) / 100
}

// SVG path in a -60..60 viewBox, identical to organicAvatarPath(seed, phaseOffset).
function organicPath(seed, phaseOffset) {
  var offset = phaseOffset === undefined ? 0 : phaseOffset
  var phase = ((seed % 360) * Math.PI) / 180 + offset
  var family = seed % 10
  var all = templates()
  var base = all[family] || all[5]
  var xScale = 1 + Math.sin(phase) * 0.035
  var yScale = 1 + Math.cos(phase) * 0.025
  var shear = Math.sin(phase * 1.7) * 0.025
  var points = []
  for (var i = 0; i < base.length; i++)
    points.push({ x: base[i][0] * xScale + base[i][1] * shear, y: base[i][1] * yScale })
  var passes = family >= 3 && family <= 5 ? 1 : 2
  for (var pass = 0; pass < passes; pass++) {
    var smoothed = []
    for (var j = 0; j < points.length; j++) {
      var point = points[j]
      var next = points[(j + 1) % points.length]
      smoothed.push({ x: point.x * 0.75 + next.x * 0.25, y: point.y * 0.75 + next.y * 0.25 })
      smoothed.push({ x: point.x * 0.25 + next.x * 0.75, y: point.y * 0.25 + next.y * 0.75 })
    }
    points = smoothed
  }
  var count = points.length
  var first = points[0]
  var path = "M" + round2(first.x) + " " + round2(first.y)
  for (var k = 0; k < count; k++) {
    var before = points[(k - 1 + count) % count]
    var current = points[k]
    var after1 = points[(k + 1) % count]
    var after2 = points[(k + 2) % count]
    path += "C" + round2(current.x + (after1.x - before.x) / 6) + " " + round2(current.y + (after1.y - before.y) / 6)
      + " " + round2(after1.x - (after2.x - current.x) / 6) + " " + round2(after1.y - (after2.y - current.y) / 6)
      + " " + round2(after1.x) + " " + round2(after1.y)
  }
  return path + "Z"
}

// Working body motion per shape family, from styles.css.
function workingMotion(seed) {
  var family = seed % 10
  if (family === 0) return "float"
  if (family === 1) return "stretch"
  if (family === 2 || family === 8) return "sway"
  if (family === 3 || family === 4) return "turn"
  if (family === 6) return "pulse"
  if (family === 7) return "ring"
  return "squash"
}

function adjustColor(hex, percent) {
  var clean = String(hex || "").replace(/^#/, "")
  if (clean.length !== 6 && clean.length !== 3)
    return hex
  var full = clean
  if (clean.length === 3)
    full = clean.charAt(0) + clean.charAt(0) + clean.charAt(1) + clean.charAt(1) + clean.charAt(2) + clean.charAt(2)
  var num = parseInt(full, 16)
  if (isNaN(num))
    return hex
  var delta = Math.round((255 * percent) / 100)
  var r = Math.min(255, Math.max(0, (num >> 16) + delta))
  var g = Math.min(255, Math.max(0, ((num >> 8) & 0xff) + delta))
  var b = Math.min(255, Math.max(0, (num & 0xff) + delta))
  return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)
}
