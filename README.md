<div align="center">

<img src="assets/icon/hoza_icon.png" width="120" alt="HozaSend">

# HozaSend

**Send files straight between your devices. No internet, no account, no cloud.**

Two devices on the same Wi-Fi — or one phone's hotspot — find each other and
transfer directly. Nothing is uploaded anywhere, because there is nowhere to
upload it to.

[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android-1E4ED8)](#)
[![Apple](https://img.shields.io/badge/macOS%20%7C%20iOS-coming%20soon-8A5A12)](#macos--coming-soon)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-3B72FF)](https://flutter.dev)
[![Offline](https://img.shields.io/badge/internet-not%20required-34D399)](#)

</div>

---

## Screens

<table>
<tr>
<td width="62%" valign="top">

**Windows & Mac os**

<img src="docs/screenshots/windows-home.png" alt="HozaSend on Windows, showing a discovered Android device">

</td>
<td width="38%" valign="top">

**Android & ios**

<img src="docs/screenshots/android-home.png" alt="HozaSend on Android, searching for nearby devices">

</td>
</tr>
</table>

*Left: Windows has found the phone and is ready to send. Right: Android
sweeping for devices. Same codebase, same design, laid out for each screen.*

---

## What it does

| | |
|---|---|
| **Finds devices by itself** | UDP beacons on the local subnet. Open the app on both, and they appear |
| **Works with no internet** | A hotspot with no connection behind it is a perfectly good network |
| **Streams everything** | 64 KB chunks, straight from disk to socket. A 5 GB video never touches RAM |
| **Verifies every file** | SHA-256 checked before a file is given its real name |
| **Asks before it saves** | A six-digit code on both screens to pair, then accept or reject each transfer |
| **Remembers nothing it shouldn't** | No account, no telemetry, no server. Files go to `Downloads/HozaSend` |

---

## Install

Grab the newest build from the [**Releases**](../../releases/latest) page —
the `.zip` for Windows, the `.apk` for Android, a `.zip` for macOS and an
unsigned `.ipa` for iOS. Every platform is compiled by GitHub Actions on real
hardware, so no Mac is needed to produce the Apple builds — see
[**Download a build**](#download-a-build). Step-by-step instructions, including
the firewall prompt and the SmartScreen and Play Protect warnings, are in
**[INSTALL.md](INSTALL.md)**.

### Windows

Extract the zip somewhere it can stay — the `.exe` needs the DLLs and the
`data\` folder beside it — and run `hoza_send.exe`.

The first launch asks about the firewall. **Allow it on private networks** — a
blocked firewall is the single most common reason two devices never see each
other.

### Android

Install the APK; Android will ask you to allow installs from your browser
first. HozaSend then asks for notification permission on first launch;
declining only costs the alerts.

The APK is signed with HozaSend's own release key (v1+v2+v3 schemes), so
updates install cleanly over each other. Play Protect may still warn, because
the app did not come from the Play Store — that is about where the file came
from, not about how it was signed. See
**[docs/ANDROID-RELEASE.md](docs/ANDROID-RELEASE.md)**.

### macOS

**The codebase supports macOS.** Not a plan or a maybe: the platform work is
done and in the repo.

- Sandbox entitlements for the network server, client, file picker and
  Downloads — in **both** debug and release, which is the trap the stock
  template leaves you in
- `NSLocalNetworkUsageDescription`, so the macOS 15 local-network prompt
  explains itself
- Reveal in Finder with the file selected, notifications through Notification
  Centre, `⌘O` in the picker, window sizing and minimum size
- The intro names *the macOS local-network prompt* rather than the Windows
  firewall
- App icons generated at all seven sizes

The networking needed no changes at all — it is pure `dart:io`, and every
plugin in use already ships macOS support.

**On first launch macOS will claim the app is damaged.** It is not. The build
is ad-hoc signed rather than Developer-ID signed, and macOS quarantines any
unsigned app that arrived through a browser. Clear the flag once:

```bash
xattr -dr com.apple.quarantine /Applications/HozaSend.app
```

Right-clicking the app and choosing **Open** offers the same override in a
dialog. Removing the warning for everyone needs a paid Apple Developer account
(~$99/yr) for Developer-ID signing and notarisation — that is a credential
added to the workflow, not a code change.

### iOS — one blocker to clear first

The platform work is in the repo too: local-network and Bonjour keys, file
sharing so received files appear in the Files app under **On My iPhone**, the
device name from Settings, notifications, and app icons.

**But discovery will not work yet, and that is Apple's rule, not a bug.**
Since iOS 14, UDP broadcast is silently dropped unless the app carries
`com.apple.developer.networking.multicast` — a *managed* entitlement Apple
grants case by case on request. HozaSend discovers by broadcasting, so on iOS
devices will not find each other until either:

- **Apple grants that entitlement** (needs a paid Developer account and their
  approval), or
- **discovery gains a Bonjour/mDNS path** — Apple's sanctioned route, needing
  no special entitlement. The `NSBonjourServices` declaration is already in
  place for it; what is missing is the second discovery implementation.

Everything else on iOS — pairing, transfer, verification, history — is the
same code that runs everywhere else and needs nothing new.

### Both Apple platforms: compiled, never run

The Apple builds are produced by GitHub Actions on a hosted Mac runner, so a
real Xcode does compile them. What has *not* happened is anyone launching them:
nobody has opened the `.app`, paired two devices, or moved a file on macOS. The
Dart analyses clean and the Swift compiles — neither is the same as working.

If you have a Mac:

```bash
flutter run -d macos
flutter run -d <your-iphone>
```

Issues and reports from that are very welcome.

### Build it yourself

```bash
flutter pub get
flutter run -d windows        # or: flutter run -d <your-device>
```

Windows builds need Visual Studio with the **Desktop development with C++**
workload — `flutter doctor -v` will tell you if it is missing.

To produce the Windows installer (needs [Inno Setup 6](https://jrsoftware.org/isdl.php)):

```powershell
.\installer\build_installer.ps1
```

---

## Download a build

Builds come from the **Flutter Release** workflow in
[`.github/workflows/release.yml`](.github/workflows/release.yml) — Android,
Windows, macOS and iOS, each on its own runner, all gated behind
`flutter analyze`. Nothing it produces is committed: `build/` is gitignored, so
a compiled app never appears in the repo or in your working copy.

**A build to try out** — Actions tab → **Flutter Release** → *Run workflow*.
When the run finishes, its **Artifacts** sit at the bottom of the run summary:

| Artifact | Contents |
|---|---|
| `windows-release` | `HozaSend-windows.zip` |
| `android-apk` / `android-aab` | `HozaSend-<version>.apk` (signed, with `.sha256`) / `.aab` |
| `macos-release` | `HozaSend-macos.zip` |
| `ios-release` | `HozaSend-ios-unsigned.ipa` |

Artifacts expire after 90 days and always download as a zip.

**A build to hand out** — push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The same four platforms build, and are then collected into a **draft** GitHub
Release with generated notes. Review it on the Releases page and press
*Publish* when you are ready — nothing is public until you do.

macOS runners bill at ten times the Linux rate, but this repository is public,
so the minutes cost nothing.

---

## Using it

1. Open HozaSend on **both** devices, on the same Wi-Fi or hotspot.
2. Tap the device you want under **Nearby devices**.
3. Accept the request on the other device — check the six-digit code matches.
4. Choose files and send.

Receiving needs nothing: the app is findable whenever it is open. **Receive**
just shows you the name to look for while you wait.

> **The one rule:** both devices must be on the *same* network. Being on Wi-Fi
> is not enough if it is a different Wi-Fi. There is a full guide inside the
> app, under Settings.

---

## How it works

```
Discovery   UDP 47820   beacon every 2s, device expires after 7s
Transfer    TCP 47821   one connection carries the whole conversation
```

One socket per session, switching between newline-delimited JSON and raw file
bytes:

```
initiator → hello {version, session code, identity}
receiver  → welcome                    ← "asking the user"
receiver  → accept | reject
initiator → offer {files}
receiver  → offerAccept
initiator → file {name, size, kind, mtime, rel}
initiator → chunk {n}                  ← then exactly `n` raw bytes
initiator → chunk {n}                  ← …repeated to the end of the file
initiator → fileDone {sha256}          ← checksum as a trailer
initiator → end
receiver  → result
either    ↔ pause / resume             ← at any chunk boundary
both      ↔ ping / pong every 5s
```

**Why the bytes are chunked, not one run of `size`:** because a file sent as one
unbroken run leaves no moment at which either side may write a control line — so
the pong owed to the peer's five-second ping lands *inside the file*. That was
real, and it silently damaged every transfer that lasted longer than five
seconds, which is to say every large one. Returning to text between chunks gives
the heartbeat, a cancel and a pause somewhere safe to go. The cost is a ~30-byte
header per 64 KB, under 0.05%. `test/transfer_test.dart` pins it down.

**Why the checksum is a trailer, not part of the offer:** the file is hashed
*while* it streams. Reading a 5 GB video twice just to know its digest up front
would be absurd.

**Why one connection, not two:** a second data socket would need its own
handshake, its own liveness handling and a way to tie it back to the right
session — for nothing.

### Getting the details right

- **No file type is special.** Every picker is opened for anything the OS will
  offer, and the engine only ever sees a name, a byte count and something that
  streams. Documents, archives, installers, audio, video, images and files with
  no extension at all take exactly the same path.
- **Backpressure both ways.** The sender flushes every 512 KB; the receiver
  pauses socket reads across each 8 MB disk flush. Never flushing lets a fast
  disk queue a whole file in RAM ahead of a slow network.
- **A flush blocks writes.** A Dart socket counts as bound to a stream while its
  own flush is in flight, so control lines written in that window are held and
  emitted the instant it resolves — still on a chunk boundary.
- **The receiver does its file work on one queue.** Messages arrive
  synchronously from the socket and the work they cause is asynchronous, and
  `fileDone` for one file arrives in the same read as the `file` header for the
  next. Without the queue the trailer for one file resolves against the handle
  of the one after it, and the wrong file is verified and renamed.
- **Nothing lands looking finished.** Bytes go to a `.hozapart` file; only when
  the byte count *and* the SHA-256 both match is it renamed. Failures delete
  the partial.
- **A file keeps what it is.** Its name, extension, size and modification time
  survive the trip, and a file sent from inside a folder is rebuilt inside that
  folder rather than emptied into the download directory.
- **Names are sanitised, not mangled.** Separators, drive letters and traversal
  segments are stripped, Windows device names (`CON`, `LPT1`) are prefixed, and
  a name too long to store is shortened *through the stem* so the extension
  survives. A leading dot is kept: `.gitignore` arrives as `.gitignore`.
- **Pause is flow control, not a teardown.** The sender stops feeding bytes at
  the next chunk boundary. The socket stays up, the partial file stays put, the
  digest keeps its state, and both heartbeats keep proving the link is alive.
- **Android reads picked files where they are.** Every Flutter picker answers a
  selection by copying the file into the app's cache first — 4 GB of free space
  and a full copy before a single byte is sent. HozaSend goes to the Storage
  Access Framework directly and streams the original; the copying picker is
  kept only as a fallback.
- **`Downloads/HozaSend` on both.** Windows writes there directly; Android
  streams into app storage, verifies, then publishes through MediaStore —
  scoped storage gives you a stream, not a path.

---

## Project layout

```
lib/
├── app/           theme tokens, router
├── core/          models, services, errors, utils
├── data/          preferences, storage, history
├── features/      one folder per screen + its controller
├── network/       discovery, connection, protocol, transfer
└── shared/        widgets used across features
```

UI never touches a socket. `network/` knows nothing about widgets — it
publishes streams, and the controllers in `features/` turn those into state.

**Dependencies:** `provider`, `shared_preferences`, `file_picker`,
`path_provider`, `crypto`, `flutter_local_notifications`, `desktop_drop`.
The networking is pure `dart:io` — no networking package at all.

---

## Known limits

Stated plainly, because pretending otherwise wastes your time:

- **Android cannot enable its own hotspot.** No app can; the system forbids it.
  Turn it on yourself, then open HozaSend.
- **Taskbar pinning cannot be automated.** Microsoft removed the shell verb in
  Windows 10. The installer creates desktop and Start Menu shortcuts; pinning
  is a right-click.
- **iOS copies a picked file before handing it over**, so a multi-GB video
  costs that much temporary storage while it sends. Its document picker offers
  no other route; Android's does, and HozaSend takes it. Old copies are cleared
  at startup, which is the one moment nothing is queued or being read.
- **iOS cannot send a folder.** Its folder picker returns a security-scoped URL
  that has to be held open by whoever received it, and the picker plugin does
  not hold it — so the folder would be chosen and then found empty. Windows,
  macOS and Android all send folders, structure intact.
- **Protocol 2 does not talk to protocol 1.** Both devices need this build. The
  handshake says so plainly rather than letting an older peer corrupt a file,
  which is what the previous wire format did to anything over five seconds.
- **Discovery assumes a /24 subnet** for its directed broadcast. Dart exposes
  no interface netmask. The limited broadcast covers everything else.
- **The macOS build is untested.** The code is there and analyses clean, but it
  has never been compiled on a Mac. Treat it as ready to try, not as shipped.
- **iOS cannot discover yet.** Apple blocks UDP broadcast without a managed
  entitlement. See [iOS — one blocker to clear first](#ios--one-blocker-to-clear-first).

---

## Author

**Rahoz Osman Salim** — [hozahoza2001@gmail.com](mailto:hozahoza2001@gmail.com)

## Privacy

HozaSend collects nothing: no accounts, no servers, no analytics, no tracking.
The full policy is at
[rahozosman.github.io/Hoza-Send/privacy-policy.html](https://rahozosman.github.io/Hoza-Send/privacy-policy.html)
(source: [PRIVACY.md](PRIVACY.md)).
