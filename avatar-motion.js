.pragma library

// Avatar keyframes from Rakazo's packages/ui-web/src/styles.css (ef63e35),
// sampled by BotAvatar.qml on a timer instead of CSS animations.
// Eye frames:  [percent, translateX, translateY, scaleX, scaleY]
// Body frames: [percent, translateX, translateY, rotateDeg, scaleX, scaleY]
// Idle and robot eye offsets are CSS px (robot px are relative to a 38 px
// avatar); organic offsets are units of the 120-unit viewBox.

var eyesIdle = [
  [[0, 0, 0, 1, 1], [32, 0, 0, 1, 1], [35, 0, 0, 1, 0.08], [38, 0, 0, 1, 1], [48, 3, -0.5, 1, 1],
   [62, 3, -0.5, 1, 1], [70, -2.5, 0.5, 1, 1], [84, -2.5, 0.5, 1, 1], [89, 0, 0, 1, 0.12],
   [91, 0, 0, 1, 1], [100, 0, 0, 1, 1]],
  [[0, 0, 0, 1, 1], [25, 0, 0, 1, 1], [32, -3, -1, 1, 1], [48, -3, -1, 1, 1], [54, 0, 0, 1, 0.08],
   [56, 0, 0, 1, 1], [59, 0, 0, 1, 0.08], [61, 0, 0, 1, 1], [68, 2.5, 0.5, 1, 1], [82, 2.5, 0.5, 1, 1],
   [100, 0, 0, 1, 1]],
  [[0, 0, 0, 1, 1], [28, 0, 0, 1, 1], [36, 0.5, -1.8, 1, 1.05], [52, 0.5, -1.8, 1, 1.05],
   [58, 0, 0, 1, 0.08], [60, 0, 0, 1, 1], [68, 3, 0, 1, 1], [85, 3, 0, 1, 1], [92, 0, 0, 1, 0.1],
   [94, 0, 0, 1, 1], [100, 0, 0, 1, 1]],
  [[0, 0, 0, 1, 1], [24, 0, 0, 1, 1], [30, -2.5, 1.2, 1, 0.95], [46, -2.5, 1.2, 1, 0.95],
   [52, 0, 0, 1, 0.08], [54, 0, 0, 1, 1], [62, 2.8, -1, 1, 1], [78, 2.8, -1, 1, 1], [86, 0, 0, 1, 0.08],
   [88, 0, 0, 1, 1], [100, 0, 0, 1, 1]]
]

// [seconds, delaySeconds] for the organic idle eye patterns.
var eyesIdleTiming = [[5.8, 0], [6.4, -1.7], [5.2, -3.1], [6.8, -2.3]]

var robotEyesWorking = [
  [0, -4, 0, 0.92, 0.95], [25, 0, -2, 1.08, 1.08], [50, 4, 0, 0.92, 0.95], [75, 0, 2, 1, 0.9],
  [100, -4, 0, 0.92, 0.95]
]

// CSS percentages of the 120-unit viewBox, already multiplied by 1.2.
var organicEyesWorking = [
  [[0, -10.8, 1.2, 1, 0.94], [18, 10.8, -2.4, 1, 1.04], [34, 0, -9.6, 1.08, 1.08], [48, 0, 0, 1.12, 0.82],
   [51, 0, 0, 1.05, 0.08], [54, 0, 0, 1.12, 0.9], [72, -6, 8.4, 1, 0.9], [86, 8.4, 3.6, 1, 1],
   [100, -10.8, 1.2, 1, 0.94]],
  [[0, 0, -9.6, 1.06, 1.06], [16, 9.6, 2.4, 1, 1], [31, 0, 9.6, 1, 0.9], [46, -9.6, 2.4, 1, 1],
   [61, 0, 0, 0.88, 1.1], [76, 0, -8.4, 1, 1.08], [88, 0, 7.2, 1.08, 0.86], [100, 0, -9.6, 1.06, 1.06]],
  [[0, 0, 0, 0.9, 1.08], [20, 0, 0, 1.14, 0.84], [24, 0, 0, 1.08, 0.08], [28, 0, 0, 1.02, 1.02],
   [45, -10.8, -3.6, 1, 0.94], [62, 10.8, 2.4, 1, 1.05], [80, 0, -9.6, 1.06, 1.06], [100, 0, 0, 0.9, 1.08]],
  [[0, 0, 8.4, 1, 0.9], [14, 0, -10.8, 1, 1.08], [30, 9.6, -2.4, 1, 1], [47, -9.6, 3.6, 1, 0.94],
   [63, 0, 0, 1.12, 0.82], [78, 0, -8.4, 0.9, 1.08], [91, 0, 6, 1.06, 0.9], [100, 0, 8.4, 1, 0.9]]
]

var organicEyesWorkingTiming = [[6.6, 0], [7.2, -1.4], [6.1, -3.2], [7.8, -2.1]]

var body = {
  idle: [[0, 0, 1.2, 0, 1.012, 0.988], [50, 0, -1.4, 0, 0.988, 1.012], [100, 0, 1.2, 0, 1.012, 0.988]],
  float: [[0, 0, 2, 0, 1.02, 1], [50, 0, -3, 0, 0.98, 1], [100, 0, 2, 0, 1.02, 1]],
  stretch: [[0, 0, 2, 0, 1.04, 0.96], [50, 0, -3, 0, 0.96, 1.05], [100, 0, 2, 0, 1.04, 0.96]],
  sway: [[0, -1, 0, -3, 1, 1], [50, 1, 0, 3, 1, 1], [100, -1, 0, -3, 1, 1]],
  turn: [[0, 0, 0, -4, 0.98, 0.98], [50, 0, 0, 4, 1.04, 1.04], [100, 0, 0, -4, 0.98, 0.98]],
  squash: [[0, 0, 0, 0, 1.04, 0.96], [50, 0, 0, 0, 0.96, 1.04], [100, 0, 0, 0, 1.04, 0.96]],
  pulse: [[0, 0, 0, 0, 0.96, 0.96], [45, 0, 0, 0, 1.06, 1.06], [100, 0, 0, 0, 0.96, 0.96]],
  ring: [[0, 0, 0, -4, 1, 1], [35, 0, 0, 5, 1, 1], [65, 0, 0, -3, 1, 1], [100, 0, 0, -4, 1, 1]]
}

var bodySeconds = { idle: 5.6, float: 1.8, stretch: 1.35, sway: 1.6, turn: 2.4, squash: 1.35, pulse: 1.1, ring: 1.35 }

// Position in a looping animation, 0..100, honoring a negative CSS delay.
function progress(nowMs, seconds, delaySeconds) {
  var span = Math.max(1, seconds * 1000)
  var elapsed = nowMs - (delaySeconds || 0) * 1000
  return ((elapsed % span) + span) % span / span * 100
}

// Values at `percent`, eased between neighbouring frames like ease-in-out.
function sample(frames, percent) {
  if (!frames || frames.length === 0)
    return []
  if (percent <= frames[0][0])
    return frames[0]
  for (var i = 1; i < frames.length; i++) {
    var to = frames[i]
    if (percent <= to[0]) {
      var from = frames[i - 1]
      var span = to[0] - from[0]
      var u = span > 0 ? (percent - from[0]) / span : 1
      u = u * u * (3 - 2 * u)
      var out = [percent]
      for (var k = 1; k < to.length; k++)
        out.push(from[k] + (to[k] - from[k]) * u)
      return out
    }
  }
  return frames[frames.length - 1]
}
