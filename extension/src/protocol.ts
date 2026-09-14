// The native-messaging schema, hand-written against docs/spec/protocol.md. The
// Bridge's Swift types are the other hand-written half; fixtures/protocol/ is what
// holds the two to the same shape.

/** The wire version this Extension sends. */
export const protocolVersion = 1;

/** One `name=value` pair, as a two-element array, because a form can repeat a name. */
export type FormField = [name: string, value: string];

/** The Application's original request to the identity provider, as observed. */
export type SignInRequest =
  { url: string; method: "GET" } | { url: string; method: "POST"; fields: FormField[] };

/** The exact object posted to the native-messaging port. */
export function requestMessage(request: SignInRequest) {
  return { version: protocolVersion, ...request };
}

/**
 * The closed error set, plus `unrecognized` for a code outside it. That case is not a
 * wire code: it is how a newer Bridge's code reaches the copy layer intact, so an
 * older Extension can fall back to generic copy instead of failing to parse.
 */
export type BridgeError =
  | { code: "unsupported_version"; bridgeVersion: number; detail?: string }
  | {
      code:
        | "malformed_request"
        | "unsupported_request"
        | "callback_too_large"
        | "navigation_failed"
        | "internal";
      detail?: string;
    }
  | { code: "unrecognized"; received: string; detail?: string };

/** The one message the Bridge sends, tagged on `result`. */
export type BridgeResponse =
  | { result: "callback"; url: string; method: "GET" }
  | { result: "callback"; url: string; method: "POST"; fields: FormField[] }
  | { result: "declined" }
  | ({ result: "error" } & BridgeError);

const knownErrorCodes = [
  "unsupported_version",
  "malformed_request",
  "unsupported_request",
  "callback_too_large",
  "navigation_failed",
  "internal",
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function parseFields(value: unknown): FormField[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const fields: FormField[] = [];
  for (const pair of value) {
    if (!Array.isArray(pair) || pair.length !== 2) {
      return null;
    }
    const [name, fieldValue] = pair;
    if (typeof name !== "string" || typeof fieldValue !== "string") {
      return null;
    }
    fields.push([name, fieldValue]);
  }
  return fields;
}

function parseError(message: Record<string, unknown>): BridgeResponse | null {
  const code = message.code;
  if (typeof code !== "string") {
    return null;
  }
  const detail = optionalString(message.detail);
  if (code === "unsupported_version") {
    const bridgeVersion = message.bridgeVersion;
    if (typeof bridgeVersion !== "number") {
      return null;
    }
    return { result: "error", code, bridgeVersion, ...(detail === undefined ? {} : { detail }) };
  }
  if ((knownErrorCodes as readonly string[]).includes(code)) {
    return {
      result: "error",
      code: code as Exclude<BridgeError["code"], "unsupported_version" | "unrecognized">,
      ...(detail === undefined ? {} : { detail }),
    };
  }
  return {
    result: "error",
    code: "unrecognized",
    received: code,
    ...(detail === undefined ? {} : { detail }),
  };
}

/**
 * A message from the port as a `BridgeResponse`, or null when it is not a response at
 * all. Null means the Bridge said something this Extension cannot read, which is a
 * different failure from an unrecognized error code and gets different copy.
 */
export function parseBridgeResponse(message: unknown): BridgeResponse | null {
  if (!isRecord(message)) {
    return null;
  }
  switch (message.result) {
    case "declined":
      return { result: "declined" };
    case "callback": {
      const url = message.url;
      if (typeof url !== "string") {
        return null;
      }
      if (message.method === "GET") {
        return { result: "callback", url, method: "GET" };
      }
      if (message.method === "POST") {
        const fields = parseFields(message.fields);
        return fields === null ? null : { result: "callback", url, method: "POST", fields };
      }
      return null;
    }
    case "error":
      return parseError(message);
    default:
      return null;
  }
}
