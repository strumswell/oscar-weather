import SwiftUI

struct MemberCardSignaturePad: View {
    @Binding var strokes: [[CGPoint]]

    @State private var current: [CGPoint] = []

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, size in
                let baseline = size.height * 0.74
                var line = Path()
                line.move(to: CGPoint(x: 22, y: baseline))
                line.addLine(to: CGPoint(x: size.width - 22, y: baseline))
                context.stroke(line, with: .color(MemberCardInk.color.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                context.draw(
                    Text(verbatim: "×").font(.system(size: 20, weight: .light)).foregroundStyle(MemberCardInk.color.opacity(0.4)),
                    at: CGPoint(x: 24, y: baseline - 12)
                )
                MemberCardInk.draw(strokes + [current], in: context, rect: CGRect(origin: .zero, size: size), lineWidth: max(2.4, size.height / 34))
            }
            .overlay {
                if strokes.isEmpty && current.isEmpty {
                    Text("Hier unterschreiben")
                        .font(.system(.title3, design: .serif).italic())
                        .foregroundStyle(MemberCardInk.color.opacity(0.3))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = CGPoint(
                            x: min(max(value.location.x / size.width, 0), 1),
                            y: min(max(value.location.y / size.height, 0), 1)
                        )
                        guard let last = current.last else {
                            current = [raw]
                            return
                        }
                        let smoothed = CGPoint(x: last.x + (raw.x - last.x) * 0.55, y: last.y + (raw.y - last.y) * 0.55)
                        guard hypot((smoothed.x - last.x) * size.width, (smoothed.y - last.y) * size.height) > 1.2 else { return }
                        current.append(smoothed)
                    }
                    .onEnded { _ in
                        guard !current.isEmpty else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            strokes.append(current)
                        }
                        current = []
                    }
            )
        }
        .overlay(alignment: .topTrailing) {
            if !strokes.isEmpty {
                HStack(spacing: 8) {
                    padButton("arrow.uturn.backward", label: Text("Rückgängig")) {
                        _ = strokes.popLast()
                    }
                    padButton("trash", label: Text("Löschen")) {
                        strokes = []
                    }
                }
                .padding(10)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.35), value: strokes.isEmpty)
        .background(MemberCardInk.paper)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Unterschriftsfeld"))
        .accessibilityValue(Text(strokes.isEmpty ? "Leer" : "Unterschrieben"))
        .accessibilityHint(Text("Mit dem Finger unterschreiben."))
    }

    private func padButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tick()
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MemberCardInk.color)
                .frame(width: 36, height: 36)
                .background(MemberCardInk.color.opacity(0.08), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
