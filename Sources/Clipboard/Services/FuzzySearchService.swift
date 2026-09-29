import Foundation

struct FuzzySearchService {
    func search(query: String, items: [ClipboardItem]) -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        let normalizedQuery = normalize(trimmedQuery)
        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)

        return items
            .compactMap { item -> (ClipboardItem, Int)? in
                let normalizedText = normalize(item.text)
                let score = score(itemText: normalizedText, query: normalizedQuery, queryTokens: queryTokens)
                guard score > 0 else { return nil }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.createdAt > rhs.0.createdAt
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func score(itemText: String, query: String, queryTokens: [String]) -> Int {
        guard !itemText.isEmpty else { return 0 }

        var total = 0

        if itemText.hasPrefix(query) {
            total += 250
        }

        if itemText.contains(query) {
            total += 120
            total += max(0, 40 - distancePenalty(source: itemText, match: query))
        }

        let wordTokens = itemText.split(whereSeparator: \.isWhitespace).map(String.init)
        for queryToken in queryTokens where !queryToken.isEmpty {
            if let matchingWord = wordTokens.first(where: { $0.hasPrefix(queryToken) }) {
                total += 110
                total += max(0, 20 - abs(matchingWord.count - queryToken.count))
            } else if wordTokens.contains(where: { $0.contains(queryToken) }) {
                total += 70
            }
        }

        if let subsequenceScore = subsequenceScore(source: itemText, query: query) {
            total += subsequenceScore
        }

        return total
    }

    private func subsequenceScore(source: String, query: String) -> Int? {
        guard !query.isEmpty else { return nil }

        var sourceIndex = source.startIndex
        var matchedCharacters = 0
        var gaps = 0

        for queryCharacter in query {
            guard let matchIndex = source[sourceIndex...].firstIndex(of: queryCharacter) else {
                return nil
            }

            gaps += source.distance(from: sourceIndex, to: matchIndex)
            matchedCharacters += 1
            sourceIndex = source.index(after: matchIndex)
        }

        let compactnessBonus = max(0, 60 - gaps)
        return matchedCharacters * 8 + compactnessBonus
    }

    private func distancePenalty(source: String, match: String) -> Int {
        guard let range = source.range(of: match) else { return 999 }
        return source.distance(from: source.startIndex, to: range.lowerBound)
    }
}
