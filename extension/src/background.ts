import { actionState, handoffVerdict } from "./actionState";
import type { DeliverableCallback, StateName } from "./actionState";
import { entryOriginMatchPatterns } from "./generated/entryOrigins";
import { requestHandoff } from "./nativeMessaging";
import type { HandoffOutcome } from "./nativeMessaging";
import { retriedTabId } from "./retry";
import { isEntryOrigin, signInRequestFrom } from "./signInRequest";
import { tabSession } from "./tabSession";
import type { HandoffEnd } from "./tabSession";

const session = tabSession();
// Action state shares storage with the popup and Relay page.
const state = actionState();

// Main-frame navigations skip the initiator permission check in both engines, so the
// generated entry origins alone are enough to see the Application's cross-site POST or
// redirect into the identity provider. `requestBody` is what carries a SAML POST's
// fields; without it a POST arrives as a bare URL and replays as nothing.
chrome.webRequest.onBeforeRequest.addListener(
  // The annotation is only for `@types/chrome`, which types every listener as the
  // blocking one. This listener observes and never asks for "blocking", so the engines
  // ignore whatever it returns.
  (details): undefined => {
    if (details.tabId < 0) {
      return;
    }
    const request = signInRequestFrom(details);
    if (request === null) {
      return;
    }
    void session.recordCapture(details.tabId, request, Date.now());
  },
  { urls: entryOriginMatchPatterns, types: ["main_frame"] },
  ["requestBody"],
);

/**
 * Drives the original tab to the Callback. Returns the state the tab is left in, or
 * null when it got there, because the tab arriving at the Application is the success
 * signal and there is no success badge.
 */
async function deliverCallback(
  tabId: number,
  callback: DeliverableCallback,
): Promise<StateName | null> {
  // Idle before the navigation rather than after it: a POST Callback's tab is about to
  // load the Relay page, which sets its own state if it finds nothing to submit, and a
  // clear arriving after that would wipe the only thing the user was told.
  await state.clear(tabId);
  if (callback.method !== "POST") {
    return navigate(tabId, callback.url);
  }
  // The Relay page reads this and deletes it as it reads, so it has to be there before
  // the tab is sent to it. A tab that never gets there must not leave the assertion
  // behind, and `takeCallback` is the delete.
  await session.storeCallback(tabId, { url: callback.url, fields: callback.fields });
  const failure = await navigate(tabId, chrome.runtime.getURL("relay.html"));
  if (failure !== null) {
    await session.takeCallback(tabId);
  }
  return failure;
}

async function navigate(tabId: number, url: string): Promise<StateName | null> {
  try {
    await chrome.tabs.update(tabId, { url });
  } catch (error) {
    // Nothing explained this one: the Bridge is done and the tab never moved.
    console.debug("Enterprise SSO Bridge: could not navigate the tab", error);
    return "unknownReason";
  }
  return null;
}

/** The console is where `detail` lives. None of it is ever shown to the user. */
function logOutcome(outcome: HandoffOutcome, name: StateName) {
  const detail =
    outcome.outcome === "disconnected"
      ? outcome.detail
      : outcome.outcome === "response" && outcome.response.result === "error"
        ? outcome.response.detail
        : undefined;
  console.debug("Enterprise SSO Bridge:", name, detail ?? "");
}

/**
 * Where a Handoff came from. A toolbar click has to be on a sign-in page; Try again
 * has been on one already and replays the capture that survived the failure.
 */
type Start = { from: "click"; tabUrl: string | undefined } | { from: "retry" };

async function runHandoff(tabId: number, start: Start) {
  if (!(await session.claimHandoff(tabId, Date.now()))) {
    // A Handoff is already running for this tab and the Bridge window has the user's
    // attention. A second click is not a second sign-in.
    return;
  }
  // Every exit from here releases the claim, or the tab could never start another
  // Handoff. Only a terminal success spends the capture.
  let end: HandoffEnd = "failure";
  try {
    if (start.from === "click" && !isEntryOrigin(start.tabUrl)) {
      await state.show(tabId, "wrongPage");
      return;
    }
    await state.show(tabId, "inFlight");
    const request = await session.readCapture(tabId, Date.now());
    if (request === null) {
      // Nothing to replay: the capture aged out, or Gecko missed the Sign-in request
      // issued before its listener was primed. Both send the user back to the
      // Application's login page, which is what this copy says.
      await state.settle(tabId, "cannotStart");
      return;
    }
    const outcome = await requestHandoff(request);
    const verdict = handoffVerdict(outcome);
    if ("state" in verdict) {
      logOutcome(outcome, verdict.state);
      await state.settle(tabId, verdict.state);
      return;
    }
    const failure = await deliverCallback(tabId, verdict.deliver);
    if (failure !== null) {
      await state.settle(tabId, failure);
      return;
    }
    end = "success";
  } finally {
    await session.finishHandoff(tabId, end);
  }
}

chrome.action.onClicked.addListener((tab) => {
  // `activeTab` grants the URL for the moment of the interaction, so read it before
  // anything is awaited rather than asking for it again after the Bridge replies.
  const { id, url } = tab;
  if (id === undefined || id < 0) {
    return;
  }
  void runHandoff(id, { from: "click", tabUrl: url });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const tabId = retriedTabId(message);
  if (tabId === null) {
    return false;
  }
  // The clear is what the button promises, and it happens even if the Handoff below
  // cannot start, so Try again is never a dead end with the popup still attached.
  void state.clear(tabId).then(() => runHandoff(tabId, { from: "retry" }));
  sendResponse();
  return false;
});

// Without the `tabs` permission a navigation away from an entry origin arrives with no
// URL, so the load itself is the signal. A Handoff never moves the tab on its own, so
// the only loads seen mid-Handoff are the Callback's, which wants the badge cleared too.
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "loading") {
    void state.clear(tabId);
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  void session.forgetTab(tabId);
});
