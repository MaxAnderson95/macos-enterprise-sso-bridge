// What the toolbar action says, and what a finished Handoff leaves behind. The copy
// table is the whole point: it is the spec's table in docs/spec/extension.md as data,
// so changing a sentence is a one-line diff and a state with no copy cannot compile.
//
// No error code name, no `OSStatus`, no protocol `detail` reaches this file. The
// `detail` field stays in the console, which is why nothing here takes one.

import { isDeliverableCallbackUrl } from "./callbackUrl";
import { engineApi } from "./engineApi";
import type { HandoffOutcome } from "./nativeMessaging";
import type { BridgeError, BridgeResponse } from "./protocol";
import { tabSession } from "./tabSession";
import type { TabSession } from "./tabSession";

/** The badge that means something needs attention, and the only one drawn on red. */
export const attentionBadge = "!";

/** The badge while a Handoff is in flight. There is no success badge. */
export const inFlightBadge = "…";

const attentionColor = "#d93025";

/** The packaged page attached with `action.setPopup`, by relative path. */
export const popupPage = "popup.html";

export interface ActionCopy {
  /** Badge text: empty, `…` in flight, `!` when something needs attention. */
  badge: string;
  title: string;
  /** The sentence the popup shows, or null when no popup is attached to the tab. */
  popup: string | null;
}

/**
 * Every state the action can be in, with its copy.
 *
 * A state gets a popup only when nothing else spoke. The Bridge shows its own failures
 * in its own window until dismissed, so `bridgeExplained` covers the three codes the
 * user has already read an explanation for and says only what the badge and title can.
 */
export const stateCopy = {
  idle: {
    badge: "",
    title: "Sign in with Enterprise SSO Bridge",
    popup: null,
  },
  inFlight: {
    badge: inFlightBadge,
    title: "Sign-in is open in Enterprise SSO Bridge.",
    popup: null,
  },
  wrongPage: {
    badge: attentionBadge,
    title: "Open the application's Microsoft sign-in page first.",
    popup: "Open the application's Microsoft sign-in page first, then click this button.",
  },
  noReply: {
    badge: attentionBadge,
    title: "Enterprise SSO Bridge did not respond.",
    popup:
      "Enterprise SSO Bridge did not respond. Install it from the release page, or check that it is installed in /Applications.",
  },
  versionMismatch: {
    badge: attentionBadge,
    title: "Version mismatch with Enterprise SSO Bridge.",
    popup:
      "Enterprise SSO Bridge is a different version than this extension. Install the matching release of both.",
  },
  cannotStart: {
    badge: attentionBadge,
    title: "This sign-in could not be started.",
    popup:
      "This sign-in could not be started. Go back to the application's login page and start again from there.",
  },
  unreadableRequest: {
    badge: attentionBadge,
    title: "The sign-in request could not be read.",
    popup: "The sign-in request could not be read. Start again from the application's login page.",
  },
  bridgeExplained: {
    badge: attentionBadge,
    title: "Sign-in failed. Enterprise SSO Bridge has the details.",
    popup: null,
  },
  unknownReason: {
    badge: attentionBadge,
    title: "Sign-in failed for an unrecognized reason.",
    popup:
      "Sign-in failed for an unrecognized reason. Check that Enterprise SSO Bridge and this extension are the same version.",
  },
  rejectedCallback: {
    badge: attentionBadge,
    title: "The sign-in response pointed somewhere unexpected.",
    popup: "The sign-in response pointed somewhere unexpected and was not opened.",
  },
  cancelled: {
    // A declined Approval is not a failure. The user clicked Cancel a second earlier
    // and already knows what happened, and a cancellation that looks like an error
    // teaches them to distrust the red badge.
    badge: "",
    title: "Sign-in cancelled. Click to start again.",
    popup: null,
  },
  alreadyCompleted: {
    badge: attentionBadge,
    title: "This sign-in has already been completed or has expired.",
    popup:
      "This sign-in has already been completed or has expired. Start again from the application's login page.",
  },
} as const satisfies Record<string, ActionCopy>;

export type StateName = keyof typeof stateCopy;

/** The copy for a stored state name, or null when there is no state to explain. */
export function copyFor(name: string | null): ActionCopy | null {
  return name !== null && name in stateCopy ? stateCopy[name as StateName] : null;
}

/** A Callback whose URL this Extension is willing to send the tab to. */
export type DeliverableCallback = Extract<BridgeResponse, { result: "callback" }>;

/**
 * What a finished exchange with the Bridge amounts to: a Callback to deliver, or the
 * state the tab is left in. Nothing else, so the caller cannot forget a case.
 */
export type HandoffVerdict = { deliver: DeliverableCallback } | { state: StateName };

/**
 * `unrecognized` is how a newer Bridge's error code arrives, and it falls back to the
 * generic copy rather than failing: an older Extension has to survive a newer Bridge.
 */
const errorStates: Record<BridgeError["code"], StateName> = {
  unsupported_version: "versionMismatch",
  unsupported_request: "cannotStart",
  malformed_request: "unreadableRequest",
  callback_too_large: "bridgeExplained",
  navigation_failed: "bridgeExplained",
  internal: "bridgeExplained",
  unrecognized: "unknownReason",
};

/**
 * The verdict on one exchange with the Bridge.
 *
 * The returned URL is re-checked here, so a `deliver` verdict is already known to be
 * HTTPS with no embedded credentials and the caller navigates without deciding again.
 */
export function handoffVerdict(outcome: HandoffOutcome): HandoffVerdict {
  if (outcome.outcome === "disconnected") {
    return { state: "noReply" };
  }
  if (outcome.outcome === "unreadable") {
    // The Bridge said something this Extension cannot read at all, which is a version
    // problem wearing a different hat, so it gets the same generic copy.
    return { state: "unknownReason" };
  }
  const response = outcome.response;
  switch (response.result) {
    case "declined":
      return { state: "cancelled" };
    case "error":
      return { state: errorStates[response.code] };
    case "callback":
      return isDeliverableCallbackUrl(response.url)
        ? { deliver: response }
        : { state: "rejectedCallback" };
  }
}

/** The part of `action` this module uses, so a test can supply one. */
export interface ActionArea {
  setBadgeText(details: { tabId: number; text: string }): Promise<void>;
  setBadgeBackgroundColor(details: { tabId: number; color: string }): Promise<void>;
  setTitle(details: { tabId: number; title: string }): Promise<void>;
  setPopup(details: { tabId: number; popup: string }): Promise<void>;
}

function actionArea(): ActionArea {
  const action = engineApi().action;
  return {
    setBadgeText: (details) => action.setBadgeText(details),
    setBadgeBackgroundColor: (details) => action.setBadgeBackgroundColor(details),
    setTitle: (details) => action.setTitle(details),
    setPopup: (details) => action.setPopup(details),
  };
}

export interface ActionState {
  /** Puts a tab into a state: badge, title, popup, and the record the popup reads. */
  show(tabId: number, name: StateName): Promise<void>;
  /** Back to idle, dropping the record and the popup. Cheap when there is no state. */
  clear(tabId: number): Promise<void>;
}

/**
 * The per-tab state as the user sees it. The name is written to `storage.session` as
 * it is applied, because the popup is a separate document that has to know which
 * sentence it was opened to say, and the Chromium service worker can be evicted
 * between the failure and the click that opens it.
 */
export function actionState(
  area: ActionArea = actionArea(),
  session: TabSession = tabSession(),
): ActionState {
  async function apply(tabId: number, name: StateName) {
    const copy = stateCopy[name];
    await area.setBadgeText({ tabId, text: copy.badge });
    if (copy.badge === attentionBadge) {
      await area.setBadgeBackgroundColor({ tabId, color: attentionColor });
    }
    await area.setTitle({ tabId, title: copy.title });
    // An empty string is the documented reset in both engines: the popup is disabled
    // and `action.onClicked` fires again, which is what makes the next click start a
    // Handoff rather than reopen the explanation.
    await area.setPopup({ tabId, popup: copy.popup === null ? "" : popupPage });
  }

  return {
    async show(tabId, name) {
      await apply(tabId, name);
      await session.recordState(tabId, name);
    },

    // Every navigation in every tab reaches this, so it asks before it writes.
    async clear(tabId) {
      if ((await session.readState(tabId)) === null) {
        return;
      }
      await session.clearState(tabId);
      await apply(tabId, "idle");
    },
  };
}
