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

@MainActor
@Observable
final class CatModel {
    static let shared = CatModel()

    var needs = CatNeeds.load()
    var anim = CatAnim.sit
    var animStart = Date.now
    var glide = Glide.rest(0)
    var facesLeft = false
    var item: CatItem?
    var isMenuOpen = false
    var menuPage = CatMenuPage.toys
    var arrangeUntil = Date.distantPast
    var swingAt = Date.distantPast
    var placement = CatFurniture.load()
    var dragging: CatFurniture?
    var dragRise: CGFloat = 0
    var colors = UserDefaults.standard.dictionary(forKey: CatFurniture.colorsKey) as? [String: Int] ?? [:] {
        didSet { UserDefaults.standard.set(colors, forKey: CatFurniture.colorsKey) }
    }
    private var dragGrab: CGFloat?
    var burst: CatBurst?
    var revision = 0
    var weather = CatWeather()
    var calm = false
    var stageFrame = CGRect.zero
    private(set) var floor: CGFloat = 0
    private var greets = false
    private var zoomies = 0
    private var scratches = 0
    private var postRestUntil = Date.distantPast
    private var busyUntil = Date.distantPast
    private var strokeEnd = CGSize.zero
    private var strokeTravel: CGFloat = 0
    private var loop = UUID()

    static let margin: CGFloat = 12
    private static let reach: CGFloat = 11
    private static let wandLift: CGFloat = 44
    static let bedLift: CGFloat = 8
    static let bowlDepth: CGFloat = 5
    static let removeRise: CGFloat = 40
    private static let spotKey = "catSpot"

    var mood: CatNeeds.Mood { needs.mood(isSleepTime: weather.isNight || weather.isPouring) }

    var wish: CatItemKind? {
        guard item == nil, !isMenuOpen else { return nil }
        switch mood {
        case .hungry: return .fish
        case .bored: return .ball
        case .sleepy, .happy: return nil
        }
    }

    func x(at date: Date) -> CGFloat { glide.x(at: date) }

    var spots: [CatFurniture: CGFloat] { CatFurniture.layout(placement, width: floor) }
    var isArranging: Bool {
        dragging != nil || Date.now < arrangeUntil || (isMenuOpen && menuPage != .toys)
    }

    func variant(of kind: CatFurniture) -> Int {
        min(colors[kind.rawValue] ?? 0, kind.variants - 1)
    }

    func isInBed(at x: CGFloat) -> Bool {
        guard anim.isResting, let bed = spots[.bed] else { return false }
        return abs(x - bed) < 3
    }

    func setFloor(_ width: CGFloat) {
        let spot = floor > 0 ? glide.x(at: .now) / floor : CGFloat(UserDefaults.standard.object(forKey: Self.spotKey) as? Double ?? 0.72)
        floor = width
        glide = .rest(clamp(width * spot))
    }

    func live() async {
        let id = UUID()
        loop = id
        sync()
        while !Task.isCancelled, loop == id {
            let wait = step(at: .now)
            try? await Task.sleep(for: .seconds(wait))
        }
        needs.save()
        if floor > 0 { UserDefaults.standard.set(Double(glide.x(at: .now) / floor), forKey: Self.spotKey) }
    }

    func toggleMenu() {
        Haptics.tick()
        if !isMenuOpen { menuPage = .toys }
        withAnimation(.bouncy) { isMenuOpen.toggle() }
    }

    func dismissMenu(outside point: CGPoint) {
        guard point.y < stageFrame.minY - 8 || point.y > stageFrame.maxY else { return }
        if arrangeUntil > .now { arrangeUntil = .distantPast }
        if isMenuOpen { toggleMenu() }
    }

    func showPage(_ page: CatMenuPage) {
        Haptics.tick()
        withAnimation(.bouncy) { menuPage = page }
    }

    func choose(_ kind: CatFurniture, variant: Int) {
        colors[kind.rawValue] = variant
        if placement[kind] == nil {
            withAnimation(.bouncy) { placement[kind] = kind.home }
        }
        CatFurniture.save(placement)
        Haptics.impact()
        revision += 1
    }

    func remove(_ kind: CatFurniture) {
        withAnimation(.bouncy) { placement[kind] = nil }
        CatFurniture.save(placement)
        Haptics.impact()
        revision += 1
    }

    func pickUp(_ kind: CatFurniture) {
        guard dragging == nil else { return }
        dragging = kind
        dragGrab = nil
        dragRise = 0
        Haptics.impact()
    }

    func drag(_ kind: CatFurniture, from start: CGFloat, to x: CGFloat, rise: CGFloat) {
        guard floor > 0 else { return }
        pickUp(kind)
        let grab = dragGrab ?? (spots[kind] ?? start) - start
        dragGrab = grab
        if (dragRise > Self.removeRise) != (rise > Self.removeRise) { Haptics.tick() }
        dragRise = max(rise, 0)
        placement[kind] = min(max((x + grab) / floor, 0), 1)
    }

    func drop(_ kind: CatFurniture) {
        guard dragging != nil else { return }
        if dragRise > Self.removeRise {
            withAnimation(.bouncy) { placement[kind] = nil }
            Haptics.impact()
        } else {
            Haptics.land()
        }
        dragging = nil
        dragGrab = nil
        dragRise = 0
        arrangeUntil = .now.addingTimeInterval(4)
        CatFurniture.save(placement)
        revision += 1
    }

    func tap() {
        if anim == .sleep {
            burst = CatBurst(image: "cat_z", count: 1, at: .now)
            react(.sit, for: 1.2)
        }
        toggleMenu()
    }

    func doubleTap() {
        burst = CatBurst(image: "cat_heart", count: 1, at: .now)
        react(.jump)
        leap()
    }

    func hop() {
        guard anim != .sleep, !calm else { return }
        react(.jump)
        leap()
    }

    func stroke(to translation: CGSize) {
        strokeTravel += hypot(translation.width - strokeEnd.width, translation.height - strokeEnd.height)
        strokeEnd = translation
        guard strokeTravel >= 14 else { return }
        strokeTravel = 0
        Haptics.purr()
    }

    func pet() {
        strokeEnd = .zero
        strokeTravel = 0
        burst = CatBurst(image: "cat_heart", count: 3, at: .now)
        needs.add(fun: 0.05)
        Haptics.impact()
        UsageStatsStore.shared.recordCat(.pets)
        guard anim != .sleep, Date.now >= busyUntil else { return }
        react(.sit, for: 1.5)
    }

    func look(atGlobalX globalX: CGFloat) {
        guard item == nil, anim == .idle || anim == .sit else { return }
        facesLeft = globalX - stageFrame.minX < x(at: .now)
    }

    func feel(tilt: Double, shake: Double) {
        let now = Date.now
        if shake > 2.2, now >= busyUntil { hop() }
        guard abs(tilt) > 0.2, let ball = item, ball.kind == .ball, !ball.glide.isMoving(at: now) else { return }
        let bx = ball.glide.x(at: now)
        item?.glide = Glide(from: bx, to: bounce(bx + CGFloat(tilt) * 60), start: now, duration: 0.6, easesOut: true)
        touchItem()
        Haptics.purr()
    }

    func spawn(_ kind: CatItemKind) {
        let now = Date.now
        let x = x(at: now)
        let ahead: CGFloat = facesLeft ? -1 : 1
        let distance: CGFloat = kind == .ball ? 80 : 40
        var spot = clamp(x + ahead * distance)
        if abs(spot - x) < distance / 2 { spot = clamp(x - ahead * distance) }
        withAnimation(.bouncy) { isMenuOpen = false }
        if kind == .fish, let bowl = spots[.bowl] {
            item = CatItem(kind: kind, glide: .rest(bowl), height: Self.bowlDepth)
        } else {
            item = CatItem(kind: kind, glide: .rest(spot), height: kind == .wand ? 30 : 0)
        }
        revision += 1
        Haptics.impact()
    }

    func flick(_ distance: CGFloat) {
        guard let ball = item, ball.kind == .ball else { return }
        let now = Date.now
        let bx = ball.glide.x(at: now)
        var push = min(max(distance * 1.5, -260), 260)
        if abs(push) < 30 { push = (bx >= x(at: now) ? 1 : -1) * .random(in: 70...130) }
        item?.glide = Glide(from: bx, to: bounce(bx + push + wind(60)), start: now, duration: 1.3, easesOut: true)
        touchItem()
        revision += 1
        Haptics.impact()
    }

    func touchItem() {
        item?.touched = .now
        item?.leftAt = nil
    }

    func dragWand(to point: CGPoint, stageHeight: CGFloat) {
        guard item?.kind == .wand else { return }
        item?.glide = .rest(clamp(point.x))
        item?.height = min(max(stageHeight - point.y + Self.wandLift, 8), stageHeight - 8)
        touchItem()
    }

    private func sync() {
        let stored = CatNeeds.load()
        if stored.updated > needs.updated { needs = stored }
        let away = Date.now.timeIntervalSince(needs.updated)
        greets = away > 3 * 3600 || !Calendar.current.isDateInToday(needs.updated)
    }

    private func react(_ next: CatAnim, for duration: TimeInterval? = nil) {
        let now = Date.now
        _ = rest(next, at: x(at: now), now)
        busyUntil = now.addingTimeInterval(duration ?? next.duration)
        revision += 1
    }

    private func step(at now: Date) -> TimeInterval {
        guard floor > Self.margin * 2 else { return 0.5 }
        needs = needs.aged(to: now, speed: needsSpeed)

        if now < busyUntil { return busyUntil.timeIntervalSince(now) }

        if let gone = item?.leftAt, now.timeIntervalSince(gone) >= CatItem.fade { item = nil }
        if let stale = item, stale.leftAt == nil, now.timeIntervalSince(stale.touched) > stale.kind.lifetime {
            item?.leftAt = now
        }

        let x = x(at: now)
        if let item, item.leftAt == nil, item.kind == .fish || needs.energy >= 0.2 {
            return pursue(item, from: x, at: now)
        }
        let wait = wander(from: x, at: now)
        return item == nil ? wait : min(wait, CatItem.fade)
    }

    private func wander(from x: CGFloat, at now: Date) -> TimeInterval {
        if greets {
            greets = false
            if !calm { return rest(.jump, at: x, now) }
        }
        if zoomies > 0 { return zoom(from: x, at: now) }
        if scratches > 0, let post = spots[.post] { return scratch(post, from: x, at: now) }
        if weather.isStormy, !calm, chance(1, in: 6) { return rest(.jump, at: x, now) }

        switch mood {
        case .sleepy:
            if let bed = spots[.bed], abs(bed - x) > 2 { return move(to: bed, from: x, running: false, at: now) }
            return rest(.sleep, at: x, now, for: 8)
        case .bored:
            if let post = spots[.post], now >= postRestUntil, chance(1, in: 3) { return startScratching(post, from: x, at: now) }
            return rest(.sit, at: x, now, for: 5)
        case .hungry: return rest(.sit, at: x, now, for: 5)
        case .happy where calm || weather.isRaining: return rest(.sit, at: x, now, for: 8)
        case .happy: return play(from: x, at: now)
        }
    }

    private func play(from x: CGFloat, at now: Date) -> TimeInterval {
        if weather.isSnowing, chance(1, in: 4) { return rest(.jump, at: x, now) }
        if weather.isHotAndSunny, chance(1, in: 8) { return rest(.sleep, at: x, now, for: 12) }
        if needs.energy > 0.6, chance(1, in: 12) {
            zoomies = 2
            return zoom(from: x, at: now)
        }
        if let post = spots[.post], now >= postRestUntil, chance(1, in: 6) {
            return startScratching(post, from: x, at: now)
        }

        switch Int.random(in: 0..<10) {
        case 0:
            return rest(.pounce, at: x, now)
        case 1...4:
            let target = clamp(x + .random(in: 25...80) * (Bool.random() ? 1 : -1))
            guard abs(target - x) > 18 else { return rest(.idle, at: x, now, for: 3) }
            return move(to: target, from: x, running: false, at: now)
        case 5, 6:
            return rest(.idle, at: x, now, for: .random(in: 3...6))
        default:
            return rest(.sit, at: x, now, for: .random(in: 5...9))
        }
    }

    private func zoom(from x: CGFloat, at now: Date) -> TimeInterval {
        let end = facesLeft ? Self.margin : floor - Self.margin
        if abs(end - x) > 2 { return move(to: end, from: x, running: true, at: now) }
        zoomies -= 1
        facesLeft.toggle()
        return rest(.idle, at: x, now, for: 0.2)
    }

    private var needsSpeed: Double {
        UserDefaults.standard.bool(forKey: CatNeeds.fastKey) ? 360 : 1
    }

    private func startScratching(_ post: CGFloat, from x: CGFloat, at now: Date) -> TimeInterval {
        scratches = .random(in: 2...4)
        postRestUntil = now.addingTimeInterval(20 * 60 / needsSpeed)
        return scratch(post, from: x, at: now)
    }

    private func scratch(_ post: CGFloat, from x: CGFloat, at now: Date) -> TimeInterval {
        let stand = clamp(post - 27)
        guard abs(stand - x) <= 2 else { return move(to: stand, from: x, running: false, at: now) }
        scratches -= 1
        facesLeft = false
        swingAt = now.addingTimeInterval(0.38)
        needs.add(fun: 0.02, energy: -0.02)
        UsageStatsStore.shared.recordCat(.scratches)
        return rest(.jump, at: x, now)
    }

    private func pursue(_ item: CatItem, from x: CGFloat, at now: Date) -> TimeInterval {
        let target = item.glide.x(at: now)
        let side: CGFloat = target < x ? 1 : -1
        let isClose = abs(target - x) <= Self.reach + 2

        switch item.kind {
        case .fish:
            guard isClose else { return move(to: target + side * Self.reach, from: x, running: true, at: now) }
            facesLeft = target < x
            needs.add(food: 0.4)
            burst = CatBurst(image: "cat_heart", count: 3, at: now.addingTimeInterval(1.2))
            self.item?.leftAt = now.addingTimeInterval(1.2)
            for bite in [0, 0.5, 1.0] { buzz(after: bite, Haptics.chomp) }
            buzz(after: 1.2, Haptics.success)
            UsageStatsStore.shared.recordCat(.fish)
            return rest(.sit, at: x, now, for: 1.6)

        case .ball:
            let restingFor = now.timeIntervalSince(item.glide.start.addingTimeInterval(item.glide.duration))
            if item.glide.duration > 0, restingFor < 0.8 {
                facesLeft = target < x
                return rest(.idle, at: x, now, for: min(0.8 - restingFor, 0.3))
            }
            guard isClose else { return move(to: target + side * Self.reach, from: x, running: true, at: now) }
            facesLeft = target < x
            let kick = -side * .random(in: 90...170) + wind(60)
            self.item?.glide = Glide(from: target, to: bounce(target + kick), start: now.addingTimeInterval(0.45), duration: 1.5, easesOut: true)
            needs.add(fun: 0.08, energy: -0.04)
            buzz(after: 0.45, Haptics.impact)
            UsageStatsStore.shared.recordCat(.kicks)
            return rest(.pounce, at: x, now)

        case .wand:
            guard isClose else { return move(to: target + side * Self.reach * 0.5, from: x, running: true, at: now) }
            facesLeft = target < x
            guard item.height < 34 else { return rest(.sit, at: x, now, for: 0.4) }
            needs.add(fun: 0.06, energy: -0.03)
            buzz(after: 0.38, Haptics.impact)
            buzz(after: 0.69, Haptics.land)
            UsageStatsStore.shared.recordCat(.catches)
            return rest(.jump, at: x, now)
        }
    }

    private func rest(_ next: CatAnim, at x: CGFloat, _ now: Date, for duration: TimeInterval? = nil) -> TimeInterval {
        if next != anim || next.isOneShot {
            if next == .sleep, anim != .sleep { UsageStatsStore.shared.recordCat(.naps) }
            anim = next
            animStart = now
        }
        if next.isOneShot { busyUntil = now.addingTimeInterval(next.duration) }
        glide = .rest(x)
        return duration ?? next.duration
    }

    private func move(to target: CGFloat, from x: CGFloat, running: Bool, at now: Date) -> TimeInterval {
        let target = clamp(target)
        let next: CatAnim = running ? .run : .walk
        let tailwind = wind(target > x ? 1 : -1)
        let speed: CGFloat = running ? 70 : 16 * (1 + 0.4 * tailwind)
        let time = abs(target - x) / speed
        if abs(target - x) > 1 { facesLeft = target < x }
        if next != anim {
            anim = next
            animStart = now
        }
        glide = Glide(from: x, to: target, start: now, duration: time)
        return max(running ? min(time, 0.3) : time, 0.1)
    }

    private func leap() {
        buzz(after: 0.23, Haptics.purr)
        buzz(after: 0.69, Haptics.land)
    }

    private func buzz(after delay: TimeInterval, _ haptic: @escaping @MainActor () -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            haptic()
        }
    }

    private func wind(_ scale: CGFloat) -> CGFloat {
        CGFloat(weather.windPush) * scale
    }

    private func chance(_ hits: Int, in total: Int) -> Bool {
        Int.random(in: 0..<total) < hits
    }

    private func clamp(_ x: CGFloat) -> CGFloat {
        min(max(x, Self.margin), max(floor - Self.margin, Self.margin))
    }

    private func bounce(_ x: CGFloat) -> CGFloat {
        let low = Self.margin, high = floor - Self.margin
        if x > high { return clamp(high - (x - high)) }
        if x < low { return clamp(low + (low - x)) }
        return x
    }
}
