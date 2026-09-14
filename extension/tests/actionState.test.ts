import { describe, expect, it } from "vitest";
import {
  actionState,
  attentionBadge,
  copyFor,
  handoffVerdict,
  inFlightBadge,
  popupPage,
  stateCopy,
} from "../src/actionState";
import type { ActionArea, ActionCopy, StateName } from "../src/actionState";
import type { HandoffOutcome } from "../src/nativeMessaging";
import { tabSession } from "../src/tabSession";
import { fakeSessionArea } from "./helpers/fakeSessionArea";

/**
 * The copy table in docs/spec/extension.md, transcribed. Asserting the module against
 * this rather than against itself is the point: an edited sentence fails here until
 * the spec's row is edited too, and a state with no row fails for being absent.
 */
const spec: Record<StateName, ActionCopy> = {
  idle: {
    badge: "",
    title: "Sign in with Enterprise SSO Bridge",
    popup: null,
  },
  inFlight: {
    badge: "…",
    title: "Sign-in is open in Enterprise SSO Bridge.",
    popup: null,
  },
  wrongPage: {
    badge: "!",
    title: "Open the application's Microsoft sign-in page first.",
    popup: "Open the application's Microsoft sign-in page first, then click this button.",
  },
  noReply: {
    badge: "!",
    title: "Enterprise SSO Bridge did not respond.",
    popup:
      "Enterprise SSO Bridge did not respond. Install it from the release page, or check that it is installed in /Applications.",
  },
  versionMismatch: {
    badge: "!",
    title: "Version mismatch with Enterprise SSO Bridge.",
    popup:
      "Enterprise SSO Bridge is a different version than this extension. Install the matching release of both.",
  },
  cannotStart: {
    badge: "!",
    title: "This sign-in could not be started.",
    popup:
      "This sign-in could not be started. Go back to the application's login page and start again from there.",
  },
  unreadableRequest: {
    badge: "!",
    title: "The sign-in request could not be read.",
    popup: "The sign-in request could not be read. Start again from the application's login page.",
  },
  bridgeExplained: {
    badge: "!",
    title: "Sign-in failed. Enterprise SSO Bridge has the details.",
    popup: null,
  },
  unknownReason: {
    badge: "!",
    title: "Sign-in failed for an unrecognized reason.",
    popup:
      "Sign-in failed for an unrecognized reason. Check that Enterprise SSO Bridge and this extension are the same version.",
  },
  rejectedCallback: {
    badge: "!",
    title: "The sign-in response pointed somewhere unexpected.",
    popup: "The sign-in response pointed somewhere unexpected and was not opened.",
  },
  cancelled: {
    badge: "",
    title: "Sign-in cancelled. Click to start again.",
    popup: null,
  },
  alreadyCompleted: {
    badge: "!",
    title: "This sign-in has already been completed or has expired.",
    popup:
      "This sign-in has already been completed or has expired. Start again from the application's login page.",
  },
};

const specNames = Object.keys(spec) as StateName[];

function response(result: unknown): HandoffOutcome {
  return { outcome: "response", response: result as never };
}

/** An `action` stand-in that records what a real toolbar button would have been told. */
function fakeActionArea() {
  const calls: { method: string; details: Record<string, unknown> }[] = [];
  const record =
    (method: string) =>
    async (details: Record<string, unknown>): Promise<void> => {
      calls.push({ method, details });
    };
  const area: ActionArea = {
    setBadgeText: record("setBadgeText"),
    setBadgeBackgroundColor: record("setBadgeBackgroundColor"),
    setTitle: record("setTitle"),
    setPopup: record("setPopup"),
  };
  const detailsOf = (method: string) =>
    calls.filter((call) => call.method === method).map((call) => call.details);
  return { area, calls, detailsOf };
}

describe("the copy table", () => {
  it.each(specNames)("says what the spec says for %s", (name) => {
    expect(stateCopy[name]).toEqual(spec[name]);
  });

  it("has no state the spec does not list", () => {
    expect(Object.keys(stateCopy).sort()).toEqual([...specNames].sort());
  });

  // Three badge states and no fourth, and no success badge: the tab navigating to the
  // Application is the success signal.
  it("uses only the three badges", () => {
    const badges = new Set(specNames.map((name) => stateCopy[name].badge));
    expect([...badges].sort()).toEqual(["", attentionBadge, inFlightBadge].sort());
  });

  // No error code name, no OSStatus, nothing the user cannot act on. `detail` stays in
  // the console. The codes that are also ordinary English (`internal`, `declined`,
  // `unrecognized`) are left out: the copy uses them as words, which is the point.
  it("never spells a wire code or a status at the user", () => {
    const words =
      /unsupported_version|unsupported_request|malformed_request|callback_too_large|navigation_failed|OSStatus|NSURLError|errSec/;
    for (const name of specNames) {
      const copy = stateCopy[name];
      expect(copy.title).not.toMatch(words);
      expect(copy.popup ?? "").not.toMatch(words);
    }
  });

  // "Enterprise SSO Bridge" on first mention, "the Bridge" after, so no sentence may
  // open with the short form.
  it("names the Bridge in full wherever it names it", () => {
    for (const name of specNames) {
      for (const sentence of [stateCopy[name].title, stateCopy[name].popup ?? ""]) {
        if (sentence.includes("Bridge")) {
          expect(sentence).toContain("Enterprise SSO Bridge");
        }
      }
    }
  });

  it("reads a stored state name back, and ignores one it does not know", () => {
    expect(copyFor("noReply")).toEqual(spec.noReply);
    expect(copyFor("sunspots")).toBeNull();
    expect(copyFor(null)).toBeNull();
  });
});

describe("the verdict on an exchange with the Bridge", () => {
  it("takes a deliverable Callback to deliver", () => {
    const callback = { result: "callback", url: "https://app.example.com/acs", method: "GET" };
    expect(handoffVerdict(response(callback))).toEqual({ deliver: callback });
  });

  // The Extension drives the tab, so it does not take the Bridge's word for where.
  it.each([
    ["a plaintext target", "http://app.example.com/acs"],
    ["embedded credentials", "https://user:secret@app.example.com/acs"],
  ])("refuses a Callback with %s", (_name, url) => {
    expect(handoffVerdict(response({ result: "callback", url, method: "GET" }))).toEqual({
      state: "rejectedCallback",
    });
  });

  it.each([
    ["unsupported_version", "versionMismatch"],
    ["unsupported_request", "cannotStart"],
    ["malformed_request", "unreadableRequest"],
    ["callback_too_large", "bridgeExplained"],
    ["navigation_failed", "bridgeExplained"],
    ["internal", "bridgeExplained"],
  ])("shows %s as %s", (code, state) => {
    expect(handoffVerdict(response({ result: "error", code, detail: "secret" }))).toEqual({
      state,
    });
  });

  // An older Extension has to survive a newer Bridge, so a code outside the closed set
  // falls back to the generic copy rather than failing.
  it("falls back to the generic copy for a code it does not know", () => {
    const outcome = response({ result: "error", code: "unrecognized", received: "sunspots" });
    expect(handoffVerdict(outcome)).toEqual({ state: "unknownReason" });
  });

  it("shows a reply it cannot read at all as the generic failure", () => {
    expect(handoffVerdict({ outcome: "unreadable", message: 7 })).toEqual({
      state: "unknownReason",
    });
  });

  it("shows a disconnect with no reply as the Bridge not responding", () => {
    expect(handoffVerdict({ outcome: "disconnected", detail: "no such native app" })).toEqual({
      state: "noReply",
    });
  });

  // A cancellation that looks like an error teaches the user to distrust the red badge.
  it("shows a declined Approval as cancelled, with no red and no popup", () => {
    expect(handoffVerdict(response({ result: "declined" }))).toEqual({ state: "cancelled" });
    expect(stateCopy.cancelled.badge).toBe("");
    expect(stateCopy.cancelled.popup).toBeNull();
  });
});

describe("showing a state on the action", () => {
  function subject() {
    const { area, detailsOf } = fakeActionArea();
    const { area: storage } = fakeSessionArea();
    const session = tabSession(storage);
    return { state: actionState(area, session), session, detailsOf };
  }

  it.each(specNames)("applies the badge, the title, and the popup for %s", async (name) => {
    const { state, session, detailsOf } = subject();
    await state.show(7, name);
    const copy = spec[name];

    expect(detailsOf("setBadgeText")).toEqual([{ tabId: 7, text: copy.badge }]);
    expect(detailsOf("setTitle")).toEqual([{ tabId: 7, title: copy.title }]);
    // An empty string is the documented reset in both engines: no popup, and
    // `action.onClicked` fires again.
    expect(detailsOf("setPopup")).toEqual([
      { tabId: 7, popup: copy.popup === null ? "" : popupPage },
    ]);
    expect(detailsOf("setBadgeBackgroundColor")).toHaveLength(copy.badge === "!" ? 1 : 0);
    await expect(session.readState(7)).resolves.toBe(name);
  });

  it("clears back to idle, dropping the popup and the record", async () => {
    const { state, session, detailsOf } = subject();
    await state.show(7, "noReply");
    await state.clear(7);

    expect(detailsOf("setBadgeText").at(-1)).toEqual({ tabId: 7, text: "" });
    expect(detailsOf("setTitle").at(-1)).toEqual({ tabId: 7, title: spec.idle.title });
    expect(detailsOf("setPopup").at(-1)).toEqual({ tabId: 7, popup: "" });
    await expect(session.readState(7)).resolves.toBeNull();
  });

  // Every navigation in every tab reaches `clear`, so an idle tab must cost one read.
  it("touches nothing when the tab has no state", async () => {
    const { state, detailsOf } = subject();
    await state.clear(7);

    expect(detailsOf("setBadgeText")).toEqual([]);
    expect(detailsOf("setPopup")).toEqual([]);
  });
});
