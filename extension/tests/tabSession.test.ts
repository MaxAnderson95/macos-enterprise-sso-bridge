import { describe, expect, it } from "vitest";
import { captureMaxAgeMs, tabSession } from "../src/tabSession";
import type { PostCallback, SessionArea } from "../src/tabSession";
import type { SignInRequest } from "../src/protocol";
import { fakeSessionArea } from "./helpers/fakeSessionArea";

const request: SignInRequest = {
  url: "https://login.microsoftonline.com/common/saml2",
  method: "POST",
  fields: [["SAMLRequest", "fZJNb9sw"]],
};

/**
 * The same stand-in, with a real delay inside every read. The browser's storage area
 * takes time to answer, so two clicks arriving together would both read an absent claim
 * and both start a Handoff unless the claim is serialized. The instant fake above
 * resolves too promptly for that window to exist.
 */
function slowSessionArea() {
  const { area, items } = fakeSessionArea();
  const settle = () => new Promise((resolve) => setTimeout(resolve, 5));
  const slow: SessionArea = {
    ...area,
    get: async (keys) => {
      await settle();
      return area.get(keys);
    },
    // The write is delayed too. Without it the first claim's write always lands during
    // the gap between the two reads, and the race the serializer prevents never appears.
    set: async (entries) => {
      await settle();
      return area.set(entries);
    },
  };
  return { area: slow, items };
}

const callback: PostCallback = {
  url: "https://app.example.com/sso/acs",
  fields: [
    ["SAMLResponse", "PHNhbWxwOlJlc3BvbnNl"],
    ["RelayState", "opaque"],
  ],
};

const now = 1_780_000_000_000;

describe("tabSession", () => {
  it("returns the capture it recorded for that tab and no other", async () => {
    const { area } = fakeSessionArea();
    const session = tabSession(area);
    await session.recordCapture(7, request, now);

    await expect(session.readCapture(7, now)).resolves.toEqual(request);
    await expect(session.readCapture(8, now)).resolves.toBeNull();
  });

  // An attempt abandoned an hour ago must never replay.
  it("ignores a capture older than ten minutes", async () => {
    const { area } = fakeSessionArea();
    const session = tabSession(area);
    await session.recordCapture(7, request, now);

    await expect(session.readCapture(7, now + captureMaxAgeMs)).resolves.toEqual(request);
    await expect(session.readCapture(7, now + captureMaxAgeMs + 1)).resolves.toBeNull();
  });

  it("grants the claim once until the Handoff finishes", async () => {
    const { area } = fakeSessionArea();
    const session = tabSession(area);

    await expect(session.claimHandoff(7, now)).resolves.toBe(true);
    await expect(session.claimHandoff(7, now)).resolves.toBe(false);
    // Another tab's Handoff is nobody else's business.
    await expect(session.claimHandoff(8, now)).resolves.toBe(true);

    await session.finishHandoff(7, "failure");
    await expect(session.claimHandoff(7, now)).resolves.toBe(true);
  });

  // The opposite of the Relay page's consume-once rule, on purpose: replaying a Sign-in
  // request starts a fresh authentication, so a failure leaves it there to retry.
  it("spends the capture on success and keeps it on failure", async () => {
    const { area } = fakeSessionArea();
    const session = tabSession(area);

    await session.recordCapture(7, request, now);
    await session.claimHandoff(7, now);
    await session.finishHandoff(7, "failure");
    await expect(session.readCapture(7, now)).resolves.toEqual(request);

    await session.claimHandoff(7, now);
    await session.finishHandoff(7, "success");
    await expect(session.readCapture(7, now)).resolves.toBeNull();
  });

  it("grants only one of two claims that overlap on the same tab", async () => {
    const { area } = slowSessionArea();
    const session = tabSession(area);

    // Both clicks start before either read has answered, which is the ordering a
    // second toolbar click during the first click's read produces.
    const claims = await Promise.all([session.claimHandoff(7, now), session.claimHandoff(7, now)]);

    expect(claims).toEqual([true, false]);
  });

  it("recovers an inherited claim after thirty minutes, once even for overlapping clicks", async () => {
    const { area } = slowSessionArea();
    await tabSession(area).claimHandoff(7, now);
    const afterEviction = tabSession(area);
    const thirtyMinutesLater = now + 30 * 60 * 1000;

    await expect(afterEviction.claimHandoff(7, thirtyMinutesLater)).resolves.toBe(false);
    await afterEviction.recordCapture(7, request, thirtyMinutesLater);
    const claims = await Promise.all([
      afterEviction.claimHandoff(7, thirtyMinutesLater + 1),
      afterEviction.claimHandoff(7, thirtyMinutesLater + 1),
    ]);
    expect(claims).toEqual([true, false]);
    await expect(afterEviction.readCapture(7, thirtyMinutesLater + 1)).resolves.toEqual(request);
  });

  it("never expires a claim still active in the same background instance", async () => {
    const { area } = fakeSessionArea();
    const session = tabSession(area);
    await session.claimHandoff(7, now);

    await expect(session.claimHandoff(7, now + 24 * 60 * 60 * 1000)).resolves.toBe(false);
    await session.finishHandoff(7, "failure");
    await expect(session.claimHandoff(7, now + 24 * 60 * 60 * 1000)).resolves.toBe(true);
  });

  it("drops the capture, the claim, the callback, and the state when the tab closes", async () => {
    const { area, items } = fakeSessionArea();
    const session = tabSession(area);

    await session.recordCapture(7, request, now);
    await session.claimHandoff(7, now);
    await session.storeCallback(7, callback);
    await session.recordState(7, "noReply");
    await session.forgetTab(7);

    expect([...items.keys()]).toEqual([]);
  });

  // The popup is a separate document, so the state it was opened to explain has to
  // survive the click that opens it, and an eviction in between.
  it("keeps the state for a tab until it is cleared", async () => {
    const { area } = fakeSessionArea();

    await tabSession(area).recordState(7, "noReply");
    await expect(tabSession(area).readState(7)).resolves.toBe("noReply");
    await expect(tabSession(area).readState(8)).resolves.toBeNull();

    await tabSession(area).clearState(7);
    await expect(tabSession(area).readState(7)).resolves.toBeNull();
  });

  // Chromium can evict the service worker between the navigation and the click, and
  // again between the click and the Bridge's reply. A second instance over the same
  // area is what is left after that, and it has to find both.
  it("finds the capture and the live claim from a fresh instance", async () => {
    const { area } = fakeSessionArea();

    await tabSession(area).recordCapture(7, request, now);
    await expect(tabSession(area).claimHandoff(7, now)).resolves.toBe(true);

    const afterEviction = tabSession(area);
    await expect(afterEviction.readCapture(7, now)).resolves.toEqual(request);
    await expect(afterEviction.claimHandoff(7, now)).resolves.toBe(false);

    await afterEviction.finishHandoff(7, "success");
    await expect(tabSession(area).readCapture(7, now)).resolves.toBeNull();
  });

  // The Relay page's rule, and the reason it is the opposite of the capture's: a reload
  // that resubmitted the assertion would be a replay of a credential.
  it("hands the callback over once and leaves nothing behind", async () => {
    const { area, items } = fakeSessionArea();
    const session = tabSession(area);

    await session.storeCallback(7, callback);

    await expect(session.takeCallback(7)).resolves.toEqual(callback);
    await expect(session.takeCallback(7)).resolves.toBeNull();
    expect([...items.keys()]).toEqual([]);
  });

  // The Relay page is a fresh context with no memory of the background worker, so what
  // it reads is whatever the area holds, and what a reload finds is what it left.
  it("consumes the callback from the instance that did not store it", async () => {
    const { area } = fakeSessionArea();

    await tabSession(area).storeCallback(7, callback);

    await expect(tabSession(area).takeCallback(7)).resolves.toEqual(callback);
    await expect(tabSession(area).takeCallback(7)).resolves.toBeNull();
    await expect(tabSession(area).takeCallback(8)).resolves.toBeNull();
  });

  // The callback is stored a moment before the terminal success is recorded, so ending
  // the Handoff must not spend it.
  it("keeps the callback when the Handoff that stored it finishes", async () => {
    const { area } = fakeSessionArea();
    const session = tabSession(area);

    await session.claimHandoff(7, now);
    await session.storeCallback(7, callback);
    await session.finishHandoff(7, "success");

    await expect(session.takeCallback(7)).resolves.toEqual(callback);
  });

  it("ignores a stored value it cannot read as a capture or a callback", async () => {
    const { area } = fakeSessionArea();
    await area.set({ "capture:7": "nonsense", "callback:7": "nonsense" });

    await expect(tabSession(area).readCapture(7, now)).resolves.toBeNull();
    await expect(tabSession(area).takeCallback(7)).resolves.toBeNull();
  });
});
