import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Telegram's inline thumbnail ("immediateThumbnailData"): a tiny JPEG stored with the preview and shown blurred until
/// the real image loads, so previews never look empty, even offline or right after a relaunch.
public enum PreviewPlaceholder {
    /// Longest side of the stored thumbnail. Telegram's are about 40px, a few hundred bytes.
    static let pixelSize = 40
    /// Blurred images for placeholders already shown, keyed by their bytes. They're tiny (40×21 is about 3 KB).
    private static let rendered = Mutex<[Data: CGImage]>([:])

    /// The stored bytes: a 40px JPEG at quality 0.5.
    static func make(from source: CGImageSource) -> Data? {
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The placeholder decoded and blurred, ready to draw scaled up. Telegram blurs its thumbnail the same way
    /// (`telegramFastBlurMore`); here it's a tent blur, done once and remembered.
    public static func image(from data: Data) -> CGImage? {
        if let image = rendered.withLock({ $0[data] }) { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let blurred = blurred(decoded)
        else { return nil }
        rendered.withLock {
            if $0.count > 1000 { $0.removeAll() }
            $0[data] = blurred
        }
        return blurred
    }

    private static func blurred(_ image: CGImage) -> CGImage? {
        guard let format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ) else { return nil }
        guard var source = try? vImage_Buffer(cgImage: image, format: format) else { return nil }
        defer { source.free() }
        guard var destination = try? vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 32) else {
            return nil
        }
        defer { destination.free() }
        let kernel: UInt32 = 7
        vImageTentConvolve_ARGB8888(&source, &destination, nil, 0, 0, kernel, kernel, nil, vImage_Flags(kvImageEdgeExtend))
        return try? destination.createCGImage(format: format)
    }
}
