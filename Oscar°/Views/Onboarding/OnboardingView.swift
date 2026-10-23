//
//  OnboardingView.swift
//  Oscar°
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = ScreenshotMode.onboardingStep ?? .welcome
    @State private var tourPage = OnboardingTourPage.staged ?? .forecast
    @State private var radarGrids: Task<[[UInt8]], Never>?
    private let coordinator = OnboardingCoordinator.shared
    private let locationService = LocationService.shared

    var body: some View {
        GeometryReader { proxy in
            content(size: proxy.size, insets: proxy.safeAreaInsets)
        }
        .onChange(of: step, initial: true) { _, step in
            coordinator.frosted = step != .finale
        }
        .onAppear {
            if radarGrids == nil {
                radarGrids = Task { await OnboardingMapStage.buildGrids() }
            }
        }
        .onDisappear { coordinator.frosted = false }
    }

    private func content(size: CGSize, insets: EdgeInsets) -> some View {
        let layout = OnboardingLayout(size: size, insets: insets)
        let showsSky = layout.isPad ? step != .finale : step == .welcome || step == .tour
        return ZStack {
            if step == .finale {
                OnboardingFrost()
                    .transition(.opacity)
            } else {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if showsSky {
                OnboardingSky(layout: layout, isWindowed: step == .tour, showsCard: layout.isPad && step != .welcome) {
                    if step == .tour {
                        OnboardingFeatureStage(page: tourPage, radarGrids: radarGrids)
                            .id(tourPage)
                            .transition(.onboardingSlide(reduceMotion: reduceMotion))
                    }
                }
                .transition(.opacity)
            }

            stepContent
                .id(step)
                .transition(.onboardingSlide(reduceMotion: reduceMotion))
                .zIndex(1)
        }
        .environment(\.onboardingLayout, layout)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep { advance(to: .tour) }
        case .tour:
            OnboardingTourStep(page: $tourPage) {
                advance(to: .afterTour(locationService: locationService))
            }
        case .location:
            OnboardingLocationStep { granted in
                advance(to: granted ? .afterLocationResolved(locationService: locationService) : .manualLocation)
            }
        case .manualLocation:
            OnboardingManualLocationStep {
                advance(to: .afterLocationResolved(locationService: locationService))
            }
        case .notifications:
            OnboardingNotificationsStep { advance(to: .afterNotifications) }
        case .crashReports:
            OnboardingCrashReportsStep { advance(to: .finale) }
        case .finale:
            OnboardingFinaleStep { coordinator.complete() }
        }
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.smooth(duration: 0.6)) {
            step = next
        }
    }
}

private struct OnboardingSky<Stage: View>: View {
    let layout: OnboardingLayout
    let isWindowed: Bool
    let showsCard: Bool
    @ViewBuilder var stage: Stage

    var body: some View {
        let shrinks = isWindowed && !layout.isPad
        let frame = shrinks ? layout.heroFrame : layout.fullBleed

        ZStack {
            ZStack {
                OnboardingSceneView(scene: .day)
                if !layout.isPad {
                    stage
                }
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(.rect(cornerRadius: shrinks ? OnboardingMetrics.cornerRadius : 0))
            .shadow(color: .black.opacity(shrinks ? 0.3 : 0), radius: 24, y: 12)
            .catDash()
            .position(x: frame.midX, y: frame.midY)
            .animation(.smooth(duration: 0.7), value: isWindowed)

            if showsCard {
                let card = layout.cardFrame
                RoundedRectangle(cornerRadius: OnboardingMetrics.cornerRadius)
                    .fill(.regularMaterial)
                    .frame(width: card.width, height: card.height)
                    .shadow(color: .black.opacity(0.25), radius: 30, y: 16)
                    .position(x: card.midX, y: card.midY)
                    .transition(.opacity)
            }

            if layout.isPad, isWindowed {
                let window = layout.heroFrame
                ZStack(alignment: .top) {
                    OnboardingSceneView(scene: .day)
                    stage
                }
                .frame(width: window.width, height: window.height, alignment: .top)
                .clipShape(.rect(cornerRadius: OnboardingMetrics.cornerRadius))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                .catDash()
                .position(x: window.midX, y: window.midY)
                .transition(.opacity)
            }
        }
    }
}

private struct OnboardingFrost: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .light)
            .overlay(Color.black.opacity(0.18))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

#Preview {
    OnboardingView()
        .environment(Weather.mock)
        .environment(Location())
        .preferredColorScheme(.dark)
}
