// Everything a Handoff has to remember between two events that may not share a
// process: the captured Sign-in request and whether a Handoff is already running for
// that tab. Chromium can evict the MV3 service worker between the navigation and the
// click, and again between the click and the Bridge's reply, so none of it may live in
// a module-level variable. `storage.session` is memory-only in both engines and dies
// with the browser, which is the lifetime this state wants anyway.

import { engineApi } from "./engineApi";
import type { FormField, SignInRequest } from "./protocol";

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

/** A POST Callback waiting in a tab for the Relay page to submit it. */
export interface PostCallback {
  url: string;
  fields: FormField[];
}

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
  /** Leaves a POST Callback for the Relay page that is about to load in this tab. */
  storeCallback(tabId: number, callback: PostCallback): Promise<void>;
  /**
   * The POST Callback for a tab, deleted as it is read, so a reload of the Relay page
   * finds nothing. Resubmitting an assertion is a replay of a credential, which is why
   * this is the opposite of the capture's survive-on-failure rule.
   */
  takeCallback(tabId: number): Promise<PostCallback | null>;
  /**
   * Remembers which state the action is showing for a tab, so the popup, which is a
   * separate document, knows which sentence it was opened to say.
   */
  recordState(tabId: number, state: string): Promise<void>;
  /** The state name recorded for a tab, or null when the tab is idle. */
  readState(tabId: number): Promise<string | null>;
  /** Forgets the recorded state, leaving the tab idle. */
  clearState(tabId: number): Promise<void>;
  /** Drops everything held for a tab, for when it closes. */
  forgetTab(tabId: number): Promise<void>;
}

interface StoredCapture {
  request: SignInRequest;
  capturedAt: number;
}

const captureKey = (tabId: number) => `capture:${tabId}`;
const handoffKey = (tabId: number) => `handoff:${tabId}`;
const callbackKey = (tabId: number) => `callback:${tabId}`;
const stateKey = (tabId: number) => `state:${tabId}`;

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

function storedCallback(value: unknown): PostCallback | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const { url, fields } = value as Partial<PostCallback>;
  if (typeof url !== "string" || !Array.isArray(fields)) {
    return null;
  }
  return { url, fields };
}

function sessionStorage(): SessionArea {
  const area = engineApi().storage.session;
  return {
    get: (keys) => area.get(keys),
    set: (items) => area.set(items),
    remove: (keys) => area.remove(keys),
  };
}

/**
 * The per-tab state, over one storage area. It caches nothing: a fresh instance after
 * an eviction reads exactly what the evicted one wrote, so there is nothing in front
 * of `storage.session` to lose.
 *
 * The one piece of memory it does keep is a per-tab promise chain, because claiming is
 * a read followed by a write and two toolbar clicks can otherwise both read an absent
 * key and both start a Handoff. That chain only orders operations inside one worker,
 * which is the only place two of them can overlap; an evicted worker has nothing left
 * in flight to order, and the claim itself still lives in storage.
 */
export function tabSession(area: SessionArea = sessionStorage()): TabSession {
  const chains = new Map<number, Promise<unknown>>();

  function serialized<T>(tabId: number, operation: () => Promise<T>): Promise<T> {
    const result = (chains.get(tabId) ?? Promise.resolve()).then(operation, operation);
    // Keep the chain alive for the next caller but never let it reject, and drop it
    // once this tab is idle so a long-lived worker does not accumulate entries.
    const link = result.catch(() => undefined);
    chains.set(tabId, link);
    void link.then(() => {
      if (chains.get(tabId) === link) {
        chains.delete(tabId);
      }
    });
    return result;
  }

  return {
    async recordCapture(tabId, request, capturedAt) {
      const stored: StoredCapture = { request, capturedAt };
      await area.set({ [captureKey(tabId)]: stored });
    },

    claimHandoff(tabId, startedAt) {
      return serialized(tabId, async () => {
        const key = handoffKey(tabId);
        const existing = await area.get([key]);
        if (existing[key] !== undefined) {
          return false;
        }
        await area.set({ [key]: { startedAt } });
        return true;
      });
    },

    async readCapture(tabId, now) {
      const key = captureKey(tabId);
      const stored = storedCapture((await area.get([key]))[key]);
      if (stored === null || now - stored.capturedAt > captureMaxAgeMs) {
        return null;
      }
      return stored.request;
    },

    // Releasing runs through the same chain as claiming, so a release cannot land
    // between a claim's read and its write.
    finishHandoff(tabId, end) {
      return serialized(tabId, async () => {
        await area.remove(
          end === "success" ? [handoffKey(tabId), captureKey(tabId)] : [handoffKey(tabId)],
        );
      });
    },

    async storeCallback(tabId, callback) {
      await area.set({ [callbackKey(tabId)]: callback });
    },

    // The delete goes out before the value is returned, so nothing that happens to the
    // caller afterwards can leave the assertion behind for a second reader.
    async takeCallback(tabId) {
      const key = callbackKey(tabId);
      const stored = storedCallback((await area.get([key]))[key]);
      await area.remove([key]);
      return stored;
    },

    async recordState(tabId, state) {
      await area.set({ [stateKey(tabId)]: state });
    },

    async readState(tabId) {
      const key = stateKey(tabId);
      const stored = (await area.get([key]))[key];
      return typeof stored === "string" ? stored : null;
    },

    async clearState(tabId) {
      await area.remove([stateKey(tabId)]);
    },

    forgetTab(tabId) {
      return serialized(tabId, async () => {
        await area.remove([
          handoffKey(tabId),
          captureKey(tabId),
          callbackKey(tabId),
          stateKey(tabId),
        ]);
      });
    },
  };
}
