import Foundation

/// Generations supported by the existing Gen-V hatch/sprite catalog.
enum HatchGeneration: Int, CaseIterable, Sendable {
    case kanto = 1, johto, hoenn, sinnoh, unova

    var speciesIDs: ClosedRange<Int> {
        switch self {
        case .kanto: 1...151
        case .johto: 152...251
        case .hoenn: 252...386
        case .sinnoh: 387...493
        case .unova: 494...649
        }
    }

    var label: String {
        switch self {
        case .kanto: "Gen 1 · Kanto"
        case .johto: "Gen 2 · Johto"
        case .hoenn: "Gen 3 · Hoenn"
        case .sinnoh: "Gen 4 · Sinnoh"
        case .unova: "Gen 5 · Unova"
        }
    }

    static var all: Set<Int> { Set(allCases.map(\.rawValue)) }

    static func contains(_ speciesID: Int, selected: Set<Int>) -> Bool {
        allCases.contains { selected.contains($0.rawValue) && $0.speciesIDs.contains(speciesID) }
    }

    static func candidates(selected: Set<Int>) -> [Int] {
        allCases.filter { selected.contains($0.rawValue) }.flatMap { Array($0.speciesIDs) }
    }
}
