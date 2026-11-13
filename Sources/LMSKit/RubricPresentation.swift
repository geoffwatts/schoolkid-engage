import Foundation

/// Match SEQTA's rubric mode. The API can include both grade and score on the same descriptor.
public enum RubricPresentation {
    public static func mark(for descriptor: JSONValue, mode: String = "numeric") -> String? {
        switch mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "numeric": return descriptor["score"].string.map(ScorePresentation.format)
        case "graded":
            guard let grade = descriptor["grade"].string, !grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return grade
        default: return nil
        }
    }
    public static func orderedDescriptors(in line: JSONValue, mode: String = "numeric") -> [JSONValue] {
        let descriptors = line["descriptors"].array ?? []
        func rank(_ descriptor: JSONValue) -> Double? {
            switch mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "numeric": return descriptor["score"].string.flatMap(Double.init).map { -$0 }
            case "graded":
                guard let grade = descriptor["grade"].string?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                      let index = ["A", "B", "C", "D", "E"].firstIndex(of: grade) else { return nil }
                return Double(index)
            default: return nil
            }
        }
        guard descriptors.allSatisfy({ rank($0) != nil }) else { return descriptors }
        return descriptors.enumerated().sorted {
            let a = rank($0.element)!, b = rank($1.element)!
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
}
