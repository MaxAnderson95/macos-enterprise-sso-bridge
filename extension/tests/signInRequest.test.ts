import { describe, expect, it } from "vitest";
import { isEntryOrigin, signInRequestFrom } from "../src/signInRequest";
import type { CapturedRequestDetails } from "../src/signInRequest";

const authorizeUrl =
  "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=00000000-0000-0000-0000-000000000000&redirect_uri=https%3A%2F%2Fapp.example.com%2Fsso%2Fcallback";
const samlUrl = "https://login.microsoftonline.com/common/saml2";

function encode(value: string): ArrayBuffer {
  const bytes = new TextEncoder().encode(value);
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

function details(overrides: Partial<CapturedRequestDetails>): CapturedRequestDetails {
  return { url: samlUrl, method: "POST", ...overrides };
}

describe("signInRequestFrom", () => {
  // The OIDC shape: everything that matters is already in the query string.
  it("keeps a GET's URL, redirect_uri and all", () => {
    expect(signInRequestFrom({ url: authorizeUrl, method: "GET" })).toEqual({
      url: authorizeUrl,
      method: "GET",
    });
  });

  it("reads a SAML POST's fields from formData", () => {
    const request = signInRequestFrom(
      details({
        requestBody: { formData: { SAMLRequest: ["fZJNb9sw"], RelayState: ["/dashboard"] } },
      }),
    );

    expect(request).toEqual({
      url: samlUrl,
      method: "POST",
      fields: [
        ["SAMLRequest", "fZJNb9sw"],
        ["RelayState", "/dashboard"],
      ],
    });
  });

  // Chromium hands back an ArrayBuffer for any value that is not valid UTF-8 and for
  // every multipart value, and the Bridge only ever sees strings.
  it("decodes Chromium's ArrayBuffer values to strings", () => {
    const request = signInRequestFrom(
      details({ requestBody: { formData: { SAMLRequest: [encode("fZJNb9sw")] } } }),
    );

    expect(request).toEqual({
      url: samlUrl,
      method: "POST",
      fields: [["SAMLRequest", "fZJNb9sw"]],
    });
  });

  // The protocol carries pairs rather than an object for exactly this: an object would
  // silently drop one of them.
  it("keeps a repeated field name as separate pairs", () => {
    const request = signInRequestFrom(
      details({ requestBody: { formData: { scope: ["openid", "profile"], state: ["abc"] } } }),
    );

    expect(request).toEqual({
      url: samlUrl,
      method: "POST",
      fields: [
        ["scope", "openid"],
        ["scope", "profile"],
        ["state", "abc"],
      ],
    });
  });

  it("parses raw bytes as urlencoded when formData is absent", () => {
    const request = signInRequestFrom(
      details({
        requestBody: {
          raw: [{ bytes: encode("SAMLRequest=fZJNb9sw%3D%3D&scope=open+id&scope=profile") }],
        },
      }),
    );

    expect(request).toEqual({
      url: samlUrl,
      method: "POST",
      fields: [
        ["SAMLRequest", "fZJNb9sw=="],
        ["scope", "open id"],
        ["scope", "profile"],
      ],
    });
  });

  it("joins raw elements before parsing, since a body can arrive in chunks", () => {
    const request = signInRequestFrom(
      details({ requestBody: { raw: [{ bytes: encode("a=1&b") }, { bytes: encode("=2") }] } }),
    );

    expect(request).toEqual({
      url: samlUrl,
      method: "POST",
      fields: [
        ["a", "1"],
        ["b", "2"],
      ],
    });
  });

  it("takes a POST with no readable body as a POST with no fields", () => {
    expect(signInRequestFrom(details({ requestBody: {} }))).toEqual({
      url: samlUrl,
      method: "POST",
      fields: [],
    });
  });

  it("ignores a method that is not a sign-in navigation", () => {
    expect(signInRequestFrom(details({ method: "HEAD" }))).toBeNull();
  });
});

describe("isEntryOrigin", () => {
  it("accepts the generated entry origin whatever the path", () => {
    expect(isEntryOrigin(authorizeUrl)).toBe(true);
    expect(isEntryOrigin("https://login.microsoftonline.com/")).toBe(true);
  });

  it("rejects a look-alike host, a plain-HTTP origin, and a missing URL", () => {
    expect(isEntryOrigin("https://login.microsoftonline.com.evil.test/common")).toBe(false);
    expect(isEntryOrigin("http://login.microsoftonline.com/common")).toBe(false);
    expect(isEntryOrigin("not a url")).toBe(false);
    expect(isEntryOrigin(undefined)).toBe(false);
  });
});
