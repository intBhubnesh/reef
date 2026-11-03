import CoreGraphics
import Foundation

/// Small SVG path-data reader used by Reef's bundled avatar silhouettes. It deliberately accepts
/// path commands only; no SVG/XML markup reaches the renderer. The open-bot-avatar catalogue uses
/// M/L/H/V/C/Q/A/Z, but relative forms are supported as well so future definitions stay portable.
enum SVGPathParser {
    enum ParseError: Error, Equatable {
        case expectedNumber(Int)
        case expectedCommand(Int)
        case unsupportedCommand(Character)
    }

    static func path(_ source: String) throws -> CGPath {
        var reader = Reader(source)
        let path = CGMutablePath()
        var command: UInt8?
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        while reader.hasMore {
            if let next = reader.peekCommand() {
                command = next
                reader.advance()
            } else if command == nil {
                throw ParseError.expectedCommand(reader.offset)
            }

            guard let raw = command else { break }
            let relative = raw >= 97 && raw <= 122
            let upper = raw >= 97 ? raw - 32 : raw
            let point: (Double, Double) -> CGPoint = { x, y in
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch upper {
            case 77: // M
                let p = point(try reader.number(), try reader.number())
                path.move(to: p)
                current = p
                subpathStart = p
                command = relative ? 108 : 76
                while reader.startsNumber {
                    let p = point(try reader.number(), try reader.number())
                    path.addLine(to: p)
                    current = p
                }
            case 76: // L
                repeat {
                    let p = point(try reader.number(), try reader.number())
                    path.addLine(to: p)
                    current = p
                } while reader.startsNumber
            case 72: // H
                repeat {
                    let x = try reader.number()
                    current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                    path.addLine(to: current)
                } while reader.startsNumber
            case 86: // V
                repeat {
                    let y = try reader.number()
                    current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                    path.addLine(to: current)
                } while reader.startsNumber
            case 67: // C
                repeat {
                    let c1 = point(try reader.number(), try reader.number())
                    let c2 = point(try reader.number(), try reader.number())
                    let end = point(try reader.number(), try reader.number())
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                } while reader.startsNumber
            case 81: // Q
                repeat {
                    let control = point(try reader.number(), try reader.number())
                    let end = point(try reader.number(), try reader.number())
                    path.addQuadCurve(to: end, control: control)
                    current = end
                } while reader.startsNumber
            case 65: // A
                repeat {
                    let rx = try reader.number()
                    let ry = try reader.number()
                    let rotation = try reader.number()
                    let large = try reader.number() != 0
                    let sweep = try reader.number() != 0
                    let end = point(try reader.number(), try reader.number())
                    addArc(to: path, from: current, to: end, rx: rx, ry: ry,
                           rotation: rotation, large: large, sweep: sweep)
                    current = end
                } while reader.startsNumber
            case 90: // Z
                path.closeSubpath()
                current = subpathStart
                command = nil
            default:
                throw ParseError.unsupportedCommand(Character(UnicodeScalar(raw)))
            }
        }
        return path.copy()!
    }

    /// Converts an SVG elliptical arc to at most 90-degree cubic Bézier segments.
    private static func addArc(to path: CGMutablePath, from start: CGPoint, to end: CGPoint,
                               rx rawRX: Double, ry rawRY: Double, rotation: Double,
                               large: Bool, sweep: Bool) {
        var rx = abs(rawRX), ry = abs(rawRY)
        guard rx > 0, ry > 0, start != end else {
            if start != end { path.addLine(to: end) }
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = Double(start.x - end.x) / 2
        let dy = Double(start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let scale = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if scale > 1 {
            let factor = sqrt(scale)
            rx *= factor
            ry *= factor
        }

        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = max(Double.leastNonzeroMagnitude, rx * rx * y1 * y1 + ry * ry * x1 * x1)
        let sign = large == sweep ? -1.0 : 1.0
        let factor = sign * sqrt(numerator / denominator)
        let cx1 = factor * rx * y1 / ry
        let cy1 = factor * -ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + Double(start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + Double(start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let ux = (x1 - cx1) / rx, uy = (y1 - cy1) / ry
        let vx = (-x1 - cx1) / rx, vy = (-y1 - cy1) / ry
        var delta = angle(ux, uy, vx, vy)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }
        let startAngle = atan2(uy, ux)
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(segments)

        func mapped(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: cx + rx * cosPhi * x - ry * sinPhi * y,
                    y: cy + rx * sinPhi * x + ry * cosPhi * y)
        }
        for index in 0..<segments {
            let a = startAngle + Double(index) * step
            let b = a + step
            let k = 4.0 / 3.0 * tan(step / 4)
            let p1 = mapped(cos(a) - k * sin(a), sin(a) + k * cos(a))
            let p2 = mapped(cos(b) + k * sin(b), sin(b) - k * cos(b))
            path.addCurve(to: mapped(cos(b), sin(b)), control1: p1, control2: p2)
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        init(_ source: String) { bytes = Array(source.utf8) }
        var offset: Int { index }
        var hasMore: Bool {
            var copy = self
            copy.skipSeparators()
            return copy.index < copy.bytes.count
        }
        var startsNumber: Bool {
            var copy = self
            copy.skipSeparators()
            guard copy.index < copy.bytes.count else { return false }
            return copy.bytes[copy.index] == 43 || copy.bytes[copy.index] == 45 || copy.bytes[copy.index] == 46
                || (copy.bytes[copy.index] >= 48 && copy.bytes[copy.index] <= 57)
        }
        mutating func peekCommand() -> UInt8? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let value = bytes[index]
            return (value >= 65 && value <= 90) || (value >= 97 && value <= 122) ? value : nil
        }
        mutating func advance() { index += 1 }

        mutating func number() throws -> Double {
            skipSeparators()
            let start = index
            if index < bytes.count, (bytes[index] == 43 || bytes[index] == 45) { index += 1 }
            var digits = false
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                digits = true; index += 1
            }
            if index < bytes.count, bytes[index] == 46 {
                index += 1
                while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                    digits = true; index += 1
                }
            }
            if digits, index < bytes.count, (bytes[index] == 69 || bytes[index] == 101) {
                let exponent = index
                index += 1
                if index < bytes.count, (bytes[index] == 43 || bytes[index] == 45) { index += 1 }
                let exponentStart = index
                while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1 }
                if exponentStart == index { index = exponent }
            }
            guard digits, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw ParseError.expectedNumber(start)
            }
            return value
        }

        mutating func skipSeparators() {
            while index < bytes.count, bytes[index] == 44 || bytes[index] == 32
                    || bytes[index] == 9 || bytes[index] == 10 || bytes[index] == 13 { index += 1 }
        }
    }
}
