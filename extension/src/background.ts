import { isDeliverableCallbackUrl } from "./callbackUrl";
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

/**
 * Drives the original tab to the Callback, and reports whether the Handoff got there.
 * Only a delivered Callback spends the capture: everything else leaves it in place so
 * the same Sign-in request can be replayed without going back through the
 * Application's login page.
 */
async function deliverCallback(tabId: number, outcome: HandoffOutcome): Promise<HandoffEnd> {
  if (outcome.outcome !== "response" || outcome.response.result !== "callback") {
    return "failure";
  }
  const callback = outcome.response;
  if (!isDeliverableCallbackUrl(callback.url)) {
    console.log("Enterprise SSO Bridge: the returned callback URL was rejected");
    return "failure";
  }
  if (callback.method === "POST") {
    // A POST Callback is submitted from the Relay page, which is issue #26.
    console.log("Enterprise SSO Bridge: a POST callback cannot be delivered yet");
    return "failure";
  }
  try {
    await chrome.tabs.update(tabId, { url: callback.url });
  } catch (error) {
    console.log("Enterprise SSO Bridge: could not navigate the tab", error);
    return "failure";
  }
  return "success";
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
    // The badge, the title, and the popup copy arrive with the states in
    // docs/spec/extension.md, which is issue #27. Until then the console is the only
    // observable for anything that is not a delivered Callback.
    console.log("Enterprise SSO Bridge:", outcome);
    end = await deliverCallback(tabId, outcome);
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
