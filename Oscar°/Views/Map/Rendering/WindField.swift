import Foundation

struct WindField {
    let tiles: [WindFieldTile]

    func sample(latitude: Double, longitude: Double) -> SIMD2<Double>? {
        for tile in tiles {
            let b = tile.bounds
            guard latitude >= b.south, latitude <= b.north,
                  longitude >= b.west, longitude <= b.east else { continue }
            let tx = (longitude - b.west) / max(1e-6, b.east - b.west)
            let ty = (b.north - latitude) / max(1e-6, b.north - b.south)
            if let result = bilinear(tile: tile, tx: tx, ty: ty) { return result }
        }
        return nil
    }

    private func bilinear(tile: WindFieldTile, tx: Double, ty: Double) -> SIMD2<Double>? {
        let gw = tile.gridWidth
        let gh = tile.gridHeight
        let fx = max(0, min(1, tx)) * Double(gw - 1)
        let fy = max(0, min(1, ty)) * Double(gh - 1)
        let x0 = Int(fx), y0 = Int(fy)
        let x1 = min(gw - 1, x0 + 1)
        let y1 = min(gh - 1, y0 + 1)
        let sx = fx - Double(x0)
        let sy = fy - Double(y0)

        let i00 = y0 * gw + x0, i10 = y0 * gw + x1
        let i01 = y1 * gw + x0, i11 = y1 * gw + x1

        guard let u00 = tile.u[i00], let u10 = tile.u[i10],
              let u01 = tile.u[i01], let u11 = tile.u[i11],
              let v00 = tile.v[i00], let v10 = tile.v[i10],
              let v01 = tile.v[i01], let v11 = tile.v[i11] else { return nil }

        let w00 = (1 - sx) * (1 - sy), w10 = sx * (1 - sy)
        let w01 = (1 - sx) * sy,       w11 = sx * sy
        return SIMD2(
            u00 * w00 + u10 * w10 + u01 * w01 + u11 * w11,
            v00 * w00 + v10 * w10 + v01 * w01 + v11 * w11
        )
    }
}
