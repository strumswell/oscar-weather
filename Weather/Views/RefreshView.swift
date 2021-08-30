//
//  RefreshView.swift
//  RefreshView
//
//  Created by Philipp Bolte on 14.08.21.
//  Thanks to https://prafullkumar77.medium.com/how-to-making-pure-swiftui-pull-to-refresh-b497d3639ee5

import SwiftUI
import CoreHaptics
import SPIndicator

struct RefreshView: View {
    var coordinateSpace: CoordinateSpace
    var nowViewModel: NowViewModel

    @State var refresh: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            if (geo.frame(in: coordinateSpace).midY > 50) {
                Spacer()
                    .onAppear {
                        if refresh == false {
                            nowViewModel.update()
                            nowViewModel.dispatchGroup.notify(queue: DispatchQueue.main, execute: {
                                if (nowViewModel.updateDidFinish) {
                                    SPIndicator.present(title: "Aktualisiert", preset: .done, haptic: .success)
                                } else {
                                    SPIndicator.present(title: "Fehlgeschlagen", preset: .error, haptic: .error)
                                }
                                nowViewModel.updateDidFinish = true // reset for next refresh
                                refresh = false
                            })
                        }
                        refresh = true
                    }
            }
            ZStack(alignment: .center) {
                if refresh {
                    ProgressView("Aktualisiere...")
                }
            }.frame(width: geo.size.width)
        }.padding(.top, -50)
    }
}
