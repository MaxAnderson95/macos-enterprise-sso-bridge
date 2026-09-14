import { entryOriginMatchPatterns } from "./generated/entryOrigins";
import { requestHandoff } from "./nativeMessaging";
import type { HandoffOutcome } from "./nativeMessaging";
import { isEntryOrigin, signInRequestFrom } from "./signInRequest";
import { tabSession } from "./tabSession";
import type { HandoffEnd } from "./tabSession";

const session = tabSession();

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

function isTerminalSuccess(outcome: HandoffOutcome): boolean {
  return outcome.outcome === "response" && outcome.response.result === "callback";
}

async function startHandoff(tabId: number, tabUrl: string | undefined) {
  if (!(await session.claimHandoff(tabId, Date.now()))) {
    // A Handoff is already running for this tab and the Bridge window has the user's
    // attention. A second click is not a second sign-in.
    return;
  }
  // Every exit from here releases the claim, or the tab could never start another
  // Handoff. Only a terminal success spends the capture.
  let end: HandoffEnd = "failure";
  try {
    if (!isEntryOrigin(tabUrl)) {
      console.log("Enterprise SSO Bridge: not on a sign-in page");
      return;
    }
    const request = await session.readCapture(tabId, Date.now());
    if (request === null) {
      console.log("Enterprise SSO Bridge: no recent capture for this tab");
      return;
    }
    const outcome = await requestHandoff(request);
    end = isTerminalSuccess(outcome) ? "success" : "failure";
    // The badge, the title, the popup copy, and driving the tab to the Callback all
    // arrive with the states in docs/spec/extension.md. Until then the console is the
    // observable.
    console.log("Enterprise SSO Bridge:", outcome);
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
  void startHandoff(id, url);
});

chrome.tabs.onRemoved.addListener((tabId) => {
  void session.forgetTab(tabId);
});
