# Security notes

Phase 1 is intended for a trusted local network.

- All Agent API routes except `/health` require a random device token.
- Tokens are never embedded in the APK and are stored by the app using Android
  secure storage.
- Uploaded files are size-limited, checked by MIME type and magic bytes, and
  renamed to server-generated IDs.
- Only configured workflow IDs and input keys are accepted.
- The phone cannot submit arbitrary ComfyUI JSON or filesystem paths.
- Raw ComfyUI tracebacks are logged under a debug ID and are not returned as a
  normal user-facing message.

HTTP/WS is a development concession for LAN testing. Before external release,
replace it with HTTPS/WSS, certificate pinning, token rotation, and a pairing
flow. ComfyUI port 8188 must never be exposed to the public internet.

