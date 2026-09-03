import Foundation
import OpenAPIRuntime

extension NotificationSettingsManager {
    enum PatchResult {
        case success
        case notFound
        case failure
    }

    struct SentSubscriptionState: Codable, Equatable {
        let locationLat: Double
        let locationLon: Double
        let locationName: String
        let timezone: String
        let language: String
        let timeFormat: String
        let rainAlertsEnabled: Bool
        let weatherAlertsEnabled: Bool
        let liveRainStatusEnabled: Bool
        let apnsEnvironment: APNsEnvironment
    }

    func performSubscriptionSync(forceRegister: Bool) async {
        guard let token = keychain.load(key: cachedDeviceTokenKey), !token.isEmpty else {
            notificationLogger.info("Lifecycle: subscription sync skipped; missing cached device token")
            return
        }

        let apnsEnvironment = APNsEnvironment.current()

        notificationLogger.info("Lifecycle: subscription sync started; forceRegister=\(forceRegister, privacy: .public) apnsEnvironment=\(apnsEnvironment.rawValue, privacy: .public) enabled=\(self.enabled, privacy: .public) rainAlerts=\(self.rainAlertsEnabled, privacy: .public) weatherAlerts=\(self.weatherAlertsEnabled, privacy: .public)")

        locationService.update()
        let currentLocation = await locationService.getLocation()
        let outboundCoordinates = LocationService.outboundCoordinate(currentLocation.coordinates)
        let cityName = currentLocation.name.isEmpty ? "Current Location" : currentLocation.name

        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        let language = languageCode.lowercased().hasPrefix("de") ? "de" : "en"

        var patchBody: [String: any Sendable] = [
            "locationLat": outboundCoordinates.latitude,
            "locationLon": outboundCoordinates.longitude,
            "locationName": cityName,
            "timezone": TimeZone.current.identifier,
            "language": language,
            "timeFormat": SettingService.resolvedTimeFormatAPIValue,
            "apnsEnvironment": apnsEnvironment.rawValue,
        ]
        patchBody.merge(notificationSettingsPayload()) { _, new in new }

        var registrationBody = patchBody
        registrationBody["deviceToken"] = token

        let currentState = SentSubscriptionState(
            locationLat: outboundCoordinates.latitude,
            locationLon: outboundCoordinates.longitude,
            locationName: cityName,
            timezone: TimeZone.current.identifier,
            language: language,
            timeFormat: SettingService.resolvedTimeFormatAPIValue,
            rainAlertsEnabled: rainAlertsEnabled,
            weatherAlertsEnabled: weatherAlertsEnabled,
            liveRainStatusEnabled: liveRainStatusEnabled,
            apnsEnvironment: apnsEnvironment
        )

        let lastSentToken = keychain.load(key: lastSentDeviceTokenKey)
        let lastSentState = loadLastSentSubscriptionState()
        let lastSentAPNsEnvironment = loadLastSentAPNsEnvironment() ?? lastSentState?.apnsEnvironment
        let registrationCompleted = UserDefaults.standard.bool(forKey: installationRegistrationCompletedKey)
        let shouldRegister = forceRegister
            || !registrationCompleted
            || keychain.load(key: subscriptionKey) == nil
            || keychain.load(key: apiKeyKey) == nil
            || lastSentAPNsEnvironment != apnsEnvironment
            || lastSentToken != token

        if shouldRegister {
            let reason: String
            if forceRegister {
                reason = "forced"
            } else if !registrationCompleted {
                reason = "installationRegistrationIncomplete"
            } else if keychain.load(key: subscriptionKey) == nil || keychain.load(key: apiKeyKey) == nil {
                reason = "missingCredentials"
            } else if lastSentAPNsEnvironment != apnsEnvironment {
                reason = "apnsEnvironmentChanged"
            } else {
                reason = "deviceTokenChanged"
            }
            notificationLogger.info("Lifecycle: subscription sync choosing register path; reason=\(reason, privacy: .public)")
            await register(body: registrationBody, token: token, state: currentState)
            return
        }

        guard lastSentState != currentState else {
            notificationLogger.info("Lifecycle: subscription sync skipped; outbound state unchanged")
            return
        }

        switch await patchSettings(patchBody, token: token, state: currentState) {
        case .success:
            notificationLogger.info("Lifecycle: subscription sync patch succeeded")
        case .notFound:
            notificationLogger.info("Lifecycle: subscription sync patch returned notFound; retrying with register")
            await register(body: registrationBody, token: token, state: currentState)
        case .failure:
            notificationLogger.error("Lifecycle: subscription sync patch failed")
        }
    }

    func register(body: [String: any Sendable], token: String, state: SentSubscriptionState) async {
        guard let payload = try? OpenAPIObjectContainer(unvalidatedValue: body.mapValues { $0 as (any Sendable)? })
        else { return }

        notificationLogger.info("Lifecycle: subscription register request started; payload=\(self.loggablePayload(from: body), privacy: .public)")

        do {
            let output = try await oscarNotifications.registerNotifications(
                .init(body: .json(.init(additionalProperties: payload))))
            let registerResponse: Components.Schemas.NotificationRegisterResponse
            switch output {
            case .ok(let ok):
                registerResponse = try ok.body.json
            case .created(let created):
                registerResponse = try created.body.json
            case .undocumented(let statusCode, _):
                notificationLogger.error("Lifecycle: subscription register request failed; status=\(statusCode, privacy: .public)")
                return
            }
            keychain.save(key: subscriptionKey, value: registerResponse.subscriptionId)
            keychain.save(key: apiKeyKey, value: registerResponse.apiKey)
            keychain.save(key: lastSentDeviceTokenKey, value: token)
            persistLastSentSubscriptionState(state)
            UserDefaults.standard.set(true, forKey: installationRegistrationCompletedKey)
            notificationLogger.info("Lifecycle: subscription register request succeeded; subscriptionIdLength=\(registerResponse.subscriptionId.count, privacy: .public)")
            // A register creates a new subscription row: a previously synced
            // push-to-start token belongs to the old one — re-send it.
            if let latest = UserDefaults.standard.string(forKey: latestLiveActivityPushToStartTokenKey) {
                UserDefaults.standard.set(latest, forKey: pendingLiveActivityPushToStartTokenKey)
                UserDefaults.standard.removeObject(forKey: latestLiveActivityPushToStartTokenKey)
            }
            await flushPendingLiveActivityTokens()
        } catch {
            notificationLogger.error("Lifecycle: subscription register request threw error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func patchSettings(_ body: [String: any Sendable], token: String, state: SentSubscriptionState) async -> PatchResult {
        guard let subscriptionId = keychain.load(key: subscriptionKey),
              keychain.load(key: apiKeyKey) != nil,
              let payload = try? OpenAPIObjectContainer(unvalidatedValue: body.mapValues { $0 as (any Sendable)? })
        else {
            return .notFound
        }

        notificationLogger.info("Lifecycle: subscription patch request started; payload=\(self.loggablePayload(from: body), privacy: .public)")

        do {
            let output = try await oscarNotifications.patchNotificationSettings(
                .init(path: .init(subscriptionId: subscriptionId), body: .json(.init(additionalProperties: payload))))
            switch output {
            case .ok, .noContent:
                keychain.save(key: lastSentDeviceTokenKey, value: token)
                persistLastSentSubscriptionState(state)
                notificationLogger.info("Lifecycle: subscription patch request succeeded")
                await flushPendingLiveActivityTokens()
                return .success
            case .undocumented(let statusCode, _) where statusCode == 404:
                keychain.delete(key: subscriptionKey)
                keychain.delete(key: apiKeyKey)
                notificationLogger.info("Lifecycle: subscription patch request returned 404; cleared stored credentials")
                return .notFound
            case .undocumented(let statusCode, _):
                notificationLogger.error("Lifecycle: subscription patch request failed; status=\(statusCode, privacy: .public)")
                return .failure
            }
        } catch {
            notificationLogger.error("Lifecycle: subscription patch request threw error=\(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    func loadLastSentSubscriptionState() -> SentSubscriptionState? {
        guard let data = UserDefaults.standard.data(forKey: lastSentStateKey) else {
            return nil
        }

        return try? JSONDecoder().decode(SentSubscriptionState.self, from: data)
    }

    func loadLastSentAPNsEnvironment() -> APNsEnvironment? {
        guard let rawValue = UserDefaults.standard.string(forKey: lastSentAPNsEnvironmentKey) else {
            return nil
        }

        return APNsEnvironment(rawValue: rawValue)
    }

    func persistLastSentSubscriptionState(_ state: SentSubscriptionState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        UserDefaults.standard.set(data, forKey: lastSentStateKey)
        UserDefaults.standard.set(state.apnsEnvironment.rawValue, forKey: lastSentAPNsEnvironmentKey)
    }

    func loggablePayload(from body: [String: any Sendable]) -> String {
        var sanitizedBody = body
        if let deviceToken = sanitizedBody["deviceToken"] as? String {
            sanitizedBody["deviceToken"] = redactedDeviceToken(deviceToken)
        }

        guard JSONSerialization.isValidJSONObject(sanitizedBody),
              let data = try? JSONSerialization.data(withJSONObject: sanitizedBody, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return String(describing: sanitizedBody)
        }

        return json
    }

    func redactedDeviceToken(_ token: String) -> String {
        guard token.count > 12 else { return "<redacted len=\(token.count)>" }
        let prefix = token.prefix(8)
        let suffix = token.suffix(4)
        return "\(prefix)...\(suffix) (len=\(token.count))"
    }
}
