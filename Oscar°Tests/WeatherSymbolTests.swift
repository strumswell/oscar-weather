import Testing
@testable import Oscar_

struct WeatherSymbolTests {
    @Test
    func clearSkyFollowsDayAndNight() {
        #expect(WeatherSymbol.sfSymbol(weathercode: 0, isDay: true) == "sun.max.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 0, isDay: false) == "moon.stars.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 2, isDay: false) == "cloud.moon.fill")
    }

    @Test
    func precipitationCodesMapToTheirOwnSymbols() {
        #expect(WeatherSymbol.sfSymbol(weathercode: 53) == "cloud.drizzle.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 65) == "cloud.heavyrain.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 73) == "cloud.snow.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 95) == "cloud.bolt.rain.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 123) == "cloud.fill")
    }

    @Test
    func radarRainLiftsADrySkyCode() {
        #expect(WeatherSymbol.sfSymbol(weathercode: 0, isDay: 1, isRaining: true, precipitation: 0) == "cloud.drizzle.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 0, isDay: 1, isRaining: false, precipitation: 0.3) == "cloud.drizzle.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 0, isDay: 0, isRaining: false, precipitation: 0) == "moon.stars.fill")
    }

    @Test
    func dryRadarKeepsSnowAndThunderCodesPlain() {
        #expect(WeatherSymbol.sfSymbol(weathercode: 73, isDay: 1, isRaining: false, precipitation: 0) == "cloud.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 73, isDay: 1, isRaining: true, precipitation: 0) == "cloud.snow.fill")
        #expect(WeatherSymbol.sfSymbol(weathercode: 95, isDay: 1, isRaining: true, precipitation: 0) == "cloud.bolt.rain.fill")
    }
}
