//
//  EmailContentProcessor.swift
//  PackageTraker
//
//  郵件內容處理器（HTML 轉純文字）
//

import Foundation

/// 郵件內容處理器
/// 負責將 HTML 郵件內容轉換為純文字
final class EmailContentProcessor {

    // MARK: - Singleton

    static let shared = EmailContentProcessor()

    private init() {}

    // MARK: - Public Methods

    /// 將 HTML 轉換為純文字
    func htmlToPlainText(_ html: String) -> String {
        var text = html

        // 1. 移除 <script> 和 <style> 標籤及其內容
        text = removeTag(text, tag: "script")
        text = removeTag(text, tag: "style")

        // 2. 將 <br> 和 </p> 轉換為換行
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</tr>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</td>", with: " ", options: .caseInsensitive)

        // 3. 移除所有 HTML 標籤
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // 4. 解碼 HTML entities
        text = decodeHTMLEntities(text)

        // 5. 清理多餘空白
        text = cleanWhitespace(text)

        return text
    }

    /// 從 base64 編碼的內容解碼
    func decodeBase64Content(_ encoded: String) -> String? {
        // Gmail API 使用 URL-safe base64 編碼
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // 補足 padding
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// 提取郵件中的特定資訊
    func extractInfo(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        // 如果有捕獲組，返回第一個捕獲組
        if match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: text) {
            return String(text[captureRange])
        }

        // 否則返回整個匹配
        if let matchRange = Range(match.range, in: text) {
            return String(text[matchRange])
        }

        return nil
    }

    /// 提取所有匹配的資訊
    func extractAllInfo(from text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.compactMap { match in
            // 如果有捕獲組，返回第一個捕獲組
            if match.numberOfRanges > 1,
               let captureRange = Range(match.range(at: 1), in: text) {
                return String(text[captureRange])
            }

            // 否則返回整個匹配
            if let matchRange = Range(match.range, in: text) {
                return String(text[matchRange])
            }

            return nil
        }
    }

    // MARK: - Private Methods

    private func removeTag(_ html: String, tag: String) -> String {
        let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
        return html.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text

        // 常見 HTML entities
        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™",
            "&#x200B;": "",  // Zero-width space
            "&#8203;": ""    // Zero-width space
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        // 解碼數字實體 (&#xxxx;)
        let numericPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()

            for match in matches {
                if let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    let char = String(Character(scalar))
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: char)
                    }
                }
            }
        }

        return result
    }

    private func cleanWhitespace(_ text: String) -> String {
        var result = text

        // 將多個空白字元替換為單個空格
        result = result.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)

        // 將多個換行替換為最多兩個換行
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        // 移除每行開頭和結尾的空白
        result = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
