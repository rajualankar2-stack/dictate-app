import AppKit
import Foundation

/// Reads text from the currently focused UI element via the Accessibility API.
public enum AccessibilityTextReader {
    /// Returns the full text value of the focused text field, or nil if unavailable.
    public static func readFocusedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }
}

/// Extracts word-level substitution pairs between an original (pasted) text
/// and a corrected (current field) text.
public enum CorrectionExtractor {
    /// Returns candidate (from, to) replacement pairs found by diffing.
    public static func extract(original: String, corrected: String) -> [(from: String, to: String)] {
        let origWords = original.split(separator: " ").map(String.init)
        let corrWords = corrected.split(separator: " ").map(String.init)
        guard !origWords.isEmpty, !corrWords.isEmpty else { return [] }

        // Find contiguous runs of differing words using simple alignment.
        // We walk both arrays; when words match, advance both. When they differ,
        // collect a run of differing words from each side.
        var pairs: [(from: String, to: String)] = []
        var i = 0, j = 0
        while i < origWords.count && j < corrWords.count {
            if origWords[i].lowercased() == corrWords[j].lowercased() {
                i += 1; j += 1
                continue
            }
            // Collect differing run from original
            var origRun: [String] = []
            var corrRun: [String] = []
            // Gather until we find a matching word again
            let startI = i, startJ = j
            while i < origWords.count && j < corrWords.count
                  && origWords[i].lowercased() != corrWords[j].lowercased() {
                // Try to find next sync point
                if i + 1 < origWords.count && j < corrWords.count
                   && origWords[i + 1].lowercased() == corrWords[j].lowercased() {
                    break
                }
                if j + 1 < corrWords.count && i < origWords.count
                   && origWords[i].lowercased() == corrWords[j + 1].lowercased() {
                    break
                }
                origRun.append(origWords[i])
                corrRun.append(corrWords[j])
                i += 1; j += 1
            }
            if !origRun.isEmpty && !corrRun.isEmpty {
                let from = origRun.joined(separator: " ")
                let to = corrRun.joined(separator: " ")
                if from.lowercased() != to.lowercased() {
                    pairs.append((from: from, to: to))
                }
            }
            // If we broke out without advancing, advance one to avoid infinite loop
            if i == startI && j == startJ {
                i += 1; j += 1
            }
        }
        return pairs
    }
}