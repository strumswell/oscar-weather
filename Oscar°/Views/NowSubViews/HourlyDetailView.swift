import SwiftUI

struct HourlyDetailView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(\.presentationMode) var presentationMode
    @State private var chartScrollPosition = Date.now
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        let time = weather.forecast.hourly?.time ?? []
                        let maxTimeRange = getMaxTimeRange(time)
                        
                        // Temperature Chart
                        GroupBox(label: Text("Temperatur").padding(.bottom, 2)) {
                            let temperature = weather.forecast.hourly?.temperature_2m ?? []
                            let apparentTemperature = weather.forecast.hourly?.apparent_temperature ?? []
                            let temperatureUnit = weather.forecast.hourly_units?.temperature_2m ?? "°C"
                            TemperatureChart(
                                temperature: temperature,
                                apparentTemperature: apparentTemperature,
                                time: time,
                                unit: temperatureUnit,
                                maxTimeRange: maxTimeRange
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        // Precipitation Chart
                        GroupBox(label: Text("Regen").padding(.bottom, 2)) {
                            let precipitation = weather.forecast.hourly?.precipitation ?? []
                            let precipitationUnit = weather.forecast.hourly_units?.precipitation ?? "mm"
                            PrecipitationChart(
                                precipitation: precipitation,
                                time: time,
                                unit: precipitationUnit,
                                maxTimeRange: maxTimeRange
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        // Humidity Chart
                        GroupBox(label: Text("Luftfeuchtigkeit").padding(.bottom, 2)) {
                            let humidity = weather.forecast.hourly?.relativehumidity_2m ?? []
                            let humidityUnit = "%"
                            HumidityChart(
                                humidity: humidity,
                                time: time,
                                unit: humidityUnit,
                                maxTimeRange: maxTimeRange
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        // Wind Chart
                        GroupBox(label: Text("Wind").padding(.bottom, 2)) {
                            let windspeed10m = weather.forecast.hourly?.windspeed_10m ?? []
                            let windspeed80m = weather.forecast.hourly?.windspeed_80m ?? []
                            let windspeed120m = weather.forecast.hourly?.windspeed_120m ?? []
                            let windspeed180m = (weather.forecast.hourly?.windspeed_180m ?? []).map { $0 ?? 0 }
                            let winddirection10m = weather.forecast.hourly?.winddirection_10m ?? []
                            let windUnit = weather.forecast.hourly_units?.windspeed_10m ?? "km/h"
                            
                            WindChart(
                                windspeed10m: windspeed10m,
                                windspeed80m: windspeed80m,
                                windspeed120m: windspeed120m,
                                windspeed180m: windspeed180m,
                                winddirection10m: winddirection10m,
                                time: time,
                                unit: windUnit,
                                maxTimeRange: maxTimeRange
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        // Pressure Chart
                        GroupBox(label: Text("Luftdruck").padding(.bottom, 2)) {
                            let pressure = weather.forecast.hourly?.pressure_msl ?? []
                            let pressureUnit = "hPa"
                            PressureChart(
                                pressure: pressure,
                                time: time,
                                unit: pressureUnit,
                                maxTimeRange: maxTimeRange
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                            HStack {
                                Text("Sinkender Luftdruck deutet auf schlechtes Wetter oder Stürme hin, steigender Luftdruck auf gutes Wetter oder Hochdruckgebiete.")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                                    .padding(.top, 1)
                                Spacer()
                            }
                        }
                        
                        // Soil Temperature Chart
                        GroupBox(label: Text("Bodentemperatur").padding(.bottom, 2)) {
                            let soilTemp0cm = weather.forecast.hourly?.soil_temperature_0cm ?? []
                            let soilTemp6cm = weather.forecast.hourly?.soil_temperature_6cm ?? []
                            let soilTemp18cm = weather.forecast.hourly?.soil_temperature_18cm ?? []
                            let soilTemp54cm = weather.forecast.hourly?.soil_temperature_54cm ?? []
                            let soilTempUnit = weather.forecast.hourly_units?.soil_temperature_0cm ?? "°C"
                            
                            SoilTemperatureChart(
                                soilTemp0cm: soilTemp0cm,
                                soilTemp6cm: soilTemp6cm,
                                soilTemp18cm: soilTemp18cm,
                                soilTemp54cm: soilTemp54cm,
                                time: time,
                                unit: soilTempUnit,
                                maxTimeRange: maxTimeRange
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        // Soil Moisture Chart
                        GroupBox(label: Text("Bodenwassergehalt").padding(.bottom, 2)) {
                            let soilMoisture0_1cm = weather.forecast.hourly?.soil_moisture_0_1cm ?? []
                            let soilMoisture1_3cm = weather.forecast.hourly?.soil_moisture_1_3cm ?? []
                            let soilMoisture3_9cm = weather.forecast.hourly?.soil_moisture_3_9cm ?? []
                            let soilMoisture9_27cm = weather.forecast.hourly?.soil_moisture_9_27cm ?? []
                            let soilMoisture27_81cm = weather.forecast.hourly?.soil_moisture_27_81cm ?? []
                            let soilMoistureUnit = weather.forecast.hourly_units?.soil_moisture_0_1cm ?? "m³/m³"
                            
                            SoilMoistureChart(
                                soilMoisture0_1cm: soilMoisture0_1cm,
                                soilMoisture1_3cm: soilMoisture1_3cm,
                                soilMoisture3_9cm: soilMoisture3_9cm,
                                soilMoisture9_27cm: soilMoisture9_27cm,
                                soilMoisture27_81cm: soilMoisture27_81cm,
                                time: time,
                                unit: soilMoistureUnit,
                                maxTimeRange: maxTimeRange
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                            HStack {
                                Text("Durchschnittlicher Wassergehalt des Bodens als volumetrisches Mischungsverhältnis in verschiedenen Tiefen.")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                                    .padding(.top, 1)
                                Spacer()
                            }
                        }
                        
                        // ET0 Evapotranspiration Chart
                        GroupBox(label: Text("Referenz-Evapotranspiration (ET₀)").padding(.bottom, 2)) {
                            let et0 = weather.forecast.hourly?.et0_fao_evapotranspiration ?? []
                            let et0Unit = weather.forecast.hourly_units?.et0_fao_evapotranspiration ?? "mm"
                            ET0EvapotranspirationChart(
                                et0: et0,
                                time: time,
                                unit: et0Unit,
                                maxTimeRange: maxTimeRange
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                            HStack {
                                Text("ET₀ ist die Referenz-Evapotranspiration eines gut bewässerten Grasfeldes und dient zur Schätzung des Bewässerungsbedarfs von Pflanzen.")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                                    .padding(.top, 1)
                                Spacer()
                            }
                        }
                        
                    }
                    .padding()
                }
            }
            .navigationBarTitle(Text("Stündliche Details"), displayMode: .inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing, content: {
                    Button(String(localized: "Fertig"), action: {
                        presentationMode.wrappedValue.dismiss()
                        UIApplication.shared.playHapticFeedback()
                    })
                })
            })
        }
    }
    
    private func getMaxTimeRange(_ time: [Double]) -> ClosedRange<Date> {
        guard let start = time.first, let end = time.last else {
            return Date.now...Date.now.addingTimeInterval(86400)
        }
        return Date(timeIntervalSince1970: start)...Date(timeIntervalSince1970: end)
    }
}

func dayChangeIndices(time: [Double]) -> [Int] {
    var indices: [Int] = []
    let calendar = Calendar.current
    for index in 1..<time.count {
        let previousDate = Date(timeIntervalSince1970: TimeInterval(time[index - 1]))
        let currentDate = Date(timeIntervalSince1970: TimeInterval(time[index]))
        if !calendar.isDate(previousDate, inSameDayAs: currentDate) {
            indices.append(index)
        }
    }
    return indices
}

func dayAbbreviation(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "E"
    return formatter.string(from: date)
}

func calculateTicks(from minValue: Double, to maxValue: Double, count: Int) -> [Double] {
    let step = (maxValue - minValue) / Double(count - 1)
    return stride(from: minValue, through: maxValue, by: step).map { $0 }
}
