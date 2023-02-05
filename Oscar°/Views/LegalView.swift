//
//  LegalView.swift
//  LegalView
//
//  Created by Philipp Bolte on 28.08.21.
//

import SwiftUI

struct LegalView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Über")) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(5)
                            Link("Datenschutz", destination: URL(string: "https://oscars.love/")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Image(systemName: "figure.wave")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(5)
                            Link("Impressum", destination: URL(string: "https://oscars.love/")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                    }
                    
                    Section(header: Text("Services")) {
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.green)
                                .cornerRadius(5)
                            Link("OpenMeteo", destination: URL(string: "https://open-meteo.com/en")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.green)
                                .cornerRadius(5)
                            Link("Deutscher Wetterdienst", destination: URL(string: "https://www.dwd.de")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Image(systemName: "map.fill")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.green)
                                .cornerRadius(5)
                            Link("Rainviewer", destination: URL(string: "https://www.rainviewer.com")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                    }
                    
                    Section(header: Text("Sonstiges")) {
                        HStack {
                            Image(systemName: "chart.pie.fill")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.red)
                                .cornerRadius(5)
                            Link("swiftui-charts", destination: URL(string: "https://github.com/spacenation/swiftui-charts")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Image(systemName: "network")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.red)
                                .cornerRadius(5)
                            Link("Alamofire", destination: URL(string: "https://github.com/Alamofire/Alamofire")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.red)
                                .cornerRadius(5)
                            Link("SPIndicator", destination: URL(string: "https://github.com/ivanvorobei/SPIndicator")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Image(systemName: "heart.fill")
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .background(Color.red)
                                .cornerRadius(5)
                            Link("Icons by Hosein Bagheri", destination: URL(string: "https://ui8.net/hosein_bagheri/products/3d-weather-icons40")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                    }
                    
                    Section(header: Text("Datenquellen")) {
                        HStack {
                            Link("ICON (Deutscher Wetterdienst)", destination: URL(string: "https://www.dwd.de")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Link("GFS (NOAA)", destination: URL(string: "https://www.nco.ncep.noaa.gov/pmb/products/gfs/")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Link("Arpege & Arome (MeteoFrance)", destination: URL(string: "https://meteofrance.com")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {
                            Link("IFS (ECMWF)", destination: URL(string: "https://www.ecmwf.int/en/forecasts/datasets/open-data")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {

                            Link("JMA (JMA)", destination: URL(string: "https://www.jma.go.jp/jma/en/Activities/nwp.html")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {

                            Link("MET Nordic (MET Norway)", destination: URL(string: "https://github.com/metno/NWPdocs/wiki/MET-Nordic-dataset")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                        HStack {

                            Link("GEM (Canadian Weather Service)", destination: URL(string: "https://en.wikipedia.org/wiki/Global_Environmental_Multiscale_Model")!)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .font(.body)
                        }
                    }
                    
                    HStack {
                        Spacer()
                        VStack {
                            Text("Oscar° Weather")
                                .font(.body)
                                .bold()
                            Text("by Philipp Bolte")
                                .font(.caption)
                                .padding(.bottom, 2)
                            Text("In Gedenken an Kater Oscar von der Katzenfreiheit")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text("* 17.04.02 – † 03.08.21")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 1)
                }
            }
            .navigationBarTitle(Text("Rechtliches"), displayMode: .inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing, content: {
                    Button("Fertig", action: {
                        presentationMode.wrappedValue.dismiss()
                        UIApplication.shared.playHapticFeedback()
                    })
                })
            })
        }
    }
}

struct LegalView_Previews: PreviewProvider {
    static var previews: some View {
        LegalView()
    }
}
