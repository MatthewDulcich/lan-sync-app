import Foundation

enum FieldValue: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case date(Date)

    enum CodingKeys: String, CodingKey { case t, s, i, b, d }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let v): try c.encode("s", forKey: .t); try c.encode(v, forKey: .s)
        case .int(let v):    try c.encode("i", forKey: .t); try c.encode(v, forKey: .i)
        case .bool(let v):   try c.encode("b", forKey: .t); try c.encode(v, forKey: .b)
        case .date(let v):   try c.encode("d", forKey: .t); try c.encode(v, forKey: .d)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "s": self = .string(try c.decode(String.self, forKey: .s))
        case "i": self = .int(try c.decode(Int.self, forKey: .i))
        case "b": self = .bool(try c.decode(Bool.self, forKey: .b))
        case "d": self = .date(try c.decode(Date.self, forKey: .d))
        default: throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Unknown type"))
        }
    }
}