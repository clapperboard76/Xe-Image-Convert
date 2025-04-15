import Foundation
import libwebp

class WebPEncoder {
    static func encode(rgb: UnsafePointer<UInt8>?, width: Int32, height: Int32, stride: Int32, quality: Float) -> Data? {
        var output: UnsafeMutablePointer<UInt8>?
        let size = WebPEncodeLosslessRGB(rgb, width, height, stride, &output)
        
        guard size > 0, let outputBuffer = output else {
            return nil
        }
        
        let data = Data(bytes: outputBuffer, count: Int(size))
        WebPFree(output)
        
        return data
    }
} 
