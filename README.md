# ValidationRelay

ValidationRelay is an iOS companion used by OpenBubbles to keep the Apple-side
validation channel available. It is a relay component, not an iMessage client:
the Android app still owns the user interface and message persistence, while
this app provides device identifiers and validation data over its WebSocket
connection.

## Repository status and licensing

This checkout does not currently contain a declared repository license. Do not
redistribute binaries or publish a fork until the project owner confirms the
license and the terms for the Apple/TrollStore integration. Contributions may
still be prepared as reviewable patches, but licensing is a release gate.

## Build requirements

- macOS with Xcode and the iOS SDK
- An iOS device that can install the resulting app (the project deployment
  settings currently include iOS 14 and newer)
- Swift Package Manager access to `pusher/NWWebSocket` 0.5.10 or newer within
  the declared major range
- For the TrollStore path, the repository's `TrollStore/` submodule and its
  documented signing tools

The checked-in `build.sh` produces an unsigned device build and then packages a
`.tipa` using `ldid` for the normal path. `./build.sh --embed` additionally
builds the embedded fastPathSign helper. Review the script before running it on
a new machine because signing and installation are intentionally environment-
specific.

## Runtime architecture

`RelayConnectionManager` owns one active WebSocket delegate, reconnect backoff,
connection timeout, foreground health checks, and the watchdog. Registration
code and secret are treated as a pair. The secret is stored in Keychain when
available, with a legacy local-storage migration only for existing installs.

Validation generation runs on a dedicated serial queue. Apple certificate and
validation requests use HTTPS, bounded URL-session timeouts, throwing plist
decoders, and native-operation status checks. The UI receives a success or
failure result on the main queue.

## Safe testing checklist

1. Use a test Apple account and a non-production relay where possible.
2. Keep the relay app foregrounded and the phone awake for initial testing.
3. Test connect, reconnect, network change, foreground resume, malformed
   registration response, and validation failure separately.
4. Confirm that one connection manager and one reconnect timer are active.
5. Check the event log for operation names and redacted IDs only.
6. Never paste registration secrets, Apple credentials, device identifiers, or
   validation payloads into an issue.

An apparent WebSocket “connected” state is not sufficient evidence of a usable
relay. The registration response, validation request, and downstream message
acknowledgement must each succeed.

## Known limitations

- Windows-side tooling can capture iPhone Bluetooth traffic for diagnostics,
  but it does not expose raw Apple UWB frames or private Find My session keys.
- A phone can be connected to the relay while Apple validation is failing due
  to certificate, network, account, or native `absd` errors.
- Background execution and network path migration remain device/OS dependent;
  the app cannot guarantee an always-on WebSocket when iOS suspends it.
- Xcode compilation and a long locked-device endurance test are still required
  before calling a change release-ready.

For Android-client routing and redacted receive diagnostics, see the
corresponding `docs/DEVELOPMENT.md` and `docs/DIAGNOSTICS.md` files in the
OpenBubbles Android client checkout.
