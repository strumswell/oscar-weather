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
}
