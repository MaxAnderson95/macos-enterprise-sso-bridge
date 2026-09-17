// Turning what `webRequest.onBeforeRequest` hands over into the Sign-in request the
// Bridge replays. Pure functions over values: the listener registration lives in
// background.ts, so every normalization rule here is testable without a browser.

import { identityProviderOrigins, signInRequestMarkers } from "./generated/entryOrigins";
import type { FormField, SignInRequest } from "./protocol";

/**
 * The part of an `onBeforeRequest` detail this module reads. Declared here rather than
 * imported from `chrome.webRequest` so a test can pass a literal; a real detail object
 * satisfies it structurally. `formData` values are `string | ArrayBuffer` because
 * Chromium hands back an `ArrayBuffer` for any value that is not valid UTF-8 and for
 * every multipart value, while Gecko always decodes to a string.
 */
export interface CapturedRequestDetails {
  url: string;
  method: string;
  requestBody?:
    | {
        formData?: Record<string, (string | ArrayBuffer)[]> | undefined;
        raw?: { bytes?: ArrayBuffer | undefined }[] | undefined;
      }
    | undefined;
}

const decoder = new TextDecoder();

function decodeValue(value: string | ArrayBuffer): string {
  return typeof value === "string" ? value : decoder.decode(new Uint8Array(value));
}

/**
 * `formData` groups values under their name, so a form that repeats a name arrives as
 * one key with several values. Flattening keeps every occurrence as its own pair,
 * which is the whole reason the protocol carries pairs instead of an object. Order is
 * the object's key-insertion order within each name's values; the engines give us no
 * finer record of the original field order.
 */
function fieldsFromFormData(formData: Record<string, (string | ArrayBuffer)[]>): FormField[] {
  const fields: FormField[] = [];
  for (const [name, values] of Object.entries(formData)) {
    for (const value of values) {
      fields.push([name, decodeValue(value)]);
    }
  }
  return fields;
}

/**
 * The fallback for when form parsing did not happen: Gecko skips it for a non-seekable
 * upload stream, and either engine skips it for a content type it does not parse.
 * `URLSearchParams` keeps repeats and their order, and unlike Gecko's own splitter it
 * does not truncate a value at a second `=`.
 */
function fieldsFromRaw(raw: { bytes?: ArrayBuffer | undefined }[]): FormField[] {
  const chunks = raw.flatMap((element) =>
    element.bytes === undefined ? [] : [new Uint8Array(element.bytes)],
  );
  const total = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return [...new URLSearchParams(decoder.decode(body))];
}

/**
 * The Sign-in request carried by this navigation, or null when it is not one this
 * Extension can replay. A GET keeps only its URL; a POST carries its form fields in
 * order. Anything other than GET or POST is not a sign-in navigation worth capturing.
 *
 * Nor is a load that carries none of the generated markers. Once a saved account
 * exists, Entra moves the user through pages of its own before asking for a credential:
 * the username POST to `/login`, "Sign in another way" back to `/reprocess?ctx=...`, a
 * forgotten account. Each lands on the entry origin with no `redirect_uri` and no
 * `SAMLRequest`, and recording one would replace the only request the Bridge can
 * replay with one it would refuse. The markers are what decide, not who issued the
 * navigation or which redirect chain delivered it: an Application whose Callback
 * handler answers with a fresh authorization arrives with Entra as initiator and often
 * the same request ID, and it has to win.
 */
export function signInRequestFrom(details: CapturedRequestDetails): SignInRequest | null {
  const request = requestFrom(details);
  return request !== null && carriesMarker(request) ? request : null;
}

function requestFrom(details: CapturedRequestDetails): SignInRequest | null {
  if (details.method === "GET") {
    return { url: details.url, method: "GET" };
  }
  if (details.method !== "POST") {
    return null;
  }
  const body = details.requestBody;
  if (body?.formData !== undefined) {
    return { url: details.url, method: "POST", fields: fieldsFromFormData(body.formData) };
  }
  if (body?.raw !== undefined) {
    return { url: details.url, method: "POST", fields: fieldsFromRaw(body.raw) };
  }
  return { url: details.url, method: "POST", fields: [] };
}

/** A marker in the query counts for either method; the HTTP-Redirect SAML binding uses it. */
function carriesMarker(request: SignInRequest): boolean {
  let query: URLSearchParams;
  try {
    query = new URL(request.url).searchParams;
  } catch {
    return false;
  }
  if (signInRequestMarkers.some((marker) => query.has(marker))) {
    return true;
  }
  return (
    request.method === "POST" &&
    request.fields.some(([name]) => signInRequestMarkers.includes(name))
  );
}

/**
 * Whether a tab sitting at this URL is on the identity provider: an entry origin or one
 * of the interior origins it moves the user through. The click handler's "wrong page"
 * check, compared as bare origins so a path or query cannot widen the match.
 */
export function isIdentityProviderOrigin(url: string | undefined): boolean {
  if (url === undefined) {
    return false;
  }
  try {
    return identityProviderOrigins.includes(new URL(url).origin);
  } catch {
    return false;
  }
}
