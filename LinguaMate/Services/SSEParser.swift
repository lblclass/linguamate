import Foundation

/// Incremental parser for `text/event-stream` bodies.
///
/// The network layer feeds raw chunks here and gets back the payloads of every
/// complete `data:` line. Kept free of URLSession so it can be unit tested with
/// hand-written chunk splits (servers do split JSON mid-token).
struct SSEDecoder {
    private var buffer = ""

    mutating func push(_ chunk: String) -> [String] {
        buffer.append(chunk)
        var payloads: [String] = []
        while let newlineRange = buffer.rangeOfCharacter(from: .newlines) {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
            if let payload = Self.payload(fromLine: line) {
                payloads.append(payload)
            }
        }
        return payloads
    }

    /// Flushes a trailing line that arrived without a final newline.
    mutating func flush() -> [String] {
        let remainder = buffer
        buffer = ""
        guard !remainder.isEmpty, let payload = Self.payload(fromLine: remainder) else { return [] }
        return [payload]
    }

    static func payload(fromLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let value = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        return value
    }

    static let doneToken = "[DONE]"
}

/// Reads the interesting fields out of an OpenAI-compatible streaming chunk.
enum OpenAIChunk {
    static func deltaContent(fromJSON payload: String) -> String? {
        guard let object = jsonObject(payload) else { return nil }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
            return content
        }
        if let text = first["text"] as? String {
            return text
        }
        return nil
    }

    /// Some providers report failures inside the stream with HTTP 200.
    static func streamErrorMessage(fromJSON payload: String) -> String? {
        guard let object = jsonObject(payload) else { return nil }
        guard let error = object["error"] else { return nil }
        if let dict = error as? [String: Any] {
            return (dict["message"] as? String) ?? "\(dict)"
        }
        return "\(error)"
    }

    static func jsonObject(_ payload: String) -> [String: Any]? {
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return object as? [String: Any]
    }
}