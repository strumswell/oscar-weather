//
//  CatTypes.swift
//  Oscar°
//

import SwiftUI

enum CatAnim {
    case idle, walk, run, sit, sleep, pounce, jump

    var sheet: String {
        switch self {
        case .idle: "cat_idle"
        case .walk, .run: "cat_run"
        case .sit: "cat_sit"
        case .sleep: "cat_sleep"
        case .pounce: "cat_pounce"
        case .jump: "cat_jump"
        }
    }

    var frames: Int {
        switch self {
        case .idle, .walk, .run: 7
        case .sit, .sleep: 3
        case .pounce: 9
        case .jump: 13
        }
    }

    var fps: Double {
        switch self {
        case .idle: 8
        case .walk: 9
        case .run: 15
        case .sit: 2
        case .sleep: 1.5
        case .pounce: 12
        case .jump: 13
        }
    }

    var isOneShot: Bool { self == .pounce || self == .jump }
    var isResting: Bool { self == .sit || self == .sleep }
    var duration: TimeInterval { Double(frames) / fps }

    func frame(after elapsed: TimeInterval) -> Int {
        let frame = Int(max(elapsed, 0) * fps)
        return isOneShot ? min(frame, frames - 1) : frame % frames
    }
}

struct Glide: Equatable {
    var from: CGFloat
    var to: CGFloat
    var start = Date.now
    var duration: TimeInterval = 0
    var easesOut = false

    static func rest(_ x: CGFloat) -> Glide { Glide(from: x, to: x) }

    func x(at date: Date) -> CGFloat {
        guard duration > 0 else { return to }
        var progress = min(max(date.timeIntervalSince(start) / duration, 0), 1)
        if easesOut { progress = 1 - (1 - progress) * (1 - progress) }
        return from + (to - from) * progress
    }

    func isMoving(at date: Date) -> Bool {
        from != to && date < start.addingTimeInterval(duration)
    }
}

enum CatItemKind: CaseIterable, Identifiable {
    case fish, ball, wand

    var id: Self { self }

    var label: LocalizedStringResource {
        switch self {
        case .fish: "Fisch"
        case .ball: "Ball"
        case .wand: "Angel"
        }
    }

    var sheet: String { "cat_\(self)" }

    var lifetime: TimeInterval { self == .wand ? 4 : 15 }

    var frames: Int {
        switch self {
        case .fish: 1
        case .ball: 5
        case .wand: 6
        }
    }

    var pixels: CGSize {
        switch self {
        case .fish: CGSize(width: 16, height: 11)
        case .ball: CGSize(width: 16, height: 16)
        case .wand: CGSize(width: 32, height: 32)
        }
    }
}

struct CatItem: Equatable {
    let kind: CatItemKind
    var glide: Glide
    var height: CGFloat = 0
    var touched = Date.now
    var leftAt: Date?

    static let fade: TimeInterval = 0.3
    let born = Date.now
}

enum CatFurniture: String, CaseIterable, Identifiable {
    case bowl, bed, post

    var id: Self { self }

    var label: LocalizedStringResource {
        switch self {
        case .bowl: "Napf"
        case .bed: "Bett"
        case .post: "Kratzbaum"
        }
    }

    var variants: Int {
        switch self {
        case .bowl, .post: 4
        case .bed: 6
        }
    }

    func image(_ variant: Int) -> String {
        switch self {
        case .post: "cat_post_body_\(variant)"
        case .bowl, .bed: "cat_\(self)_\(variant)"
        }
    }

    var pixels: CGSize {
        switch self {
        case .bowl: CGSize(width: 16, height: 14)
        case .bed: CGSize(width: 50, height: 28)
        case .post: CGSize(width: 40, height: 45)
        }
    }

    var home: CGFloat {
        switch self {
        case .bed: 0.12
        case .post: 0.6
        case .bowl: 0.9
        }
    }

    static let storageKey = "catFurniture"
    static let colorsKey = "catFurnitureColors"

    static func load() -> [CatFurniture: CGFloat] {
        let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, x in CatFurniture(rawValue: key).map { ($0, CGFloat(x)) } })
    }

    static func save(_ placement: [CatFurniture: CGFloat]) {
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: placement.map { ($0.rawValue, Double($1)) }), forKey: storageKey)
    }

    static func layout(_ placement: [CatFurniture: CGFloat], width: CGFloat) -> [CatFurniture: CGFloat] {
        var kept = allCases.filter { placement[$0] != nil }
        while kept.map(\.pixels.width).reduce(0, +) > width { kept.removeLast() }
        let row = kept.sorted { placement[$0, default: 0] < placement[$1, default: 0] }
        var left = row.map { kind in placement[kind, default: 0] * width - kind.pixels.width / 2 }
        var edge: CGFloat = 0
        for index in row.indices {
            left[index] = max(left[index], edge)
            edge = left[index] + row[index].pixels.width
        }
        edge = width
        for index in row.indices.reversed() {
            left[index] = min(left[index], edge - row[index].pixels.width)
            edge = left[index]
        }
        return Dictionary(uniqueKeysWithValues: zip(row, left).map { kind, left in (kind, left + kind.pixels.width / 2) })
    }
}

enum CatMenuPage: Equatable {
    case toys, furniture, colors(CatFurniture)
}

struct CatWeather: Equatable {
    var isNight = false
    var rain = 0.0
    var isSnowing = false
    var isStormy = false
    var isHotAndSunny = false
    var windPush = 0.0

    var isRaining: Bool { rain >= 0.1 && !isSnowing }
    var isPouring: Bool { rain >= 2 && !isSnowing }
}

struct CatBurst: Equatable {
    let image: String
    let count: Int
    let at: Date
}
