import { describe, expect, it } from "vitest";
import { isIdentityProviderOrigin, signInRequestFrom } from "../src/signInRequest";
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

  // A saved account sends Entra through its own pages before any credential is asked
  // for: the username POST, the passkey page's "Sign in another way", a forgotten
  // account. Each lands back on the entry origin with nothing left to replay, and each
  // would otherwise replace the Application's request.
  it("ignores a navigation the identity provider issued itself, under either engine's name", () => {
    const reprocess = "https://login.microsoftonline.com/tenant/reprocess?ctx=opaque";
    expect(
      signInRequestFrom({
        url: reprocess,
        method: "GET",
        initiator: "https://login.microsoft.com",
      }),
    ).toBeNull();
    expect(
      signInRequestFrom({
        url: reprocess,
        method: "GET",
        originUrl: "https://login.microsoft.com/tenant/bridge/fido?iiv=1",
      }),
    ).toBeNull();
    expect(
      signInRequestFrom(
        details({
          initiator: "https://login.microsoftonline.com",
          requestBody: { formData: { login: ["user@example.com"] } },
        }),
      ),
    ).toBeNull();
  });

  it("captures a navigation from the Application, from nowhere, or from an opaque origin", () => {
    const expected = { url: authorizeUrl, method: "GET" };
    expect(
      signInRequestFrom({ url: authorizeUrl, method: "GET", initiator: "https://app.example.com" }),
    ).toEqual(expected);
    expect(signInRequestFrom({ url: authorizeUrl, method: "GET" })).toEqual(expected);
    expect(signInRequestFrom({ url: authorizeUrl, method: "GET", initiator: "null" })).toEqual(
      expected,
    );
  });
});

describe("isIdentityProviderOrigin", () => {
  it("accepts the entry origin and the interior origin whatever the path", () => {
    expect(isIdentityProviderOrigin(authorizeUrl)).toBe(true);
    expect(isIdentityProviderOrigin("https://login.microsoftonline.com/")).toBe(true);
    expect(isIdentityProviderOrigin("https://login.microsoft.com/tenant/bridge/fido?iiv=1")).toBe(
      true,
    );
  });

  it("rejects a look-alike host, a plain-HTTP origin, and a missing URL", () => {
    expect(isIdentityProviderOrigin("https://login.microsoftonline.com.evil.test/common")).toBe(
      false,
    );
    expect(isIdentityProviderOrigin("http://login.microsoftonline.com/common")).toBe(false);
    expect(isIdentityProviderOrigin("not a url")).toBe(false);
    expect(isIdentityProviderOrigin(undefined)).toBe(false);
  });
});
