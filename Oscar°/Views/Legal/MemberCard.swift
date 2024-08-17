import SwiftUI
import CoreMotion
import UIKit

struct MemberCard: View {
    @State private var os: String = UIDevice.current.systemName
    @State private var version: String = UIDevice.current.systemVersion
    //@State private var motionManager = MotionManager()
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [.sunnyDayStart, .sunnyDayEnd]), startPoint: .topLeading, endPoint: .bottomTrailing)
            Image("cloud5")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 300)
                .offset(x: 50, y: -50)
                .opacity(0.7)
            VStack {
                HStack {
                    Text("Member")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Image(systemName: "sparkles")
                        .padding(.bottom)
                        .padding(.leading, -7)
                    Spacer()
                    Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                        .resizable()
                        .frame(width: 35, height: 35)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .padding(.bottom, 10)
                Spacer()
                HStack {
                    Text("Beta User")
                        .font(.callout)
                        .fontWeight(.medium)
                    Spacer()
                }
                HStack {
                    Text("\(os) \(version)")
                        .monospaced()
                        .font(.footnote)
                        .foregroundColor(.white)
                    Spacer()
                }
            }
            .padding(25)
            
            //DynamicShineEffect(roll: $motionManager.roll, pitch: $motionManager.pitch)
        }
        .frame(height: 200)
        .cornerRadius(20)
        .shadow(radius: 10)
//        .rotation3DEffect(
//            Angle(degrees: motionManager.roll * 6),
//            axis: (x: 0, y: 1, z: 0)
//        )
//        .rotation3DEffect(
//            Angle(degrees: motionManager.pitch * 6),
//            axis: (x: 1, y: 0, z: 0)
//        )
//        .onAppear {
//            motionManager.startUpdates()
//        }
//        .onDisappear {
//            motionManager.stopUpdates()
//        }
    }
}

#Preview {
    MemberCard()
}


struct ShineEffect: View {
    @Binding var roll: Double
    @Binding var pitch: Double
    
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(gradient: Gradient(colors: [.clear, .white.opacity(0.1), .clear]),
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .mask(
                    Rectangle()
                        .fill(
                            LinearGradient(gradient: Gradient(colors: [.black.opacity(0.5), .clear]),
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .rotationEffect(.degrees(-45))
                        .frame(width: geometry.size.width * 2)
                        .offset(x: -geometry.size.width / 2)
                        .offset(x: CGFloat(roll * geometry.size.width / 4),
                                y: CGFloat(pitch * geometry.size.height / 4))
                )
                .blendMode(.overlay)
        }
    }
}

struct DynamicShineEffect: View {
    @Binding var roll: Double
    @Binding var pitch: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base shine
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.3),
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.size.width / 1.5
                )
                .blur(radius: 10)
                .opacity(0.7)
                
                // Dynamic shine based on tilt
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.3),
                        Color.white.opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.size.width / 3
                )
                .blur(radius: 5)
                .opacity(0.5)
                .offset(
                    x: CGFloat(roll * geometry.size.width / 3),
                    y: CGFloat(pitch * geometry.size.height / 3)
                )
            }
            .blendMode(.overlay)
        }
    }
}

@Observable
class MotionManager {
    private var motionManager: CMMotionManager
    var pitch: Double = 0.0
    var roll: Double = 0.0
    private var initialPitch: Double = 0.0
    private var initialRoll: Double = 0.0
    var isInitialized: Bool = false
    
    private let dampeningFactor: Double = 0.2
    
    init() {
        self.motionManager = CMMotionManager()
        self.motionManager.deviceMotionUpdateInterval = 1/60
    }
    
    func startUpdates() {
        self.motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            guard let motion = motion, let self = self else { return }
            
            if !self.isInitialized {
                self.initialPitch = motion.attitude.pitch
                self.initialRoll = motion.attitude.roll
                self.isInitialized = true
            }
            
            let newPitch = motion.attitude.pitch - self.initialPitch
            let newRoll = motion.attitude.roll - self.initialRoll
            
            self.pitch += (newPitch - self.pitch) * self.dampeningFactor
            self.roll += (newRoll - self.roll) * self.dampeningFactor
        }
    }
    
    func stopUpdates() {
        self.motionManager.stopDeviceMotionUpdates()
        self.isInitialized = false
    }
}

struct HolographicPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        let rows = 10
        let columns = 10
        
        for row in 0...rows {
            for column in 0...columns {
                let x = CGFloat(column) * width / CGFloat(columns)
                let y = CGFloat(row) * height / CGFloat(rows)
                let size = min(width / CGFloat(columns), height / CGFloat(rows))
                
                if (row + column) % 2 == 0 {
                    path.addRect(CGRect(x: x, y: y, width: size, height: size))
                } else {
                    path.addEllipse(in: CGRect(x: x, y: y, width: size, height: size))
                }
            }
        }
        
        return path
    }
}

struct HolographicEffect: View {
    @Binding var roll: Double
    @Binding var pitch: Double
    
    let baseColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<3) { index in
                    HolographicPattern()
                        .fill(
                            LinearGradient(gradient: Gradient(colors: baseColors.map { $0.saturated() }),
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .hueRotation(Angle(degrees: Double(index) * 120))
                        .opacity(0.4)  // Slightly increased opacity
                        .blendMode(.plusLighter)
                        .mask(
                            GeometryReader { innerGeometry in
                                LinearGradient(gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white, location: calculateGradientPosition(size: innerGeometry.size).0),
                                    .init(color: .white, location: calculateGradientPosition(size: innerGeometry.size).1),
                                    .init(color: .clear, location: 1)
                                ]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        )
                }
            }
        }
    }
    
    private func calculateGradientPosition(size: CGSize) -> (CGFloat, CGFloat) {
        let normalizedRoll = (roll + 1) / 2
        let normalizedPitch = (pitch + 1) / 2
        
        let start = max(0, min(0.7, normalizedRoll - 0.15))
        let end = min(1, max(0.3, normalizedRoll + 0.15))
        
        return (start, end)
    }
}

extension Color {
    func saturated() -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        return Color(hue: hue, saturation: min(1, saturation * 2), brightness: min(1, brightness * 1.2), opacity: alpha)
    }
}
