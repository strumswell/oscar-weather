// Colormap stops mirrored from the server palettes, shared by app, widgets and watch.
import Foundation

enum ServerColormapStops {
    static let radar: [(dbz: Double, hex: Int)] = [
        (1, 0x99ffff),
        (5.5, 0x32ffff), (10, 0x00caca), (14.5, 0x009934), (19, 0x4cbf19),
        (23.5, 0x98cb03), (28, 0xcce603), (32.5, 0xffff00), (37, 0xffc400),
        (41.5, 0xff8901), (46, 0xff0000), (50.5, 0xb40000), (55, 0x4848ff),
        (60, 0x0000c9), (65, 0x990199),
        (75, 0xfe33ff),
    ]

    static let temperature: [Int] = [
        0x3f49b3, 0x4263d8, 0x3f7df1, 0x3896f9, 0x2bb1ef, 0x1ec9d8, 0x20dbbf,
        0x25eca5, 0xd2e92a, 0xe3d630, 0xf0c331, 0xf7ad2b, 0xf89525, 0xf77b1a,
        0xed610e, 0xe14906, 0xd13503, 0xbe2400, 0xa91500,
    ]

    static let wind: [Int] = [
        0xf7fcff, 0xd2ddf2, 0xadbfe5, 0x9a9edc, 0x8a7fcf, 0x795eb5, 0x693e9a,
        0x581d77, 0x4a0059,
    ]

    static let pressure: [(hpa: Double, hex: Int)] = [
        (950, 0x001261), (960, 0x023175), (970, 0x055189), (980, 0x2575a1),
        (990, 0x64a0be), (1000, 0xa3c7d9), (1005, 0xc3dae5), (1010, 0xe0e6e9),
        (1013, 0xece5e0), (1016, 0xeed9cd), (1020, 0xe6c4b0), (1025, 0xdbaa8d),
        (1030, 0xd0906b), (1040, 0xbb602d), (1050, 0x892606), (1060, 0x590008),
    ]

    static let stormCellSteps: [(hex: Int, label: LocalizedStringResource)] = [
        (0x00CACA, "Leicht"),
        (0xFFFF00, "Mäßig"),
        (0xFF0000, "Stark"),
        (0xFE33FF, "Extrem"),
    ]

    static func stormCellStep(_ millimetersPerHour: Double) -> Int {
        [2.0, 10, 50].firstIndex { millimetersPerHour < $0 } ?? 3
    }
}
