//
//  Brand.swift
//  Xe-Image Convert
//
//  Xe-Image Convert brand colours — single source of truth used across all views.
//

import SwiftUI
import AppKit

extension Color {
    enum brand {
        static let background  = Color(red: 11/255,  green: 12/255,  blue: 15/255)
        static let surface     = Color(red: 19/255,  green: 20/255,  blue: 26/255)
        static let surface2    = Color(red: 26/255,  green: 28/255,  blue: 36/255)
        static let textPrimary = Color(red: 234/255, green: 236/255, blue: 240/255)
        static let textMuted   = Color(red: 160/255, green: 166/255, blue: 184/255)
        static let textFaint   = Color(red: 122/255, green: 128/255, blue: 144/255)
        static let xenonBlue   = Color(red: 110/255, green: 168/255, blue: 216/255)
        static let orange      = Color(red: 195/255, green: 123/255, blue: 54/255)
        static let border      = Color(red: 36/255,  green: 38/255,  blue: 48/255)
    }

    // Top-level alias so existing call sites (HelpView, etc.) keep working.
    static let xenonBlue = Color.brand.xenonBlue
}

/// Renders the app icon from the asset catalogue at any size.
/// Always reflects the current built icon — never a cached/running-app version.
struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: size, height: size)
    }
}
