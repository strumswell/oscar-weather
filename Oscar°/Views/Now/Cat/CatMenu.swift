//
//  CatMenu.swift
//  Oscar°
//

import CoreMotion
import SwiftUI

struct CatMenu: View {
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

struct CatMenuBubble<Content: View>: View {
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
