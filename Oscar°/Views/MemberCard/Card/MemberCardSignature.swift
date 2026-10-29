import SwiftUI

enum MemberCardSignature {
    static func decode(_ data: Data) -> [[CGPoint]] {
        (try? JSONDecoder().decode([[CGPoint]].self, from: data)) ?? []
    }

    static func encode(_ strokes: [[CGPoint]]) -> Data {
        strokes.isEmpty ? Data() : (try? JSONEncoder().encode(strokes)) ?? Data()
    }
}

struct MemberCardSignatureStrip: View {
    let strokes: [[CGPoint]]

    var body: some View {
        Canvas { context, size in
            var stripes = Path()
            var x = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF4F1EA)))
            context.stroke(stripes, with: .color(Color(hex: 0xE3DED2)), lineWidth: 3.5)
            let height = size.height * 0.92
            let rect = CGRect(x: size.height * 0.2, y: (size.height - height) / 2, width: height * MemberCardInk.aspect, height: height)
            MemberCardInk.draw(strokes, in: context, rect: rect, lineWidth: max(1, size.height / 26))
        }
        .clipShape(.rect(cornerRadius: 3))
        .overlay {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.black.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Unterschriftsfeld"))
        .accessibilityValue(Text(strokes.isEmpty ? "Leer" : "Unterschrieben"))
    }
}

enum MemberCardInk {
    static let aspect: CGFloat = 2.2
    static let color = Color(hex: 0x1F2C5C)
    static let paper = Color(hex: 0xF7F4EC)

    static func draw(_ strokes: [[CGPoint]], in context: GraphicsContext, rect: CGRect, lineWidth: CGFloat) {
        for stroke in strokes where !stroke.isEmpty {
            let points = stroke.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
            guard points.count > 1 else {
                let dot = CGRect(x: points[0].x - lineWidth / 2, y: points[0].y - lineWidth / 2, width: lineWidth, height: lineWidth)
                context.fill(Path(ellipseIn: dot), with: .color(color))
                continue
            }
            var width = lineWidth
            var start = points[0]
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let end = index == points.count - 1 ? current : CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                let speed = hypot(current.x - previous.x, current.y - previous.y) / max(rect.height, 1)
                let target = lineWidth * min(max(1.3 - speed * 5, 0.45), 1.3)
                width += (target - width) * 0.35
                var segment = Path()
                segment.move(to: start)
                segment.addQuadCurve(to: end, control: previous)
                context.stroke(segment, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                start = end
            }
        }
    }
}
