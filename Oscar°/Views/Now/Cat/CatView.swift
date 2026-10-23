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
            if isEnabled, !ScreenshotMode.active, let shelf = shelf(in: proxy) {
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
    @State private var viewport: CGRect?

    static let stageHeight: CGFloat = 112

    private var isActive: Bool {
        isOnScreen && scenePhase == .active && presentation.selectedTab == .forecast
    }

    private var frameInterval: TimeInterval {
        let isStill = cat.anim.isResting && cat.item == nil && !cat.isArranging && Date.now.timeIntervalSince(cat.swingAt) > 3
        return isStill ? 1 / 12 : 1 / 60
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: !isActive)) { context in
            CatStage(cat: cat, date: context.date, viewport: viewport, isAway: presentation.isNudgeOut)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.stageHeight)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { cat.setFloor($0) }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { cat.stageFrame = $0 }
        .onGeometryChange(for: CGRect?.self, of: { $0.bounds(of: .scrollView) }) { viewport = $0 }
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
    let viewport: CGRect?
    let isAway: Bool
    @GestureState private var held: CatFurniture?

    private static let space = "catStage"
    private static let wishWidth: CGFloat = 26
    private var floorY: CGFloat { CatView.stageHeight }

    var body: some View {
        let x = cat.x(at: date)
        let lift = cat.isInBed(at: x) ? CatModel.bedLift : 0
        let spots = cat.spots
        ZStack(alignment: .topLeading) {
            Color.clear

            ForEach(CatFurniture.allCases) { kind in
                if let spot = spots[kind] {
                    furnitureSprite(kind)
                        .position(x: spot, y: floorY - kind.pixels.height / 2)
                }
            }

            if !isAway {
                catLayer(x: x, lift: lift, bowl: spots[.bowl])
            }
        }
        .coordinateSpace(.named(Self.space))
        .onChange(of: held) { old, new in
            if new == nil, let old { cat.drop(old) }
        }
        .onChange(of: isAway) {
            if isAway, cat.isMenuOpen { cat.toggleMenu() }
        }
    }

    @ViewBuilder
    private func catLayer(x: CGFloat, lift: CGFloat, bowl: CGFloat?) -> some View {
        if let item = cat.item {
            itemSprite(item)
            if item.kind == .fish, item.height > 0, let bowl {
                FurnitureSprite(kind: .bowl, variant: cat.variant(of: .bowl))
                    .mask(alignment: .bottom) { Rectangle().frame(height: 8) }
                    .allowsHitTesting(false)
                    .position(x: bowl, y: floorY - CatFurniture.bowl.pixels.height / 2)
            }
        }

        Ellipse()
            .fill(.black.opacity(0.15))
            .frame(width: 18, height: 3)
            .position(x: x, y: floorY - 1 - lift)

        catSprite
            .position(x: x, y: floorY - 20 - lift)

        burst(x: x, lift: lift)

        if let wish = cat.wish {
            CatBubble(tailOnRight: tailOnRight(x)) {
                CatItemIcon(kind: wish, scale: 1)
            }
            .frame(width: Self.wishWidth)
            .offset(y: Int(date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2) ? 0 : -1)
            .padding(8)
            .contentShape(.rect)
            .onTapGesture { cat.spawn(wish) }
            .accessibilityHidden(true)
            .position(x: bubbleCenter(x, width: Self.wishWidth, tail: 5), y: floorY - 38 - lift)
        }

        if cat.isMenuOpen {
            let width = CatMenu.width(page: cat.menuPage)
            let head = x + (cat.facesLeft ? -7 : 7)
            let center = menuCenter(head: head, width: width)
            CatMenuBubble(tailX: min(max(head - center + width / 2, 12), width - 12), width: width) {
                CatMenu(cat: cat)
            }
            .position(x: center, y: floorY - 74 - lift)
            .transition(.asymmetric(insertion: .identity, removal: .scale(scale: 0.5).combined(with: .opacity)))
        }
    }

    private func menuCenter(head: CGFloat, width: CGFloat) -> CGFloat {
        let bounds = viewport ?? CGRect(x: 0, y: 0, width: cat.floor, height: 0)
        let low = bounds.minX + width / 2 + 6
        let high = bounds.maxX - width / 2 - 6
        guard low <= high else { return bounds.midX }
        return min(max(head, low), high)
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

    private var swing: Angle {
        let t = date.timeIntervalSince(cat.swingAt)
        guard t > 0, t < 3 else { return .zero }
        return .degrees(-28 * exp(-t / 0.8) * sin(t * 2 * .pi / 0.75))
    }

    private func furnitureSprite(_ kind: CatFurniture) -> some View {
        let isDragged = cat.dragging == kind
        let wiggle = cat.isArranging && !isDragged && !cat.calm ? sin(date.timeIntervalSinceReferenceDate * 14 + kind.home * 9) * 1.5 : 0
        return FurnitureSprite(kind: kind, variant: cat.variant(of: kind), swing: swing)
            .rotationEffect(.degrees(wiggle), anchor: .bottom)
            .scaleEffect(isDragged ? 1.08 : 1, anchor: .bottom)
            .opacity(isDragged && cat.dragRise > CatModel.removeRise ? 0.35 : 1)
            .contentShape(.rect)
            .gesture(
                LongPressGesture(minimumDuration: cat.isArranging ? 0.01 : 0.35)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
                    .updating($held) { value, state, _ in
                        guard case .second(true, let drag) = value else { return }
                        state = kind
                        if let drag {
                            cat.drag(kind, from: drag.startLocation.x, to: drag.location.x, rise: -drag.translation.height)
                        } else {
                            cat.pickUp(kind)
                        }
                    }
            )
            .overlay(alignment: .topTrailing) {
                if cat.isArranging, !isDragged {
                    Button { cat.remove(kind) } label: {
                        Image("cat_close")
                            .interpolation(.none)
                            .frame(width: 32, height: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 24, y: -24)
                }
            }
            .offset(y: isDragged ? -cat.dragRise : 0)
            .accessibilityHidden(true)
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
        .rotationEffect(.degrees(item.kind == .fish && item.height > 0 ? -45 : 0))
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
                .position(x: x, y: floorY - 18 - item.height)
        case .ball:
            target
                .gesture(DragGesture(minimumDistance: 0).onEnded { cat.flick($0.predictedEndTranslation.width) })
                .position(x: x, y: floorY - 18)
        case .wand:
            sprite
                .frame(width: 64, height: 64)
                .contentShape(.rect)
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
    private func burst(x: CGFloat, lift: CGFloat) -> some View {
        if let burst = cat.burst, date.timeIntervalSince(burst.at) < 1.6 {
            ForEach(0..<burst.count, id: \.self) { index in
                let age = CGFloat(date.timeIntervalSince(burst.at)) - CGFloat(index) * 0.2
                let rise: CGFloat = max(age, 0) * 20
                let fade: CGFloat = age > 0 ? max(1 - age / 1.2, 0) : 0
                let spread = CGFloat(index) - CGFloat(burst.count - 1) / 2
                Image(burst.image)
                    .interpolation(.none)
                    .opacity(fade)
                    .position(x: x + spread * 7, y: floorY - 26 - lift - rise)
                    .accessibilityHidden(true)
            }
        }
    }

    private func tailOnRight(_ x: CGFloat) -> Bool { x > cat.floor / 2 }

    private func bubbleCenter(_ x: CGFloat, width: CGFloat, tail: CGFloat) -> CGFloat {
        let head = x + (cat.facesLeft ? -7 : 7)
        let center = tailOnRight(x) ? head + tail - width / 2 : head - tail + width / 2
        guard cat.floor > width else { return center }
        return min(max(center, width / 2), cat.floor - width / 2)
    }
}

private struct CatMenu: View {
    let cat: CatModel
    @Environment(NowPresentationCoordinator.self) private var presentation
    @State private var shown = false
    private let supporter = SupporterStore.shared

    static let spacing: CGFloat = 6

    static func width(page: CatMenuPage) -> CGFloat {
        let tiles: CGFloat = switch page {
        case .toys: CGFloat(CatItemKind.allCases.count + 1)
        case .furniture: CGFloat(CatFurniture.allCases.count + 1)
        case .colors(let kind): CGFloat(kind.variants + 1)
        }
        return tiles * 44 + (tiles - 1) * spacing + 20
    }

    var body: some View {
        VStack(spacing: 6) {
            Image("cat_name")
                .resizable()
                .interpolation(.none)
                .frame(width: 62, height: 14)
                .accessibilityHidden(true)
            HStack(alignment: .bottom, spacing: Self.spacing) {
                switch cat.menuPage {
                case .toys:
                    ForEach(CatItemKind.allCases.enumerated(), id: \.element) { index, kind in
                        tile(index) { cat.spawn(kind) } label: {
                            CatItemIcon(kind: kind, scale: kind == .wand ? 1 : 2)
                                .offset(y: kind == .ball ? -9 : 0)
                        }
                        .accessibilityLabel(Text(kind.label))
                    }
                    tile(CatItemKind.allCases.count) { cat.showPage(.furniture) } label: {
                        FurnitureFan()
                    }
                    .accessibilityLabel(Text("Möbel"))
                case .furniture:
                    backTile(to: .toys)
                    ForEach(CatFurniture.allCases.enumerated(), id: \.element) { index, kind in
                        furnitureTile(kind, index: index + 1)
                    }
                case .colors(let kind):
                    backTile(to: .furniture)
                    ForEach(0..<kind.variants, id: \.self) { variant in
                        colorTile(kind, variant: variant)
                    }
                }
            }
        }
        .onAppear { shown = true }
        .task(id: cat.menuPage) {
            guard (try? await Task.sleep(for: .seconds(6))) != nil else { return }
            if cat.isMenuOpen { cat.toggleMenu() }
        }
    }

    private func backTile(to page: CatMenuPage) -> some View {
        tile(0) { cat.showPage(page) } label: {
            Image("cat_back")
                .resizable()
                .interpolation(.none)
                .frame(width: 12, height: 21)
        }
        .accessibilityLabel(Text("Zurück"))
    }

    private func furnitureTile(_ kind: CatFurniture, index: Int) -> some View {
        let isLocked = !supporter.isSupporter
        let isPlaced = cat.placement[kind] != nil
        return tile(index) { open(kind, isLocked: isLocked) } label: {
            FurnitureIcon(kind: kind, variant: isPlaced ? cat.variant(of: kind) : 0)
                .saturation(isLocked ? 0 : 1)
                .opacity(isLocked ? 0.45 : 1)
                .overlay {
                    if isLocked {
                        Image("cat_locked")
                            .interpolation(.none)
                            .rotationEffect(.degrees(-45))
                    }
                }
        }
        .overlay(alignment: .topTrailing) {
            if isPlaced {
                Button { cat.remove(kind) } label: {
                    Image("cat_close")
                        .interpolation(.none)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .offset(x: 13, y: -13)
                .accessibilityLabel(Text("Entfernen"))
            }
        }
        .accessibilityLabel(Text(kind.label))
        .accessibilityValue(isLocked ? Text("Gesperrt") : Text(verbatim: ""))
        .accessibilityAddTraits(isPlaced ? .isSelected : [])
    }

    private func open(_ kind: CatFurniture, isLocked: Bool) {
        if isLocked {
            cat.toggleMenu()
            presentation.present(.support)
        } else {
            cat.showPage(.colors(kind))
        }
    }

    private func colorTile(_ kind: CatFurniture, variant: Int) -> some View {
        let isChosen = cat.placement[kind] != nil && cat.variant(of: kind) == variant
        return tile(variant + 1) { cat.choose(kind, variant: variant) } label: {
            ZStack(alignment: .topTrailing) {
                FurnitureIcon(kind: kind, variant: variant)
                    .frame(width: 44, height: 44)
                if isChosen {
                    Image("cat_heart")
                        .interpolation(.none)
                        .padding(5)
                }
            }
        }
        .accessibilityLabel(Text(kind.label))
        .accessibilityValue(Text(verbatim: "\(variant + 1)/\(kind.variants)"))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func tile<Label: View>(_ index: Int, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .frame(width: 44, height: 44)
                .background {
                    Image("cat_slot")
                        .resizable(capInsets: EdgeInsets(top: 6, leading: 6, bottom: 8, trailing: 6), resizingMode: .stretch)
                        .interpolation(.none)
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(shown ? 1 : 0.2, anchor: .bottom)
        .opacity(shown ? 1 : 0)
        .animation(.bouncy.delay(Double(index) * 0.05), value: shown)
    }
}

private struct FurnitureSprite: View {
    let kind: CatFurniture
    let variant: Int
    var swing = Angle.zero

    var body: some View {
        ZStack {
            Image(kind.image(variant))
                .interpolation(.none)
            if kind == .post {
                Image("cat_post_swing_\(variant)")
                    .interpolation(.none)
                    .rotationEffect(swing, anchor: UnitPoint(x: 0.5, y: 3 / kind.pixels.height))
            }
        }
    }
}

private struct FurnitureFan: View {
    var body: some View {
        ZStack {
            FurnitureSprite(kind: .post, variant: 0)
                .scaleEffect(0.42)
                .offset(y: -3)
            FurnitureSprite(kind: .bed, variant: 0)
                .scaleEffect(0.42)
                .rotationEffect(.degrees(-10), anchor: .bottom)
                .offset(x: -7, y: 7)
            FurnitureSprite(kind: .bowl, variant: 0)
                .scaleEffect(0.75)
                .rotationEffect(.degrees(12), anchor: .bottom)
                .offset(x: 10, y: 7)
        }
        .frame(width: 44, height: 44)
    }
}

private struct FurnitureIcon: View {
    let kind: CatFurniture
    let variant: Int

    var body: some View {
        let fit = min(34 / kind.pixels.width, 34 / kind.pixels.height)
        let scale = fit >= 1 ? fit.rounded(.down) : fit
        FurnitureSprite(kind: kind, variant: variant)
            .scaleEffect(scale)
            .frame(width: kind.pixels.width * scale, height: kind.pixels.height * scale)
    }
}

private struct CatBubble<Content: View>: View {
    let tailOnRight: Bool
    @ViewBuilder let content: Content
    @State private var shown = false

    var body: some View {
        content
            .padding(.horizontal, 5)
            .padding(.top, 4)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity)
            .background {
                Image("cat_bubble_small")
                    .resizable(capInsets: EdgeInsets(top: 3, leading: 3, bottom: 5, trailing: 9), resizingMode: .stretch)
                    .interpolation(.none)
                    .scaleEffect(x: tailOnRight ? 1 : -1)
            }
            .scaleEffect(shown ? 1 : 0.3, anchor: tailOnRight ? .bottomTrailing : .bottomLeading)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.bouncy) { shown = true } }
    }
}

private struct CatMenuBubble<Content: View>: View {
    let tailX: CGFloat
    let width: CGFloat
    @ViewBuilder let content: Content
    @State private var shown = false

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: width)
            .background {
                Image("cat_bubble_body")
                    .resizable(capInsets: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6), resizingMode: .stretch)
                    .interpolation(.none)
            }
            .overlay(alignment: .bottomLeading) {
                Image("cat_bubble_tail")
                    .interpolation(.none)
                    .offset(x: ((tailX - 7) / 2).rounded() * 2, y: 4)
            }
            .scaleEffect(shown ? 1 : 0.3, anchor: UnitPoint(x: tailX / width, y: 1))
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

struct PixelSprite: View {
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
