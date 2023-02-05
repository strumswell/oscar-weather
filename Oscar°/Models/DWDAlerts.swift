//
//  DWDAlerts.swift
//  Oscar°
//
//  Created by Philipp Bolte on 21.02.22.
//

import Foundation

struct DWDAlert: Codable, Hashable {
    let warnId: String
    let type, level, start, end: Int
    let bn: Bool
    let instruction, description, descriptionText, event: String
    let headline: String
    
    public func getFormattedHeadline() -> String {
        return self.headline
            .replacingOccurrences(of: "Amtliche", with: "")
            .replacingOccurrences(of: "UNWETTER", with: "")
    }
        
    public func getStartDate() -> String {
        return formatDate(time: self.start)
    }
    
    public func getEndDate() -> String {
        return formatDate(time: self.end)
    }
    
    public func formatDate(time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time / 1000))
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "de")
        return dateFormatter.string(from: date)
    }
    
    public static func == (lhs: DWDAlert, rhs: DWDAlert) -> Bool {
        lhs.warnId == rhs.warnId
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(warnId)
    }
}

typealias DWDAlerts = [DWDAlert]
