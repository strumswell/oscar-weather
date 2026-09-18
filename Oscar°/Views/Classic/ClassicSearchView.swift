//
//  ClassicSearchView.swift
//  Oscar°
//
//  The iOS 6 "add city" screen: a dark gradient bar with a white search
//  field next to "Abbrechen", and bold result rows on white. Picking a row
//  saves the city and closes the screen.
//

import SwiftUI

struct ClassicSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Components.Schemas.Location] = []
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.gray)
                    TextField("", text: $query)
                        .focused($isFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .foregroundStyle(.black)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray)
                        }
                        .accessibilityLabel(Text("Löschen"))
                    }
                }
                .font(.custom("HelveticaNeue", fixedSize: 17))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.white, in: .capsule)
                Button {
                    dismiss()
                } label: {
                    Text("Abbrechen")
                        .font(.custom("HelveticaNeue-Bold", fixedSize: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(LinearGradient(colors: [Color(white: 0.4), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            )

            List(results, id: \.id) { result in
                Button {
                    CityService.shared.addCity(searchResult: result)
                    Haptics.impact()
                    dismiss()
                } label: {
                    Text(verbatim: [result.displayName, result.country].compactMap { $0 }.joined(separator: ", "))
                        .font(.custom("HelveticaNeue-Bold", fixedSize: 20))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .frame(height: 44)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.white)
            .environment(\.colorScheme, .light)
        }
        .background(.white)
        .onAppear { isFocused = true }
        .task(id: query) {
            guard !query.isEmpty else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = (try? await APIClient.shared.getGeocodeSearchResult(name: query))?.results ?? []
        }
    }
}
