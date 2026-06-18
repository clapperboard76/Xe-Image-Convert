//
//  ContentView.swift
//  Xe-Image Convert
//
//  Created by Myles Conti on 28/4/2025.
//

import SwiftUI
import PhotoshopReader
import QuickLookThumbnailing
import SDWebImage
import SDWebImageWebPCoder
import ImageIO

// MARK: - Image saving helpers

func saveImageAsWebP(_ nsImage: NSImage, to url: URL, quality: CGFloat = 0.8) -> Bool {
    guard nsImage.tiffRepresentation != nil else { return false }
    let webpData = SDImageWebPCoder.shared.encodedData(
        with: nsImage,
        format: .webP,
        options: [.encodeCompressionQuality: quality]
    )
    do {
        try webpData?.write(to: url)
        return true
    } catch {
        return false
    }
}

// MARK: - ContentView

struct ContentView: View {
    // Registers the WebP coder exactly once for the process lifetime.
    private static let _coderRegistration: Void = {
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
    }()
    @State private var droppedImageURLs: [URL] = []
    @State private var thumbnails: [URL: NSImage] = [:]
    @State private var selectedFormat: ImageFormat = .jpg
    @State private var selectedAspect: AspectOption = .original
    @State private var selectedResolution: ResolutionOption = .original
    @State private var selectedScalingMode: ScalingMode = .fill
    @State private var quality: Double = 0.8
    @State private var saveURL: URL? = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
    @State private var showFolderPicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showPermissionAlert = false
    @State private var permissionDeniedFolders: Set<URL> = []
    @State private var accessibleImageURLs: [URL] = []
    @State private var isConverting = false
    @State private var conversionProgress: Double = 0
    @State private var currentFile: String = ""
    @State private var showProgress = false
    @State private var bookmarkedURLs: [URL: Data] = [:]
    @State private var selectedThumbnails: Set<URL> = []
    @State private var lastSelectedThumbnail: URL? = nil
    @State private var anchorPoints: [URL: CGPoint] = [:]
    @State private var shouldRemoveLetterboxing: Bool = false
    @State private var showDuplicateAlert = false
    @State private var duplicateFiles: [(original: URL, new: URL)] = []
    @State private var processingQueue: [URL] = []
    @State private var shouldReplaceAll = false
    @State private var shouldAddVersionAll = false
    @State private var showHelp = false

    init() {
        loadBookmarks()
    }

    // MARK: - Bookmark helpers

    private func loadBookmarks() {
        if let bookmarksData = UserDefaults.standard.dictionary(forKey: "FolderBookmarks") as? [String: Data] {
            for (urlString, bookmarkData) in bookmarksData {
                if let url = URL(string: urlString) {
                    bookmarkedURLs[url] = bookmarkData
                }
            }
        }
    }

    private func saveBookmarks() {
        var bookmarksDict: [String: Data] = [:]
        for (url, bookmarkData) in bookmarkedURLs {
            bookmarksDict[url.absoluteString] = bookmarkData
        }
        UserDefaults.standard.set(bookmarksDict, forKey: "FolderBookmarks")
    }

    private func requestFolderAccess(for url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarkedURLs[url] = bookmarkData
            saveBookmarks()
            return true
        } catch {
            return false
        }
    }

    private func restoreAccess(for url: URL) -> Bool {
        guard let bookmarkData = bookmarkedURLs[url] else { return false }
        do {
            var isStale = false
            let restoredURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                bookmarkedURLs.removeValue(forKey: url)
                saveBookmarks()
                return false
            }
            return restoredURL.startAccessingSecurityScopedResource()
        } catch {
            return false
        }
    }

    // MARK: - Selection helpers

    private func handleThumbnailSelection(_ url: URL, isShiftPressed: Bool) {
        if isShiftPressed, let lastSelected = lastSelectedThumbnail {
            if let lastIndex = accessibleImageURLs.firstIndex(of: lastSelected),
               let currentIndex = accessibleImageURLs.firstIndex(of: url) {
                let startIndex = min(lastIndex, currentIndex)
                let endIndex = max(lastIndex, currentIndex)
                for index in startIndex...endIndex {
                    selectedThumbnails.insert(accessibleImageURLs[index])
                }
            }
        } else {
            if selectedThumbnails.contains(url) {
                selectedThumbnails.remove(url)
            } else {
                selectedThumbnails.insert(url)
            }
        }
        lastSelectedThumbnail = url
    }

    private func updateAnchorPoint(for url: URL, to point: CGPoint) {
        anchorPoints[url] = point
    }

    private func getAnchorPoint(for url: URL) -> CGPoint {
        anchorPoints[url] ?? CGPoint(x: 0.5, y: 0.5)
    }

    // MARK: - Drawing helper (replaces deprecated lockFocus/unlockFocus)

    /// Draws into a new off-screen NSImage using an `NSBitmapImageRep` context.
    private func drawIntoNewImage(size: NSSize, draw: () -> Void) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw()
        let newImage = NSImage(size: size)
        newImage.addRepresentation(rep)
        return newImage
    }

    // MARK: - Letterboxing

    private func detectLetterboxing(_ image: NSImage) -> (top: Int, bottom: Int, left: Int, right: Int)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let threshold: CGFloat = 0.1

        func isBlack(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Bool {
            r < threshold && g < threshold && b < threshold
        }

        func isBlackPixel(x: Int, y: Int) -> Bool {
            guard let color = bitmap.colorAt(x: x, y: y) else { return false }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return isBlack(r, g, b)
        }

        var topBars = 0
        for y in 0..<height {
            if (0..<width).allSatisfy({ isBlackPixel(x: $0, y: y) }) { topBars += 1 } else { break }
        }

        var bottomBars = 0
        for y in (0..<height).reversed() {
            if (0..<width).allSatisfy({ isBlackPixel(x: $0, y: y) }) { bottomBars += 1 } else { break }
        }

        var leftBars = 0
        for x in 0..<width {
            if (0..<height).allSatisfy({ isBlackPixel(x: x, y: $0) }) { leftBars += 1 } else { break }
        }

        var rightBars = 0
        for x in (0..<width).reversed() {
            if (0..<height).allSatisfy({ isBlackPixel(x: x, y: $0) }) { rightBars += 1 } else { break }
        }

        guard topBars > 0 || bottomBars > 0 || leftBars > 0 || rightBars > 0 else { return nil }
        return (topBars, bottomBars, leftBars, rightBars)
    }

    private func cropLetterboxing(_ image: NSImage) -> NSImage {
        guard let letterboxing = detectLetterboxing(image) else { return image }

        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let newWidth = width - letterboxing.left - letterboxing.right
        let newHeight = height - letterboxing.top - letterboxing.bottom
        let newSize = NSSize(width: newWidth, height: newHeight)

        return drawIntoNewImage(size: newSize) {
            image.draw(
                in: NSRect(origin: .zero, size: newSize),
                from: NSRect(x: letterboxing.left, y: letterboxing.bottom, width: newWidth, height: newHeight),
                operation: .copy,
                fraction: 1.0
            )
        } ?? image
    }

    // MARK: - File naming

    private func findNextAvailableFileName(baseURL: URL) -> URL {
        let fileManager = FileManager.default
        let originalName = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var index = 1
        var newURL = baseURL

        while fileManager.fileExists(atPath: newURL.path) {
            newURL = baseURL.deletingLastPathComponent()
                .appendingPathComponent("\(originalName) (\(index))")
                .appendingPathExtension(ext)
            index += 1
        }
        return newURL
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Branded header ─────────────────────────────────────────
            HStack(spacing: 10) {
                AppIconView(size: 28)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Xe-Image Convert")
                        .font(.system(size: 13, weight: .semibold))
                    Text("by Xenon Post")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.brand.textFaint)
                }

                Spacer()

                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Xe-Image Convert Help")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── Drop zone ──────────────────────────────────────────────
            DragDropView(droppedImageURLs: $droppedImageURLs)
                .frame(height: 88)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, accessibleImageURLs.isEmpty ? 14 : 10)
                .onChange(of: droppedImageURLs) { _, newURLs in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        var processedURLs: [URL] = []
                        accessibleImageURLs.removeAll { !newURLs.contains($0) }
                        for url in newURLs {
                            if url.hasDirectoryPath {
                                let contents = (try? FileManager.default.contentsOfDirectory(
                                    at: url, includingPropertiesForKeys: nil
                                )) ?? []
                                processedURLs.append(contentsOf: contents.filter { isImageFile(url: $0) })
                            } else {
                                processedURLs.append(url)
                            }
                        }
                        accessibleImageURLs = processedURLs
                    }
                }

            // ── Thumbnail strip ────────────────────────────────────────
            if !accessibleImageURLs.isEmpty {
                VStack(spacing: 4) {
                    // Strip toolbar
                    HStack {
                        let count = accessibleImageURLs.filter { isImageFile(url: $0) }.count
                        Text("\(count) image\(count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if !selectedThumbnails.isEmpty {
                            Button {
                                withAnimation(.easeInOut) {
                                    for url in selectedThumbnails {
                                        accessibleImageURLs.removeAll { $0 == url }
                                        droppedImageURLs.removeAll { $0 == url }
                                        thumbnails.removeValue(forKey: url)
                                    }
                                    selectedThumbnails.removeAll()
                                }
                            } label: {
                                Text("Remove \(selectedThumbnails.count) selected")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)

                            Text("·")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            withAnimation(.easeInOut) {
                                accessibleImageURLs.removeAll()
                                droppedImageURLs.removeAll()
                                thumbnails.removeAll()
                                selectedThumbnails.removeAll()
                                lastSelectedThumbnail = nil
                            }
                        } label: {
                            Text("Clear All")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                    // Thumbnails
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(accessibleImageURLs.filter { isImageFile(url: $0) }, id: \.self) { url in
                                ThumbnailView(
                                    url: url,
                                    thumbnails: $thumbnails,
                                    isSelected: selectedThumbnails.contains(url),
                                    onSelect: { isShiftPressed in
                                        handleThumbnailSelection(url, isShiftPressed: isShiftPressed)
                                    },
                                    onRemove: {
                                        withAnimation(.easeInOut) {
                                            accessibleImageURLs.removeAll { $0 == url }
                                            droppedImageURLs.removeAll { $0 == url }
                                            thumbnails.removeValue(forKey: url)
                                            selectedThumbnails.remove(url)
                                            if lastSelectedThumbnail == url { lastSelectedThumbnail = nil }
                                        }
                                    },
                                    onAnchorPointUpdate: { point in updateAnchorPoint(for: url, to: point) },
                                    anchorPoint: getAnchorPoint(for: url)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 86)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.bottom, 4)
            }

            // ── Settings ──────────────────────────────────────────────
            VStack(spacing: 8) {

                // Output options card
                SettingsCard {
                    SettingsRow(label: "Format") {
                        Picker("", selection: $selectedFormat) {
                            ForEach(ImageFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsRow(label: "Aspect Ratio") {
                        Picker("", selection: $selectedAspect) {
                            ForEach(AspectOption.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsRow(label: "Scaling") {
                        Picker("", selection: $selectedScalingMode) {
                            ForEach(ScalingMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsRow(label: "Resolution") {
                        Picker("", selection: $selectedResolution) {
                            ForEach(ResolutionOption.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                // Processing options card
                SettingsCard {
                    SettingsRow(label: "Remove Letterboxing") {
                        Toggle("", isOn: $shouldRemoveLetterboxing).labelsHidden()
                    }
                    if selectedFormat == .jpg || selectedFormat == .webp {
                        SettingsDivider()
                        SettingsRow(label: "Quality") {
                            HStack(spacing: 8) {
                                Slider(value: $quality, in: 0.1...1.0)
                                    .frame(width: 110)
                                Text("\(Int(quality * 100))%")
                                    .monospacedDigit()
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .trailing)
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedFormat)

                // Save location card
                SettingsCard {
                    SettingsRow(label: "Save to") {
                        HStack(spacing: 6) {
                            Text(saveURL?.lastPathComponent ?? "Pictures")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Change…") { showFolderPicker = true }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // ── Convert button + progress ──────────────────────────────
            VStack(spacing: 8) {
                if showProgress {
                    VStack(spacing: 4) {
                        ProgressView(value: conversionProgress, total: 1.0)
                            .progressViewStyle(.linear)
                        Text(currentFile)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }

                Button(action: convertImages) {
                    Text(isConverting ? "Converting…" : "Convert Images")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConverting)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            .padding(.top, 2)
            .animation(.easeInOut, value: showProgress)
        }
        .frame(minWidth: 380, maxWidth: 460)
        .background(Color.brand.background)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: accessibleImageURLs.isEmpty)
        .sheet(isPresented: $showHelp) { HelpView() }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result {
                    alertMessage = "Error selecting folder: \(error.localizedDescription)"
                    showAlert = true
                }
                return
            }
            if url.startAccessingSecurityScopedResource() {
                saveURL = url
                permissionDeniedFolders.remove(url)
            } else {
                permissionDeniedFolders.insert(url)
                showPermissionAlert = true
            }
        }
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please grant permission to access the selected folder in System Settings > Privacy & Security > Files and Folders.")
        }
        .alert("Duplicate Files Found", isPresented: $showDuplicateAlert) {
            Button("Replace All") {
                shouldReplaceAll = true
                processingQueue.append(contentsOf: duplicateFiles.map { $0.original })
                beginConversion()
            }
            Button("Add New Versions") {
                shouldAddVersionAll = true
                processingQueue.append(contentsOf: duplicateFiles.map { $0.original })
                beginConversion()
            }
            Button("Cancel", role: .cancel) {
                processingQueue = []
                duplicateFiles = []
            }
        } message: {
            Text("Some files already exist in the destination folder:\n\n" +
                 duplicateFiles.map { $0.new.lastPathComponent }.joined(separator: "\n"))
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Conversion Complete"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Image utilities

    func isImageFile(url: URL) -> Bool {
        let imageTypes = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp", "psd", "jp2", "j2k", "jpx",
                          "afdesign", "afphoto", "afpub", "af"]
        return imageTypes.contains(url.pathExtension.lowercased())
    }

    func loadImage(from url: URL) -> NSImage? {
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        // Fallback: use Quick Look for formats ImageIO can't read (e.g. Affinity files)
        let semaphore = DispatchSemaphore(value: 0)
        var result: NSImage?
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 8192, height: 8192),
            scale: 1.0,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
            if let cgImage = thumbnail?.cgImage {
                result = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        drawIntoNewImage(size: size) {
            image.draw(
                in: NSRect(origin: .zero, size: size),
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0
            )
        } ?? image
    }

    func resizeImageToResolution(_ image: NSImage, targetResolution: ResolutionOption) -> NSImage {
        guard targetResolution != .original else { return image }

        let currentSize = image.size
        let isPortrait = currentSize.height > currentSize.width
        let targetDimension = CGFloat(targetResolution.maxDimension)

        let newSize: NSSize
        if isPortrait {
            let scale = targetDimension / currentSize.height
            newSize = NSSize(
                width: round(currentSize.width * scale),
                height: round(targetDimension)
            )
        } else {
            let scale = targetDimension / currentSize.width
            newSize = NSSize(
                width: round(targetDimension),
                height: round(currentSize.height * scale)
            )
        }

        return drawIntoNewImage(size: newSize) {
            image.draw(
                in: NSRect(origin: .zero, size: newSize),
                from: NSRect(origin: .zero, size: currentSize),
                operation: .copy,
                fraction: 1.0
            )
        } ?? image
    }

    func cropImageToAspectRatio(
        _ image: NSImage,
        aspectRatio: CGFloat,
        mode: ScalingMode,
        anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) -> NSImage {
        let currentAspect = image.size.width / image.size.height
        var newSize = image.size
        var sourceRect = NSRect(origin: .zero, size: image.size)
        var destinationRect = NSRect(origin: .zero, size: image.size)

        // Flip Y to match macOS coordinate system
        let flippedAnchor = CGPoint(x: anchorPoint.x, y: 1 - anchorPoint.y)

        switch mode {
        case .fill:
            if currentAspect > aspectRatio {
                newSize.width = image.size.height * aspectRatio
                newSize.height = image.size.height
                sourceRect.origin.x = (image.size.width - newSize.width) * flippedAnchor.x
                sourceRect.size = newSize
            } else {
                newSize.width = image.size.width
                newSize.height = image.size.width / aspectRatio
                sourceRect.origin.y = (image.size.height - newSize.height) * flippedAnchor.y
                sourceRect.size = newSize
            }
            destinationRect.size = newSize

        case .fit:
            if currentAspect > aspectRatio {
                newSize.width = image.size.height * aspectRatio
                newSize.height = image.size.height
            } else {
                newSize.width = image.size.width
                newSize.height = image.size.width / aspectRatio
            }

            let scale = min(newSize.width / image.size.width, newSize.height / image.size.height)
            let scaledSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            destinationRect = NSRect(
                x: (newSize.width - scaledSize.width) / 2,
                y: (newSize.height - scaledSize.height) / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )
        }

        return drawIntoNewImage(size: newSize) {
            if case .fit = mode {
                NSColor.clear.set()
                NSRect(origin: .zero, size: newSize).fill()
            }
            image.draw(in: destinationRect, from: sourceRect, operation: .copy, fraction: 1.0)
        } ?? image
    }

    // MARK: - Conversion

    func convertImages() {
        guard let outputFolder = saveURL else {
            alertMessage = "Please select a folder to save the images."
            showAlert = true
            return
        }

        let testFile = outputFolder.appendingPathComponent(".xe_write_test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
        } catch {
            permissionDeniedFolders.insert(outputFolder)
            alertMessage = "Permission denied to access the output folder. Please grant access in System Settings."
            showAlert = true
            return
        }

        duplicateFiles = []
        processingQueue = []
        shouldReplaceAll = false
        shouldAddVersionAll = false

        let fileManager = FileManager.default
        for url in accessibleImageURLs.filter({ isImageFile(url: $0) }) {
            let baseName = url.deletingPathExtension().lastPathComponent
            let outURL = outputFolder
                .appendingPathComponent(baseName)
                .appendingPathExtension(selectedFormat.rawValue)

            if fileManager.fileExists(atPath: outURL.path) {
                duplicateFiles.append((original: url, new: outURL))
            } else {
                processingQueue.append(url)
            }
        }

        if !duplicateFiles.isEmpty {
            showDuplicateAlert = true
            return
        }

        beginConversion()
    }

    /// The full convert-one-file pipeline, driven by explicit settings instead of
    /// @State so it can run from both the UI and the headless `--convert` CLI
    /// (see Xe_Image_ConvertApp.swift). Returns nil on success, or an error string.
    func convert(inputURL: URL, outputURL: URL, settings: ConvertSettings) -> String? {
        guard let nsImage = loadImage(from: inputURL) else {
            return "Failed to load image: \(inputURL.lastPathComponent)"
        }

        var processedImage = nsImage

        if settings.removeLetterboxing {
            processedImage = cropLetterboxing(processedImage)
        }

        if settings.aspect != .original {
            let targetAspect: CGFloat
            switch settings.aspect {
            case .original: targetAspect = nsImage.size.width / nsImage.size.height
            case .square: targetAspect = 1.0
            case .fourThree: targetAspect = 4.0 / 3.0
            case .sixteenNine: targetAspect = 16.0 / 9.0
            case .nineSixteen: targetAspect = 9.0 / 16.0
            case .threeTwo: targetAspect = 3.0 / 2.0
            case .twoThree: targetAspect = 2.0 / 3.0
            case .twoOne: targetAspect = 2.0 / 1.0
            case .twoFourOne: targetAspect = 2.4 / 1.0
            }
            processedImage = cropImageToAspectRatio(
                processedImage,
                aspectRatio: targetAspect,
                mode: settings.scalingMode,
                anchorPoint: settings.anchor
            )
        }

        if settings.resolution != .original {
            processedImage = resizeImageToResolution(processedImage, targetResolution: settings.resolution)
        }

        switch settings.format {
        case .jpg:
            guard let tiffData = processedImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiffData),
                  let data = rep.representation(using: .jpeg, properties: [.compressionFactor: settings.quality]) else {
                return "Failed to encode JPEG: \(inputURL.lastPathComponent)"
            }
            do { try data.write(to: outputURL) } catch {
                return "Error saving \(inputURL.lastPathComponent): \(error.localizedDescription)"
            }
        case .png:
            guard let tiffData = processedImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiffData),
                  let data = rep.representation(using: .png, properties: [:]) else {
                return "Failed to encode PNG: \(inputURL.lastPathComponent)"
            }
            do { try data.write(to: outputURL) } catch {
                return "Error saving \(inputURL.lastPathComponent): \(error.localizedDescription)"
            }
        case .tiff:
            guard let tiffData = processedImage.tiffRepresentation else {
                return "Failed to encode TIFF: \(inputURL.lastPathComponent)"
            }
            do { try tiffData.write(to: outputURL) } catch {
                return "Error saving \(inputURL.lastPathComponent): \(error.localizedDescription)"
            }
        case .webp:
            if !saveImageAsWebP(processedImage, to: outputURL, quality: CGFloat(settings.quality)) {
                return "Error saving WebP: \(inputURL.lastPathComponent)"
            }
        }

        return nil
    }

    private func beginConversion() {
        DispatchQueue.main.async {
            isConverting = true
            conversionProgress = 0
            currentFile = "Starting conversion..."
            showProgress = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let totalFiles = processingQueue.count + duplicateFiles.count
            var processedFiles = 0
            var successCount = 0
            var failCount = 0
            var errorMessages: [String] = []

            func processImage(inputURL: URL, outputURL: URL) -> Bool {
                let settings = ConvertSettings(
                    format: selectedFormat,
                    aspect: selectedAspect,
                    resolution: selectedResolution,
                    scalingMode: selectedScalingMode,
                    removeLetterboxing: shouldRemoveLetterboxing,
                    quality: quality,
                    anchor: getAnchorPoint(for: inputURL)
                )
                if let error = convert(inputURL: inputURL, outputURL: outputURL, settings: settings) {
                    errorMessages.append(error)
                    return false
                }
                return true
            }

            for url in processingQueue {
                let outURL = saveURL!
                    .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                    .appendingPathExtension(selectedFormat.rawValue)

                DispatchQueue.main.async {
                    currentFile = "Converting: \(url.lastPathComponent)"
                }

                if processImage(inputURL: url, outputURL: outURL) {
                    successCount += 1
                } else {
                    failCount += 1
                }

                processedFiles += 1
                DispatchQueue.main.async {
                    conversionProgress = Double(processedFiles) / Double(totalFiles)
                }
            }

            for duplicate in duplicateFiles {
                let outURL: URL
                if shouldAddVersionAll {
                    outURL = findNextAvailableFileName(baseURL: duplicate.new)
                } else {
                    if FileManager.default.isDeletableFile(atPath: duplicate.new.path) {
                        do {
                            try FileManager.default.removeItem(at: duplicate.new)
                        } catch {
                            errorMessages.append("Error replacing \(duplicate.new.lastPathComponent): \(error.localizedDescription)")
                            processedFiles += 1
                            failCount += 1
                            continue
                        }
                    }
                    outURL = duplicate.new
                }

                DispatchQueue.main.async {
                    currentFile = "Converting: \(duplicate.original.lastPathComponent)"
                }

                if processImage(inputURL: duplicate.original, outputURL: outURL) {
                    successCount += 1
                } else {
                    failCount += 1
                }

                processedFiles += 1
                DispatchQueue.main.async {
                    conversionProgress = Double(processedFiles) / Double(totalFiles)
                }
            }

            DispatchQueue.main.async {
                isConverting = false
                currentFile = ""
                showProgress = false

                if failCount > 0 {
                    alertMessage = "Converted \(successCount) image(s).\n\nFailed: \(failCount)\n" + errorMessages.joined(separator: "\n")
                } else {
                    alertMessage = "Successfully converted \(successCount) image(s)."
                }
                showAlert = true
            }
        }
    }
}

// MARK: - Settings components

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Color.brand.border
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

// MARK: - ThumbnailView

struct ThumbnailView: View {
    let url: URL
    @Binding var thumbnails: [URL: NSImage]
    @State private var isLoading = false
    @State private var loadFailed = false
    var isSelected: Bool
    var onSelect: (Bool) -> Void
    var onRemove: () -> Void
    var onAnchorPointUpdate: ((CGPoint) -> Void)?
    var anchorPoint: CGPoint

    var body: some View {
        Group {
            if let nsImage = thumbnails[url] {
                let aspectRatio = nsImage.size.width / max(nsImage.size.height, 1)
                ZStack {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(aspectRatio, contentMode: .fit)
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                        )

                    if isSelected {
                        GeometryReader { geometry in
                            Circle()
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                                .position(
                                    x: geometry.size.width * anchorPoint.x,
                                    y: geometry.size.height * anchorPoint.y
                                )
                                .gesture(
                                    DragGesture().onChanged { value in
                                        let newX = max(0, min(1, value.location.x / geometry.size.width))
                                        let newY = max(0, min(1, value.location.y / geometry.size.height))
                                        onAnchorPointUpdate?(CGPoint(x: newX, y: newY))
                                    }
                                )
                        }
                    }

                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onRemove) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .shadow(radius: 1)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(4)
                        }
                        Spacer()
                    }
                }
                .frame(height: 80)
                .onTapGesture {
                    onSelect(NSEvent.modifierFlags.contains(.shift))
                }
            } else if loadFailed {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.brand.surface)
                        .frame(height: 80)
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
                .frame(height: 80)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.brand.surface)
                        .frame(height: 80)
                    ProgressView().scaleEffect(0.7)
                }
                .onAppear {
                    guard !isLoading else { return }
                    isLoading = true
                    ThumbnailLoader.shared.loadThumbnail(for: url, fixedHeight: 80) { image in
                        if let image = image {
                            thumbnails[url] = image
                        } else {
                            loadFailed = true
                        }
                        isLoading = false
                    }
                }
            }
        }
    }
}

// MARK: - Enums

enum ImageFormat: String, CaseIterable {
    case jpg, png, tiff, webp

    var displayName: String {
        switch self {
        case .jpg: return "JPG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .webp: return "WEBP"
        }
    }
}

enum AspectOption: String, CaseIterable {
    case original, square, fourThree, sixteenNine, nineSixteen, threeTwo, twoThree, twoOne, twoFourOne

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        case .nineSixteen: return "9:16"
        case .threeTwo: return "3:2"
        case .twoThree: return "2:3"
        case .twoOne: return "2:1"
        case .twoFourOne: return "2.4:1"
        }
    }
}

enum ResolutionOption: String, CaseIterable {
    case original, r4k, r1080p, r2000, r1000, r500

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .r4k: return "4K (3840)"
        case .r1080p: return "1080p (1920)"
        case .r2000: return "2000px"
        case .r1000: return "1000px"
        case .r500: return "500px"
        }
    }

    var maxDimension: Int {
        switch self {
        case .original: return 0
        case .r4k: return 3840
        case .r1080p: return 1920
        case .r2000: return 2000
        case .r1000: return 1000
        case .r500: return 500
        }
    }
}

enum ScalingMode: String, CaseIterable {
    case fill, fit

    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        }
    }
}

/// All inputs to a single conversion, decoupled from the UI's @State so the
/// pipeline can be driven headlessly for testing.
struct ConvertSettings {
    var format: ImageFormat
    var aspect: AspectOption
    var resolution: ResolutionOption
    var scalingMode: ScalingMode
    var removeLetterboxing: Bool
    var quality: Double
    var anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
}

#Preview {
    ContentView()
}
