import Foundation
import UIKit
import UserNotifications

/// Manages APNs registration, token storage, and incoming push notification handling.
/// Set as UNUserNotificationCenter delegate and wired into UIApplicationDelegate for token callbacks.
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {

    static let shared = PushNotificationManager()

    @Published var deviceToken: String?
    @Published var permissionGranted = false

    private override init() {
        super.init()
    }

    // MARK: - Registration

    /// Request notification permission and register for remote notifications.
    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { [weak self] granted, error in
            if let error {
                print("[Push] Authorization error: \(error.localizedDescription)")
            }
            Task { @MainActor in
                self?.permissionGranted = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - Token Handling

    /// Called from AppDelegate when APNs returns a device token.
    func didRegisterForRemoteNotifications(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        print("[Push] Device token: \(token)")

        // Store token in Supabase
        Task {
            await storeTokenInSupabase(token)
        }
    }

    /// Called from AppDelegate when APNs registration fails.
    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[Push] Registration failed: \(error.localizedDescription)")
    }

    // MARK: - Token Storage

    private func storeTokenInSupabase(_ token: String) async {
        guard let userId = SupabaseService.shared.currentUser?.id else {
            print("[Push] No authenticated user, deferring token storage")
            return
        }

        do {
            // Upsert: insert or update on conflict (user_id, token)
            try await SupabaseService.shared.client
                .from("device_tokens")
                .upsert([
                    "user_id": userId.uuidString,
                    "token": token,
                    "platform": "ios"
                ], onConflict: "user_id,token")
                .execute()

            print("[Push] Token stored for user \(userId)")
        } catch {
            print("[Push] Failed to store token: \(error.localizedDescription)")
        }
    }

    /// Re-register the current device token after login.
    /// Call this after authentication completes.
    func registerTokenAfterLogin() {
        guard let token = deviceToken else { return }
        Task {
            await storeTokenInSupabase(token)
        }
    }

    /// Remove the current device's token on logout.
    func removeTokenOnLogout() async {
        guard let token = deviceToken,
              let userId = SupabaseService.shared.currentUser?.id else { return }

        do {
            try await SupabaseService.shared.client
                .from("device_tokens")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("token", value: token)
                .execute()

            print("[Push] Token removed for user \(userId)")
        } catch {
            print("[Push] Failed to remove token: \(error.localizedDescription)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    /// Handle notification when app is in foreground — show it as a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap — navigate to the relevant conversation.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let type = userInfo["type"] as? String,
           let conversationId = userInfo["conversation_id"] as? String {
            print("[Push] Tapped notification: type=\(type), conversation=\(conversationId)")

            // Post a notification so the UI can navigate
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .pushNotificationTapped,
                    object: nil,
                    userInfo: [
                        "type": type,
                        "conversation_id": conversationId
                    ]
                )
            }
        }

        completionHandler()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
