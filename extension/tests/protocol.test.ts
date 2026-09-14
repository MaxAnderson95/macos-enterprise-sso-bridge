import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { parseBridgeResponse, requestMessage } from "../src/protocol";
import type { FormField, SignInRequest } from "../src/protocol";
import { encodeFrame, hostIsLittleEndian, toHex } from "./helpers/nativeMessagingFrame";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "fixtures", "protocol");

function fixture(name: string): string {
  return readFileSync(join(fixtures, name), "utf8");
}

function fixtureJson(name: string): Record<string, unknown> {
  return JSON.parse(fixture(name));
}

describe("the request the Extension sends", () => {
  it("matches the GET fixture the Bridge decodes", () => {
    const wire = fixtureJson("request-get.json");
    const request: SignInRequest = { url: wire.url as string, method: "GET" };
    expect(requestMessage(request)).toEqual(wire);
  });

  it("matches the POST fixture, repeated field name included", () => {
    const wire = fixtureJson("request-post.json");
    const fields = wire.fields as FormField[];
    const request: SignInRequest = { url: wire.url as string, method: "POST", fields };
    expect(requestMessage(request)).toEqual(wire);
    expect(fields.filter(([name]) => name === "RelayState")).toHaveLength(2);
  });

  // The bytes in this fixture are what the Bridge's FrameChannel is given in
  // ProtocolFixtureTests, so the two suites pin one frame between them.
  it.skipIf(!hostIsLittleEndian)("frames to the bytes the Bridge decodes", () => {
    const wire = fixtureJson("request-post.json");
    const request: SignInRequest = {
      url: wire.url as string,
      method: "POST",
      fields: wire.fields as FormField[],
    };
    const frame = encodeFrame(JSON.stringify(requestMessage(request)));
    expect(toHex(frame)).toBe(fixture("request-post-frame.le.hex").trim());
  });
});

describe("the response the Extension parses", () => {
  it("reads a GET Callback", () => {
    expect(parseBridgeResponse(fixtureJson("response-callback-get.json"))).toEqual({
      result: "callback",
      url: "https://app.example.com/sso/callback?code=0.AXkAo1&state=abc123",
      method: "GET",
    });
  });

  it("reads a POST Callback with its fields in order", () => {
    const response = parseBridgeResponse(fixtureJson("response-callback-post.json"));
    expect(response).toEqual(fixtureJson("response-callback-post.json"));
  });

  it("reads declined", () => {
    expect(parseBridgeResponse(fixtureJson("response-declined.json"))).toEqual({
      result: "declined",
    });
  });

  it("reads an error with its detail", () => {
    expect(parseBridgeResponse(fixtureJson("response-error.json"))).toEqual({
      result: "error",
      code: "navigation_failed",
      detail: "NSURLErrorDomain -1003",
    });
  });

  it("reads unsupported_version with the Bridge's version", () => {
    expect(parseBridgeResponse(fixtureJson("response-unsupported-version.json"))).toEqual({
      result: "error",
      code: "unsupported_version",
      bridgeVersion: 1,
    });
  });

  it("keeps a code it does not know, so the copy layer can fall back", () => {
    expect(parseBridgeResponse({ result: "error", code: "sunspots" })).toEqual({
      result: "error",
      code: "unrecognized",
      received: "sunspots",
    });
  });

  it.each([
    ["a non-object", 7],
    ["an unknown result", { result: "shrug" }],
    ["a Callback with no url", { result: "callback", method: "GET" }],
    [
      "a Callback with an unknown method",
      { result: "callback", url: "https://a.example", method: "PUT" },
    ],
    [
      "a POST Callback with a one-element field",
      { result: "callback", url: "https://a.example", method: "POST", fields: [["only"]] },
    ],
    ["unsupported_version with no bridgeVersion", { result: "error", code: "unsupported_version" }],
  ])("rejects %s", (_name, message) => {
    expect(parseBridgeResponse(message)).toBeNull();
  });
});
