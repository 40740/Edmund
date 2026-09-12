import AppKit

// MARK: - PNG rasterization
//
// `NSImage` → PNG `Data`, carrying the PNG's *actual* pixel dimensions so the
// caller derives CSS sizes from them rather than re-rounding `image.size × scale`
// (the two roundings can disagree and leave a non-exact scale ratio).
//
// Used by the HTML pipeline to inline a rendered equation as a data URI. The
// editor, which draws the `NSImage` straight into a TextKit fragment, has no use
// for it — which is why it lives with the HTML pipeline in `EdmundRender`.

public enum ImageRaster {

    public struct PNGResult {
        public let data: Data
        public let pixelSize: CGSize
        public let scale: CGFloat
        public var cssWidth: CGFloat { pixelSize.width / scale }
        public var cssHeight: CGFloat { pixelSize.height / scale }
    }

    /// Rasterizes an `NSImage` to PNG `Data` at `scale`× its point size.
    /// Returns the PNG's actual pixel dimensions alongside it — those, not an
    /// independent re-rounding of `image.size * scale`, are what the caller
    /// must derive the `<img>`'s CSS size from, or the two roundings can
    /// disagree and leave a non-exact scale ratio (see `PNGResult`).
    public static func pngData(_ image: NSImage, scale: CGFloat) -> PNGResult? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let pixelsWide = Int((size.width * scale).rounded())
        let pixelsHigh = Int((size.height * scale).rounded())
        guard pixelsWide > 0, pixelsHigh > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return PNGResult(data: data, pixelSize: CGSize(width: pixelsWide, height: pixelsHigh), scale: scale)
    }
}
