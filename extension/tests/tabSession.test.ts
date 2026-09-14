import { describe, expect, it } from "vitest";
import { captureMaxAgeMs, tabSession } from "../src/tabSession";
import type { SessionArea } from "../src/tabSession";
import type { SignInRequest } from "../src/protocol";

const request: SignInRequest = {
  url: "https://login.microsoftonline.com/common/saml2",
  method: "POST",
  fields: [["SAMLRequest", "fZJNb9sw"]],
};

/**
 * A `storage.session` stand-in that outlives the module reading it, which is the point:
 * the browser's area belongs to the browser context, not to the service worker, so a
 * test that builds a second `tabSession` over the same area is asking the same question
 * an eviction asks.
 */
function fakeSessionArea() {
  const items = new Map<string, unknown>();
  const area: SessionArea = {
    get: async (keys) =>
      Object.fromEntries(keys.filter((key) => items.has(key)).map((key) => [key, items.get(key)])),
    set: async (entries) => {
      for (const [key, value] of Object.entries(entries)) {
        items.set(key, value);
      }
    },
    remove: async (keys) => {
      for (const key of keys) {
        items.delete(key);
      }
    },
  };
  return { area, items };
}

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

  it("drops the capture and the claim when the tab closes", async () => {
    const { area, items } = fakeSessionArea();
    const session = tabSession(area);

    await session.recordCapture(7, request, now);
    await session.claimHandoff(7, now);
    await session.forgetTab(7);

    expect([...items.keys()]).toEqual([]);
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

  it("ignores a stored value it cannot read as a capture", async () => {
    const { area } = fakeSessionArea();
    await area.set({ "capture:7": "nonsense" });

    await expect(tabSession(area).readCapture(7, now)).resolves.toBeNull();
  });
});
