import UIKit
import PDFKit

/// Rotates a local copy; the school file and cached original remain unchanged.
enum AttachmentRotation {
    static func clockwise(data: Data) -> Data? {
        if let document = PDFDocument(data: data) {
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) { page.rotation = (page.rotation + 90) % 360 }
            }
            return document.dataRepresentation()
        }
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat(); format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
}
