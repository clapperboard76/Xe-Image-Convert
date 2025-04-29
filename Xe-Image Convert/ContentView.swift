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

func registerWebPCoder() {
    let webpCoder = SDImageWebPCoder.shared
    SDImageCodersManager.shared.addCoder(webpCoder)
}

func saveImageAsWebP(_ nsImage: NSImage, to url: URL, quality: CGFloat = 0.8) -> Bool {
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let _ = bitmap.cgImage else { return false }
    let webpData = SDImageWebPCoder.shared.encodedData(with: nsImage, format: .webP, options: [.encodeCompressionQuality: quality])
    do {
        try webpData?.write(to: url)
        return true
    } catch {
        print("Failed to save WEBP: \(error)")
        return false
    }
}

struct ContentView: View {
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

    let controlWidth: CGFloat = 140

    init() {
        registerWebPCoder()
        loadBookmarks()
    }

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
        let granted = url.startAccessingSecurityScopedResource()
        if granted {
            do {
                let bookmarkData = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                      includingResourceValuesForKeys: nil,
                                                      relativeTo: nil)
                bookmarkedURLs[url] = bookmarkData
                saveBookmarks()
                return true
            } catch {
                print("Error creating bookmark: \(error)")
                return false
            }
        }
        return false
    }

    private func restoreAccess(for url: URL) -> Bool {
        if let bookmarkData = bookmarkedURLs[url] {
            do {
                var isStale = false
                let restoredURL = try URL(resolvingBookmarkData: bookmarkData,
                                        options: [.withSecurityScope],
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &isStale)
                if isStale {
                    bookmarkedURLs.removeValue(forKey: url)
                    saveBookmarks()
                    return false
                }
                return restoredURL.startAccessingSecurityScopedResource()
            } catch {
                print("Error resolving bookmark: \(error)")
                return false
            }
        }
        return false
    }

    // Add this new function to handle range selection
    private func handleThumbnailSelection(_ url: URL, isShiftPressed: Bool) {
        if isShiftPressed, let lastSelected = lastSelectedThumbnail {
            // Get the indices of the last selected and current thumbnail
            if let lastIndex = accessibleImageURLs.firstIndex(of: lastSelected),
               let currentIndex = accessibleImageURLs.firstIndex(of: url) {
                // Determine the range
                let startIndex = min(lastIndex, currentIndex)
                let endIndex = max(lastIndex, currentIndex)
                
                // Select all thumbnails in the range
                for index in startIndex...endIndex {
                    selectedThumbnails.insert(accessibleImageURLs[index])
                }
            }
        } else {
            // Normal selection behavior
            if selectedThumbnails.contains(url) {
                selectedThumbnails.remove(url)
            } else {
                selectedThumbnails.insert(url)
            }
        }
        lastSelectedThumbnail = url
    }

    var body: some View {
        VStack(spacing: 20) {
            DragDropView(droppedImageURLs: $droppedImageURLs)
                .onChange(of: droppedImageURLs) { newURLs in
                    var processedURLs: [URL] = []
                    
                    for url in newURLs {
                        if url.hasDirectoryPath {
                            // For development, we'll use a simpler approach
                            let fileManager = FileManager.default
                            do {
                                // Get all files in the directory
                                let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                                
                                // Filter for image files
                                let imageFiles = contents.filter { isImageFile(url: $0) }
                                
                                // Add all image files to the processed URLs
                                processedURLs.append(contentsOf: imageFiles)
                                
                                print("Found \(imageFiles.count) images in folder: \(url.lastPathComponent)")
                            } catch {
                                print("Error accessing folder: \(error.localizedDescription)")
                                // In development, we'll just show the error in the console
                            }
                        } else {
                            // For individual files, just add them directly
                            processedURLs.append(url)
                        }
                    }
                    
                    // Update the accessible URLs
                    accessibleImageURLs = processedURLs
                    
                    // Print some debug information
                    print("Total files processed: \(processedURLs.count)")
                }
            
            // Thumbnails row
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(accessibleImageURLs.filter { isImageFile(url: $0) }, id: \.self) { url in
                            ThumbnailView(
                                url: url,
                                thumbnails: $thumbnails,
                                isSelected: selectedThumbnails.contains(url),
                                onSelect: { isShiftPressed in
                                    handleThumbnailSelection(url, isShiftPressed: isShiftPressed)
                                },
                                onRemove: {
                                    accessibleImageURLs.removeAll { $0 == url }
                                    droppedImageURLs.removeAll { $0 == url }
                                    thumbnails.removeValue(forKey: url)
                                    selectedThumbnails.remove(url)
                                    if lastSelectedThumbnail == url {
                                        lastSelectedThumbnail = nil
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 90)

                // Add bulk remove button when items are selected
                if !selectedThumbnails.isEmpty {
                    Button(action: {
                        // Remove all selected thumbnails
                        for url in selectedThumbnails {
                            accessibleImageURLs.removeAll { $0 == url }
                            droppedImageURLs.removeAll { $0 == url }
                            thumbnails.removeValue(forKey: url)
                        }
                        selectedThumbnails.removeAll()
                    }) {
                        Text("Remove Selected (\(selectedThumbnails.count))")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }
            }

            // Controls panel
            VStack(spacing: 16) {
                HStack {
                    Text("Format")
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Picker("", selection: $selectedFormat) {
                        ForEach(ImageFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: controlWidth, alignment: .trailing)
                }
                HStack {
                    Text("Aspect")
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Picker("", selection: $selectedAspect) {
                        ForEach(AspectOption.allCases, id: \.self) { aspect in
                            Text(aspect.displayName).tag(aspect)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: controlWidth, alignment: .trailing)
                }
                HStack {
                    Text("Scaling")
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Picker("", selection: $selectedScalingMode) {
                        ForEach(ScalingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: controlWidth, alignment: .trailing)
                }
                HStack {
                    Text("Resolution")
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Picker("", selection: $selectedResolution) {
                        ForEach(ResolutionOption.allCases, id: \.self) { res in
                            Text(res.displayName).tag(res)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: controlWidth, alignment: .trailing)
                }
                HStack {
                    Text("Quality")
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Slider(value: $quality, in: 0.1...1.0, step: 0.01)
                        .labelsHidden()
                        .frame(width: controlWidth, alignment: .trailing)
                    Text("\(Int(quality * 100))%")
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("Save to")
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Text(saveURL?.path ?? "Choose folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: controlWidth, alignment: .trailing)
                    Button("Choose…") {
                        showFolderPicker = true
                    }
                }
            }
            .padding(.horizontal)

            // Convert button and progress
            VStack(spacing: 8) {
                Button(action: convertImages) {
                    Text("Convert Images")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConverting)
                
                if showProgress {
                    VStack(spacing: 4) {
                        ProgressView(value: conversionProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(height: 8)
                        Text(currentFile)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal)
            .animation(.easeInOut, value: showProgress)
        }
        .padding()
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            do {
                let url = try result.get().first!
                // Request access to the folder
                let granted = url.startAccessingSecurityScopedResource()
                if granted {
                    saveURL = url
                    permissionDeniedFolders.remove(url)
                } else {
                    permissionDeniedFolders.insert(url)
                    showPermissionAlert = true
                }
            } catch {
                alertMessage = "Error selecting folder: \(error.localizedDescription)"
                showAlert = true
            }
        }
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please grant permission to access the selected folder in System Settings > Privacy & Security > Files and Folders.")
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Conversion Complete"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    // Helper to check if a file is an image
    func isImageFile(url: URL) -> Bool {
        let imageTypes = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp", "psd", "jp2", "j2k", "jpx"]
        return imageTypes.contains(url.pathExtension.lowercased())
    }

    // Add this new function to load images with HEIC support
    func loadImage(from url: URL) -> NSImage? {
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) {
            // Get the image type
            if let type = CGImageSourceGetType(imageSource) {
                print("Loading image of type: \(type)")
            }
            
            if let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        return nil
    }

    // Helper function to resize image while maintaining aspect ratio
    func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: image.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    // Helper function to resize image to target resolution
    func resizeImageToResolution(_ image: NSImage, targetResolution: ResolutionOption) -> NSImage {
        guard targetResolution != .original else { return image }
        
        // Get the current pixel dimensions
        let currentSize = image.size
        let isPortrait = currentSize.height > currentSize.width
        let targetDimension = CGFloat(targetResolution.maxDimension)
        
        print("\nResolution scaling process:")
        print("1. Input image size: \(currentSize.width) x \(currentSize.height)")
        print("2. Target dimension: \(targetDimension)")
        print("3. Is portrait: \(isPortrait)")
        
        // Calculate new size in points (half of target pixels)
        var newSize: NSSize
        if isPortrait {
            // For portrait images, scale based on height
            let scale = (targetDimension / 2) / currentSize.height
            newSize = NSSize(
                width: round(currentSize.width * scale),
                height: round(targetDimension / 2)
            )
        } else {
            // For landscape images, scale based on width
            let scale = (targetDimension / 2) / currentSize.width
            newSize = NSSize(
                width: round(targetDimension / 2),
                height: round(currentSize.height * scale)
            )
        }
        
        print("4. Calculated new size: \(newSize.width) x \(newSize.height)")
        
        // Create a new image with the exact size we want
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: currentSize),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        
        print("5. New image size: \(newImage.size.width) x \(newImage.size.height)")
        
        // Check CGImage dimensions
        if let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            print("6. CGImage dimensions: \(cgImage.width) x \(cgImage.height)")
            
            // Check the image representation
            if let rep = newImage.bestRepresentation(for: NSRect(origin: .zero, size: newSize), context: nil, hints: nil) {
                print("7. Best representation size: \(rep.size.width) x \(rep.size.height)")
                print("8. Best representation pixels: \(rep.pixelsWide) x \(rep.pixelsHigh)")
            }
        }
        
        return newImage
    }

    // Helper function to crop or fit image to aspect ratio
    func cropImageToAspectRatio(_ image: NSImage, aspectRatio: CGFloat, mode: ScalingMode) -> NSImage {
        let currentAspect = image.size.width / image.size.height
        var newSize = image.size
        var sourceRect = NSRect(origin: .zero, size: image.size)
        var destinationRect = NSRect(origin: .zero, size: image.size)
        
        switch mode {
        case .fill:
            if currentAspect > aspectRatio {
                // Image is wider than target ratio
                newSize.width = image.size.height * aspectRatio
                newSize.height = image.size.height
                sourceRect.origin.x = (image.size.width - newSize.width) / 2
                sourceRect.size = newSize
            } else {
                // Image is taller than target ratio
                newSize.width = image.size.width
                newSize.height = image.size.width / aspectRatio
                sourceRect.origin.y = (image.size.height - newSize.height) / 2
                sourceRect.size = newSize
            }
            destinationRect.size = newSize
            
        case .fit:
            // Calculate the target size based on aspect ratio
            if currentAspect > aspectRatio {
                // Image is wider than target ratio
                newSize.width = image.size.height * aspectRatio
                newSize.height = image.size.height
            } else {
                // Image is taller than target ratio
                newSize.width = image.size.width
                newSize.height = image.size.width / aspectRatio
            }
            
            // Calculate the scale factor to fit the image
            let scaleX = newSize.width / image.size.width
            let scaleY = newSize.height / image.size.height
            let scale = min(scaleX, scaleY)
            
            // Calculate the scaled size
            let scaledWidth = image.size.width * scale
            let scaledHeight = image.size.height * scale
            
            // Center the scaled image
            destinationRect.origin.x = (newSize.width - scaledWidth) / 2
            destinationRect.origin.y = (newSize.height - scaledHeight) / 2
            destinationRect.size = NSSize(width: scaledWidth, height: scaledHeight)
        }
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        // For PNG and TIFF, we want to preserve transparency
        if case .fit = mode {
            NSColor.clear.set()
            NSRect(origin: .zero, size: newSize).fill()
        }
        
        image.draw(in: destinationRect,
                  from: sourceRect,
                  operation: .copy,
                  fraction: 1.0)
        
        newImage.unlockFocus()
        return newImage
    }

    // Update the conversion logic to use the new image loading function
    func convertImages() {
        guard let outputFolder = saveURL else {
            alertMessage = "Please select a folder to save the images."
            showAlert = true
            return
        }

        // Try to create a test file to check write access
        let testFile = outputFolder.appendingPathComponent(".test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
        } catch {
            permissionDeniedFolders.insert(outputFolder)
            alertMessage = "Permission denied to access the output folder. Please grant access in System Settings."
            showAlert = true
            return
        }

        DispatchQueue.main.async {
            isConverting = true
            conversionProgress = 0
            currentFile = "Starting conversion..."
            showProgress = true
        }

        // Run conversion in background
        DispatchQueue.global(qos: .userInitiated).async {
            let totalFiles = accessibleImageURLs.filter { isImageFile(url: $0) }.count
            var processedFiles = 0
            var successCount = 0
            var failCount = 0
            var errorMessages: [String] = []

            for url in accessibleImageURLs.filter({ isImageFile(url: $0) }) {
                DispatchQueue.main.async {
                    currentFile = "Converting: \(url.lastPathComponent)"
                }
                
                // Use the new image loading function
                guard let nsImage = loadImage(from: url) else {
                    failCount += 1
                    errorMessages.append("Failed to load image: \(url.lastPathComponent)")
                    processedFiles += 1
                    DispatchQueue.main.async {
                        conversionProgress = Double(processedFiles) / Double(totalFiles)
                    }
                    continue
                }

                let baseName = url.deletingPathExtension().lastPathComponent
                let outURL = outputFolder
                    .appendingPathComponent(baseName)
                    .appendingPathExtension(selectedFormat.rawValue)

                // Apply aspect ratio if needed
                var processedImage = nsImage
                print("\nProcessing image: \(url.lastPathComponent)")
                print("1. Original size: \(nsImage.size.width) x \(nsImage.size.height)")
                
                if selectedAspect != .original {
                    let targetAspect: CGFloat
                    switch selectedAspect {
                    case .original:
                        targetAspect = nsImage.size.width / nsImage.size.height
                    case .square:
                        targetAspect = 1.0
                    case .fourThree:
                        targetAspect = 4.0 / 3.0
                    case .sixteenNine:
                        targetAspect = 16.0 / 9.0
                    case .nineSixteen:
                        targetAspect = 9.0 / 16.0
                    case .threeTwo:
                        targetAspect = 3.0 / 2.0
                    case .twoThree:
                        targetAspect = 2.0 / 3.0
                    case .twoOne:
                        targetAspect = 2.0 / 1.0
                    case .twoFourOne:
                        targetAspect = 2.4 / 1.0
                    }
                    processedImage = cropImageToAspectRatio(nsImage, aspectRatio: targetAspect, mode: selectedScalingMode)
                    print("2. After aspect ratio: \(processedImage.size.width) x \(processedImage.size.height)")
                }

                // Apply resolution if needed
                if selectedResolution != .original {
                    processedImage = resizeImageToResolution(processedImage, targetResolution: selectedResolution)
                    print("3. After resolution: \(processedImage.size.width) x \(processedImage.size.height)")
                }

                var success = false
                switch selectedFormat {
                case .jpg:
                    // Create a new bitmap with the exact size we want
                    let bitmap = NSBitmapImageRep(
                        bitmapDataPlanes: nil,
                        pixelsWide: Int(processedImage.size.width),
                        pixelsHigh: Int(processedImage.size.height),
                        bitsPerSample: 8,
                        samplesPerPixel: 4,
                        hasAlpha: true,
                        isPlanar: false,
                        colorSpaceName: .deviceRGB,
                        bytesPerRow: 0,
                        bitsPerPixel: 0
                    )
                    
                    // Create a new image with the exact size
                    let newImage = NSImage(size: processedImage.size)
                    newImage.lockFocus()
                    processedImage.draw(in: NSRect(origin: .zero, size: processedImage.size),
                                      from: NSRect(origin: .zero, size: processedImage.size),
                                      operation: .copy,
                                      fraction: 1.0)
                    newImage.unlockFocus()
                    
                    // Get the bitmap representation directly
                    if let tiffData = newImage.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiffData) {
                        print("4. Bitmap size: \(rep.pixelsWide) x \(rep.pixelsHigh)")
                        
                        let properties: [NSBitmapImageRep.PropertyKey: Any] = [
                            .compressionFactor: quality
                        ]
                        if let data = rep.representation(using: .jpeg, properties: properties) {
                            do {
                                try data.write(to: outURL)
                                success = true
                            } catch {
                                errorMessages.append("Error saving \(baseName): \(error.localizedDescription)")
                            }
                        }
                    }
                case .png:
                    // Create a new bitmap with the exact size we want
                    let bitmap = NSBitmapImageRep(
                        bitmapDataPlanes: nil,
                        pixelsWide: Int(processedImage.size.width),
                        pixelsHigh: Int(processedImage.size.height),
                        bitsPerSample: 8,
                        samplesPerPixel: 4,
                        hasAlpha: true,
                        isPlanar: false,
                        colorSpaceName: .deviceRGB,
                        bytesPerRow: 0,
                        bitsPerPixel: 0
                    )
                    
                    // Create a new image with the exact size
                    let newImage = NSImage(size: processedImage.size)
                    newImage.lockFocus()
                    processedImage.draw(in: NSRect(origin: .zero, size: processedImage.size),
                                      from: NSRect(origin: .zero, size: processedImage.size),
                                      operation: .copy,
                                      fraction: 1.0)
                    newImage.unlockFocus()
                    
                    // Get the bitmap representation directly
                    if let tiffData = newImage.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiffData) {
                        print("4. Bitmap size: \(rep.pixelsWide) x \(rep.pixelsHigh)")
                        
                        if let data = rep.representation(using: .png, properties: [:]) {
                            do {
                                try data.write(to: outURL)
                                success = true
                            } catch {
                                errorMessages.append("Error saving \(baseName): \(error.localizedDescription)")
                            }
                        }
                    }
                case .tiff:
                    if let tiffData = processedImage.tiffRepresentation {
                        do {
                            try tiffData.write(to: outURL)
                            success = true
                        } catch {
                            errorMessages.append("Error saving \(baseName): \(error.localizedDescription)")
                        }
                    }
                case .webp:
                    DispatchQueue.main.async {
                        currentFile = "Converting to WebP: \(url.lastPathComponent)"
                    }
                    success = saveImageAsWebP(processedImage, to: outURL, quality: CGFloat(quality))
                }
                
                if success {
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
                
                let message = "Successfully converted \(successCount) image(s)."
                if failCount > 0 {
                    alertMessage = message + "\n\nFailed: \(failCount)\nErrors:\n" + errorMessages.joined(separator: "\n")
                } else {
                    alertMessage = message
                }
                showAlert = true
            }
        }
    }
}

struct ThumbnailView: View {
    let url: URL
    @Binding var thumbnails: [URL: NSImage]
    @State private var isLoading = false
    var isSelected: Bool
    var onSelect: (Bool) -> Void
    var onRemove: () -> Void

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
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                        )
                    
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onRemove) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
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
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 80)
                    ProgressView()
                        .scaleEffect(0.7)
                }
                .frame(height: 80)
                .onAppear {
                    if !isLoading {
                        isLoading = true
                        ThumbnailLoader.shared.loadThumbnail(for: url, fixedHeight: 80) { image in
                            if let image = image {
                                thumbnails[url] = image
                            }
                        }
                    }
                }
            }
        }
    }
}

// Supported output formats
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

#Preview {
    ContentView()
}
