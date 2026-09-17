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
      details({
        requestBody: {
          formData: { SAMLRequest: ["fZJNb9sw"], scope: ["openid", "profile"], state: ["abc"] },
        },
      }),
    );

    expect(request).toEqual({
      url: samlUrl,
      method: "POST",
      fields: [
        ["SAMLRequest", "fZJNb9sw"],
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
      details({
        requestBody: { raw: [{ bytes: encode("SAMLRequest=fZJ&b") }, { bytes: encode("=2") }] },
      }),
    );

    expect(request).toEqual({
      url: samlUrl,
      method: "POST",
      fields: [
        ["SAMLRequest", "fZJ"],
        ["b", "2"],
      ],
    });
  });

  // The HTTP-Redirect SAML binding puts the request in the query, and the marker check
  // has to find it there for a GET as well as in a POST's fields.
  it("keeps a GET carrying SAMLRequest in its query", () => {
    const url = `${samlUrl}?SAMLRequest=fZJNb9sw&RelayState=%2F`;
    expect(signInRequestFrom({ url, method: "GET" })).toEqual({ url, method: "GET" });
  });

  it("ignores a method that is not a sign-in navigation", () => {
    expect(signInRequestFrom(details({ method: "HEAD" }))).toBeNull();
  });

  // A saved account sends Entra through its own pages before any credential is asked
  // for: the username POST, the passkey page's "Sign in another way", a forgotten
  // account. Each lands back on the entry origin with nothing the Bridge can replay,
  // and each would otherwise replace the Application's request.
  it("ignores a load with no marker, which is a step inside a sign-in and not one", () => {
    expect(
      signInRequestFrom({
        url: "https://login.microsoftonline.com/tenant/reprocess?ctx=opaque",
        method: "GET",
      }),
    ).toBeNull();
    expect(
      signInRequestFrom({
        url: "https://login.microsoftonline.com/tenant/login",
        method: "POST",
        requestBody: { formData: { login: ["user@example.com"], ctx: ["opaque"] } },
      }),
    ).toBeNull();
    expect(signInRequestFrom(details({ requestBody: {} }))).toBeNull();
  });

  it("does not let a marker-shaped path or a marker inside a value count", () => {
    expect(
      signInRequestFrom({
        url: "https://login.microsoftonline.com/redirect_uri/SAMLRequest",
        method: "GET",
      }),
    ).toBeNull();
    expect(
      signInRequestFrom(details({ requestBody: { formData: { ctx: ["SAMLRequest"] } } })),
    ).toBeNull();
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
