import Foundation
import NaturalLanguage

public enum LanguageValidationResult: Equatable {
    case validEnglish
    case rejectedNonEnglish(reason: String)
}

public struct LanguageValidator {
    /// Validates whether a transcript is acceptable English for Mockexa Group Discussion practice.
    public static func validateGDInput(_ text: String) -> LanguageValidationResult {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return .rejectedNonEnglish(reason: "Empty transcript")
        }
        
        // 1. Devanagari script detection (Hindi text written in Devanagari)
        let devanagariRange = cleanText.range(of: "\\p{Devanagari}", options: .regularExpression)
        if devanagariRange != nil {
            return .rejectedNonEnglish(reason: "Hindi Devanagari text detected")
        }
        
        // 2. Transliterated Hindi / Hinglish keyword analysis (Latin script)
        let hinglishKeywords: Set<String> = [
            "kya", "kyun", "kyunki", "kyon", "hai", "hain", "hoon", "ho", "tha", "thi", "the",
            "mera", "meri", "mere", "aap", "aapka", "aapki", "aapke", "tum", "tumhara", "hum", "humara",
            "kaam", "karo", "karna", "karke", "karta", "karti", "karte", "karne",
            "achha", "accha", "acchi", "acche", "bahut", "badi", "bada", "pade",
            "nahi", "nahin", "mat", "kabhi", "hamesha",
            "aur", "ya", "lekin", "magar", "par", "parantu",
            "kaise", "kaisa", "kaisi", "kitna", "kitne",
            "bohot", "sabse", "ziyada", "kam", "thora", "thoda",
            "samjhna", "samajh", "bolo", "bolna", "sunno", "dekh", "rahe", "rahi", "raha"
        ]
        
        let words = cleanText.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        var hinglishMatchCount = 0
        for word in words {
            if hinglishKeywords.contains(word) {
                hinglishMatchCount += 1
            }
        }
        
        let totalWordCount = max(1, words.count)
        let hinglishRatio = Double(hinglishMatchCount) / Double(totalWordCount)
        
        // Reject if multiple Hinglish indicators are present or form a substantial portion of the sentence
        if hinglishMatchCount >= 2 || (hinglishMatchCount >= 1 && (totalWordCount <= 4 || hinglishRatio >= 0.15)) {
            return .rejectedNonEnglish(reason: "Hindi/Hinglish speech detected")
        }
        
        // 3. Apple NaturalLanguage framework detection
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(cleanText)
        
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let dominantLanguage = recognizer.dominantLanguage
        let englishScore = hypotheses[.english] ?? 0.0
        
        // If dominant language is explicitly Hindi or non-English with low English confidence
        if let dominant = dominantLanguage, dominant != .english {
            if dominant == .hindi || dominant == NLLanguage("hi") {
                if englishScore < 0.4 {
                    return .rejectedNonEnglish(reason: "Hindi language detected by NaturalLanguage")
                }
            }
        }
        
        return .validEnglish
    }
}
