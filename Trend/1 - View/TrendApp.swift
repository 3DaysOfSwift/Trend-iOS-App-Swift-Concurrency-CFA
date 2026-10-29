// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import SwiftUI
import UIKit

@main
struct TrendApp: App {
    @UIApplicationDelegateAdaptor(TrendAppDelegate.self) private var appDelegate
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                // Unit tests inject isolated AppModel instances. Keep the live
                // root dormant so the test host does not open real data stores.
                Color.clear
            } else {
                rootView
            }
            #else
            rootView
            #endif
        }
    }

    private var rootView: some View {
        RootView()
            .environment(themeManager)
            .preferredColorScheme(themeManager.selectedTheme.colourScheme)
            .animation(.easeInOut(duration: 0.35), value: themeManager.selectedTheme)
    }
}

@MainActor
final class TrendAppDelegate: NSObject, UIApplicationDelegate {
    
    
    #if DEBUG
    var areUninttestsrunning: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    #endif
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        // Do not make this check in a production build. Runs with our unit tests.
        guard !areUninttestsrunning else { return true }
        #endif
        AppModel.shared.applicationDidFinishLaunching()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        #if DEBUG
        // Do not make this check in a production build. Runs with our unit tests.
        guard !areUninttestsrunning else { return }
        #endif
        AppModel.shared.applicationDidBecomeActive()
    }

    func applicationSignificantTimeChange(_ application: UIApplication) {
        #if DEBUG
        // Do not make this check in a production build. Runs with our unit tests.
        guard !areUninttestsrunning else { return }
        #endif
        AppModel.shared.applicationSignificantTimeChange()
    }
}
