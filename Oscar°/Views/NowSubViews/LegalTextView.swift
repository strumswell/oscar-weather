//
//  LegalTextView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import SwiftUI

struct LegalTextView: View {
    @State private var isLegalSheetPresented = false

    var body: some View {
        HStack {
            Spacer()
            Image(systemName: "info.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundColor(Color(UIColor.label))
            Text("Rechtliche\nInformationen")
                .foregroundColor(Color(UIColor.label))
                .font(.system(size: 10))
                .bold()
            Spacer()
        }
        .padding(.top)
        .padding(.bottom, 50)
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
        .onTapGesture {
            UIApplication.shared.playHapticFeedback()
            isLegalSheetPresented.toggle()
        }
        .sheet(isPresented: $isLegalSheetPresented) {
            LegalView()
        }
    }
}

#Preview {
    LegalTextView()
}
