import Foundation

enum WaterUnit: String, CaseIterable, Identifiable, Codable {
    case milliliters
    case usFluidOunces

    var id: String { rawValue }

    static let millilitersPerUSFluidOunce = 29.5735295625

    var symbol: String {
        switch self {
        case .milliliters: "mL"
        case .usFluidOunces: "fl oz"
        }
    }

    var label: String {
        switch self {
        case .milliliters: "Milliliters (mL)"
        case .usFluidOunces: "US fluid ounces (fl oz)"
        }
    }

    func toMilliliters(_ value: Double) -> Double {
        switch self {
        case .milliliters: value
        case .usFluidOunces: value * WaterUnit.millilitersPerUSFluidOunce
        }
    }

    func fromMilliliters(_ milliliters: Double) -> Double {
        switch self {
        case .milliliters: milliliters
        case .usFluidOunces: milliliters / WaterUnit.millilitersPerUSFluidOunce
        }
    }

    /// Display text such as "1,000 mL" or "33.8 fl oz".
    func format(milliliters: Double) -> String {
        let value = fromMilliliters(milliliters)
        let digits = self == .milliliters ? 0 : 1
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)))) \(symbol)"
    }

    /// Editable text without grouping separators.
    func editText(milliliters: Double) -> String {
        let value = fromMilliliters(milliliters)
        let digits = self == .milliliters ? 0 : 1
        return value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
    }
}

enum HabitValidationError: Error, Equatable, LocalizedError {
    case waterNotANumber
    case waterNegative
    case movementNotWholeNumber
    case movementNegative

    var errorDescription: String? {
        switch self {
        case .waterNotANumber: "Water must be a number."
        case .waterNegative: "Water cannot be negative."
        case .movementNotWholeNumber: "Movement must be a whole number of minutes."
        case .movementNegative: "Movement minutes cannot be negative."
        }
    }
}

enum HabitParsing {
    /// Blank text means "Not logged" and returns nil. "0" is a recorded zero.
    static func water(_ text: String, unit: WaterUnit, locale: Locale = .current) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let value = number(trimmed, locale: locale), value.isFinite else {
            throw HabitValidationError.waterNotANumber
        }
        guard value >= 0 else { throw HabitValidationError.waterNegative }
        return unit.toMilliliters(value)
    }

    static func movement(_ text: String) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let value = Int(trimmed) else {
            if let number = Double(trimmed), number < 0 { throw HabitValidationError.movementNegative }
            throw HabitValidationError.movementNotWholeNumber
        }
        guard value >= 0 else { throw HabitValidationError.movementNegative }
        return value
    }

    private static func number(_ text: String, locale: Locale) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if let n = formatter.number(from: text) { return n.doubleValue }
        return Double(text)
    }
}
