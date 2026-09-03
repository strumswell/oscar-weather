import Foundation

extension Components.Schemas.Location {
    var displayName: String {
        name ?? String(localized: "Unbekannter Ort")
    }

    /// Region line without the place name itself.
    var detailLine: String? {
        let detail = [admin3, admin1, country]
            .compactMap { $0 }
            .filter { $0 != name }
            .joined(separator: ", ")
        return detail.isEmpty ? nil : detail
    }

    var flagEmoji: String? {
        guard let code = country_code?.uppercased(), code.count == 2 else { return nil }
        var flag = ""
        for scalar in code.unicodeScalars {
            guard let regional = UnicodeScalar(0x1F1E6 + scalar.value - UnicodeScalar("A").value) else {
                return nil
            }
            flag.unicodeScalars.append(regional)
        }
        return flag
    }
}
