// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let welcome = try? newJSONDecoder().decode(Welcome.self, from: jsonData)

import Foundation

struct AWAlert: Codable, Hashable {
    let countryCode: String
    let alertID: Int
    let description: Tion
    let category: String
    let priority: Int
    let type, typeID, alertClass, level: String?
    let source: String
    let sourceID: Int
    //let disclaimer: JSONNull?
    let area: [Area]
    let haveReadyStatements: Bool
    let mobileLink, link: String

    enum CodingKeys: String, CodingKey {
        case countryCode = "CountryCode"
        case alertID = "AlertID"
        case description = "Description"
        case category = "Category"
        case priority = "Priority"
        case type = "Type"
        case typeID = "TypeID"
        case alertClass = "Class"
        case level = "Level"
        case source = "Source"
        case sourceID = "SourceId"
        //case disclaimer = "Disclaimer"
        case area = "Area"
        case haveReadyStatements = "HaveReadyStatements"
        case mobileLink = "MobileLink"
        case link = "Link"
    }
    
    static func == (lhs: AWAlert, rhs: AWAlert) -> Bool {
        lhs.alertID == rhs.alertID
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(alertID)
    }
}

// MARK: - Area
struct Area: Codable {
    let name: String
    let startTime: String
    let epochStartTime: Int
    let endTime: String
    let epochEndTime: Int
    let lastAction: Tion
    let summary: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case startTime = "StartTime"
        case epochStartTime = "EpochStartTime"
        case endTime = "EndTime"
        case epochEndTime = "EpochEndTime"
        case lastAction = "LastAction"
        case summary = "Summary"
    }
}

// MARK: - Tion
struct Tion: Codable {
    let localized, english: String

    enum CodingKeys: String, CodingKey {
        case localized = "Localized"
        case english = "English"
    }
}

typealias AlertResponse = [AWAlert]

// MARK: - Encode/decode helpers

class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
        return true
    }

    public var hashValue: Int {
        return 0
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
