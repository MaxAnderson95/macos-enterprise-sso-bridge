import { requestHandoff } from "./nativeMessaging";
import type { SignInRequest } from "./protocol";

// Hardcoded so the wire can be exercised before there is anything to capture.
// Observing the real Sign-in request through `webRequest` is issue #22, and it
// replaces this constant and the click handler's use of it.
const developmentSignInRequest: SignInRequest = {
  url: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=00000000-0000-0000-0000-000000000000&response_type=code&redirect_uri=https%3A%2F%2Fapp.example.com%2Fsso%2Fcallback&scope=openid&state=development",
  method: "GET",
};

chrome.action.onClicked.addListener(() => {
  void (async () => {
    const outcome = await requestHandoff(developmentSignInRequest);
    // The badge, the title, and the popup copy are per-tab state that arrives with
    // the states in docs/spec/extension.md. Until then the console is the observable.
    console.log("Enterprise SSO Bridge:", outcome);
  })();
});
