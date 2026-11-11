import { describe, expect, it } from "vitest";
import { isDeliverableCallbackUrl } from "../src/callbackUrl";

describe("isDeliverableCallbackUrl", () => {
  it("accepts an ordinary HTTPS callback", () => {
    expect(isDeliverableCallbackUrl("https://app.example.com/signin-oidc?code=0.Ac8")).toBe(true);
    expect(isDeliverableCallbackUrl("https://app.example.com:8443/sso/acs")).toBe(true);
  });

  it("accepts plain HTTP only on loopback", () => {
    expect(isDeliverableCallbackUrl("http://localhost:8080/?code=0.Ac8")).toBe(true);
    expect(isDeliverableCallbackUrl("http://LOCALHOST/signin-oidc")).toBe(true);
    expect(isDeliverableCallbackUrl("http://127.0.0.1:5000/signin-oidc")).toBe(true);
    expect(isDeliverableCallbackUrl("http://localhost.example.com/signin-oidc")).toBe(false);
    expect(isDeliverableCallbackUrl("http://[::1]:8080/signin-oidc")).toBe(false);
    expect(isDeliverableCallbackUrl("http://user:secret@localhost:8080/c")).toBe(false);
  });

  // The Extension drives the tab, so it does not take the Bridge's word for where.
  it("rejects anything else that is not HTTPS", () => {
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
