// The popup's Try again button, as a message. The popup is a separate document and
// cannot start a Handoff itself, so it names its tab and the background does the work.

const retryType = "retryHandoff";

export function retryMessage(tabId: number) {
  return { type: retryType, tabId };
}

/** The tab a retry is for, or null when the message is not a retry at all. */
export function retriedTabId(message: unknown): number | null {
  if (typeof message !== "object" || message === null) {
    return null;
  }
  const { type, tabId } = message as { type?: unknown; tabId?: unknown };
  return type === retryType && typeof tabId === "number" ? tabId : null;
}
