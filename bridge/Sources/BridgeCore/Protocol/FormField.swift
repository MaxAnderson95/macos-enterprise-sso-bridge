/// One `name=value` pair of a form body, on a Sign-in request or on a Callback.
///
/// The wire spells it as a two-element array rather than an object member, because a
/// form can repeat a name and an object would silently drop all but one of them. The
/// order of a `[FormField]` is the order the form carried, and is preserved on replay.
public struct FormField: Equatable, Sendable {
  public let name: String
  public let value: String

  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

extension FormField: Codable {
  public init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let name = try container.decode(String.self)
    let value = try container.decode(String.self)
    guard container.isAtEnd else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "a form field is a two-element [name, value] array"
      )
    }
    self.init(name: name, value: value)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(name)
    try container.encode(value)
  }
}
