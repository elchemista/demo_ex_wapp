# demo_ex_wapp

A one-page Phoenix LiveView harness for manually exercising the structured-message APIs on ExWapp's `feat/media-location-contacts` branch.

It connects a WhatsApp linked device with a QR code, loads contacts, sends an automatic feature suite, and marks inbound checks when you reply from WhatsApp. Received images, audio, and documents are downloaded and decrypted automatically. Image previews, an audio player, and document links remain available in memory for ten minutes.

## Setup

The ExWapp repository is deliberately vendored only in your local checkout. The complete `vendor/` directory is ignored by Git and is never included in this repository.

```bash
git clone https://github.com/elchemista/demo_ex_wapp.git
cd demo_ex_wapp

mkdir -p vendor
git clone --branch feat/media-location-contacts \
  git@github.com:elchemista/ex_wapp.git \
  vendor/ex_wapp

mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

If you already cloned ExWapp on another branch:

```bash
git -C vendor/ex_wapp fetch origin
git -C vendor/ex_wapp switch feat/media-location-contacts
git -C vendor/ex_wapp pull --rebase origin feat/media-location-contacts
```

## Test flow

1. Click **Start test** and scan the QR from WhatsApp → Settings → Linked devices.
2. Wait for the status to become `connected` and refresh contacts if the selector is still empty.
3. Select a contact, or enter a complete JID such as `393331234567@s.whatsapp.net`.
4. Run the automatic suite. It attempts text, image, Opus voice note, document, GPS location, vCard contact, and the optional calendar event independently.
5. From WhatsApp, reply to the same chat with text, image, audio, document, location, contact, and optionally an event. Each decoded reply updates its checklist item.

The calendar event is intentionally marked optional because the WhatsApp Web message is less stable than the other message types.

## Logs and error reports

Application, session lifecycle, QR pairing, every suite operation, every inbound content type, and every media download emit structured logs. Start with debug logging when collecting a report:

```bash
EX_WAPP_DEBUG=1 mix phx.server 2>&1 | tee demo_ex_wapp.log
```

Development now enables ExWapp debug logging by default. `EX_WAPP_DEBUG=1`
makes the intent explicit; set `EX_WAPP_DEBUG=0` to turn it off.
`DEMO_LOG_LEVEL=debug` remains available as a general-purpose switch.

For the first structured-message check, choose a direct `@s.whatsapp.net` chat.
A `@g.us` target first exercises group metadata lookup and sender-key fanout; if
that preflight fails, the demo blocks the remaining checks instead of reporting
the same group error seven times.

The chat selector joins chat history with the synced contact directory. A direct
chat is displayed with its contact name and phone number and sends to the
phone-number JID. Unresolved `@lid` entries are labeled explicitly and cannot be
tested until **Refresh chats** resolves their mapping.

Pairing credentials are persisted under `var/ex_wapp/default.etf`, which is also ignored by Git. **Reset pairing** stops the session and removes that local store.

Do not publish QR payloads, pairing-store files, raw media keys, or full logs containing private JIDs.

## Useful commands

```bash
mix format --check-formatted
mix compile --warnings-as-errors
```

This repository intentionally does not duplicate ExWapp's library test suite. Its purpose is an interactive end-to-end check against a real linked device.
