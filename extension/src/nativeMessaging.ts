import { parseBridgeResponse, requestMessage } from "./protocol";
import type { BridgeResponse, SignInRequest } from "./protocol";

/**
 * Both engines reject a hyphen in a native-messaging host name, which is why this is
 * not the bundle identifier. The two installed manifests are named after it.
 */
export const nativeHostName = "tech.maxanderson.enterprise_sso_bridge";

/** The part of a `runtime.Port` this module uses, so a test can supply one. */
export interface NativePort {
  postMessage(message: unknown): void;
  disconnect(): void;
  onMessage: { addListener(listener: (message: unknown) => void): void };
  onDisconnect: { addListener(listener: () => void): void };
}

/**
 * How the exchange ended. The Bridge always sends a terminal response, so a
 * disconnect without one is a crash, a rejected Caller, or no Bridge installed at
 * all, and the Extension's copy for it says something different from any `error`.
 */
export type HandoffOutcome =
  | { outcome: "response"; response: BridgeResponse }
  | { outcome: "unreadable"; message: unknown }
  | { outcome: "disconnected"; detail?: string };

function lastErrorMessage(): string | undefined {
  return globalThis.chrome?.runtime?.lastError?.message;
}

/**
 * Sends one request frame and settles on whichever comes first, the terminal response
 * or the port closing. There are no timers: Entra can legitimately take minutes for
 * MFA, and `onDisconnect` covers the cases where nothing is coming.
 */
export function requestHandoff(
  request: SignInRequest,
  connect: () => NativePort = () => chrome.runtime.connectNative(nativeHostName),
): Promise<HandoffOutcome> {
  return new Promise((resolve) => {
    let settled = false;
    const settle = (outcome: HandoffOutcome) => {
      if (settled) {
        return;
      }
      settled = true;
      resolve(outcome);
    };

    let port: NativePort;
    try {
      port = connect();
    } catch (error) {
      settle({ outcome: "disconnected", detail: String(error) });
      return;
    }

    port.onMessage.addListener((message) => {
      const response = parseBridgeResponse(message);
      settle(
        response === null ? { outcome: "unreadable", message } : { outcome: "response", response },
      );
      // One process serves one Handoff, so there is nothing further to hear.
      port.disconnect();
    });

    port.onDisconnect.addListener(() => {
      const detail = lastErrorMessage();
      settle(
        detail === undefined ? { outcome: "disconnected" } : { outcome: "disconnected", detail },
      );
    });

    port.postMessage(requestMessage(request));
  });
}
