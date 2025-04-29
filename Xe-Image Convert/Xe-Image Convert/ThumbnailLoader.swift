import Foundation
import AppKit
import QuickLookThumbnailing

class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSURL, NSImage>()
    
    func loadThumbnail(for url: URL, fixedHeight: CGFloat = 80, completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        // Try to get the original image size
        var aspectRatio: CGFloat = 1.0
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           height > 0 {
            aspectRatio = width / height
        } else if let nsImage = NSImage(contentsOf: url), nsImage.size.height > 0 {
            aspectRatio = nsImage.size.width / nsImage.size.height
        }
        let size = CGSize(width: fixedHeight * aspectRatio, height: fixedHeight)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { (thumbnail, error) in
            DispatchQueue.main.async {
                if let cgImage = thumbnail?.cgImage {
                    let nsImage = NSImage(cgImage: cgImage, size: size)
                    self.cache.setObject(nsImage, forKey: url as NSURL)
                    completion(nsImage)
                } else {
                    completion(nil)
                }
            }
        }
    }
} 