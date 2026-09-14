import { describe, expect, it } from "vitest";
import { isDeliverableCallbackUrl } from "../src/callbackUrl";

describe("isDeliverableCallbackUrl", () => {
  it("accepts an ordinary HTTPS callback", () => {
    expect(isDeliverableCallbackUrl("https://app.example.com/signin-oidc?code=0.Ac8")).toBe(true);
    expect(isDeliverableCallbackUrl("https://app.example.com:8443/sso/acs")).toBe(true);
  });

  // The Extension drives the tab, so it does not take the Bridge's word for where.
  it("rejects anything that is not HTTPS", () => {
    expect(isDeliverableCallbackUrl("http://app.example.com/signin-oidc")).toBe(false);
    expect(isDeliverableCallbackUrl("javascript:alert(1)")).toBe(false);
    expect(isDeliverableCallbackUrl("file:///etc/passwd")).toBe(false);
  });

  it("rejects embedded credentials", () => {
    expect(isDeliverableCallbackUrl("https://user:secret@app.example.com/c")).toBe(false);
    expect(isDeliverableCallbackUrl("https://user@app.example.com/c")).toBe(false);
    expect(isDeliverableCallbackUrl("https://:secret@app.example.com/c")).toBe(false);
  });

  it("rejects anything that is not a URL at all", () => {
    expect(isDeliverableCallbackUrl("")).toBe(false);
    expect(isDeliverableCallbackUrl("/signin-oidc")).toBe(false);
  });
});
