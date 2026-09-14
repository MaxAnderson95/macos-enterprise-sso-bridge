import { describe, expect, it } from "vitest";
import { requestHandoff } from "../src/nativeMessaging";
import type { NativePort } from "../src/nativeMessaging";
import type { SignInRequest } from "../src/protocol";

const request: SignInRequest = {
  url: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
  method: "GET",
};

/** A port whose two events the test fires by hand, in whichever order it wants. */
function fakePort() {
  const messageListeners: ((message: unknown) => void)[] = [];
  const disconnectListeners: (() => void)[] = [];
  const posted: unknown[] = [];
  let disconnected = false;

  const port: NativePort = {
    postMessage: (message) => posted.push(message),
    disconnect: () => {
      disconnected = true;
    },
    onMessage: { addListener: (listener) => messageListeners.push(listener) },
    onDisconnect: { addListener: (listener) => disconnectListeners.push(listener) },
  };

  return {
    port,
    posted,
    get disconnected() {
      return disconnected;
    },
    deliver: (message: unknown) => messageListeners.forEach((listener) => listener(message)),
    close: () => disconnectListeners.forEach((listener) => listener()),
  };
}

describe("requestHandoff", () => {
  it("sends exactly one versioned request frame", async () => {
    const fake = fakePort();
    const settled = requestHandoff(request, () => fake.port);
    fake.deliver({ result: "declined" });
    await settled;

    expect(fake.posted).toEqual([{ version: 1, url: request.url, method: "GET" }]);
  });

  it("resolves on the terminal response and closes the port", async () => {
    const fake = fakePort();
    const settled = requestHandoff(request, () => fake.port);
    fake.deliver({ result: "callback", url: "https://app.example.com/sso/acs", method: "GET" });

    await expect(settled).resolves.toEqual({
      outcome: "response",
      response: { result: "callback", url: "https://app.example.com/sso/acs", method: "GET" },
    });
    expect(fake.disconnected).toBe(true);
  });

  it("tells a disconnect with no reply apart from a response", async () => {
    const fake = fakePort();
    const settled = requestHandoff(request, () => fake.port);
    fake.close();

    await expect(settled).resolves.toEqual({ outcome: "disconnected" });
  });

  // The Bridge exits after its terminal response, so the port always closes. The
  // response has to win that race or every successful Handoff would read as a crash.
  it("keeps the response when the port closes straight afterwards", async () => {
    const fake = fakePort();
    const settled = requestHandoff(request, () => fake.port);
    fake.deliver({ result: "declined" });
    fake.close();

    await expect(settled).resolves.toEqual({
      outcome: "response",
      response: { result: "declined" },
    });
  });

  it("reports a message it cannot read without pretending it was an error", async () => {
    const fake = fakePort();
    const settled = requestHandoff(request, () => fake.port);
    fake.deliver({ result: "shrug" });

    await expect(settled).resolves.toEqual({
      outcome: "unreadable",
      message: { result: "shrug" },
    });
  });

  it("reports a connect that throws as a disconnect", async () => {
    await expect(
      requestHandoff(request, () => {
        throw new Error("Specified native messaging host not found.");
      }),
    ).resolves.toEqual({
      outcome: "disconnected",
      detail: "Error: Specified native messaging host not found.",
    });
  });
});
