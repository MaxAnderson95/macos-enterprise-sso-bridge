import Foundation
import Testing

/// The shared protocol fixtures at the repository root, which the Extension's suite
/// reads too. Located from `#filePath` because SwiftPM can only carry resources that
/// live inside the target's own directory, and these deliberately belong to neither
/// half.
enum Fixtures {
  static let directory = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "fixtures/protocol")

  static func data(_ name: String) throws -> Data {
    try Data(contentsOf: directory.appending(path: name))
  }

  static func text(_ name: String) throws -> String {
    try String(decoding: data(name), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// JSON compared as objects rather than bytes, so key order and whitespace are not
  /// part of the contract. The schema is.
  static func object(_ name: String) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data(name)) as? NSDictionary)
  }
}

extension NSDictionary {
  static func parsing(_ data: Data) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
  }
}

/// Bytes to their hexadecimal spelling, and back, for the frame fixture.
enum Hex {
  static func data(_ text: String) throws -> Data {
    let characters = Array(text)
    try #require(characters.count.isMultiple(of: 2))
    var bytes = Data(capacity: characters.count / 2)
    for index in stride(from: 0, to: characters.count, by: 2) {
      let byte = try #require(UInt8(String(characters[index...(index + 1)]), radix: 16))
      bytes.append(byte)
    }
    return bytes
  }
}
