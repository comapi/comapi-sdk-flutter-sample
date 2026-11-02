// ============================================================================
// DOTDIGITAL PUSH PLUGIN - IOS IMPLEMENTATION (CMPCOMAPIFOUNDATION)
// ============================================================================
// This native plugin connects Flutter to the Dotdigital iOS SDK (CMPComapiFoundation)
// and Apple Push Notification service (APNs).
//
// HIGH LEVEL NARRATIVE:
// 1. SDK CONFIGURATION & INITIALIZATION (`initializeSdk`):
//    Configures `ComapiConfig` with `apiSpaceID` and the APNs environment.
//    Then initializes the shared singleton via `Comapi.initialiseSharedInstance()`.
// 2. APNS TOKEN REGISTRATION (`didRegisterForRemoteNotificationsWithDeviceToken`):
//    Apple delivers device token bytes in `didRegisterForRemoteNotificationsWithDeviceToken`.
//    The plugin converts the bytes into a 64-character lowercase hex string and
//    passes it to `client.setPushToken()`.
// 3. FOREGROUND NOTIFICATIONS (`willPresentNotification`):
//    Intercepts foreground pushes, forwards the payload to Flutter via `onPushReceived`,
//    and instructs UNUserNotificationCenter to present a banner and badge.
// 4. NOTIFICATION RESPONSE & CLICK TRACKING (`didReceiveResponse`):
//    When a user taps an APNs notification, the response is delivered to
//    `client.handle(notificationResponse:)`. This records click analytics in
//    Dotdigital Marketing, extracts `dd_deepLink` and `dd_data`, and sends them to Flutter.
// 5. SILENT BACKGROUND DATA PUSHES (`didReceiveRemoteNotification`):
//    Processes background pushes (`content-available: 1`) and forwards `dd_data`
//    to Flutter via `onSilentPushReceived` without user interruption.
// 6. CONTACT DISCOVERY (`updateUserEmail`):
//    Retrieves current `eTag` from `client.services.profile.getProfile()` and patches
//    the profile with `email`, linking the device to a contact in Dotdigital Marketing.
//
// ⚠️ SECURITY WARNING:
// Storing Shared Secrets in mobile application packages is UNSAFE in production.
// This example app supports client-side JWT generation solely for demonstration,
// sandbox evaluation, and documentation validation. In production environments,
// JWTs must be requested from an authenticated server-side API.
// ============================================================================

import Flutter
import UIKit
import UserNotifications
#if canImport(CMPComapiFoundation)
import CMPComapiFoundation
#endif

public class DotdigitalPushPlugin: NSObject, FlutterPlugin, FlutterApplicationLifeCycleDelegate, UNUserNotificationCenterDelegate {

    private var channel: FlutterMethodChannel
    private var cachedPushToken: String?
    private var currentEmail: String?
    private var initialTapEvent: [String: Any]?
    private var sessionChallengeReceived = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    /// Registers the plugin with the Flutter engine registrar.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.dotdigital.push/methods", binaryMessenger: registrar.messenger())
        let instance = DotdigitalPushPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)

        UNUserNotificationCenter.current().delegate = instance
    }

    /// Handles incoming Flutter method calls.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let apiSpaceId = args["apiSpaceId"] as? String, !apiSpaceId.isEmpty else {
                result(FlutterError(code: "INVALID_ARGS", message: "apiSpaceId is required", details: nil))
                return
            }

            if let email = args["contactEmail"] as? String, !email.isEmpty {
                self.currentEmail = email
            }

            let envArg = args["apnsEnvironment"] as? String
            initializeSdk(apiSpaceId: apiSpaceId, environmentOverride: envArg, result: result)

        case "requestNotificationPermissions":
            requestNotificationPermissions(result: result)

        case "getNotificationPermissionStatus":
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let status: String
                switch settings.authorizationStatus {
                case .notDetermined: status = "notDetermined"
                case .denied: status = "denied"
                case .authorized, .provisional: status = "authorized"
                default: status = "unknown"
                }
                DispatchQueue.main.async { result(status) }
            }

        case "openNotificationSettings":
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                result(false)
                return
            }
            DispatchQueue.main.async { UIApplication.shared.open(url, options: [:]) { success in result(success) } }

        case "registerPushToken":
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
                result(true)
            }

        case "startSession":
            startSession(result: result)

        case "endSession":
            endSession(result: result)

        case "updateUserEmail":
            guard let args = call.arguments as? [String: Any],
                  let email = args["email"] as? String, !email.isEmpty else {
                result(FlutterError(code: "INVALID_ARGS", message: "email cannot be empty", details: nil))
                return
            }
            self.currentEmail = email
            updateUserEmail(email: email, result: result)

        case "getPushToken":
            result(self.cachedPushToken)

        case "getSessionState":
            getSessionState(result: result)

        case "getInitialNotification":
            let event = self.initialTapEvent
            self.initialTapEvent = nil
            result(event)

        case "openDeepLink":
            guard let args = call.arguments as? [String: Any],
                  let urlString = args["url"] as? String, !urlString.isEmpty else {
                result(FlutterError(code: "INVALID_ARGS", message: "url cannot be empty", details: nil))
                return
            }
            let launchExternal = args["launchExternal"] as? Bool ?? true
            if launchExternal {
                let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = (!trimmed.contains("://") && (trimmed.lowercased().hasPrefix("www.") || trimmed.contains(".")))
                    ? "https://\(trimmed)"
                    : trimmed
                if let url = URL(string: normalized) {
                    DispatchQueue.main.async {
                        UIApplication.shared.open(url, options: [:]) { success in
                            result(success)
                        }
                    }
                } else {
                    result(false)
                }
            } else {
                result(true)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Configures and initializes the native `CMPComapiFoundation` client singleton.
    private func initializeSdk(apiSpaceId: String, environmentOverride: String?, result: @escaping FlutterResult) {
        #if canImport(CMPComapiFoundation)
        #if DEBUG
        let defaultEnvironment = "development"
        #else
        let defaultEnvironment = "production"
        #endif
        let apnsEnvironment = environmentOverride ?? defaultEnvironment
        guard apnsEnvironment == "development" || apnsEnvironment == "production" else {
            result(FlutterError(code: "INVALID_APNS_ENVIRONMENT", message: "APNs environment must be development or production", details: nil))
            return
        }

        let config = ComapiConfig()
            .setApiSpaceID(apiSpaceId)
            .setAuthDelegate(self)
            .setApi(APIConfiguration.production())

        _ = config.setApnsEnvironment(apnsEnvironment)

        #if DEBUG
        _ = config.setLogLevel(.debug)
        #else
        _ = config.setLogLevel(.warning)
        #endif

        if Comapi.initialiseSharedInstance(with: config) != nil {
            result(true)
        } else {
            result(FlutterError(code: "INITIALIZATION_FAILED", message: "Dotdigital SDK initialization failed", details: nil))
        }
        #else
        result(FlutterError(code: "SDK_UNAVAILABLE", message: "Dotdigital SDK is not linked", details: nil))
        #endif
    }

    /// Prompts user for notification permission via `UNUserNotificationCenter` and registers with APNs on approval.
    private func requestNotificationPermissions(result: @escaping FlutterResult) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                result(granted)
            }
        }
    }

    /// Starts an active push session with Dotdigital, resolving the challenge with the JWT token.
    private func startSession(result: @escaping FlutterResult) {
        #if canImport(CMPComapiFoundation)
        guard let client = Comapi.shared else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "SDK not initialized", details: nil))
            return
        }

        sessionChallengeReceived = false
        client.services.session.startSession(completion: { [weak self] in
            guard let self = self else { return }
            // Confirm APNs registration so the device token is available.
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            DispatchQueue.main.async {
                result(true)
            }
        }, failure: { [weak self] error in
            DispatchQueue.main.async {
                let nativeError = error as NSError?
                let underlying = nativeError?.userInfo[NSUnderlyingErrorKey] as? NSError
                var details: [String: Any] = ["challengeReceived": self?.sessionChallengeReceived ?? false]
                if let nativeError = nativeError {
                    details["domain"] = nativeError.domain
                    details["code"] = nativeError.code
                }
                if let underlying = underlying {
                    details["underlyingDomain"] = underlying.domain
                    details["underlyingCode"] = underlying.code
                }
                result(FlutterError(code: "START_SESSION_FAILED", message: error?.localizedDescription, details: details))
            }
        })
        #else
        result(true)
        #endif
    }

    /// Ends the session and removes its token from Dotdigital Marketing while keeping APNs registered.
    private func endSession(result: @escaping FlutterResult) {
        #if canImport(CMPComapiFoundation)
        guard let client = Comapi.shared else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "SDK not initialized", details: nil))
            return
        }

        if !client.isSessionSuccessfullyCreated {
            DispatchQueue.main.async {
                result(true)
            }
            return
        }
        client.services.session.endSession { res in
            DispatchQueue.main.async {
                if let error = res.error {
                    result(FlutterError(code: "END_SESSION_FAILED", message: error.localizedDescription, details: nil))
                } else if res.object?.boolValue != true {
                    result(FlutterError(code: "END_SESSION_FAILED", message: "Session was not ended", details: nil))
                } else {
                    result(true)
                }
            }
        }
        #else
        result(true)
        #endif
    }

    /// Patches the user profile with their email address using the required 2-step eTag flow.
    private func updateUserEmail(email: String, result: FlutterResult?) {
        #if canImport(CMPComapiFoundation)
          guard let client = Comapi.shared,
              let profileId = client.profileID,
              client.isSessionSuccessfullyCreated else {
            result?(FlutterError(code: "NO_ACTIVE_SESSION", message: "Session is not active", details: nil))
            return
        }

        // Step 1: Retrieve profile to get latest eTag
        client.services.profile.getProfile(profileID: profileId) { getRes in
            if let error = getRes.error {
                DispatchQueue.main.async {
                    result?(FlutterError(code: "GET_PROFILE_FAILED", message: error.localizedDescription, details: nil))
                }
                return
            }

            guard let eTag = getRes.eTag else {
                DispatchQueue.main.async {
                    result?(FlutterError(code: "NO_ETAG", message: "No eTag returned from getProfile", details: nil))
                }
                return
            }

            // Step 2: Patch profile with eTag and email address
            client.services.profile.patchProfile(
                profileID: profileId,
                attributes: ["email": email],
                eTag: eTag
            ) { patchRes in
                DispatchQueue.main.async {
                    if let patchError = patchRes.error {
                        result?(FlutterError(code: "PATCH_PROFILE_FAILED", message: patchError.localizedDescription, details: nil))
                    } else {
                        result?(true)
                    }
                }
            }
        }
        #else
        result?(true)
        #endif
    }

    /// Returns the current active session state, profile ID, APNs token, and linked email.
    private func getSessionState(result: @escaping FlutterResult) {
        #if canImport(CMPComapiFoundation)
        guard let client = Comapi.shared else {
            result([
                "isSessionActive": false,
                "profileId": nil,
                "pushToken": self.cachedPushToken,
                "currentEmail": self.currentEmail
            ])
            return
        }

        let isActive = client.isSessionSuccessfullyCreated
        let profileId = client.profileID

        result([
            "isSessionActive": isActive,
            "profileId": profileId,
            "pushToken": self.cachedPushToken,
            "currentEmail": self.currentEmail
        ])
        #else
        result([
            "isSessionActive": false,
            "profileId": nil,
            "pushToken": self.cachedPushToken,
            "currentEmail": self.currentEmail
        ])
        #endif
    }

    // MARK: - FlutterApplicationLifeCycleDelegate Remote Notifications

    /// Intercepts device token registration from iOS, converts token bytes to a 64-char lowercase hex string,
    /// and passes it to `CMPComapiClient.setPushToken()`.
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert deviceToken bytes to 64 character lowercase hexadecimal string
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.cachedPushToken = tokenString
        DispatchQueue.main.async {
            self.channel.invokeMethod("onPushTokenReceived", arguments: tokenString)
        }

        #if canImport(CMPComapiFoundation)
        if let client = Comapi.shared {
            client.set(pushToken: tokenString) { success, error in
                if let error = error {
                    print("[DotdigitalPush] Failed to register APNs token with Dotdigital: \(error.localizedDescription)")
                } else {
                    print("[DotdigitalPush] Successfully registered APNs token with Dotdigital")
                }
            }
        }
        #endif
    }

    /// Handles remote notification registration failures.
    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[DotdigitalPush] Failed to register for remote notifications: \(error.localizedDescription)")
    }

    /// Intercepts silent background data pushes (`content-available: 1`) and delivers `dd_data` to Flutter.
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
        let ddData = userInfo["dd_data"] as? [String: Any]
        let event: [String: Any] = [
            "customData": ddData ?? [:],
            "rawPayload": userInfo,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]

        DispatchQueue.main.async {
            self.channel.invokeMethod("onSilentPushReceived", arguments: event)
        }
        completionHandler(.newData)
        return true
    }

    /// Extracts a URL or deep link from `dd_deepLink`, `dd_data`, or top-level userInfo keys.
    private static func extractUrl(from dict: [AnyHashable: Any]) -> String? {
        let keys = ["url", "deepLink", "deeplink", "link", "uri"]
        if let ddDeepLink = dict["dd_deepLink"] as? [AnyHashable: Any] {
            for k in keys {
                if let v = ddDeepLink[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        if let ddData = dict["dd_data"] as? [AnyHashable: Any] {
            for k in keys {
                if let v = ddData[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        for k in keys {
            if let v = dict[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Intercepts foreground pushes arriving while the app is active, forwards to Flutter,
    /// and instructs iOS to present a foreground banner and play a sound.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let userInfo = content.userInfo

        let deepLinkUrl = Self.extractUrl(from: userInfo)
        let customData = userInfo["dd_data"] as? [String: Any]

        let pushEvent: [String: Any] = [
            "title": content.title,
            "body": content.body,
            "deepLinkUrl": deepLinkUrl as Any,
            "customData": customData as Any,
            "rawPayload": userInfo,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]

        DispatchQueue.main.async {
            self.channel.invokeMethod("onPushReceived", arguments: pushEvent)
        }

        if #available(iOS 14.0, *) {
            completionHandler([.banner, .badge, .sound])
        } else {
            completionHandler([.alert, .badge, .sound])
        }
    }

    /// Intercepts notification tap responses, passes them to `CMPComapiClient.handle(notificationResponse:)`
    /// to record Dotdigital click analytics, and delivers the deep link and custom data to Flutter.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        #if canImport(CMPComapiFoundation)
        if let client = Comapi.shared {
            client.handle(notificationResponse: response) { [weak self] didHandleLink, data in
                guard let self = self else {
                    completionHandler()
                    return
                }

                let url = Self.extractUrl(from: data) ?? Self.extractUrl(from: userInfo)
                let customData = (data["dd_data"] as? [String: Any]) ?? (userInfo["dd_data"] as? [String: Any])

                let event: [String: Any] = [
                    "url": url as Any,
                    "customData": customData as Any,
                    "isClickRecorded": true,
                    "isDeepLinkCalled": didHandleLink,
                    "isDdOriginated": ComapiClient.isDotdigitalOriginated(userInfo),
                    "rawPayload": data
                ]

                self.initialTapEvent = event
                DispatchQueue.main.async {
                    self.channel.invokeMethod("onNotificationTapped", arguments: event)
                }
                completionHandler()
            }
            return
        }
        #endif

        // Fallback if client wasn't ready
        let url = Self.extractUrl(from: userInfo)
        let customData = userInfo["dd_data"] as? [String: Any]

        let event: [String: Any] = [
            "url": url as Any,
            "customData": customData as Any,
            "isClickRecorded": false,
            "isDeepLinkCalled": false,
            "isDdOriginated": true,
            "rawPayload": userInfo
        ]
        self.initialTapEvent = event
        DispatchQueue.main.async {
            self.channel.invokeMethod("onNotificationTapped", arguments: event)
        }
        completionHandler()
    }
}

#if canImport(CMPComapiFoundation)
extension DotdigitalPushPlugin: AuthenticationDelegate {
    public func client(_ client: ComapiClient, didReceive challenge: AuthenticationChallenge, completion continueWithToken: @escaping (String?) -> Void) {
        sessionChallengeReceived = true
        DispatchQueue.main.async {
            self.channel.invokeMethod("onAuthenticationChallenge", arguments: ["nonce": challenge.nonce]) { result in
                if let token = result as? String, !token.isEmpty {
                    continueWithToken(token)
                } else {
                    continueWithToken(nil)
                }
            }
        }
    }
}
#endif
