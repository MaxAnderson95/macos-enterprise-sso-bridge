import Testing

@testable import BridgeCore

@Test(
  "A missing or blank CFBundleShortVersionString reads as a development build",
  arguments: [nil, "", "   ", "\n"] as [String?]
)
func versionFallsBackToDevelopmentBuild(shortVersionString: String?) {
  #expect(BridgeVersion.resolve(shortVersionString: shortVersionString) == "0.0.0")
}

@Test("A substituted version is reported verbatim")
func versionIsReportedVerbatim() {
  #expect(BridgeVersion.resolve(shortVersionString: "1.2.3") == "1.2.3")
}

@Test("Surrounding whitespace is trimmed")
func versionIsTrimmed() {
  #expect(BridgeVersion.resolve(shortVersionString: " 1.2.3\n") == "1.2.3")
}
