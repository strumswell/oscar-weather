import SwiftUI
import Charts

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
                        
                        GroupBox(label: Text("Temperatur").padding(.bottom, 2)) {
                            let temperature = weather.forecast.hourly?.temperature_2m ?? []
                            let apparentTemperature = weather.forecast.hourly?.apparent_temperature ?? []
                            let temperatureUnit = weather.forecast.hourly_units?.temperature_2m ?? "°C"
                            TemperatureChart(
                                temperature: temperature,
                                apparentTemperature: apparentTemperature,
                                time: time,
                                unit: temperatureUnit
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        GroupBox(label: Text("Regen").padding(.bottom, 2)) {
                            let precipitation = weather.forecast.hourly?.precipitation ?? []
                            let precipitationUnit = weather.forecast.hourly_units?.precipitation ?? "mm"
                            PrecipitationChart(precipitation: precipitation, time: time, unit: precipitationUnit)
                                .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        GroupBox(label: Text("Luftfeuchtigkeit").padding(.bottom, 2)) {
                            let humidity = weather.forecast.hourly?.relativehumidity_2m ?? []
                            let humidityUnit = "%"
                            HumidityChart(humidity: humidity, time: time, unit: humidityUnit)
                                .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        GroupBox(label: Text("Wind").padding(.bottom, 2)) {
                            let windspeed10m = weather.forecast.hourly?.windspeed_10m ?? []
                            let windspeed80m = weather.forecast.hourly?.windspeed_80m ?? []
                            let windspeed120m = weather.forecast.hourly?.windspeed_120m ?? []
                            let windspeed180m = (weather.forecast.hourly?.windspeed_180m ?? []).map { $0 ?? 0 }
                            let winddirection10m = weather.forecast.hourly?.winddirection_10m ?? []
                            let windUnit = weather.forecast.hourly_units?.windspeed_10m ?? "km/h"
                            
                            WindChart(windspeed10m: windspeed10m, windspeed80m: windspeed80m, windspeed120m: windspeed120m, windspeed180m: windspeed180m, winddirection10m: winddirection10m, time: time, unit: windUnit)
                                .chartScrollPosition(x: $chartScrollPosition)
                        }
                        
                        GroupBox(label: Text("Luftdruck").padding(.bottom, 2)) {
                            let pressure = weather.forecast.hourly?.pressure_msl ?? []
                            let pressureUnit = "hPa"
                            PressureChart(pressure: pressure, time: time, unit: pressureUnit)
                                .chartScrollPosition(x: $chartScrollPosition)
                            HStack {
                                Text("Sinkender Luftdruck deutet auf schlechtes Wetter oder Stürme hin, steigender Luftdruck auf gutes Wetter oder Hochdruckgebiete.")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                                    .padding(.top, 1)
                                Spacer()
                            }
                        }
                        
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
                                unit: soilTempUnit
                            )
                            .chartScrollPosition(x: $chartScrollPosition)
                        }

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
                                unit: soilMoistureUnit
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
                        
                        GroupBox(label: Text("Referenz-Evapotranspiration (ET₀)").padding(.bottom, 2)) {
                            let et0 = weather.forecast.hourly?.et0_fao_evapotranspiration ?? []
                            let et0Unit = weather.forecast.hourly_units?.et0_fao_evapotranspiration ?? "mm"
                            ET0EvapotranspirationChart(et0: et0, time: time, unit: et0Unit)
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
}

struct TemperatureChart: View {
    var temperature: [Double]
    var apparentTemperature: [Double]
    var time: [Double]
    var unit: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(time.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("Temperatur (\(unit))", temperature[index]),
                        series: .value("Series", "Temperature")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.orange)
                    
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("Gefühlte Temperatur (\(unit))", apparentTemperature[index]),
                        series: .value("Series", "Apparent Temperature")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.red)
                }
                
                ForEach(dayChangeIndices(time: time), id: \.self) { index in
                    RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(
                            position: .topTrailing, spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                }
            }
            .chartForegroundStyleScale([String(localized: "Temperatur (\(unit))"): .orange, String(localized: "Gefühlte Temperatur (\(unit))"): .red])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 129600)
            .frame(height: 175)
        }
    }
}

struct PrecipitationChart: View {
    var precipitation: [Double]
    var time: [Double]
    var unit: String
    
    var body: some View {
        if precipitation.max() == 0 {
            ContentUnavailableView("Kein Regen", image: "icloud.slash", description: Text("Für die nächsten Tage wird kein Regen vorhergesagt."))
            .frame(height: 175)
        } else {
            VStack(alignment: .leading) {
                Chart {
                    ForEach(time.indices, id: \.self) { index in
                        BarMark(
                            x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                            y: .value("Niederschlag (\(unit))", precipitation[index])
                        )
                        .foregroundStyle(.blue)
                    }
                    
                    ForEach(dayChangeIndices(time: time), id: \.self) { index in
                        RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                            .foregroundStyle(.gray)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                            .annotation(
                                position: .topTrailing, spacing: 5,
                                overflowResolution: .init(
                                    x: .fit(to: .chart),
                                    y: .fit(to: .chart)
                                )
                            ) {
                                Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                    }
                }
                .chartForegroundStyleScale([String(localized: "Niederschlag (\(unit))"): .blue])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                        AxisGridLine()
                        AxisTick()
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let precipitation = value.as(Double.self) {
                                Text("\(precipitation, specifier: "%.1f")")
                            }
                        }
                        AxisGridLine()
                        AxisTick()
                    }
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 129600)
                .frame(height: 175)
            }
        }
    }
}

struct HumidityChart: View {
    var humidity: [Double]
    var time: [Double]
    var unit: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(time.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("Humidity", humidity[index]),
                        series: .value("Series", "Humidity")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
                }
                
                ForEach(dayChangeIndices(time: time), id: \.self) { index in
                    RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(
                            position: .topTrailing, spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                }
            }
            .chartForegroundStyleScale([String(localized: "Relative Luftfeuchtigkeit (\(unit))"): .green])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 129600)
            .frame(height: 175)
        }
    }
}

struct WindChart: View {
    var windspeed10m: [Double]
    var windspeed80m: [Double]
    var windspeed120m: [Double]
    var windspeed180m: [Double]
    var winddirection10m: [Double]
    var time: [Double]
    var unit: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(time.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("Wind 10m (\(unit))", windspeed10m[index]),
                        series: .value("Series", "10m")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal)
                    .symbol {
                        if index % 6 == 0 {
                            Image(systemName: "location.north.fill")
                                .resizable()
                                .frame(width: 10, height: 10)
                                .rotationEffect(.degrees(winddirection10m[index]))
                                .foregroundColor(.teal)
                        }
                    }

                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("Wind 80m (\(unit))", windspeed80m[index]),
                        series: .value("Series", "80m")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal.opacity(0.6))

                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("Wind 120m (\(unit))", windspeed120m[index]),
                        series: .value("Series", "120m")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal.opacity(0.4))

                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("Wind 180m (\(unit))", windspeed180m[index]),
                        series: .value("Series", "180m")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal.opacity(0.2))
                }
                
                ForEach(dayChangeIndices(time: time), id: \.self) { index in
                    RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(
                            position: .topTrailing, spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                }
            }
            .chartForegroundStyleScale([
                "10m (\(unit))": .teal,
                "80m (\(unit))": .teal.opacity(0.6),
                "120m (\(unit))": .teal.opacity(0.4),
                "180m (\(unit))": .teal.opacity(0.2)
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 129600)
            .frame(height: 200)
        }
    }
}

struct PressureChart: View {
    var pressure: [Double]
    var time: [Double]
    var unit: String
    
    var body: some View {
        VStack(alignment: .leading) {
            let minPressure = pressure.min() ?? 0
            let maxPressure = pressure.max() ?? 100
            let tickValues = calculateTicks(from: minPressure, to: maxPressure, count: 4)

            Chart {
                ForEach(time.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("Pressure", pressure[index]),
                        series: .value("Series", "Pressure")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.purple)
                }
                
                ForEach(dayChangeIndices(time: time), id: \.self) { index in
                    RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(
                            position: .topTrailing, spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                }
            }
            .chartForegroundStyleScale([String(localized: "Luftdruck (\(unit))"): .purple])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartYAxis {
                AxisMarks(values: tickValues) { value in
                    AxisValueLabel {
                        if let pressureValue = value.as(Double.self) {
                            Text("\(pressureValue, specifier: "%.0f")")
                        }
                    }
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartYScale(domain: minPressure...maxPressure)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 129600)
            .frame(height: 175)
        }
    }
}

struct SoilTemperatureChart: View {
    var soilTemp0cm: [Double?]
    var soilTemp6cm: [Double?]
    var soilTemp18cm: [Double?]
    var soilTemp54cm: [Double?]
    var time: [Double]
    var unit: String
    
    var body: some View {
        let filteredSoilTemp0cm = soilTemp0cm.compactMap { $0 }
        let filteredSoilTemp6cm = soilTemp6cm.compactMap { $0 }
        let filteredSoilTemp18cm = soilTemp18cm.compactMap { $0 }
        let filteredSoilTemp54cm = soilTemp54cm.compactMap { $0 }

        VStack(alignment: .leading) {
            Chart {
                ForEach(filteredSoilTemp0cm.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("0cm", filteredSoilTemp0cm[index]),
                        series: .value("Series", "Bodentemperatur 0cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown)
                    
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("6cm", filteredSoilTemp6cm[index]),
                        series: .value("Series", "Bodentemperatur 6cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown.opacity(0.6))
                    
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("18cm", filteredSoilTemp18cm[index]),
                        series: .value("Series", "Bodentemperatur 18cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown.opacity(0.4))
                    
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("54cm", filteredSoilTemp54cm[index]),
                        series: .value("Series", "Bodentemperatur 54cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown.opacity(0.2))
                }
                
                ForEach(dayChangeIndices(time: time), id: \.self) { index in
                    RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(
                            position: .topTrailing, spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                }
            }
            .chartForegroundStyleScale([
                "0cm (\(unit))": .brown,
                "6cm (\(unit))": .brown.opacity(0.6),
                "18cm (\(unit))": .brown.opacity(0.4),
                "54cm (\(unit))": .brown.opacity(0.2)
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 129600)
            .frame(height: 200)
        }
    }
}

struct SoilMoistureChart: View {
    var soilMoisture0_1cm: [Double?]
    var soilMoisture1_3cm: [Double?]
    var soilMoisture3_9cm: [Double?]
    var soilMoisture9_27cm: [Double?]
    var soilMoisture27_81cm: [Double?]
    var time: [Double]
    var unit: String
    
    var body: some View {
        let filteredSoilMoisture0_1cm = soilMoisture0_1cm.compactMap { $0 }
        let filteredSoilMoisture1_3cm = soilMoisture1_3cm.compactMap { $0 }
        let filteredSoilMoisture3_9cm = soilMoisture3_9cm.compactMap { $0 }
        let filteredSoilMoisture9_27cm = soilMoisture9_27cm.compactMap { $0 }
        let filteredSoilMoisture27_81cm = soilMoisture27_81cm.compactMap { $0 }
        
        VStack(alignment: .leading) {
            Chart {
                ForEach(filteredSoilMoisture0_1cm.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("0-1cm", filteredSoilMoisture0_1cm[index]),
                        series: .value("Series", "Bodenwassergehalt 0-1cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown)
                    
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("1-3cm", filteredSoilMoisture1_3cm[index]),
                        series: .value("Series", "Bodenwassergehalt 1-3cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown.opacity(0.6))
                    
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("3-9cm", filteredSoilMoisture3_9cm[index]),
                        series: .value("Series", "Bodenwassergehalt 3-9cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown.opacity(0.4))
                    
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("9-27cm", filteredSoilMoisture9_27cm[index]),
                        series: .value("Series", "Bodenwassergehalt 9-27cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown.opacity(0.2))
                    
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("27-81cm", filteredSoilMoisture27_81cm[index]),
                        series: .value("Series", "Bodenwassergehalt 27-81cm (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.brown.opacity(0.1))
                }
                
                ForEach(dayChangeIndices(time: time), id: \.self) { index in
                    RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(
                            position: .topTrailing, spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                }
            }
            .chartForegroundStyleScale([
                "0-1cm (\(unit))": .brown,
                "1-3cm (\(unit))": .brown.opacity(0.6),
                "3-9cm (\(unit))": .brown.opacity(0.4),
                "9-27cm (\(unit))": .brown.opacity(0.2),
                "27-81cm (\(unit))": .brown.opacity(0.1)
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 129600)
            .frame(height: 200)
        }
    }
}

struct ET0EvapotranspirationChart: View {
    var et0: [Double]
    var time: [Double]
    var unit: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart {
                ForEach(time.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))),
                        y: .value("ET0", et0[index]),
                        series: .value("Series", "ET0 FAO (\(unit))")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                }
                
                ForEach(dayChangeIndices(time: time), id: \.self) { index in
                    RuleMark(x: .value("Hour", Date(timeIntervalSince1970: TimeInterval(time[index]))))
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .annotation(
                            position: .topTrailing, spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            Text(dayAbbreviation(from: Date(timeIntervalSince1970: TimeInterval(time[index]))))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                }
            }
            .chartForegroundStyleScale([
                String(localized: "Referenz-Evapotranspiration (\(unit))"): .blue
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 129600)
            .frame(height: 175)
        }
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
