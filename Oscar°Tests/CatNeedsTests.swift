import Foundation
import Testing
@testable import Oscar_

struct CatNeedsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000_000)

    @Test
    func awayTimeMakesTheCatHungryButRested() {
        let needs = CatNeeds(food: 0.8, fun: 0.8, energy: 0.1, updated: start)
        let later = needs.aged(to: start.addingTimeInterval(8 * 3600))
        #expect(abs(later.food - 0.3) < 0.001)
        #expect(later.fun == 0)
        #expect(later.energy == 1)
        #expect(later.updated == start.addingTimeInterval(8 * 3600))
    }

    @Test
    func moodFollowsTheLowestNeed() {
        #expect(CatNeeds(food: 1, fun: 1, energy: 0.1).mood(isSleepTime: false) == .sleepy)
        #expect(CatNeeds(food: 1, fun: 1, energy: 1).mood(isSleepTime: true) == .sleepy)
        #expect(CatNeeds(food: 0.2, fun: 0.1, energy: 1).mood(isSleepTime: false) == .hungry)
        #expect(CatNeeds(food: 1, fun: 0.1, energy: 1).mood(isSleepTime: false) == .bored)
        #expect(CatNeeds(food: 1, fun: 1, energy: 1).mood(isSleepTime: false) == .happy)
    }

    @Test
    func furniturePacksTogetherAndDropsWhenTheShelfShrinks() {
        let placement: [CatFurniture: CGFloat] = [.bed: 0.12, .post: 0.6, .bowl: 0.9]
        for width in stride(from: CGFloat(400), through: 10, by: -7) {
            let spots = CatFurniture.layout(placement, width: width)
            let edges = spots.map { kind, x in (x - kind.pixels.width / 2, x + kind.pixels.width / 2) }.sorted { $0.0 < $1.0 }
            #expect(edges.allSatisfy { $0.0 >= -0.001 && $0.1 <= width + 0.001 })
            #expect(zip(edges, edges.dropFirst()).allSatisfy { $0.1 <= $1.0 + 0.001 })
        }
        #expect(Set(CatFurniture.layout(placement, width: 120).keys) == [.bowl, .bed, .post])
        #expect(Set(CatFurniture.layout(placement, width: 100).keys) == [.bowl, .bed])
        #expect(Set(CatFurniture.layout(placement, width: 60).keys) == [.bowl])
        #expect(CatFurniture.layout(placement, width: 10).isEmpty)
    }
}
