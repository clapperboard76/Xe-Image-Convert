//
//  Xe_Image_ConvertApp.swift
//  Xe-Image Convert
//
//  Created by Myles Conti on 28/4/2025.
//

import SwiftUI
import Sparkle

// Process entry point. A hidden `--convert` flag runs one headless conversion
// (see XeConvertCLI) and exits before any GUI/Sparkle startup; otherwise the
// normal SwiftUI app launches. This is the surface the Application Tester harness
// drives to verify output files match the requested settings.
@main
enum AppEntry {
    static func main() {
        if CommandLine.arguments.contains("--convert") {
            XeConvertCLI.run(CommandLine.arguments)
        }
        Xe_Image_ConvertApp.main()
    }
}

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

// MARK: - Headless conversion CLI
//
//   "Xe-Image Convert.app/Contents/MacOS/Xe-Image Convert" \
//       --convert <input> <output> --format jpg --aspect square \
//       --resolution r1080p --scaling fill [--quality 0.8] [--letterbox]
//
// Runs the same ContentView.convert pipeline the GUI uses, prints a one-line
// JSON result to stdout, and exits.
enum XeConvertCLI {
    static func run(_ args: [String]) -> Never {
        _ = NSApplication.shared  // initialise AppKit for offscreen drawing

        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }

        guard let i = args.firstIndex(of: "--convert"), i + 2 < args.count else {
            emit(ok: false, output: nil, error: "usage: --convert <input> <output> [--format …]")
            exit(2)
        }
        let input = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath)
        let output = URL(fileURLWithPath: (args[i + 2] as NSString).expandingTildeInPath)

        guard let format = ImageFormat(rawValue: value("--format") ?? "jpg") else {
            emit(ok: false, output: nil, error: "unknown --format"); exit(2)
        }
        guard let aspect = AspectOption(rawValue: value("--aspect") ?? "original") else {
            emit(ok: false, output: nil, error: "unknown --aspect"); exit(2)
        }
        guard let resolution = ResolutionOption(rawValue: value("--resolution") ?? "original") else {
            emit(ok: false, output: nil, error: "unknown --resolution"); exit(2)
        }
        guard let scaling = ScalingMode(rawValue: value("--scaling") ?? "fill") else {
            emit(ok: false, output: nil, error: "unknown --scaling"); exit(2)
        }
        let quality = Double(value("--quality") ?? "0.8") ?? 0.8
        let letterbox = args.contains("--letterbox")

        guard FileManager.default.fileExists(atPath: input.path) else {
            emit(ok: false, output: nil, error: "input not found: \(input.path)"); exit(2)
        }

        let settings = ConvertSettings(
            format: format, aspect: aspect, resolution: resolution,
            scalingMode: scaling, removeLetterboxing: letterbox, quality: quality
        )

        if let error = ContentView().convert(inputURL: input, outputURL: output, settings: settings) {
            emit(ok: false, output: output.path, error: error)
            exit(1)
        }
        emit(ok: true, output: output.path, error: nil)
        exit(0)
    }

    private static func emit(ok: Bool, output: String?, error: String?) {
        var parts = ["\"tool\":\"xe-image-convert\"", "\"ok\":\(ok)"]
        if let output { parts.append("\"output\":\"\(escape(output))\"") }
        if let error { parts.append("\"error\":\"\(escape(error))\"") }
        FileHandle.standardOutput.write(Data(("{" + parts.joined(separator: ",") + "}\n").utf8))
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
