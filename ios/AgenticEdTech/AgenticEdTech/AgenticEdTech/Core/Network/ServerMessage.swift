import Foundation

struct ServerMessage: Codable {
    let type: String
    let workspace: String
    let payload: [String: AnyCodable]
    let targetUser: String?
    let timestamp: String?
}

struct ClientMessage: Codable {
    let type: String
    let workspace: String
    let payload: [String: AnyCodable]
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) {
            self.value = x
        } else if let x = try? container.decode(Int.self) {
            self.value = x
        } else if let x = try? container.decode(Double.self) {
            self.value = x
        } else if let x = try? container.decode(String.self) {
            self.value = x
        } else if let x = try? container.decode([AnyCodable].self) {
            self.value = x.map { $0.value }
        } else if let x = try? container.decode([String: AnyCodable].self) {
            self.value = x.mapValues { $0.value }
        } else if container.decodeNil() {
            self.value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Type unsupported for AnyCodable decoding.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let optionalValue = value as? AnyOptional, optionalValue.isNil {
            try container.encodeNil()
        } else if value is NSNull {
            try container.encodeNil()
        } else {
            switch value {
            case let bool as Bool:
                try container.encode(bool)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let string as String:
                try container.encode(string)
            case let array as [Any]:
                try container.encode(array.map { AnyCodable($0) })
            case let dictionary as [String: Any]:
                try container.encode(dictionary.mapValues { AnyCodable($0) })
            default:
                let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported AnyCodable serialization target type.")
                throw EncodingError.invalidValue(value, context)
            }
        }
    }
}

private protocol AnyOptional {
    var isNil: Bool { get }
}

extension Optional: AnyOptional {
    var isNil: Bool {
        switch self {
        case .none: return true
        case .some: return false
        }
    }
}
