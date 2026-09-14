// The Relay page: read this tab's POST Callback once, and submit it to the Application
// from the tab the user started in. The page exists for about the length of a form
// submission, so it says one line and does not style it; a flash of styled content is
// worse than a flash of text.

import { tabSession } from "./tabSession";
import type { PostCallback } from "./tabSession";

const unavailable =
  "This sign-in has already been completed or has expired. " +
  "Start again from the application's login page.";

function showUnavailable() {
  const message = document.getElementById("message");
  if (message !== null) {
    message.textContent = unavailable;
  }
}

/**
 * Builds the Callback's form and submits it.
 *
 * `HTMLFormElement.prototype.submit` rather than `form.submit()`, because a form's own
 * named controls shadow its properties, and the field names here come from the
 * identity provider rather than from this Extension.
 */
function submit(callback: PostCallback) {
  const form = document.createElement("form");
  form.method = "POST";
  form.action = callback.url;
  for (const [name, value] of callback.fields) {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = value;
    form.append(input);
  }
  document.body.append(form);
  HTMLFormElement.prototype.submit.call(form);
}

// The extension-pages CSP keeps `form-action https:`, which blocks a plaintext
// submission target. A blocked submission is otherwise silent: the page would sit
// there saying it is returning the user to an application it never reached.
document.addEventListener("securitypolicyviolation", showUnavailable);

async function run() {
  const api = (globalThis as { browser?: typeof chrome }).browser ?? chrome;
  // The tab is the key, and a page cannot be told which tab it is in by its URL without
  // trusting the URL. Reading it needs no permission beyond what the Extension has.
  const tabId = (await api.tabs.getCurrent())?.id;
  const callback = tabId === undefined ? null : await tabSession().takeCallback(tabId);
  if (callback === null) {
    showUnavailable();
    return;
  }
  submit(callback);
}

void run();
