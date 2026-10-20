import AppKit
import CoreText
import PDFKit
import ImageIO
import UniformTypeIdentifiers

// Synthetic, disposable documents for manual testing. No user content is read.
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Tero File Tests " + UUID().uuidString.prefix(6))
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
try FileManager.default.createDirectory(at: folder.appendingPathComponent("Destination"), withIntermediateDirectories: false)
for (name, text) in [("notes.txt", "Project Orion weekly meeting\nBudget: 120 EUR\nDeliver the prototype on Friday."), ("second.txt", "Second document for batch rename and ZIP."), ("budget.csv", "Item,Amount\nDesign,120\nDevelopment,340\n")] {
  try Data(text.utf8).write(to: folder.appendingPathComponent(name))
}
func pdf(_ name: String, prefix: String, count: Int) throws {
  let data = NSMutableData(); var bounds = CGRect(x: 0, y: 0, width: 420, height: 560)
  let consumer = CGDataConsumer(data: data)!, context = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
  for page in 1...count {
    context.beginPDFPage(nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(prefix) page \(page)", attributes: [.font: NSFont.systemFont(ofSize: 26)]))
    context.textPosition = CGPoint(x: 30, y: 400); CTLineDraw(line, context); context.endPDFPage()
  }
  context.closePDF(); try (data as Data).write(to: folder.appendingPathComponent(name))
}
try pdf("pages-A.pdf", prefix: "Document A", count: 6)
try pdf("pages-B.pdf", prefix: "Document B", count: 2)
let canvas = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
canvas.setFillColor(CGColor(gray: 1, alpha: 1)); canvas.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Tero invoice 2026 - Total 120 EUR", attributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black]))
canvas.textPosition = CGPoint(x: 40, y: 400); CTLineDraw(line, canvas)
let image = canvas.makeImage()!
for (ext, type) in [("bmp", UTType.bmp), ("png", UTType.png)] {
  let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("invoice." + ext) as CFURL, type.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil); precondition(CGImageDestinationFinalize(destination))
}
let scan = PDFDocument(); scan.insert(PDFPage(image: NSImage(cgImage: image, size: .zero))!, at: 0)
precondition(scan.write(to: folder.appendingPathComponent("scanned-invoice.pdf")))
print(folder.path)
