// Draw a correct Apple MacBook Air keyboard (US/ANSI layout) as an SVG for the Dictate video.
//
// Two facts the first pass got wrong, both verified against Apple's real layout:
//   1. The bottom row is: fn, control, option, command, SPACE, command, option.
//      The space bar is flanked by the two Command keys. The Option keys sit OUTSIDE them.
//      The right Option is the last key of the row, just before the arrow cluster.
//   2. The arrow keys are an inverted T: up on top, then left / down / right below it.
//
// The app listens for the RIGHT Option key, so that is the one that gets highlighted.
import Foundation

let W = 1620.0
let H = 430.0
let unit = 95.0
let keyH = 62.0
let gap = 6.0
let bodyPad = 26.0

// Row y positions: function, number, qwerty, asdf, bottom.
// The up arrow lives in the ASDF row band, directly above the down arrow.
let rowY: [Double] = [26, 94, 162, 230, 298]

let functionRow: [(String, Double)] = [
    ("esc", 1.4), ("F1", 1.0), ("F2", 1.0), ("F3", 1.0), ("F4", 1.0), ("F5", 1.0), ("F6", 1.0),
    ("F7", 1.0), ("F8", 1.0), ("F9", 1.0), ("F10", 1.0), ("F11", 1.0), ("F12", 1.0),
    ("", 1.0),
]

let numberRow: [(String, Double)] = [
    ("`", 1.0), ("1", 1.0), ("2", 1.0), ("3", 1.0), ("4", 1.0), ("5", 1.0), ("6", 1.0),
    ("7", 1.0), ("8", 1.0), ("9", 1.0), ("0", 1.0), ("-", 1.0), ("=", 1.0),
    ("delete", 1.5),
]

let qwertyRow: [(String, Double)] = [
    ("tab", 1.5), ("Q", 1.0), ("W", 1.0), ("E", 1.0), ("R", 1.0), ("T", 1.0), ("Y", 1.0),
    ("U", 1.0), ("I", 1.0), ("O", 1.0), ("P", 1.0), ("[", 1.0), ("]", 1.0), ("\\", 1.5),
]

// The ASDF row is sized so it ends exactly where the up arrow starts (13.5u).
// That keeps the up arrow from colliding with the return key.
let asdfRow: [(String, Double)] = [
    ("caps lock", 1.5), ("A", 1.0), ("S", 1.0), ("D", 1.0), ("F", 1.0), ("G", 1.0),
    ("H", 1.0), ("J", 1.0), ("K", 1.0), ("L", 1.0), (";", 1.0), ("'", 0.8), ("return", 1.2),
]

// Bottom row, left to right. The space bar sits BETWEEN the two Command keys.
// id: fn, ctrl, optL, cmdL, space, cmdR, optR
let bottomRow: [(String, Double, String)] = [
    ("fn", 1.0, "fn"),
    ("control", 1.0, "ctrl"),
    ("option", 1.0, "optL"),
    ("command", 1.25, "cmdL"),
    ("", 5.0, "space"),
    ("command", 1.25, "cmdR"),
    ("option", 1.0, "optR"),
]

// The right option key's rect, exported so the video can align the highlight.
var optRRect = (x: 0.0, y: 0.0, w: 0.0, h: 0.0)

var svg = ""
svg += "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(W) \(H)\" fill=\"none\">\n"
svg += "  <!-- keyboard body -->\n"
svg += "  <rect x=\"6\" y=\"6\" width=\"\(W - 12)\" height=\"\(H - 12)\" rx=\"22\" fill=\"#141A2E\" stroke=\"#2A3350\" stroke-width=\"2.5\"/>\n"
svg += "  <!-- deck (speaker grille hint) -->\n"
svg += "  <rect x=\"\(W - 120)\" y=\"\(H - 46)\" width=\"88\" height=\"8\" rx=\"4\" fill=\"#1E2640\"/>\n"

func keyRect(_ x: Double, _ y: Double, _ w: Double, fill: String = "#1E2640", stroke: String = "#2A3350", sw: Double = 2, rx: Double = 8) -> String {
    "  <rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(keyH)\" rx=\"\(rx)\" fill=\"\(fill)\" stroke=\"\(stroke)\" stroke-width=\"\(sw)\"/>\n"
}

func label(_ text: String, _ x: Double, _ y: Double, _ size: Double, _ fill: String, _ weight: String = "500") -> String {
    if text.isEmpty { return "" }
    return "  <text x=\"\(x)\" y=\"\(y)\" fill=\"\(fill)\" font-family=\"Inter, -apple-system, sans-serif\" font-size=\"\(size)\" font-weight=\"\(weight)\" text-anchor=\"middle\">\(text)</text>\n"
}

// --- rows ---
var x = bodyPad
for (t, w) in functionRow {
    svg += keyRect(x, rowY[0], w * unit - gap)
    svg += label(t, x + (w * unit - gap) / 2, rowY[0] + keyH / 2 + 6, 15, t == "esc" ? "#C3C9D9" : "#8C93A6", "600")
    x += w * unit
}

// number row
x = bodyPad
for (t, w) in numberRow {
    svg += keyRect(x, rowY[1], w * unit - gap)
    svg += label(t, x + (w * unit - gap) / 2, rowY[1] + keyH / 2 + 7, 20, "#D6DCE8")
    x += w * unit
}

// qwerty
x = bodyPad
for (t, w) in qwertyRow {
    svg += keyRect(x, rowY[2], w * unit - gap)
    svg += label(t, x + (w * unit - gap) / 2, rowY[2] + keyH / 2 + 7, 21, "#E4E9F2")
    x += w * unit
}

// asdf
x = bodyPad
for (t, w) in asdfRow {
    svg += keyRect(x, rowY[3], w * unit - gap)
    svg += label(t, x + (w * unit - gap) / 2, rowY[3] + keyH / 2 + 7, 21, t == "caps lock" || t == "return" ? "#C3C9D9" : "#E4E9F2")
    x += w * unit
}

// bottom row
x = bodyPad
for (t, w, id) in bottomRow {
    let kw = w * unit - gap
    svg += keyRect(x, rowY[4], kw)
    switch id {
    case "optR":
        // The right Option key: the one the app listens for.
        optRRect = (x: x, y: rowY[4], w: kw, h: keyH)
        svg += "  <rect id=\"kbd-opt-right\" x=\"\(x)\" y=\"\(rowY[4])\" width=\"\(kw)\" height=\"\(keyH)\" rx=\"8\" fill=\"#26314F\" stroke=\"#3E4A73\" stroke-width=\"2.5\"/>\n"
        // The label gets its own id so the video can recolour it to white when the key
        // is pressed. Without that, the teal fill hides the word "option".
        svg += "  <text id=\"kbd-opt-label\" x=\"\(x + kw / 2)\" y=\"\(rowY[4] + keyH / 2 + 7)\" fill=\"#C3C9D9\" font-family=\"Inter, -apple-system, sans-serif\" font-size=\"18\" font-weight=\"600\" text-anchor=\"middle\">option</text>\n"
    case "optL":
        svg += label("option", x + kw / 2, rowY[4] + keyH / 2 + 7, 18, "#C3C9D9", "600")
    case "cmdL", "cmdR":
        svg += label("command", x + kw / 2, rowY[4] + keyH / 2 + 7, 17, "#C3C9D9", "600")
    case "fn":
        svg += label("fn", x + kw / 2, rowY[4] + keyH / 2 + 7, 19, "#C3C9D9")
    case "ctrl":
        svg += label("control", x + kw / 2, rowY[4] + keyH / 2 + 7, 17, "#C3C9D9", "600")
    default:
        break
    }
    x += w * unit
}

// Arrow cluster, inverted T, to the right of the bottom row.
// The cluster starts right after the ASDF row ends (13.5u), and the UP arrow sits in the
// ASDF row band, directly above the DOWN arrow, so nothing collides with the return key.
let arrowW = unit - gap
let arrowX = bodyPad + 13.5 * unit + 8
let upY = rowY[3]
let downY = rowY[4]
for (i, t) in ["←", "↑", "↓", "→"].enumerated() {
    let ax: Double
    let ay: Double
    switch i {
    case 0: ax = arrowX;          ay = downY
    case 1: ax = arrowX + arrowW;  ay = upY
    case 2: ax = arrowX + arrowW;  ay = downY
    default: ax = arrowX + arrowW * 2; ay = downY
    }
    svg += keyRect(ax, ay, arrowW)
    svg += label(t, ax + arrowW / 2, ay + keyH / 2 + 7, 19, "#C3C9D9", "600")
}

// --- the right Option key highlight, on top so it can be animated ---
svg += "  <rect id=\"kbd-opt-glow\" x=\"\(optRRect.x - 7)\" y=\"\(optRRect.y - 7)\" width=\"\(optRRect.w + 14)\" height=\"\(optRRect.h + 14)\" rx=\"15\" fill=\"#0D9E9E\" opacity=\"0\"/>\n"
svg += "  <rect id=\"kbd-opt-ring\" x=\"\(optRRect.x - 7)\" y=\"\(optRRect.y - 7)\" width=\"\(optRRect.w + 14)\" height=\"\(optRRect.h + 14)\" rx=\"15\" fill=\"none\" stroke=\"#0D9E9E\" stroke-width=\"3\" opacity=\"0\"/>\n"

svg += "</svg>\n"

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "keyboard.svg"
try! svg.write(toFile: out, atomically: true, encoding: .utf8)

// Also print the geometry so the video can align the highlight.
FileHandle.standardError.write("optR x=\(optRRect.x) y=\(optRRect.y) w=\(optRRect.w) h=\(optRRect.h)  viewBox=\(W)x\(H)\n".data(using: .utf8)!)
print("wrote \(out)")
