import Foundation

enum JSONPayloadExtractor {
    static func extract(from rawText: String) -> Data? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let directData = trimmed.data(using: .utf8), isValidJSON(directData) {
            return directData
        }

        if let fenced = trimmed.range(of: #"```(?:json)?\s*([\s\S]*?)\s*```"#, options: .regularExpression) {
            let block = String(trimmed[fenced])
                .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let blockData = block.data(using: .utf8), isValidJSON(blockData) {
                return blockData
            }
        }

        if let objectPayload = firstBalancedPayload(in: trimmed, opening: "{", closing: "}") {
            if let objectData = objectPayload.data(using: .utf8), isValidJSON(objectData) {
                return objectData
            }
        }

        if let arrayPayload = firstBalancedPayload(in: trimmed, opening: "[", closing: "]") {
            if let arrayData = arrayPayload.data(using: .utf8), isValidJSON(arrayData) {
                return arrayData
            }
        }

        return nil
    }

    private static func isValidJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func firstBalancedPayload(in text: String, opening: Character, closing: Character) -> String? {
        guard let start = text.firstIndex(of: opening) else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false

        for index in text.indices[start...] {
            let char = text[index]

            if inString {
                if isEscaped {
                    isEscaped = false
                    continue
                }
                if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }

            if char == "\"" {
                inString = true
                continue
            }

            if char == opening {
                depth += 1
            } else if char == closing {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }

        return nil
    }
}
