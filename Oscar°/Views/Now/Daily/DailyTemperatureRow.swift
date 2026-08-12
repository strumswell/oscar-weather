struct DailyTemperatureRow {
  let labelLow: Double
  let labelHigh: Double
  let barLow: Double
  let barHigh: Double
  let focusLow: Double?
  let focusHigh: Double?

  static func dailyOnly(low: Double, high: Double) -> DailyTemperatureRow {
    DailyTemperatureRow(
      labelLow: low,
      labelHigh: high,
      barLow: low,
      barHigh: high,
      focusLow: nil,
      focusHigh: nil
    )
  }
}
