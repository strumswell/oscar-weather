import SwiftUI
import CoreMotion
import Combine
import UIKit

// MARK: - Motion Manager
class MotionManager: ObservableObject {
    private var motionManager: CMMotionManager
    private var updateInterval = 1.0 / 60.0 // 60 Hz
    
    @Published var tilt: CGSize = .zero
    
    // Initial orientation
    private var initialRoll: CGFloat?
    private var initialPitch: CGFloat?
    
    // Separate multipliers for x and y axes
    private let rollMultiplier: CGFloat = 10.0
    private let pitchMultiplier: CGFloat = 15.0 // Increased for higher sensitivity
    
    init() {
        self.motionManager = CMMotionManager()
        self.motionManager.deviceMotionUpdateInterval = updateInterval
        startMotionUpdates()
    }
    
    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion else { return }
            let currentRoll = CGFloat(motion.attitude.roll)
            let currentPitch = CGFloat(motion.attitude.pitch)
            
            // Capture initial orientation once
            if self.initialRoll == nil && self.initialPitch == nil {
                self.initialRoll = currentRoll
                self.initialPitch = currentPitch
                return
            }
            
            // Calculate delta from initial orientation
            let deltaRoll = currentRoll - (self.initialRoll ?? 0)
            let deltaPitch = currentPitch - (self.initialPitch ?? 0)
            
            // Calculate tilt with separate multipliers
            let x = deltaRoll * self.rollMultiplier
            let y = deltaPitch * self.pitchMultiplier

            DispatchQueue.main.async {
                withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                    self.tilt = CGSize(width: x, height: y)
                }
            }
        }
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - MemberCard View
struct MemberCard: View {
    @State private var os: String = UIDevice.current.systemName
    @State private var version: String = UIDevice.current.systemVersion
    @ObservedObject private var motion = MotionManager()
    
    var body: some View {
        ZStack {
            // Background Gradient with Parallax
            LinearGradient(gradient: Gradient(colors: [.sunnyDayStart, .sunnyDayEnd]),
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)
                .offset(x: motion.tilt.width * 0.2, y: motion.tilt.height * 0.3) // Increased y multiplier
            
            // Semi-transparent Color Overlay with Parallax
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.05),
                    Color.blue.opacity(0.02),
                    Color.purple.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .edgesIgnoringSafeArea(.all)
            .offset(x: motion.tilt.width * 0.2, y: motion.tilt.height * 0.3) // Increased y multiplier
            
            // Cloud Image with Parallax
            Image("cloud5")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 300)
                .opacity(0.7)
                .offset(x: motion.tilt.width * 0.4 + 50, y: motion.tilt.height * 0.6 - 50) // Adjusted y offset
             
            // Content with Parallax
            VStack {
                HStack {
                    Text("Member")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .offset(x: motion.tilt.width * 0.6, y: motion.tilt.height * 0.6)
                        .accessibilityLabel("Member status")
                    
                    Image(systemName: "sparkles")
                        .padding(.bottom)
                        .padding(.leading, -7)
                        .offset(x: motion.tilt.width * 0.7, y: motion.tilt.height * 0.7)
                    
                    Spacer()
                    
                    Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                        .resizable()
                        .frame(width: 35, height: 35)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .offset(x: motion.tilt.width * 0.7, y: motion.tilt.height * 0.7)
                }
                .padding(.bottom, 10)
                
                Spacer()
                
                HStack {
                    Text("Beta User")
                        .font(.callout)
                        .fontWeight(.medium)
                        .offset(x: motion.tilt.width * 0.5, y: motion.tilt.height * 0.5)
                        .accessibilityLabel("User type: Beta User")
                    Spacer()
                }
                
                HStack {
                    Text("\(os) \(version)")
                        .monospaced()
                        .font(.footnote)
                        .foregroundColor(.white)
                        .offset(x: motion.tilt.width * 0.5, y: motion.tilt.height * 0.5)
                        .accessibilityLabel("Operating system and version: \(os) \(version)")
                    Spacer()
                }
            }
            .padding(25)
        }
        .frame(height: 200)
        .cornerRadius(20)
        .shadow(radius: 10)
        // 3D Rotation Effect
        .rotation3DEffect(
            .degrees(motion.tilt.width / 10),
            axis: (x: 0, y: 1, z: 0)
        )
        .rotation3DEffect(
            .degrees(motion.tilt.height / 10),
            axis: (x: 1, y: 0, z: 0)
        )
        .animation(.easeInOut, value: motion.tilt)
    }
}

// MARK: - Preview
struct MemberCard_Previews: PreviewProvider {
    static var previews: some View {
        MemberCard()
            .previewLayout(.sizeThatFits)
    }
}
