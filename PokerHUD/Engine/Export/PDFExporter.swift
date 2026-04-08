import SwiftUI
import AppKit

/// Phase 3 PR4: PDF exporter that snapshots a SwiftUI view to a single
/// PDF page using `ImageRenderer` (macOS 13+; deployment target is 14
/// so always available).
///
/// `ImageRenderer.render` exposes a closure that's invoked with a
/// `CGContext` ready to receive draw commands. We feed it a CoreGraphics
/// PDF context backed by an `NSMutableData` blob and capture the bytes
/// when the closure returns.
enum PDFExporter {
    /// Render any SwiftUI view to a PDF Data blob.
    @MainActor
    static func render<V: View>(view: V, size: CGSize? = nil) throws -> Data {
        let renderer = ImageRenderer(content: view)
        if let size = size {
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        }

        // NSMutableData bridges to CFMutableData, which CGDataConsumer
        // wants. We can't use Swift's value-type Data here because the
        // CG consumer needs a long-lived reference type to write into.
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw NSError(
                domain: "PDFExporter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataConsumer"]
            )
        }

        var didRender = false
        renderer.render { size, drawCallback in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                return
            }
            ctx.beginPDFPage(nil)
            drawCallback(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            didRender = true
        }

        guard didRender else {
            throw NSError(
                domain: "PDFExporter",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "ImageRenderer failed to produce a PDF page"]
            )
        }
        return pdfData as Data
    }
}
