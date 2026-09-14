# Protocol fixtures

The request and response shapes from [docs/spec/protocol.md](../../docs/spec/protocol.md), as bytes, read by both halves' test suites.

The Bridge's types and the Extension's types are hand-written against that document on each side. These files are how the two hand-written sets are held to the same schema without a JSON Schema and two generators: `bridge/Tests/BridgeCoreTests/ProtocolFixtureTests.swift` decodes and re-encodes them through `BridgeCore`, and `extension/tests/protocol.test.ts` parses and rebuilds them through the Extension's codec. A field renamed on one side alone fails on that side.

`request-post-frame.le.hex` is the same `request-post.json` as a complete native-messaging frame, length prefix included, produced by the Extension's test helper and decoded by the Bridge's `FrameChannel`. The framing is native-endian, so the file records little-endian bytes and both tests skip it on a big-endian host.

They live at the top level rather than under either half for the reason `packaging/` does: they span both and belong to neither.
