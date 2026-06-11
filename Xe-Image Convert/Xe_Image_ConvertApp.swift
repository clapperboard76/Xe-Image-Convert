//
//  Xe_Image_ConvertApp.swift
//  Xe-Image Convert
//
//  Created by Myles Conti on 28/4/2025.
//

import SwiftUI
import Sparkle

@main
struct Xe_Image_ConvertApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup("Xe-Image Convert") {
            ContentView()
        }
        .defaultSize(width: 420, height: 580)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Xe-Image Convert") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Xe-Image Convert",
                        .credits: NSAttributedString(
                            string: "A free image conversion utility by Xenon Post.\nxenon-post.com",
                            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                        )
                    ])
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.updater.checkForUpdates()
                }
                .disabled(!updaterController.updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .help) {
                Button("Xe-Image Convert Help") {
                    NSWorkspace.shared.open(URL(string: "https://xenon-post.com")!)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}
