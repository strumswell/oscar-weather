import SwiftUI

/// Every app icon and sticker, in columns that drift down endlessly at their
/// own pace. Decorative: the copy on the canvas says what it shows.
struct IconWall: View {
    private struct Item: Identifiable {
        let asset: String
        let isSticker: Bool
        var id: String { asset }
    }

    private static let columnCount = 5
    private static let spacing = 12.0

    /// A sticker after every second icon, dealt round-robin into the columns.
    private static let columns: [[Item]] = {
        let icons = AppIconCatalog.sections.flatMap(\.icons).map(\.previewAssetName)
        let stickers = MemberCardStickerCatalog.assets
        let items = icons.enumerated().flatMap { index, icon in
            var pair = [Item(asset: icon, isSticker: false)]
            if index % 2 == 1, index / 2 < stickers.count {
                pair.append(Item(asset: stickers[index / 2], isSticker: true))
            }
            return pair
        }
        return (0..<columnCount).map { column in
            items.enumerated().filter { $0.offset % columnCount == column }.map(\.element)
        }
    }()

    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(Self.columns.indices, id: \.self) { column in
                IconWallColumn(speed: 14 + 7 * Double((column * 3) % Self.columnCount), initialOffset: -Double(column * 37)) {
                    ForEach(Self.columns[column]) { item in
                        if item.isSticker {
                            Image(item.asset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                        } else {
                            Image(item.asset)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(.rect(cornerRadius: 14))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
