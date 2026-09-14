// The Relay page: read this tab's POST Callback once, and submit it to the Application
// from the tab the user started in. The page exists for about the length of a form
// submission, so it says one line and does not style it; a flash of styled content is
// worse than a flash of text.

import { actionState, stateCopy } from "./actionState";
import { engineApi } from "./engineApi";
import { tabSession } from "./tabSession";
import type { PostCallback } from "./tabSession";

// The page says its own line, and the toolbar action says the same thing, because a
// tab that has moved on from the Relay page would otherwise carry no trace of a
// sign-in that never completed. Nothing else spoke for this one: the Bridge finished
// successfully and handed the Callback back.
let currentTabId: number | undefined;

function showUnavailable() {
  const message = document.getElementById("message");
  if (message !== null) {
    message.textContent = stateCopy.alreadyCompleted.popup;
  }
  if (currentTabId !== undefined) {
    void actionState().show(currentTabId, "alreadyCompleted");
  }
}

/**
 * Builds the Callback's form and submits it.
 *
 * A form's own named controls shadow its properties, and the field names here come from
 * the identity provider rather than from this Extension, so nothing reaches the form
 * through a property that a field could have replaced. The inputs are collected in a
 * fragment, which has no named controls to shadow anything, and `submit` comes off the
 * prototype. A field named `append` would otherwise replace the method building the
 * form and throw before the assertion was ever sent.
 */
function submit(callback: PostCallback) {
  const form = document.createElement("form");
  form.method = "POST";
  form.action = callback.url;
  const fields = document.createDocumentFragment();
  for (const [name, value] of callback.fields) {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = value;
    fields.append(input);
  }
  HTMLFormElement.prototype.append.call(form, fields);
  document.body.append(form);
  HTMLFormElement.prototype.submit.call(form);
}

// The extension-pages CSP keeps `form-action https:`, which blocks a plaintext
// submission target. A blocked submission is otherwise silent: the page would sit
// there saying it is returning the user to an application it never reached.
document.addEventListener("securitypolicyviolation", showUnavailable);

async function run() {
  // The tab is the key, and a page cannot be told which tab it is in by its URL without
  // trusting the URL. Reading it needs no permission beyond what the Extension has.
  const tabId = (await engineApi().tabs.getCurrent())?.id;
  currentTabId = tabId;
  const callback = tabId === undefined ? null : await tabSession().takeCallback(tabId);
  if (callback === null) {
    showUnavailable();
    return;
  }
  submit(callback);
}

void run();
