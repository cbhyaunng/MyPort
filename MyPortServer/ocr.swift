import Foundation
import ImageIO
import Vision

struct OCRLine: Codable {
    let text: String
    let confidence: Double
}

struct OCRImageResult: Codable {
    let imagePath: String
    let lineCount: Int
    let lines: [OCRLine]
    let fullText: String
    let error: String?
}

let imagePaths = Array(CommandLine.arguments.dropFirst())
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

let results = imagePaths.map { imagePath in
    recognizeText(at: imagePath)
}

let data = try encoder.encode(results)
FileHandle.standardOutput.write(data)

private func recognizeText(at imagePath: String) -> OCRImageResult {
    let imageURL = URL(fileURLWithPath: imagePath)

    do {
        let imageData = try Data(contentsOf: imageURL)
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return OCRImageResult(
                imagePath: imagePath,
                lineCount: 0,
                lines: [],
                fullText: "",
                error: "이미지를 읽을 수 없습니다."
            )
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        if #available(macOS 13.0, *) {
            request.recognitionLanguages = ["ko-KR", "en-US"]
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? []).sorted { left, right in
            let leftY = left.boundingBox.midY
            let rightY = right.boundingBox.midY

            if abs(leftY - rightY) > 0.02 {
                return leftY > rightY
            }

            return left.boundingBox.minX < right.boundingBox.minX
        }

        let lines = observations.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let text = candidate.string
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard text.isEmpty == false else {
                return nil
            }

            return OCRLine(text: text, confidence: Double(candidate.confidence))
        }

        return OCRImageResult(
            imagePath: imagePath,
            lineCount: lines.count,
            lines: lines,
            fullText: lines.map(\.text).joined(separator: "\n"),
            error: nil
        )
    } catch {
        return OCRImageResult(
            imagePath: imagePath,
            lineCount: 0,
            lines: [],
            fullText: "",
            error: error.localizedDescription
        )
    }
}
