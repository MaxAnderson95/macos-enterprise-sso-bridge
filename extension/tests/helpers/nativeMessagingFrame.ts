// The framing the browser engines put around an extension's message on its way to a
// native-messaging host. The Extension never does this itself: the engine owns both
// ends of the pipe. It is reproduced here so a test can produce the exact bytes a
// browser would send and hand them to the Bridge's decoder.

/** Native byte order, probed rather than assumed, because the prefix is native-endian. */
export const hostIsLittleEndian = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;

export function encodeFrame(payload: string): Uint8Array {
  const body = new TextEncoder().encode(payload);
  const frame = new Uint8Array(4 + body.length);
  new DataView(frame.buffer).setUint32(0, body.length, hostIsLittleEndian);
  frame.set(body, 4);
  return frame;
}

export function toHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
