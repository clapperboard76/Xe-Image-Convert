//
//  HelpView.swift
//  Xe-Image Convert
//
//  Created by Myles Conti on 28/4/2025.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            HStack(spacing: 12) {
                AppIconView(size: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Xe-Image Convert — Help")
                        .font(.system(size: 15, weight: .semibold))
                    Text("by Xenon Post")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.brand.textFaint)
                }

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.brand.background)

            Divider()

            // ── Content ─────────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    HelpSection(title: "Getting Started") {
                        HelpStep(
                            number: "1",
                            title: "Add your images",
                            detail: "Drag images or folders directly onto the drop zone at the top of the window, or click the drop zone to open a file browser. You can add individual files or entire folders — Xe-Image Convert will find all supported images inside."
                        )
                        HelpStep(
                            number: "2",
                            title: "Choose your settings",
                            detail: "Select an output format, aspect ratio, resolution, and quality using the controls below the image strip."
                        )
                        HelpStep(
                            number: "3",
                            title: "Choose a save location",
                            detail: "Click Change… next to Save to and pick a destination folder. Xe-Image Convert defaults to your Pictures folder."
                        )
                        HelpStep(
                            number: "4",
                            title: "Convert",
                            detail: "Press Convert Images. A progress bar shows the current file being processed. When done, a summary tells you how many images were converted successfully."
                        )
                    }

                    HelpSection(title: "Supported Formats") {
                        HelpTable(rows: [
                            ("Input", "JPG, PNG, TIFF, GIF, BMP, HEIC, WebP, PSD, JP2"),
                            ("Output", "JPG, PNG, TIFF, WebP"),
                        ])
                        Text("You can drop a folder and Xe-Image Convert will find all compatible images inside it automatically.")
                            .helpBodyStyle()
                    }

                    HelpSection(title: "Output Settings") {
                        HelpEntry(
                            icon: "doc.fill",
                            title: "Format",
                            detail: "Choose the output file format. JPG and WebP support lossy compression controlled by the Quality slider. PNG and TIFF are lossless."
                        )
                        HelpEntry(
                            icon: "aspectratio",
                            title: "Aspect Ratio",
                            detail: "Crop the image to a standard ratio — 1:1, 4:3, 16:9, 9:16, 3:2, 2:3, 2:1, or 2.4:1. Select Original to leave the dimensions unchanged."
                        )
                        HelpEntry(
                            icon: "arrow.up.left.and.arrow.down.right",
                            title: "Scaling",
                            detail: "Fill crops to the exact ratio, trimming the edges. Fit letterboxes the image inside the ratio with transparent padding."
                        )
                        HelpEntry(
                            icon: "square.resize",
                            title: "Resolution",
                            detail: "Scale the longest edge to 4K (3840 px), 1080p (1920 px), 2000 px, 1000 px, or 500 px. Original leaves the pixel dimensions unchanged."
                        )
                        HelpEntry(
                            icon: "rectangle.slash",
                            title: "Remove Letterboxing",
                            detail: "Automatically detects and crops black bars from the top, bottom, or sides of an image — useful when working with broadcast or cinema footage stills."
                        )
                        HelpEntry(
                            icon: "slider.horizontal.3",
                            title: "Quality",
                            detail: "Appears when JPG or WebP is selected. Sets the compression level from 10% (smallest file) to 100% (best quality). 80% is a good balance for most images."
                        )
                    }

                    HelpSection(title: "Selecting & Anchor Points") {
                        Text("Click a thumbnail to select it (highlighted in blue). Shift-click to select a range. Selected images share a crop anchor point — the white dot you can drag around the thumbnail.")
                            .helpBodyStyle()
                        Text("The anchor point controls *where* the crop is taken from when using Fill mode. Drag it to the subject of your image so the most important area is always kept in frame.")
                            .helpBodyStyle()
                        Text("Use Remove Selected to delete images from the queue without deleting the original files.")
                            .helpBodyStyle()
                    }

                    HelpSection(title: "Duplicate Files") {
                        Text("If a converted file already exists in the destination folder, Xe-Image Convert will ask what to do:")
                            .helpBodyStyle()
                        HelpTable(rows: [
                            ("Replace All", "Overwrites the existing file"),
                            ("Add New Versions", "Saves alongside as filename (1), filename (2)…"),
                            ("Cancel", "Stops the conversion without saving anything"),
                        ])
                    }

                    HelpSection(title: "Keyboard Shortcuts") {
                        HelpTable(rows: [
                            ("⌘ Z", "Undo the last removed image from the queue"),
                            ("⌘ A", "Select all thumbnails"),
                            ("⌫ Delete", "Remove selected thumbnails from the queue"),
                        ])
                        Text("Standard macOS shortcuts work throughout the app.")
                            .helpBodyStyle()
                    }

                    // ── Footer / About ──────────────────────────────────
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            AppIconView(size: 18)
                            Text("Xe-Image Convert")
                                .font(.system(size: 13, weight: .semibold))
                            Text("· Free utility by Xenon Post")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.brand.textFaint)
                        }

                        Text("Xenon Post is a boutique post-production company specialising in film and television — offline editing, online finishing, colour grading, and delivery. Based in Sydney & Perth, Australia.")
                            .helpBodyStyle()

                        Link("xenon-post.com  →", destination: URL(string: "https://xenon-post.com")!)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.xenonBlue)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 500, idealHeight: 640)
    }
}

// MARK: - Help components

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.xenonBlue)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }
}

private struct HelpStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.xenonBlue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .helpBodyStyle()
            }
        }
    }
}

private struct HelpEntry: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.xenonBlue)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .helpBodyStyle()
            }
        }
    }
}

private struct HelpTable: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(row.0)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.xenonBlue)
                        .frame(width: 120, alignment: .leading)
                    Text(row.1)
                        .helpBodyStyle()
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(index.isMultiple(of: 2)
                    ? Color.brand.surface
                    : Color.brand.surface2.opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.brand.border, lineWidth: 1))
    }
}

private extension Text {
    func helpBodyStyle() -> some View {
        self
            .font(.system(size: 12))
            .foregroundStyle(Color.brand.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    HelpView()
}
