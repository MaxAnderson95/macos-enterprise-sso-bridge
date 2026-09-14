// The popup: one sentence about why a Handoff needs attention, and a Try again button.
// It is attached to a tab only for failures nothing else explained, so it says what the
// state recorded for that tab says, and nothing it invents.

import { copyFor } from "./actionState";
import { engineApi } from "./engineApi";
import { retryMessage } from "./retry";
import { tabSession } from "./tabSession";

async function run() {
  const api = engineApi();
  // The tab id alone needs no permission, and the popup is always over the tab whose
  // state it was attached to.
  const [tab] = await api.tabs.query({ active: true, currentWindow: true });
  const tabId = tab?.id;
  const copy = tabId === undefined ? null : copyFor(await tabSession().readState(tabId));
  const message = document.getElementById("message");
  const retry = document.getElementById("retry");
  if (message === null || retry === null) {
    return;
  }
  if (tabId === undefined || copy?.popup == null) {
    // Whatever this was opened to explain is already resolved, so it says nothing
    // rather than inventing a reason.
    window.close();
    return;
  }
  message.textContent = copy.popup;
  retry.hidden = false;
  retry.addEventListener("click", () => {
    void api.runtime.sendMessage(retryMessage(tabId));
    window.close();
  });
}

void run();
