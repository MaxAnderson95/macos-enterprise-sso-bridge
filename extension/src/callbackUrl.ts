/**
 * The same two hosts the Bridge admits for a plain `http` Callback: the loopback names
 * Entra accepts in an `http` `redirect_uri`. A loopback redirect never leaves the Mac.
 */
const loopbackHosts = new Set(["localhost", "127.0.0.1"]);

/**
 * The Extension's own check on where the Bridge says to send the tab.
 *
 * This duplicates part of the Bridge's Callback recognition on purpose. The Extension
 * is the party that actually drives the user's tab, and a Bridge bug or a swapped
 * binary should not be able to point that tab at plaintext `http://` off the Mac or at
 * a URL carrying embedded credentials. A rejected URL is not navigated to and the
 * Handoff is a failure, so the capture survives for a retry.
 */
export function isDeliverableCallbackUrl(url: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  const secure =
    parsed.protocol === "https:" ||
    (parsed.protocol === "http:" && loopbackHosts.has(parsed.hostname));
  return secure && parsed.username === "" && parsed.password === "";
}
