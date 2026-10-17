// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import AuraCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppState.shared.flush()
            AppState.shared.stopAllAudio()
            AppState.shared.audio.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppState.shared

    var body: some Scene {
        Window("AURA — Equalizer", id: "equalizer") {
            EqualizerWindow(model: model)
                .task { await model.restore() }
                .preferredColorScheme(.dark)
                .onAppear { NSApp.activate() }
        }
        .defaultSize(width: 1_120, height: 800)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(model: model) }

        MenuBarExtra("AURA · Audio EQ", image: model.menuIconAssetName) {
            MenuBarView(model: model)
                .task { await model.restore() }
                .preferredColorScheme(.dark)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model).padding(24).frame(width: 520)
                .preferredColorScheme(.dark)
        }
    }
}
