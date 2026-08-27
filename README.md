# demo_ex_wapp

A one-page Phoenix LiveView harness for manually exercising the data,
local-history, and structured-message APIs in
[ExWapp 0.1.2](https://hex.pm/packages/ex_wapp/0.1.2).

It connects a WhatsApp linked device with a QR code, loads contacts, sends an automatic feature suite, and marks inbound checks when you reply from WhatsApp. Received images, audio, and documents are downloaded and decrypted automatically. Image previews, an audio player, and document links remain available in memory for ten minutes.

## Setup

The project requires Elixir 1.19 or 1.20 and installs ExWapp exclusively from
Hex. No local checkout or `vendor/` directory is required.

```bash
git clone --branch agent/liveview-feature-harness \
  https://github.com/elchemista/demo_ex_wapp.git
cd demo_ex_wapp

mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

The dependency is pinned in `mix.exs` as `{:ex_wapp, "~> 0.1.2"}` and Jason is
configured as its JSON implementation in `config/config.exs`.

## Test flow

1. Click **Start test** and scan the QR from WhatsApp → Settings → Linked devices.
2. Wait for the status to become `connected` and refresh contacts if the selector is still empty.
3. Select a contact, or enter a complete JID such as `393331234567@s.whatsapp.net`.
4. Run the automatic suite. It first checks contact synchronization and contact/chat metadata. It then attempts text, image, Opus voice note, document, GPS location, vCard contact, and the optional calendar event independently. Finally, it checks a bounded message page and both lazy history stream APIs against the locally retained messages for that chat.
5. From WhatsApp, reply to the same chat with text, image, audio, document, location, contact, and optionally an event. Each decoded reply updates its checklist item.

The calendar event is intentionally marked optional because the WhatsApp Web message is less stable than the other message types.

## Data and chat-history checks

The data checklist calls ExWapp directly through the demo wrapper:

- `sync_contacts/1` refreshes the contact collection.
- `list_contacts/1` and `list_chats/1` verify the stored directory and chat metadata.
- `get_messages/3` reads at most 20 locally retained messages for the selected chat and fails if the page is empty.
- `stream_messages/3` and `all_messages/3` must return lazy `%Stream{}` values and yield at least one local message. The harness uses `Enum.take(stream, 1)`, so it never materializes the complete history just to mark the test green.

The history checks run after the outbound send attempts so a fresh test target
has locally retained messages to sample. If the selected chat still has no
local messages, the history checks fail instead of reporting a false pass.

The chat check also fails if a chat struct embeds a `:messages` field. Message
payloads belong to ExWapp's dedicated message store and are pulled through the
page or stream APIs. These APIs expose local retained history; they do not ask
WhatsApp to export older server-side history on demand.

## Logs and error reports

Application, session lifecycle, QR pairing, every suite operation, every inbound content type, and every media download emit structured logs. Start with debug logging when collecting a report:

```bash
EX_WAPP_DEBUG=1 mix phx.server 2>&1 | tee demo_ex_wapp.log
```

Development now enables ExWapp debug logging by default. `EX_WAPP_DEBUG=1`
makes the intent explicit; set `EX_WAPP_DEBUG=0` to turn it off.
`DEMO_LOG_LEVEL=debug` remains available as a general-purpose switch.

The demo intentionally does not override ExWapp's WhatsApp Web version,
device identity, IQ timeouts, Signal lifetime, or initial-sync settings. This
keeps the session and text-send path identical to a normal ExWapp consumer
such as `isma`; protocol overrides can authenticate successfully but still
cause later USync or prekey requests to be ignored by WhatsApp.

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
mix precommit
```

This repository intentionally does not duplicate ExWapp's library test suite. Its purpose is an interactive end-to-end check against a real linked device.
