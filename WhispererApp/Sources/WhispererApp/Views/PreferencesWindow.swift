import SwiftUI

struct PreferencesWindow: View {
    @ObservedObject var appState: AppState
    @ObservedObject var configManager: ConfigManager
    var hotkeyManager: HotkeyManager?
    var launchAtLoginManager: LaunchAtLoginManager

    var body: some View {
        TabView {
            PreferencesGeneralView(configManager: configManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PreferencesModelsView(configManager: configManager)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }

            PreferencesHotkeysView()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }

            PreferencesAppearanceView(configManager: configManager)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            PreferencesAdvancedView(
                configManager: configManager,
                launchAtLoginManager: launchAtLoginManager
            )
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 580, height: 500)
    }
}
