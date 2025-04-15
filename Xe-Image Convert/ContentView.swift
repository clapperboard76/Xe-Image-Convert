import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import CoreImage
import CoreGraphics
import libwebp
import AVFoundation

// Add this before the ContentView struct
enum OutputSize: String, CaseIterable {
    case automatic = "Automatic"
    case size1K = "1000px"
    case size2K = "2000px"
    case size3K = "3000px"
    case size4K = "4000px"
    case hdLandscape = "HD (1920×1080)"
    case hdPortrait = "HD (1080×1920)"
    case uhdLandscape = "UHD (3840×2160)"
    case uhdPortrait = "UHD (2160×3840)"
    
    var dimensions: (width: Int, height: Int)? {
        switch self {
        case .automatic: return nil
        case .size1K: return (1000, 1000)
        case .size2K: return (2000, 2000)
        case .size3K: return (3000, 3000)
        case .size4K: return (4000, 4000)
        case .hdLandscape: return (1920, 1080)
        case .hdPortrait: return (1080, 1920)
        case .uhdLandscape: return (3840, 2160)
        case .uhdPortrait: return (2160, 3840)
        }
    }
    
    var pixels: Int? {
        switch self {
        case .automatic: return nil
        case .size1K: return 1000
        case .size2K: return 2000
        case .size3K: return 3000
        case .size4K: return 4000
        case .hdLandscape: return 1920
        case .hdPortrait: return 1080
        case .uhdLandscape: return 3840
        case .uhdPortrait: return 2160
        }
    }
    
    var isFixedAspectRatio: Bool {
        switch self {
        case .automatic, .size1K, .size2K, .size3K, .size4K:
            return false
        case .hdLandscape, .hdPortrait, .uhdLandscape, .uhdPortrait:
            return true
        }
    }
    
    var aspectRatio: CGFloat? {
        guard let dims = dimensions else { return nil }
        return CGFloat(dims.width) / CGFloat(dims.height)
    }
    
    static func availableSizes(for aspectRatio: AspectRatio) -> [OutputSize] {
        switch aspectRatio {
        case .sixteenNine:
            return [.automatic, .size1K, .size2K, .size3K, .size4K, .hdLandscape, .uhdLandscape]
        case .nineSixteen:
            return [.automatic, .size1K, .size2K, .size3K, .size4K, .hdPortrait, .uhdPortrait]
        case .original:
            return [.automatic]
        default:
            return [.automatic, .size1K, .size2K, .size3K, .size4K]
        }
    }
}

struct ContentView: View {
    @State private var droppedURL: URL?
    @State private var outputFormat: ImageFormat = .jpg
    @State private var quality: Double = 0.8
    @State private var suffix: String = "_converted"
    @State private var aspectRatio: AspectRatio = .original
    @State private var isFitMode: Bool = true  // true = fit, false = fill
    @State private var outputSize: OutputSize = .automatic
    @State private var outputMessage: String = ""
    @State private var destinationURL: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @State private var isShowingDestinationPicker = false
    @State private var isConverting = false
    @State private var isShowingError = false
    @State private var errorMessage = ""
    @State private var previewImage: NSImage?
    @State private var destinationBookmark: Data?

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 300, height: 200)
                        .cornerRadius(10)
                } else {
                    Text("Drop Image Here")
                        .frame(width: 300, height: 200)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
            }
            .onDrop(of: [UTType.image], isTargeted: nil) { providers in
                if let provider = providers.first {
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (item, _) in
                        if let url = item as? URL {
                            DispatchQueue.main.async {
                                self.droppedURL = url
                                // Try to load the preview image
                                if let image = NSImage(contentsOf: url) {
                                    self.previewImage = image
                                } else {
                                    // If direct loading fails, try using a bookmark
                                    do {
                                        let bookmarkData = try url.bookmarkData(
                                            options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil
                                        )
                                        var isStale = false
                                        if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData,
                                                                    options: .withSecurityScope,
                                                                    relativeTo: nil,
                                                                    bookmarkDataIsStale: &isStale) {
                                            if resolvedURL.startAccessingSecurityScopedResource() {
                                                defer { resolvedURL.stopAccessingSecurityScopedResource() }
                                                if let image = NSImage(contentsOf: resolvedURL) {
                                                    self.previewImage = image
                                                }
                                            }
                                        }
                                    } catch {
                                        print("Error creating bookmark: \(error)")
                                    }
                                }
                            }
                        } else if let data = item as? Data,
                                  let image = NSImage(data: data) {
                            DispatchQueue.main.async {
                                self.previewImage = image
                            }
                        }
                    }
                    return true
                }
                return false
            }

            if let url = droppedURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Picker("Format", selection: $outputFormat) {
                ForEach(ImageFormat.allCases, id: \.self) {
                    Text($0.rawValue)
                }
            }.pickerStyle(SegmentedPickerStyle())

            HStack {
                Picker("Aspect Ratio", selection: $aspectRatio) {
                    ForEach(AspectRatio.allCases, id: \.self) {
                        Text($0.rawValue)
                    }
                }
                .disabled(outputSize.isFixedAspectRatio)
                
                if aspectRatio != .original {
                    HStack {
                        Text(isFitMode ? "Fit" : "Fill")
                            .frame(width: 30)
                        Toggle("", isOn: $isFitMode)
                            .toggleStyle(.switch)
                            .help(isFitMode ? "Fit: Image maintains its proportions with letterboxing/pillarboxing" : "Fill: Image fills the frame and may be cropped")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)

            if aspectRatio != .original {
                Picker("Output Size", selection: $outputSize) {
                    ForEach(OutputSize.availableSizes(for: aspectRatio), id: \.self) { size in
                        Text(size.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: aspectRatio) { newRatio in
                    // Reset to automatic if current size isn't available for new ratio
                    if !OutputSize.availableSizes(for: newRatio).contains(outputSize) {
                        outputSize = .automatic
                    }
                }
            }

            HStack {
                Text("Quality")
                Slider(value: $quality, in: 0.1...1.0)
            }

            TextField("Filename Suffix", text: $suffix)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)

            HStack {
                Button("Choose Destination") {
                    isShowingDestinationPicker = true
                }
                .buttonStyle(.bordered)
                
                Text(destinationURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button(action: {
                if let url = droppedURL {
                    isConverting = true
                    convertImage(at: url)
                    isConverting = false
                }
            }) {
                Text("Convert")
                    .frame(width: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(droppedURL == nil || isConverting)

            if !outputMessage.isEmpty {
                Text(outputMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $isShowingDestinationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        // Create a security-scoped bookmark for the destination folder
                        let bookmarkData = try url.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        self.destinationBookmark = bookmarkData
                        self.destinationURL = url
                    } catch {
                        errorMessage = "Error saving destination: \(error.localizedDescription)"
                        isShowingError = true
                    }
                }
            case .failure(let error):
                errorMessage = "Error selecting destination: \(error.localizedDescription)"
                isShowingError = true
            }
        }
        .alert("Error", isPresented: $isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    func convertImage(at url: URL) {
        print("Starting conversion for: \(url.path)")
        
        // Create a security-scoped bookmark for the input file
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var isStale = false
            if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData,
                                        options: .withSecurityScope,
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &isStale) {
                guard resolvedURL.startAccessingSecurityScopedResource() else {
                    print("Could not access input file")
                    DispatchQueue.main.async {
                        self.errorMessage = "Could not access the input file"
                        self.isShowingError = true
                    }
                    return
                }
                
                defer {
                    resolvedURL.stopAccessingSecurityScopedResource()
                }
                
                guard let inputImage = NSImage(contentsOf: resolvedURL) else {
                    print("Failed to load input image")
                    DispatchQueue.main.async {
                        self.errorMessage = "Could not load image"
                        self.isShowingError = true
                    }
                    return
                }
                
                // Process the image according to the selected aspect ratio and fit/fill mode
                let processedImage: NSImage
                if aspectRatio == .original {
                    processedImage = inputImage
                } else {
                    let ratio: CGFloat
                    switch aspectRatio {
                    case .original:
                        ratio = inputImage.size.width / inputImage.size.height
                    case .oneOne:
                        ratio = 1.0
                    case .sixteenNine:
                        ratio = 16.0 / 9.0
                    case .nineSixteen:
                        ratio = 9.0 / 16.0
                    case .twoFour:
                        ratio = 2.4
                    case .threeTwo:
                        ratio = 3.0 / 2.0
                    case .twoThree:
                        ratio = 2.0 / 3.0
                    case .fiveFour:
                        ratio = 5.0 / 4.0
                    }
                    
                    // Print debug information
                    print("Input image size: \(inputImage.size)")
                    print("Target ratio: \(ratio)")
                    print("Selected size: \(outputSize.pixels ?? 0)")
                    
                    processedImage = cropToAspectRatio(inputImage, ratio: ratio)
                    
                    // Print processed image size
                    print("Processed image size: \(processedImage.size)")
                }
                
                // Get the CGImage for saving
                guard let cgImage = processedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    print("Failed to create CGImage")
                    return
                }
                
                // Print final CGImage dimensions
                print("Final CGImage dimensions: \(cgImage.width) x \(cgImage.height)")
                
                // Create output filename
                let outputFileName = url.deletingPathExtension().lastPathComponent + suffix + "." + outputFormat.rawValue.lowercased()
                let outputURL = destinationURL.appendingPathComponent(outputFileName)
                
                // Save in the selected format
                switch outputFormat {
                case .jpg:
                    saveAsJPEG(cgImage: cgImage, to: outputURL, quality: quality)
                case .png:
                    saveAsPNG(cgImage: cgImage, to: outputURL)
                case .heic:
                    saveAsHEIC(cgImage: cgImage, to: outputURL, quality: quality)
                case .webp:
                    saveAsWebP(cgImage: cgImage, to: outputURL, quality: quality)
                }
                
                DispatchQueue.main.async {
                    self.outputMessage = "Saved to: \(outputURL.path)"
                }
            }
        } catch {
            print("Error creating bookmark: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Error creating bookmark: \(error.localizedDescription)"
                self.isShowingError = true
            }
        }
    }

    private func saveAsJPEG(cgImage: CGImage, to url: URL, quality: CGFloat) {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        do {
            try jpegData?.write(to: url)
        } catch {
            print("Error saving JPEG: \(error)")
        }
    }
    
    private func saveAsPNG(cgImage: CGImage, to url: URL) {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let pngData = bitmapRep.representation(using: .png, properties: [:])
        do {
            try pngData?.write(to: url)
        } catch {
            print("Error saving PNG: \(error)")
        }
    }

    private func saveAsHEIC(cgImage: CGImage, to url: URL, quality: CGFloat) {
        // For HEIC, we always want RGB without alpha
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            print("Failed to create context for HEIC conversion")
            return
        }
        
        // Fill with black background first
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        // Draw the image
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        guard let processedImage = context.makeImage() else {
            print("Failed to create new image for HEIC conversion")
            return
        }
        
        // Set up HEIC encoding properties
        let properties = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationOptimizeColorForSharing: true,
            kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue
        ] as [CFString : Any]
        
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.heic" as CFString,
            1,
            nil
        ) else {
            print("Failed to create HEIC destination")
            return
        }
        
        // Set the encoding properties
        let destinationProperties = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationOptimizeColorForSharing: true
        ] as CFDictionary
        CGImageDestinationSetProperties(destination, destinationProperties)
        
        // Add the image with properties
        CGImageDestinationAddImage(destination, processedImage, properties as CFDictionary)
        
        // Finalize
        if !CGImageDestinationFinalize(destination) {
            print("Failed to finalize HEIC image")
        } else {
            print("Successfully saved HEIC image")
        }
    }

    private func saveAsWebP(cgImage: CGImage, to url: URL, quality: CGFloat) {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create context with premultiplied last alpha for RGBA format
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("Failed to create context")
            return
        }
        
        // Clear the context and draw the image
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            print("Failed to get bitmap data")
            return
        }
        
        // Convert RGBA to RGB by removing alpha channel
        let rgbaBuffer = data.assumingMemoryBound(to: UInt8.self)
        let rgbData = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 3)
        defer { rgbData.deallocate() }
        
        for y in 0..<height {
            for x in 0..<width {
                let sourceIndex = (y * bytesPerRow) + (x * bytesPerPixel)
                let targetIndex = (y * width + x) * 3
                
                // Copy RGB values, skip alpha
                rgbData[targetIndex] = rgbaBuffer[sourceIndex]     // R
                rgbData[targetIndex + 1] = rgbaBuffer[sourceIndex + 1] // G
                rgbData[targetIndex + 2] = rgbaBuffer[sourceIndex + 2] // B
            }
        }
        
        // Encode as WebP using RGB data
        if let webpData = WebPEncoder.encode(
            rgb: rgbData,
            width: Int32(width),
            height: Int32(height),
            stride: Int32(width * 3), // 3 bytes per pixel for RGB
            quality: Float(quality * 100)
        ) {
            do {
                try webpData.write(to: url)
                print("Successfully wrote WebP data")
            } catch {
                print("Failed to write WebP data: \(error.localizedDescription)")
            }
        } else {
            print("Failed to encode WebP data")
        }
    }

    func cropToAspectRatio(cgImage: CGImage, aspect: AspectRatio) -> CGImage {
        guard let ratio = aspect.ratio else { return cgImage }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let currentRatio = width / height

        var newWidth = width
        var newHeight = height

        if currentRatio > ratio {
            newWidth = height * ratio
        } else {
            newHeight = width / ratio
        }

        let x = (width - newWidth) / 2
        let y = (height - newHeight) / 2

        let cropRect = CGRect(x: x, y: y, width: newWidth, height: newHeight)
        return cgImage.cropping(to: cropRect) ?? cgImage
    }

    private func cropToAspectRatio(_ image: NSImage, ratio: CGFloat) -> NSImage {
        let imageSize = image.size
        let imageRatio = imageSize.width / imageSize.height
        
        // Calculate target dimensions based on output size setting
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        
        if let dimensions = outputSize.dimensions {
            // Fixed dimensions mode (HD/UHD)
            targetWidth = CGFloat(dimensions.width)
            targetHeight = CGFloat(dimensions.height)
        } else if let maxDimension = outputSize.pixels {
            // Fixed size mode - ensure the longest side matches the requested size exactly
            if ratio > 1 {
                // Target is landscape, width should be maxDimension
                targetWidth = CGFloat(maxDimension)
                targetHeight = round(targetWidth / ratio)
            } else {
                // Target is portrait or square, height should be maxDimension
                targetHeight = CGFloat(maxDimension)
                targetWidth = round(targetHeight * ratio)
            }
        } else {
            // Automatic mode - use input image dimensions
            if ratio > 1 {
                targetWidth = imageSize.width
                targetHeight = round(targetWidth / ratio)
            } else {
                targetHeight = imageSize.height
                targetWidth = round(targetHeight * ratio)
            }
        }
        
        // Create a bitmap representation with exact pixel dimensions
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetWidth),
            pixelsHigh: Int(targetHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        
        rep.size = NSSize(width: targetWidth, height: targetHeight)
        
        // Draw into the bitmap representation
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        
        // Fill background
        if isFitMode {
            if outputFormat == .png || outputFormat == .webp {
                NSColor.clear.set()
            } else {
                NSColor.black.set()
            }
            NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight).fill()
        }
        
        // Calculate source and destination rects
        var sourceRect = NSRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        let destRect: NSRect
        
        if isFitMode {
            // Fit mode: Scale image to fit within target while maintaining aspect ratio
            if imageRatio > ratio {
                // Image is wider than target - fit to width
                let sourceWidth = targetWidth
                let sourceHeight = targetWidth / imageRatio
                let yOffset = (targetHeight - sourceHeight) / 2
                destRect = NSRect(x: 0, y: yOffset, width: sourceWidth, height: sourceHeight)
            } else {
                // Image is taller than target - fit to height
                let sourceHeight = targetHeight
                let sourceWidth = targetHeight * imageRatio
                let xOffset = (targetWidth - sourceWidth) / 2
                destRect = NSRect(x: xOffset, y: 0, width: sourceWidth, height: sourceHeight)
            }
        } else {
            // Fill mode: Scale image to fill target while maintaining aspect ratio
            if imageRatio > ratio {
                // Image is wider than target - crop sides
                let sourceHeight = targetHeight
                let sourceWidth = targetHeight * imageRatio
                let xOffset = (sourceWidth - targetWidth) / 2
                sourceRect.origin.x = xOffset * (imageSize.width / sourceWidth)
                sourceRect.size.width = targetWidth * (imageSize.width / sourceWidth)
            } else {
                // Image is taller than target - crop top/bottom
                let sourceWidth = targetWidth
                let sourceHeight = targetWidth / imageRatio
                let yOffset = (sourceHeight - targetHeight) / 2
                sourceRect.origin.y = yOffset * (imageSize.height / sourceHeight)
                sourceRect.size.height = targetHeight * (imageSize.height / sourceHeight)
            }
            destRect = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        }
        
        // Draw the image
        image.draw(in: destRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Create a new NSImage with the bitmap representation
        let newImage = NSImage(size: NSSize(width: targetWidth, height: targetHeight))
        newImage.addRepresentation(rep)
        
        return newImage
    }
}

// ImageFormat.swift
enum ImageFormat: String, CaseIterable {
    case jpg = "JPG"
    case png = "PNG"
    case heic = "HEIC"
    case webp = "WebP"

    var bitmapType: NSBitmapImageRep.FileType {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        case .heic, .webp: return .png  // These will be handled separately
        }
    }

    var fileExtension: String {
        return self.rawValue.lowercased()
    }
}

// AspectRatio.swift
enum AspectRatio: String, CaseIterable {
    case original = "Original"
    case twoFour = "2.40:1"
    case sixteenNine = "16:9"
    case threeTwo = "3:2"
    case fiveFour = "5:4"
    case oneOne = "1:1"
    case twoThree = "2:3"
    case nineSixteen = "9:16"

    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .twoFour: return 2.4
        case .sixteenNine: return 16.0 / 9.0
        case .threeTwo: return 3.0 / 2.0
        case .fiveFour: return 5.0 / 4.0
        case .oneOne: return 1.0
        case .twoThree: return 2.0 / 3.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

// NSImage Extension
extension NSImage {
    // Create a new method name to avoid ambiguity
    func toCGImage() -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaFirst,
            bytesPerRow: 0,
            bitsPerPixel: 0) {
            
            bitmapRep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            
            return bitmapRep.cgImage
        }
        return nil
    }
} 