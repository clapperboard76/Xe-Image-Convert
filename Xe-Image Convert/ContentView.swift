import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import CoreImage
import CoreGraphics
import libwebp

struct ContentView: View {
    @State private var droppedURL: URL?
    @State private var outputFormat: ImageFormat = .jpg
    @State private var quality: Double = 0.8
    @State private var suffix: String = "_converted"
    @State private var aspectRatio: AspectRatio = .original
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

            Picker("Aspect Ratio", selection: $aspectRatio) {
                ForEach(AspectRatio.allCases, id: \.self) {
                    Text($0.rawValue)
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
                
                guard let cgImage = inputImage.toCGImage() else {
                    print("Failed to convert NSImage to CGImage")
                    DispatchQueue.main.async {
                        self.errorMessage = "Could not process image"
                        self.isShowingError = true
                    }
                    return
                }

                print("Image loaded successfully, dimensions: \(cgImage.width)x\(cgImage.height)")
                
                let croppedImage = cropToAspectRatio(cgImage: cgImage, aspect: aspectRatio)
                print("Image cropped to aspect ratio: \(aspectRatio.rawValue)")
                
                let baseName = url.deletingPathExtension().lastPathComponent + suffix
                let newURL = destinationURL.appendingPathComponent(baseName).appendingPathExtension(outputFormat.fileExtension)
                print("Output path: \(newURL.path)")

                do {
                    switch outputFormat {
                    case .jpg, .png:
                        let bitmapRep = NSBitmapImageRep(cgImage: croppedImage)
                        let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: quality]
                        guard let data = bitmapRep.representation(using: outputFormat.bitmapType, properties: props) else {
                            print("Failed to create image data")
                            throw NSError(domain: "ImageConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image data"])
                        }
                        try data.write(to: newURL)
                        print("Successfully saved \(outputFormat.rawValue) image")
                        
                    case .heic:
                        saveAsHEIC(cgImage: croppedImage, to: newURL, quality: quality)
                        print("Successfully saved HEIC image")
                        
                    case .webp:
                        saveAsWebP(cgImage: croppedImage, to: newURL, quality: quality)
                        print("Successfully saved WebP image")
                    }
                    
                    DispatchQueue.main.async {
                        self.outputMessage = "Successfully saved to \(destinationURL.lastPathComponent): \(newURL.lastPathComponent)"
                    }
                } catch {
                    print("Error during conversion: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.isShowingError = true
                    }
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

    private func saveAsHEIC(cgImage: CGImage, to url: URL, quality: CGFloat) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            print("Failed to create HEIC destination")
            return
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationOptimizeColorForSharing: true
        ]
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            print("Failed to finalize HEIC image")
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