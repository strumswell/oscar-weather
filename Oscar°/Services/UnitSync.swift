import Foundation
import WatchConnectivity

@MainActor
final class UnitSync: NSObject, WCSessionDelegate {
    static let shared = UnitSync()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #if os(iOS)
        NotificationCenter.default.addObserver(forName: .watchSettingsDidChange, object: nil, queue: .main) { _ in
            Task { @MainActor in UnitSync.shared.push() }
        }
        #endif
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        Task { @MainActor in self.push() }
        #else
        apply(session.receivedApplicationContext)
        #endif
    }

    #if os(iOS)
    private func push() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        var context: [String: Any] = SettingService.unitStorageValues
        context["favoriteStationIDs"] = SettingService.shared.favoriteStationIDs
        try? session.updateApplicationContext(context)
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #else
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    nonisolated private func apply(_ context: [String: Any]) {
        let values = context.compactMapValues { $0 as? String }
        let favorites = context["favoriteStationIDs"] as? [String]
        Task { @MainActor in
            SettingService.shared.apply(unitValues: values)
            if let favorites, favorites != SettingService.shared.favoriteStationIDs {
                SettingService.shared.favoriteStationIDs = favorites
            }
        }
    }
    #endif
}
