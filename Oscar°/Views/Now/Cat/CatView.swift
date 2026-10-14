import CoreMotion
import SwiftUI

private struct CatShelves {
    var metrics: [Anchor<CGRect>] = []
    var temperature: Anchor<CGRect>?
}

extension View {
    func catShelf() -> some View {
        transformAnchorPreference(key: CatShelfKey.self, value: .bounds) { $0.metrics.append($1) }
    }

    func catPerch() -> some View {
        transformAnchorPreference(key: CatShelfKey.self, value: .bounds) { $0.temperature = $1 }
    }

    func headCat() -> some View {
        simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { CatModel.shared.look(atGlobalX: $0.location.x) })
            .overlayPreferenceValue(CatShelfKey.self) { HeadCat(shelves: $0) }
    }
}

private struct CatShelfKey: PreferenceKey {
    static let defaultValue = CatShelves()

    static func reduce(value: inout CatShelves, nextValue: () -> CatShelves) {
        let next = nextValue()
        value.metrics += next.metrics
        value.temperature = value.temperature ?? next.temperature
    }
}

private struct HeadCat: View {
    let shelves: CatShelves

    @Environment(Weather.self) private var weather
    @Environment(NowPresentationCoordinator.self) private var presentation
    @AppStorage(CatNeeds.enabledKey) private var isEnabled = true

    var body: some View {
        GeometryReader { proxy in
            if isEnabled, !presentation.isNudgeOut, !ScreenshotMode.active, let shelf = shelf(in: proxy) {
                CatView(weather: catWeather)
                    .frame(width: shelf.width)
                    .position(x: shelf.midX, y: shelf.minY - CatView.stageHeight / 2)
            }
        }
        .onChange(of: weather.isLoading) { wasLoading, isLoading in
            if wasLoading, !isLoading { CatModel.shared.hop() }
        }
    }

    private var catWeather: CatWeather {
        guard let now = weather.forecast.current else { return CatWeather() }
        let code = Int(now.weathercode)
        let towardEast = -sin(now.wind_direction_10m * .pi / 180)
        return CatWeather(
            isNight: (now.is_day ?? 1) == 0,
            rain: now.precipitation ?? 0,
            isSnowing: (71...77).contains(code) || (85...86).contains(code),
            isStormy: code >= 95,
            isHotAndSunny: celsius(now.temperature) >= 25 && now.cloudcover < 30 && (now.is_day ?? 1) == 1,
            windPush: towardEast * min(kmh(now.windspeed) / 40, 1)
        )
    }

    private func celsius(_ value: Double) -> Double {
        SettingService.resolvedTemperatureUnit == "fahrenheit" ? (value - 32) * 5 / 9 : value
    }

    private func kmh(_ value: Double) -> Double {
        switch WindSpeedUnit(settingValue: SettingService.resolvedWindSpeedUnit) {
        case .ms: value * 3.6
        case .mph: value * 1.609
        case .kn: value * 1.852
        case .kmh, .bft: value
        }
    }

    private func shelf(in proxy: GeometryProxy) -> CGRect? {
        let metrics = shelves.metrics.map { proxy[$0] }.reduce(CGRect.null) { $0.union($1) }
        if !metrics.isNull, metrics.width >= 50 {
            return metrics.offsetBy(dx: 0, dy: 3)
        }
        guard let temperature = shelves.temperature.map({ proxy[$0] }) else { return nil }
        return temperature.offsetBy(dx: 0, dy: temperature.height * 0.2)
    }
}

struct CatView: View {
    let weather: CatWeather

    @Environment(NowPresentationCoordinator.self) private var presentation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cat = CatModel.shared
    @State private var isOnScreen = true

    static let stageHeight: CGFloat = 112

    private var isActive: Bool {
        isOnScreen && scenePhase == .active && presentation.selectedTab == .forecast
    }

    private var frameInterval: TimeInterval {
        cat.anim.isResting && cat.item == nil ? 1 / 12 : 1 / 60
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: !isActive)) { context in
            CatStage(cat: cat, date: context.date)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.stageHeight)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { cat.setFloor($0) }
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }) { cat.stageMinX = $0 }
        .onScrollVisibilityChange(threshold: 0.1) { isOnScreen = $0 }
        .onChange(of: weather, initial: true) { cat.weather = weather }
        .onChange(of: reduceMotion, initial: true) { cat.calm = reduceMotion }
        .task(id: isActive ? cat.revision : -1) {
            guard isActive else { return }
            await cat.live()
        }
        .task(id: isActive && !reduceMotion) {
            guard isActive, !reduceMotion else { return }
            await feelTheDevice()
        }
    }

    private func feelTheDevice() async {
        let motion = CMMotionManager()
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates()
        defer { motion.stopDeviceMotionUpdates() }
        while (try? await Task.sleep(for: .milliseconds(33))) != nil {
            guard let data = motion.deviceMotion else { continue }
            let a = data.userAcceleration
            cat.feel(tilt: data.gravity.screenX, shake: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
        }
    }
}

private struct CatStage: View {
    let cat: CatModel
    let date: Date

    private static let space = "catStage"
    private static let menuWidth: CGFloat = 164
    private static let wishWidth: CGFloat = 26
    private var floorY: CGFloat { CatView.stageHeight }

    var body: some View {
        let x = cat.x(at: date)
        ZStack(alignment: .topLeading) {
            Color.clear

            if let item = cat.item {
                itemSprite(item)
            }

            Ellipse()
                .fill(.black.opacity(0.15))
                .frame(width: 18, height: 3)
                .position(x: x, y: floorY - 1)

            catSprite
                .position(x: x, y: floorY - 20)

            burst(x: x)

            if let wish = cat.wish {
                CatBubble(tailOnRight: tailOnRight(x), small: true) {
                    CatItemIcon(kind: wish, scale: 1)
                }
                .frame(width: Self.wishWidth)
                .offset(y: Int(date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2) ? 0 : -1)
                .padding(8)
                .contentShape(.rect)
                .onTapGesture { cat.spawn(wish) }
                .accessibilityHidden(true)
                .position(x: bubbleCenter(x, width: Self.wishWidth, tail: 5), y: floorY - 38)
            }

            if cat.isMenuOpen {
                CatBubble(tailOnRight: tailOnRight(x), small: false) {
                    CatMenu(cat: cat)
                }
                .frame(width: Self.menuWidth)
                .position(x: bubbleCenter(x, width: Self.menuWidth, tail: 10), y: floorY - 66)
                .transition(.asymmetric(insertion: .identity, removal: .scale(scale: 0.5).combined(with: .opacity)))
            }
        }
        .coordinateSpace(.named(Self.space))
    }

    private var catSprite: some View {
        PixelSprite(
            sheet: cat.anim.sheet,
            frames: cat.anim.frames,
            frame: cat.anim.frame(after: date.timeIntervalSince(cat.animStart)),
            size: CGSize(width: 32, height: 32),
            flipped: cat.facesLeft
        )
        .frame(width: 44, height: 40, alignment: .bottom)
        .contentShape(.rect)
        .onTapGesture(count: 2) { cat.doubleTap() }
        .onTapGesture { cat.tap() }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { cat.stroke(to: $0.translation) }
                .onEnded { _ in cat.pet() }
        )
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Oscar"))
        .accessibilityValue(Text(cat.mood.label))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { cat.tap() }
        .accessibilityActions {
            ForEach(CatItemKind.allCases) { kind in
                Button { cat.spawn(kind) } label: { Text(kind.label) }
            }
            Button("Streicheln") { cat.pet() }
        }
    }

    @ViewBuilder
    private func itemSprite(_ item: CatItem) -> some View {
        let x = item.glide.x(at: date)
        let size = item.kind.pixels
        let sprite = PixelSprite(
            sheet: item.kind.sheet,
            frames: item.kind.frames,
            frame: frame(of: item),
            size: size
        )
        .scaleEffect(0.3 + 0.7 * presence(of: item), anchor: .bottom)
        .opacity(presence(of: item))
        .accessibilityHidden(true)
        let target = sprite
            .frame(width: max(size.width, 36), height: 36, alignment: .bottom)
            .contentShape(.rect)

        switch item.kind {
        case .fish:
            target
                .onTapGesture { cat.touchItem() }
                .position(x: x, y: floorY - 18)
        case .ball:
            target
                .gesture(DragGesture(minimumDistance: 0).onEnded { cat.flick($0.predictedEndTranslation.width) })
                .position(x: x, y: floorY - 18)
        case .wand:
            sprite
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { cat.dragWand(to: $0.location, stageHeight: floorY) }
                )
                .position(x: x + 9, y: floorY - item.height + 1)
        }
    }

    private func presence(of item: CatItem) -> CGFloat {
        let shown = date.timeIntervalSince(item.born) / 0.2
        let gone = item.leftAt.map { date.timeIntervalSince($0) / CatItem.fade } ?? 0
        return CGFloat(min(max(min(shown, 1 - gone), 0), 1))
    }

    private func frame(of item: CatItem) -> Int {
        let elapsed = max(date.timeIntervalSince(item.born), 0)
        let isMoving = item.glide.isMoving(at: date)
        switch item.kind {
        case .fish: return 0
        case .ball: return isMoving ? [1, 2, 1, 0, 3, 4][Int(elapsed * 12) % 6] : 0
        case .wand: return Int(elapsed * 6) % 6
        }
    }

    @ViewBuilder
    private func burst(x: CGFloat) -> some View {
        if let burst = cat.burst, date.timeIntervalSince(burst.at) < 1.6 {
            ForEach(0..<burst.count, id: \.self) { index in
                let age = CGFloat(date.timeIntervalSince(burst.at)) - CGFloat(index) * 0.2
                let rise: CGFloat = max(age, 0) * 20
                let fade: CGFloat = age > 0 ? max(1 - age / 1.2, 0) : 0
                let spread = CGFloat(index) - CGFloat(burst.count - 1) / 2
                Image(burst.image)
                    .interpolation(.none)
                    .opacity(fade)
                    .position(x: x + spread * 7, y: floorY - 26 - rise)
                    .accessibilityHidden(true)
            }
        }
    }

    private func tailOnRight(_ x: CGFloat) -> Bool { x > cat.floor / 2 }

    private func bubbleCenter(_ x: CGFloat, width: CGFloat, tail: CGFloat) -> CGFloat {
        let head = x + (cat.facesLeft ? -7 : 7)
        return tailOnRight(x) ? head + tail - width / 2 : head - tail + width / 2
    }
}

private struct CatMenu: View {
    let cat: CatModel
    @State private var shown = false

    var body: some View {
        VStack(spacing: 6) {
            Image("cat_name")
                .resizable()
                .interpolation(.none)
                .frame(width: 62, height: 14)
                .accessibilityHidden(true)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(CatItemKind.allCases.enumerated()), id: \.element) { index, kind in
                    Button { cat.spawn(kind) } label: {
                        CatItemIcon(kind: kind, scale: kind == .wand ? 1 : 2)
                            .offset(y: kind == .ball ? -9 : 0)
                            .frame(width: 44, height: 44)
                            .background {
                                Image("cat_slot")
                                    .resizable(capInsets: EdgeInsets(top: 6, leading: 6, bottom: 8, trailing: 6), resizingMode: .stretch)
                                    .interpolation(.none)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(kind.label))
                    .scaleEffect(shown ? 1 : 0.2, anchor: .bottom)
                    .opacity(shown ? 1 : 0)
                    .animation(.bouncy.delay(Double(index) * 0.05), value: shown)
                }
            }
        }
        .onAppear { shown = true }
        .task {
            try? await Task.sleep(for: .seconds(6))
            if cat.isMenuOpen { cat.toggleMenu() }
        }
    }
}

private struct CatBubble<Content: View>: View {
    let tailOnRight: Bool
    let small: Bool
    @ViewBuilder let content: Content
    @State private var shown = false

    var body: some View {
        let unit: CGFloat = small ? 1 : 2
        content
            .padding(.horizontal, 5 * unit)
            .padding(.top, 4 * unit)
            .padding(.bottom, 7 * unit)
            .frame(maxWidth: .infinity)
            .background {
                Image(small ? "cat_bubble_small" : "cat_bubble")
                    .resizable(capInsets: EdgeInsets(top: 3 * unit, leading: 3 * unit, bottom: 5 * unit, trailing: 9 * unit), resizingMode: .stretch)
                    .interpolation(.none)
                    .scaleEffect(x: tailOnRight ? 1 : -1)
            }
            .scaleEffect(shown ? 1 : 0.3, anchor: tailOnRight ? .bottomTrailing : .bottomLeading)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.bouncy) { shown = true } }
    }
}

private struct CatItemIcon: View {
    let kind: CatItemKind
    let scale: CGFloat

    var body: some View {
        PixelSprite(
            sheet: kind.sheet,
            frames: kind.frames,
            frame: 0,
            size: CGSize(width: kind.pixels.width * scale, height: kind.pixels.height * scale)
        )
    }
}

private struct PixelSprite: View {
    let sheet: String
    let frames: Int
    let frame: Int
    let size: CGSize
    var flipped = false

    var body: some View {
        Image(sheet)
            .resizable()
            .interpolation(.none)
            .frame(width: size.width * CGFloat(frames), height: size.height)
            .offset(x: -size.width * CGFloat(frame))
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipped()
            .scaleEffect(x: flipped ? -1 : 1)
    }
}

private extension CatNeeds.Mood {
    var label: LocalizedStringResource {
        switch self {
        case .sleepy: "müde"
        case .hungry: "hungrig"
        case .bored: "gelangweilt"
        case .happy: "zufrieden"
        }
    }
}
