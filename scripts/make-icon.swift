import AppKit

// 사용법: swift scripts/make-icon.swift <출력 .png>
// 앱 아이콘의 전경 레이어(1024×1024, 투명 바탕)를 그린다: 갈색 말풍선과 그 안의 노란 KLEAN 글자.
// 노란 바탕은 Icon Composer 형식(Icon/AppIcon.icon/icon.json의 fill)이 칠한다. 컴파일은 scripts/make-icon.sh.
// 카카오톡 아이콘의 TALK처럼 글자를 같은 굵기의 둥근 선으로 그려서 작은 크기에서도 또렷하게 보이게 한다.
extension NSColor {
    convenience init(hex: String) {
        let v = Int(hex.dropFirst(), radix: 16)!
        self.init(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

let yellow = NSColor(hex: "#FAE100")   // 카카오톡 아이콘의 노랑 (sRGB)
let brown = NSColor(hex: "#3C1E1E")    // 카카오톡 아이콘의 갈색 (sRGB)

/// 타원의 4분의 1 곡선을 그리기 위한 베지어 상수
let k: CGFloat = 0.5523

/// 글자 하나를 선(중심선) 경로로 만든다. 원점은 글자 왼쪽 아래, h는 글자 높이, w는 선 굵기.
/// 반환값: (경로, 글자 너비)
func glyph(_ c: Character, h: CGFloat, w: CGFloat) -> (NSBezierPath, CGFloat) {
    let p = NSBezierPath()
    let lo = w / 2, hi = h - w / 2          // 선 중심이 지나는 위·아래 높이
    switch c {
    case "N":
        let width = h * 0.72
        p.move(to: NSPoint(x: lo, y: lo))
        p.line(to: NSPoint(x: lo, y: hi))
        p.line(to: NSPoint(x: width - lo, y: lo))
        p.line(to: NSPoint(x: width - lo, y: hi))
        return (p, width)
    case "K":
        let width = h * 0.66
        let mid = h * 0.47
        p.move(to: NSPoint(x: lo, y: lo))
        p.line(to: NSPoint(x: lo, y: hi))
        p.move(to: NSPoint(x: width - lo, y: hi))
        p.line(to: NSPoint(x: lo + w * 0.2, y: mid))
        p.line(to: NSPoint(x: width - lo, y: lo))
        return (p, width)
    case "L":
        let width = h * 0.56
        p.move(to: NSPoint(x: lo, y: hi))
        p.line(to: NSPoint(x: lo, y: lo))
        p.line(to: NSPoint(x: width - lo, y: lo))
        return (p, width)
    case "E":
        let width = h * 0.58
        p.move(to: NSPoint(x: width - lo, y: hi))
        p.line(to: NSPoint(x: lo, y: hi))
        p.line(to: NSPoint(x: lo, y: lo))
        p.line(to: NSPoint(x: width - lo, y: lo))
        p.move(to: NSPoint(x: lo, y: h / 2))
        p.line(to: NSPoint(x: width - lo - h * 0.06, y: h / 2))
        return (p, width)
    case "O":
        let width = h * 0.85
        p.appendOval(in: NSRect(x: lo, y: lo, width: width - w, height: h - w))
        return (p, width)
    case "A":
        let width = h * 0.82
        let left = NSPoint(x: lo, y: lo), top = NSPoint(x: width / 2, y: hi), right = NSPoint(x: width - lo, y: lo)
        p.move(to: left); p.line(to: top); p.line(to: right)
        // 가로획: 아래에서 약 3분의 1 높이
        let y = lo + (hi - lo) * 0.36, t = (y - lo) / (hi - lo)
        p.move(to: NSPoint(x: left.x + (top.x - left.x) * t, y: y))
        p.line(to: NSPoint(x: right.x + (top.x - right.x) * t, y: y))
        return (p, width)
    case "D":
        let width = h * 0.74
        let rx = (width - lo) - (lo + h * 0.18), ry = (hi - lo) / 2
        let cx = lo + h * 0.18, cy = h / 2
        p.move(to: NSPoint(x: lo, y: lo))
        p.line(to: NSPoint(x: lo, y: hi))
        p.line(to: NSPoint(x: cx, y: hi))
        p.curve(to: NSPoint(x: cx + rx, y: cy), controlPoint1: NSPoint(x: cx + rx * k, y: hi), controlPoint2: NSPoint(x: cx + rx, y: cy + ry * k))
        p.curve(to: NSPoint(x: cx, y: lo), controlPoint1: NSPoint(x: cx + rx, y: cy - ry * k), controlPoint2: NSPoint(x: cx + rx * k, y: lo))
        p.close()
        return (p, width)
    default:
        return (p, 0)
    }
}

let px = 1024
// sRGB로 직접 그린다. (다른 색 공간으로 그리면 아이콘으로 묶을 때 색 정보가 빠져 뿌옇게 보인다)
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let s = CGFloat(px)

// 말풍선: 카카오톡 아이콘 비율 (아이콘 면 너비의 76% x 57.5%), 왼쪽 아래로 뾰족한 꼬리
let bw = s * 0.76, bh = s * 0.575
let cx = s / 2, cy = s / 2 + s * 0.035
brown.setFill()
NSBezierPath(ovalIn: NSRect(x: cx - bw / 2, y: cy - bh / 2, width: bw, height: bh)).fill()
let tail = NSBezierPath()
tail.move(to: NSPoint(x: cx - bw * 0.25, y: cy - bh * 0.36))
tail.line(to: NSPoint(x: cx - bw * 0.31, y: cy - bh * 0.69))
tail.line(to: NSPoint(x: cx - bw * 0.03, y: cy - bh * 0.46))
tail.close()
tail.fill()

// 글자: 같은 굵기의 둥근 선. 선 굵기는 글자 높이의 21%, 글자 줄 너비는 말풍선 너비의 78%.
let letters: [Character] = ["K", "L", "E", "A", "N"]
let gapRatio: CGFloat = 0.14, strokeRatio: CGFloat = 0.21
let unit = letters.map { glyph($0, h: 1, w: strokeRatio).1 }.reduce(0, +) + gapRatio * CGFloat(letters.count - 1)
let h = bw * 0.78 / unit
let w = h * strokeRatio
var x = cx - h * unit / 2
yellow.setStroke()
for c in letters {
    let (path, width) = glyph(c, h: h, w: w)
    path.transform(using: AffineTransform(translationByX: x, byY: cy - h / 2))
    path.lineWidth = w
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
    x += width + h * gapRatio
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
