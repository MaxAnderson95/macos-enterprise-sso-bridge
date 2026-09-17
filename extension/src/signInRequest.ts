// Turning what `webRequest.onBeforeRequest` hands over into the Sign-in request the
// Bridge replays. Pure functions over values: the listener registration lives in
// background.ts, so every normalization rule here is testable without a browser.

import { identityProviderOrigins } from "./generated/entryOrigins";
import type { FormField, SignInRequest } from "./protocol";

/**
 * The part of an `onBeforeRequest` detail this module reads. Declared here rather than
 * imported from `chrome.webRequest` so a test can pass a literal; a real detail object
 * satisfies it structurally. `formData` values are `string | ArrayBuffer` because
 * Chromium hands back an `ArrayBuffer` for any value that is not valid UTF-8 and for
 * every multipart value, while Gecko always decodes to a string.
 *
 * Who started the navigation arrives under two names: Chromium's `initiator` is an
 * origin, Gecko's `originUrl` a full URL. Both are absent for a typed or bookmarked
 * URL, and both survive a redirect chain unchanged: Chromium documents it, and Gecko
 * clones the triggering principal as-is in `HttpBaseChannel::CloneLoadInfoForRedirect`.
 */
export interface CapturedRequestDetails {
  url: string;
  method: string;
  initiator?: string | undefined;
  originUrl?: string | undefined;
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
 * Nor is a navigation the identity provider issued itself. Submitting a username,
 * choosing "Sign in another way" from the passkey page, or forgetting an account all
 * land back on an entry origin as main-frame loads that carry no `redirect_uri` and no
 * `SAMLRequest`. They are steps inside the sign-in the Application already started,
 * and recording one would replace the only request the Bridge can replay.
 */
export function signInRequestFrom(details: CapturedRequestDetails): SignInRequest | null {
  if (isIdentityProviderOrigin(details.originUrl ?? details.initiator)) {
    return null;
  }
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

/**
 * Whether this URL is on the identity provider: an entry origin or one of the interior
 * origins it moves the user through. The click handler's "wrong page" check and the
 * capture's own-navigation check, compared as bare origins so a path or query cannot
 * widen the match. Chromium reports an opaque initiator as the string "null", which
 * does not parse and so counts as outside the provider, the same as a missing one.
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
