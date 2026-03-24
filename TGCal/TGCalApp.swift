import SwiftUI
import UIKit
import UserNotifications

@main
struct TGCalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showSplash = true
    @StateObject private var store = TGCalStore()

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environmentObject(store)

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                guard showSplash else { return }
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
            }
            .onAppear {
                if UserDefaults.standard.bool(forKey: "reminders_enabled") {
                    NotificationService.shared.requestPermission()
                }
                WidgetDataService.updateNextFlight(from: store.months)

                // Register for push notifications
                PushNotificationManager.shared.requestPermissionAndRegister()
            }
        }
    }
}

// MARK: - AppDelegate for APNs token callbacks

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set push notification delegate
        UNUserNotificationCenter.current().delegate = PushNotificationManager.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}

private struct SplashScreenView: View {
    @State private var iconAppeared = false

    var body: some View {
        ZStack {
            TGTheme.backgroundGradient
            .ignoresSafeArea()

            VStack(spacing: 16) {
                AppIconView()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: TGTheme.splashIconShadow, radius: 16, x: 0, y: 10)
                    .scaleEffect(iconAppeared ? 1 : 0.92)
                    .opacity(iconAppeared ? 1 : 0.85)

                Text("TGCal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 26)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                iconAppeared = true
            }
        }
    }
}

private struct AppIconView: View {
    var body: some View {
        if let appIcon = UIImage.primaryAppIcon {
            Image(uiImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(TGTheme.iconTileFill)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(TGTheme.indigo)
            }
        }
    }
}

private extension UIImage {
    static var primaryAppIcon: UIImage? {
        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primary["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else {
            return nil
        }

        return UIImage(named: iconName)
    }
}
