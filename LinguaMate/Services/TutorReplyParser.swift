import Foundation

/// Parses the tutor's tagged answer into a `TutorReply`.
///
/// Design notes:
/// * The model is asked for tagged sections, but we never trust it: a missing
///   tag degrades to "the whole answer is the reply", and a JSON answer (some
///   proxies rewrite the request) is understood too.
/// * Parsing is a pure function of a string, so every branch is unit tested.
enum TutorReplyParser {
    private static let bulletCharacters: Set<Character> = ["-", "•", "*", "–", "—"]

    static func parse(_ raw: String) -> TutorReply {
        let text = normalizeNewlines(raw)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let jsonReply = parseJSONFallback(trimmed) {
            return jsonReply
        }

        guard containsTag(text, PromptBuilder.replyOpen) else {
            return TutorReply(reply: stripKnownTags(trimmed), translation: nil, corrections: [], followUps: [])
        }

        let reply = section(text, open: PromptBuilder.replyOpen, close: PromptBuilder.replyClose)
            ?? trailingSection(text, open: PromptBuilder.replyOpen)
        let translation = section(text, open: PromptBuilder.translationOpen, close: PromptBuilder.translationClose)
        let correctionsBlock = section(text, open: PromptBuilder.correctionsOpen, close: PromptBuilder.correctionsClose)
        let followUpBlock = section(text, open: PromptBuilder.followUpOpen, close: PromptBuilder.followUpClose)

        let cleanedReply = cleanReply(reply)
        return TutorReply(
            reply: cleanedReply,
            translation: cleanOptional(translation),
            corrections: parseCorrections(correctionsBlock),
            followUps: parseBullets(followUpBlock)
        )
    }

    // MARK: - Sections

    static func containsTag(_ text: String, _ tag: String) -> Bool {
        text.range(of: tag, options: .caseInsensitive) != nil
    }

    /// Every tag the protocol defines.
    static let allTags: [String] = [
        PromptBuilder.replyOpen, PromptBuilder.replyClose,
        PromptBuilder.translationOpen, PromptBuilder.translationClose,
        PromptBuilder.correctionsOpen, PromptBuilder.correctionsClose,
        PromptBuilder.followUpOpen, PromptBuilder.followUpClose
    ]

    /// Body of one section. When the model forgets the closing tag we stop at
    /// whichever section tag comes first instead of swallowing the rest of the
    /// answer (a missing [/REPLY] must not leak the translation into speech).
    static func section(_ text: String, open: String, close: String) -> String? {
        guard let openRange = text.range(of: open, options: .caseInsensitive) else { return nil }
        let rest = text[openRange.upperBound...]
        var boundary = rest.endIndex
        for terminator in allTags where terminator.caseInsensitiveCompare(open) != .orderedSame {
            if let range = rest.range(of: terminator, options: .caseInsensitive), range.lowerBound < boundary {
                boundary = range.lowerBound
            }
        }
        let value = String(rest[rest.startIndex..<boundary])
        return value.isEmpty ? nil : value
    }

    static func trailingSection(_ text: String, open: String) -> String? {
        guard let openRange = text.range(of: open, options: .caseInsensitive) else { return nil }
        let tail = String(text[openRange.upperBound...])
        return tail.isEmpty ? nil : tail
    }

    // MARK: - Corrections

    static func parseCorrections(_ block: String?) -> [Correction] {
        parseBullets(block).compactMap { line in
            parseCorrectionLine(line)
        }
    }

    static func parseCorrectionLine(_ line: String) -> Correction? {
        var body = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = body.first, bulletCharacters.contains(first) {
            body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard !body.isEmpty, !isNoneToken(body) else { return nil }

        var head = body
        var note = ""

        for separator in ["::", "|", "："] {
            if let range = head.range(of: separator) {
                note = String(head[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                head = String(head[head.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        var original = ""
        var corrected = head
        for arrow in ["=>", "->", "→", "→"] {
            if let range = head.range(of: arrow) {
                original = String(head[head.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                corrected = String(head[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        original = trimQuotes(original)
        corrected = trimQuotes(corrected)
        guard !(original.isEmpty && corrected.isEmpty && note.isEmpty) else { return nil }
        return Correction(original: original, corrected: corrected, note: note)
    }

    // MARK: - Bullets

    static func parseBullets(_ block: String?) -> [String] {
        guard let block else { return [] }
        return block
            .components(separatedBy: .newlines)
            .map { line in
                var value = line.trimmingCharacters(in: .whitespaces)
                if let first = value.first, bulletCharacters.contains(first) {
                    value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                value = value.replacingOccurrences(of: "**", with: "")
                return trimQuotes(value)
            }
            .filter { !$0.isEmpty && !isNoneToken($0) }
    }

    static func isNoneToken(_ value: String) -> Bool {
        let lowered = value
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "。.!！")))
            .lowercased()
        return lowered == "none" || lowered == "n/a" || lowered == "无" || lowered == "没有" || lowered == "なし"
    }

    // MARK: - Cleanup helpers

    static func cleanReply(_ value: String?) -> String {
        guard var text = value else { return "" }
        text = stripKnownTags(text)
        text = text.replacingOccurrences(of: "**", with: "")
        text = trimQuotes(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = trimQuotes(stripKnownTags(value)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isNoneToken(text) else { return nil }
        return text
    }

    static func stripKnownTags(_ text: String) -> String {
        var result = text
        for tag in allTags {
            result = result.replacingOccurrences(of: tag, with: "", options: .caseInsensitive)
        }
        return result
    }

    static func trimQuotes(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("「", "」"), ("『", "』"), ("`", "`")]
        var changed = true
        while changed {
            changed = false
            for (open, close) in pairs where text.count >= 2 {
                if text.first == open, text.last == close {
                    text = String(text.dropFirst().dropLast())
                    changed = true
                }
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Accepts a JSON body in case the provider returns structured output.
    static func parseJSONFallback(_ text: String) -> TutorReply? {
        guard text.hasPrefix("{"), text.hasSuffix("}") else { return nil }
        guard let object = OpenAIChunk.jsonObject(text) else { return nil }
        let replyKeys = ["reply", "response", "answer", "text"]
        guard let reply = replyKeys.compactMap({ object[$0] as? String }).first else { return nil }

        var corrections: [Correction] = []
        if let rawCorrections = object["corrections"] as? [[String: Any]] {
            corrections = rawCorrections.compactMap { entry in
                let original = (entry["original"] as? String) ?? ""
                let corrected = (entry["corrected"] as? String) ?? ""
                let note = (entry["note"] as? String) ?? (entry["explanation"] as? String) ?? ""
                if original.isEmpty && corrected.isEmpty && note.isEmpty { return nil }
                return Correction(original: original, corrected: corrected, note: note)
            }
        } else if let rawCorrections = object["corrections"] as? [String] {
            corrections = rawCorrections.compactMap { parseCorrectionLine($0) }
        }

        var followUps: [String] = []
        if let rawFollowUps = object["follow_ups"] as? [String] {
            followUps = rawFollowUps.filter { !isNoneToken($0) }
        } else if let rawFollowUps = object["followups"] as? [String] {
            followUps = rawFollowUps.filter { !isNoneToken($0) }
        }

        return TutorReply(
            reply: cleanReply(reply),
            translation: cleanOptional(object["translation"] as? String),
            corrections: corrections,
            followUps: followUps
        )
    }
}

/// Pulls the spoken line out of a streamed answer so text-to-speech can start
/// before the model has finished the translation and corrections sections.
///
/// `push(_:)` returns only text that can no longer become part of a tag, which
/// is why the last few characters are held back until the next chunk arrives.
struct StreamingTutorReplyExtractor {
    private(set) var raw = ""
    private var plainTextMode = false
    private var replyBody = ""
    private var emittedCount = 0

    private var closeTagLength: Int { PromptBuilder.replyClose.count }
    private var openTagLength: Int { PromptBuilder.replyOpen.count }

    /// Feeds one streamed delta and returns the newly safe part of the reply.
    mutating func push(_ delta: String) -> String {
        guard !delta.isEmpty else { return "" }
        raw.append(delta)
        return drain()
    }

    /// Feeds the end of the stream and returns any still-unspoken reply text.
    mutating func finish() -> String {
        if plainTextMode || !TutorReplyParser.containsTag(raw, PromptBuilder.replyOpen) {
            plainTextMode = true
            replyBody = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return drain(flushAll: true)
    }

    /// Convenience: the parsed reply of everything received so far.
    func parsedReply() -> TutorReply {
        TutorReplyParser.parse(raw)
    }

    // MARK: - Internals

    private mutating func drain(flushAll: Bool = false) -> String {
        if !plainTextMode && !TutorReplyParser.containsTag(raw, PromptBuilder.replyOpen) {
            // No opening tag yet: if what we have cannot be the start of the tag,
            // the provider ignored our format and we stream the text through.
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let isTagPrefix = PromptBuilder.replyOpen.lowercased().hasPrefix(trimmed.lowercased()) || trimmed.isEmpty
            if !isTagPrefix || trimmed.count > openTagLength {
                plainTextMode = true
                replyBody = trimmed
            } else {
                return ""
            }
        } else if !plainTextMode {
            guard let openRange = raw.range(of: PromptBuilder.replyOpen, options: .caseInsensitive) else { return "" }
            // Leading whitespace after the tag is never part of the sentence.
            let body = String(String(raw[openRange.upperBound...]).drop(while: { $0.isWhitespace }))
            if let closeRange = body.range(of: PromptBuilder.replyClose, options: .caseInsensitive) {
                replyBody = String(body[body.startIndex..<closeRange.lowerBound])
            } else {
                replyBody = body
            }
        }

        let boundary: String.Index
        if flushAll {
            boundary = replyBody.endIndex
        } else if !plainTextMode, replyBody.range(of: PromptBuilder.replyClose, options: .caseInsensitive) == nil {
            boundary = safeBoundary(in: replyBody)
        } else {
            boundary = replyBody.endIndex
        }

        let safeText = String(replyBody[replyBody.startIndex..<boundary])
        guard safeText.count > emittedCount else { return "" }
        let start = safeText.index(safeText.startIndex, offsetBy: emittedCount)
        let newText = String(safeText[start...])
        emittedCount = safeText.count
        return newText
    }

    /// Everything except a trailing run of characters that could still grow into
    /// the closing tag.
    private func safeBoundary(in body: String) -> String.Index {
        let headroom = max(0, closeTagLength - 1)
        let backOff = min(headroom, body.count)
        var index = body.index(body.endIndex, offsetBy: -backOff)
        // Walk forward while the tail is a prefix of the closing tag.
        while index < body.endIndex {
            let tail = String(body[index...]).lowercased()
            if PromptBuilder.replyClose.lowercased().hasPrefix(tail) {
                return index
            }
            index = body.index(after: index)
        }
        return body.endIndex
    }
}