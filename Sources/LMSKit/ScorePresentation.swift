import Foundation

public enum ScorePresentation {
    public static func format(_ value: String) -> String {
        guard let number = Double(value), number.isFinite else { return value }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.numberStyle = .decimal; formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: number)) ?? value
    }
}
