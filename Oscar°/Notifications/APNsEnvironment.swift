import Foundation

enum APNsEnvironment: String, Codable {
    case sandbox
    case production

    /// Read from the embedded provisioning profile; App Store and TestFlight builds carry none and default to production.
    static func current() -> APNsEnvironment {
        if let provisionPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let profile = try? String(contentsOfFile: provisionPath, encoding: .isoLatin1),
           let entitlementRange = profile.range(of: "<key>aps-environment</key>"),
           let stringStartRange = profile.range(of: "<string>", range: entitlementRange.upperBound..<profile.endIndex),
           let stringEndRange = profile.range(of: "</string>", range: stringStartRange.upperBound..<profile.endIndex) {
            let entitlementValue = profile[stringStartRange.upperBound..<stringEndRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch entitlementValue.lowercased() {
            case "development":
                return .sandbox
            case "production":
                return .production
            default:
                break
            }
        }

        return .production
    }
}
