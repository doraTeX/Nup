//
//  Nup.swift
//
//  Created by Yusuke Terada on 2024/04/25.
//

import Quartz

// Definition of structures
struct CommandLineArguments {
    var rows: Int
    var columns: Int
    var direction: NupDirection
    var inputPath: String
    var outputPath: String
}

enum NupDirection: String {
    case horizontalL2R = "horizontalL2R",
         horizontalR2L = "horizontalR2L",
         verticalL2R = "verticalL2R",
         verticalR2L = "verticalR2L"
}


// Argument parser
func parseArguments(arguments: [String]) -> CommandLineArguments? {
    if arguments.count == 1 {
        showUsage()
        exit(0)
    }

    var currentIndex = 1
    var rows: Int = 1
    var columns: Int = 2
    var direction: NupDirection = .horizontalL2R
    var inputPath: String?
    var outputPath: String?

    while currentIndex < arguments.count {
        let arg = arguments[currentIndex]
        switch arg {
        case "--rows":
            guard currentIndex + 1 < arguments.count,
                  let value = Int(arguments[currentIndex + 1]),
            value > 0 else {
                print("Error: Invalid or missing value for --rows")
                return nil
            }
            rows = value
            currentIndex += 2
        case "--columns":
            guard currentIndex + 1 < arguments.count,
                  let value = Int(arguments[currentIndex + 1]),
            value > 0 else {
                print("Error: Invalid or missing value for --columns")
                return nil
            }
            columns = value
            currentIndex += 2
        case "--direction":
            guard currentIndex + 1 < arguments.count,
                let value = NupDirection(rawValue: arguments[currentIndex + 1]) else {
                print("Error: Invalid or missing value for --direction")
                return nil
            }
            direction = value
            currentIndex += 2
        case "-h", "--help":
            showUsage()
            exit(0)
        default:
            if inputPath == nil {
                inputPath = arg
            } else if outputPath == nil {
                outputPath = arg
            } else {
                print("Error: Unexpected argument \(arg)")
                return nil
            }
            currentIndex += 1
        }
    }

    guard let finalInputPath = inputPath,
          let finalOutputPath = outputPath else {
        print("Error: Missing input or output path")
        return nil
    }

    return CommandLineArguments(rows: rows, columns: columns, direction: direction, inputPath: finalInputPath, outputPath: finalOutputPath)
}


func showUsage() {
    print("""
Usage: Nup [OPTIONS] <INPUT_PDF_PATH> <OUTPUT_PDF_PATH>

Arguments:
  <INPUT_PDF_PATH>         Path to the input PDF file
  <OUTPUT_PDF_PATH>        Path to the output PDF file

Options:
  --rows <ROWS>            Set the number of rows (default: 1)
  --columns <COLUMNS>      Set the number of columns (default: 2)
  --direction <DIRECTION>  Set the direction (default: horizontalL2R)
                            Valid directions:
                              - horizontalL2R (from left to right, horizontally)
                              - horizontalR2L (from right to left, horizontally)
                              - verticalL2R   (from top to bottom vertically, left to right horizontally)
                              - verticalR2L   (from top to bottom vertically, right to left horizontally)
  -h, --help               Show help information

Examples:
  Nup input.pdf output.pdf
  Nup --rows 1 --columns 2 input.pdf output.pdf
  Nup --direction horizontalR2L input.pdf output.pdf
""")

}



// Main procedure
guard let options = parseArguments(arguments: ProcessInfo.processInfo.arguments) else { exit(1) }
let success = Nup(from: options.inputPath, to: options.outputPath, rows: options.rows, columns: options.columns, direction: options.direction)
exit(success ? 0 : 1)


// Definitions of functions
@discardableResult func Nup(from inputPath: String, to outputPath: String, rows: Int, columns: Int, direction: NupDirection) -> Bool {
    guard let newDoc = PDFDocument(atPath: inputPath)?.Nup(rows: rows, columns: columns, direction: direction) else {
        print("Error: Cannot read input file: " + inputPath)
        return false
    }
    return newDoc.write(toFile: outputPath)
}


/// Extensions
extension PDFPage {
    func pageBox(_ boxType: CGPDFBox) -> NSRect { self.pageRef?.getBoxRect(boxType) ?? NSZeroRect }
}

extension CGSize {
    func rotated(by degree: Int) -> CGSize { (degree % 180 == 0) ? self : CGSize(width: self.height, height: self.width) }
}

extension PDFDocument {
    convenience init?(atPath filePath: String) {
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("Error: File not found: " + filePath)
            return nil
        }
        self.init(url: URL(fileURLWithPath: filePath))
    }

    convenience init?(merging documents: [PDFDocument]) {
        guard !documents.isEmpty else { return nil }
        self.init()
        documents.forEach { self.join($0) }
    }

    func forEachPage(_ body: (PDFPage) throws -> Void) rethrows { try (0..<self.pageCount).compactMap{ self.page(at: $0) }.forEach{ try body($0) } }
    func append(_ page: PDFPage) { self.insert(page, at: self.pageCount) }
    func join(_ doc: PDFDocument) { doc.forEachPage{ self.append($0) } }

    func forEachPageConcurrently(_ body: @escaping (Int, PDFPage) -> Bool) -> Bool {
        let outputPageCount = self.pageCount

        var failureCount = 0

        DispatchQueue.concurrentPerform(iterations: outputPageCount) { pageIndex in
            autoreleasepool {
                let success = { () -> Bool in
                    guard let pdfPage = self.page(at: pageIndex) else {
                        print("Cannot load page \(pageIndex+1)")
                        return false
                    }

                    return body(pageIndex, pdfPage)
                }()

                if !success {
                    failureCount += 1
                }
            }
        }

        return (failureCount == 0)
    }

    func generatePDFDocumentConcurrentlyAcrossPages(body: @escaping (Int, PDFPage, CGContext) -> Bool) -> PDFDocument? {
        let newPdfDocs = (0..<self.pageCount).map { _ in PDFDocument() }

        let success = self.forEachPageConcurrently() { (pageIndex, pdfPage) in
            let pdfData = NSMutableData()
            let pdfConsumer = CGDataConsumer(data: pdfData)!
            var pdfContext: CGContext! = CGContext(consumer: pdfConsumer, mediaBox: nil, nil)
            let success = body(pageIndex, pdfPage, pdfContext)

            pdfContext = nil // release memory

            guard success,
                  let newDoc = PDFDocument(data: pdfData as Data) else { return false }

            newPdfDocs[pageIndex].join(newDoc)

            return true
        }

        guard success else { return nil }

        guard let newPdfDoc = PDFDocument(merging: newPdfDocs) else {
            print("Cannot merge PDFs")
            return nil
        }

        return newPdfDoc
    }


    static func finalizePage(pageIndex: Int,
                             pdfPage: PDFPage,
                             pdfContext: CGContext) -> Bool {
        guard let pageRef = pdfPage.pageRef else { return false }

        let boxType: CGPDFBox = .cropBox
        var newBox = CGRect(origin: CGPoint.zero, size: pdfPage.pageBox(boxType).size.rotated(by: pdfPage.rotation))

        let transform = pageRef.getDrawingTransform(boxType,
                                                    rect: newBox,
                                                    rotate: 0,
                                                    preserveAspectRatio: true)

        pdfContext.beginPage(mediaBox: &newBox)
        pdfContext.saveGState()
        pdfContext.concatenate(transform)
        pdfContext.clip(to: pdfPage.pageBox(boxType))
        pdfContext.drawPDFPage(pageRef)
        pdfContext.resetClip()
        pdfContext.restoreGState()
        pdfContext.endPage()

        return true
    }

    func finalizedDocument() -> PDFDocument? { self.generatePDFDocumentConcurrentlyAcrossPages { PDFDocument.finalizePage(pageIndex: $0, pdfPage: $1, pdfContext: $2) } }

    func Nup(rows: Int, columns: Int, direction: NupDirection, pageBox: CGPDFBox = .cropBox) -> PDFDocument {
        let newPdfData = NSMutableData()
        let newPdfConsumer = CGDataConsumer(data: newPdfData)!
        var newPdfContext: CGContext! = CGContext(consumer: newPdfConsumer, mediaBox: nil, nil)

        var firstPage = self.page(at: 0)!
        let rotation = firstPage.rotation

        let targetDocument: PDFDocument

        if (rotation == 0 || rotation == 180) {
            targetDocument = self
        } else { // if rotation == 90 or 270, finalize document in order to clear /Rotate
            targetDocument = self.finalizedDocument()!
            firstPage = targetDocument.page(at: 0)!
        }

        let originalBox = firstPage.pageBox(pageBox)
        var newBox = CGRect(origin: originalBox.origin,
                            size: NSSize(width: originalBox.width * CGFloat(columns),
                                         height: originalBox.height * CGFloat(rows)))

        func drawOriginalPageIntoNewPage(originalPage page: PDFPage, atRow r: Int, column c: Int) {
            let newRect = CGRect(origin: CGPoint(x: originalBox.minX + originalBox.width * CGFloat(c - 1),
                                                 y: originalBox.minY + originalBox.height * CGFloat(rows - r)),
                                 size: originalBox.size)
            let targetPage = page.pageRef!
            let transform = targetPage.getDrawingTransform(pageBox,
                                                           rect: newRect,
                                                           rotate: 0,
                                                           preserveAspectRatio: true)
            newPdfContext.saveGState()
            newPdfContext.concatenate(transform)
            newPdfContext.clip(to: page.pageBox(pageBox))
            newPdfContext.drawPDFPage(targetPage)
            newPdfContext.resetClip()
            newPdfContext.restoreGState()
        }

        func constructNewPage(from: Int) {
            newPdfContext.beginPage(mediaBox: &newBox)

            var pageNum = from

            let drawPage = { (r: Int, c: Int) in
                guard let page = targetDocument.page(at: pageNum) else { return }
                drawOriginalPageIntoNewPage(originalPage: page, atRow: r, column: c)
                pageNum += 1
            }

            switch direction {
            case .horizontalL2R:
                for r in 1...rows {
                    for c in 1...columns {
                        drawPage(r, c)
                    }
                }
            case .horizontalR2L:
                for r in 1...rows {
                    for c in Array(1...columns).reversed() {
                        drawPage(r, c)
                    }
                }
            case .verticalL2R:
                for c in 1...columns {
                    for r in 1...rows {
                        drawPage(r, c)
                    }
                }
            case .verticalR2L:
                for c in Array(1...columns).reversed() {
                    for r in 1...rows {
                        drawPage(r, c)
                    }
                }
            }

            newPdfContext.endPage()
        }

        var pageNum = 0
        while pageNum < targetDocument.pageCount {
            constructNewPage(from: pageNum)
            pageNum += rows * columns
        }

        newPdfContext = nil // release memory

        return PDFDocument(data: newPdfData as Data)!
    }
}
