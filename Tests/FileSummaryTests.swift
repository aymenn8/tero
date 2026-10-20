import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import TeroCore

@Test func fileSummaryPreparesPDFAndStrippedImageAndRejectsUnsupportedInputs() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let image = folder.appendingPathComponent("private-name.png")
  let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
  let canvas = try #require(CGContext(data: nil, width: 3000, height: 1500, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  let destination = try #require(CGImageDestinationCreateWithURL(image as CFURL, UTType.png.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(destination, try #require(canvas.makeImage()), [kCGImagePropertyOrientation: 6] as CFDictionary)
  #expect(CGImageDestinationFinalize(destination))
  let reader = FileSummaryReader()
  let payload = try await reader.prepare(image)
  #expect(payload.mime == "image/jpeg")
  let bytes = try #require(Data(base64Encoded: payload.data))
  let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
  let prepared = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  #expect(prepared.width == 1024 && prepared.height == 2048)
  #expect(!String(decoding: try JSONEncoder().encode(payload), as: UTF8.self).contains("private-name"))
  let pdf = folder.appendingPathComponent("private-document.pdf")
  var box = CGRect(x: 0, y: 0, width: 400, height: 300)
  let document = try #require(CGContext(pdf as CFURL, mediaBox: &box, nil))
  document.beginPDFPage(nil); document.endPDFPage(); document.closePDF()
  let pdfPayload = try await reader.prepare(pdf)
  #expect(pdfPayload.mime == "application/pdf")
  #expect(Data(base64Encoded: pdfPayload.data) == (try Data(contentsOf: pdf)))
  var context = InvocationContext(capturedAt: .now, applicationID: "com.apple.finder")
  context.files = [.read(pdf)]
  #expect(RecommendationEngine.rank(context: .init(fileContext: context)).first?.target == .native(.summarizeFile))
  #expect(Action.summarizeFile.definition?.delivery(canReplace: true) == .readingCard)
  #expect(!FileSummaryReader.accepts([.read(pdf), .read(image)]))
  let broken = folder.appendingPathComponent("broken.pdf"); try Data("not a pdf".utf8).write(to: broken)
  await #expect(throws: FileSummaryReader.Failure.unsupported) { try await reader.prepare(broken) }
  let largePDF = folder.appendingPathComponent("long.pdf")
  let long = try #require(CGContext(largePDF as CFURL, mediaBox: &box, nil))
  for _ in 0..<31 { long.beginPDFPage(nil); long.endPDFPage() }; long.closePDF()
  await #expect(throws: FileSummaryReader.Failure.tooLarge) { try await reader.prepare(largePDF) }
  let cancelled = Task { try await reader.prepare(pdf) }; cancelled.cancel()
  await #expect(throws: CancellationError.self) { try await cancelled.value }
}
