import SchoolCore

extension JSONValue {
    func required(_ key: String) throws -> String {
        guard let value = self[key].string, !value.isEmpty else { throw SEQTAError.schema("Missing \(key)") }
        return value
    }
    func requiredArray() throws -> [JSONValue] {
        guard let array else { throw SEQTAError.schema("Expected a list") }; return array
    }
}
