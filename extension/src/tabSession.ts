// Everything a Handoff has to remember between two events that may not share a
// process: the captured Sign-in request and whether a Handoff is already running for
// that tab. Chromium can evict the MV3 service worker between the navigation and the
// click, and again between the click and the Bridge's reply, so none of it may live in
// a module-level variable. `storage.session` is memory-only in both engines and dies
// with the browser, which is the lifetime this state wants anyway.

import type { SignInRequest } from "./protocol";

/** An attempt abandoned an hour ago must never replay, so a stale capture is ignored. */
export const captureMaxAgeMs = 10 * 60 * 1000;

/** The part of `storage.session` this module uses, so a test can supply one. */
export interface SessionArea {
  get(keys: string[]): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
  remove(keys: string[]): Promise<void>;
}

/**
 * How a Handoff ended, as far as the capture is concerned. On `success` the capture is
 * spent; on `failure` it survives so the same Sign-in request can be replayed without
 * sending the user back through the Application's login page. That is deliberately the
 * opposite of the Relay page's consume-once rule: replaying a Sign-in request starts a
 * fresh authentication, while resubmitting an assertion is a replay of a credential.
 */
export type HandoffEnd = "success" | "failure";

export interface TabSession {
  /** Remembers the Sign-in request observed for a tab, replacing any earlier one. */
  recordCapture(tabId: number, request: SignInRequest, capturedAt: number): Promise<void>;
  /**
   * Marks a Handoff as running for this tab, or returns false when one already is, in
   * which case the caller does nothing at all: the claim was not taken and must not be
   * released.
   */
  claimHandoff(tabId: number, startedAt: number): Promise<boolean>;
  /** The capture for a tab if one is younger than ten minutes, otherwise null. */
  readCapture(tabId: number, now: number): Promise<SignInRequest | null>;
  /** Releases the claim, and spends the capture when the Handoff succeeded. */
  finishHandoff(tabId: number, end: HandoffEnd): Promise<void>;
  /** Drops everything held for a tab, for when it closes. */
  forgetTab(tabId: number): Promise<void>;
}

interface StoredCapture {
  request: SignInRequest;
  capturedAt: number;
}

const captureKey = (tabId: number) => `capture:${tabId}`;
const handoffKey = (tabId: number) => `handoff:${tabId}`;

function storedCapture(value: unknown): StoredCapture | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const { request, capturedAt } = value as Partial<StoredCapture>;
  if (request === undefined || typeof capturedAt !== "number") {
    return null;
  }
  return { request, capturedAt };
}

/**
 * Gecko's promise-returning namespace is `browser`; Chromium defines only `chrome`,
 * whose MV3 storage methods return promises. Preferring `browser` means both engines
 * hand back a promise, rather than relying on Gecko's callback-shaped `chrome` alias.
 */
function sessionStorage(): SessionArea {
  const api = (globalThis as { browser?: typeof chrome }).browser ?? chrome;
  const area = api.storage.session;
  return {
    get: (keys) => area.get(keys),
    set: (items) => area.set(items),
    remove: (keys) => area.remove(keys),
  };
}

/**
 * The per-tab state, over one storage area. Holding no state of its own is the point:
 * a fresh instance after an eviction reads exactly what the evicted one wrote, so
 * there is no cache in front of `storage.session` to lose.
 */
export function tabSession(area: SessionArea = sessionStorage()): TabSession {
  return {
    async recordCapture(tabId, request, capturedAt) {
      const stored: StoredCapture = { request, capturedAt };
      await area.set({ [captureKey(tabId)]: stored });
    },

    async claimHandoff(tabId, startedAt) {
      const key = handoffKey(tabId);
      const existing = await area.get([key]);
      if (existing[key] !== undefined) {
        return false;
      }
      await area.set({ [key]: { startedAt } });
      return true;
    },

    async readCapture(tabId, now) {
      const key = captureKey(tabId);
      const stored = storedCapture((await area.get([key]))[key]);
      if (stored === null || now - stored.capturedAt > captureMaxAgeMs) {
        return null;
      }
      return stored.request;
    },

    async finishHandoff(tabId, end) {
      await area.remove(
        end === "success" ? [handoffKey(tabId), captureKey(tabId)] : [handoffKey(tabId)],
      );
    },

    async forgetTab(tabId) {
      await area.remove([handoffKey(tabId), captureKey(tabId)]);
    },
  };
}
