import Foundation

struct MemberCardStickerPlacement: Codable, Identifiable, Equatable {
    let id: UUID
    let assetName: String
    var xRatio: Double
    var yRatio: Double
    var scale: Double
    var rotation: Double
    var zIndex: Double

    init(
        id: UUID = UUID(),
        assetName: String,
        xRatio: Double,
        yRatio: Double,
        scale: Double = 1,
        rotation: Double = 0,
        zIndex: Double = 0
    ) {
        self.id = id
        self.assetName = assetName
        self.xRatio = xRatio
        self.yRatio = yRatio
        self.scale = scale
        self.rotation = rotation
        self.zIndex = zIndex
    }
}
