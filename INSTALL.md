# Installing HozaSend

Get the newest build from the [**Releases page**][releases], under **Assets**:

| Device | File | Status |
|---|---|---|
| Windows 10 / 11 (64-bit) | the **`.zip`** | ready |
| Android 7.0 or newer | the **`.apk`** | ready |
| macOS 10.15 or newer | the **`.app`** (inside a `.zip`) | coming soon |
| iPhone / iPad, iOS 13+ | the **`.ipa`** | coming soon |

You need two of them — HozaSend talks to another copy of itself, not to a
website.

**The Apple builds are not on the Releases page yet.** The code is written and
in the repo, but a macOS app and an iOS `.ipa` can only be compiled on a Mac
with Xcode, and that has not happened yet. The sections below are what the
steps will be. See [macOS](#macos--coming-soon) and [iOS](#ios--coming-soon).

## Windows

1. **Extract the zip** somewhere it can stay, e.g. `C:\Apps\HozaSend`.
   Double-clicking the zip only previews it; the app will not run from there.
   Keep `hoza_send.exe`, the DLLs and `data\` together in one folder.
2. **Run `hoza_send.exe`.** SmartScreen says *"Windows protected your PC"*
   because the app is unsigned — click **More info** → **Run anyway**.
3. **Allow the firewall prompt**, with **Private networks** ticked. Blocked,
   the app still opens but your phone will never find this PC.

For a shortcut: right-click `hoza_send.exe` → **Send to** → **Desktop**.

## Android

1. **Tap the `.apk`** you downloaded. Chrome warns about every APK — tap
   **Download anyway**.
2. If Android blocks it, tap **Settings** in that dialog → **Allow from this
   source**, then press back.
3. **Install**. If Play Protect complains, tap **More details** → **Install
   anyway** — the app is properly signed, it just does not come from the Play
   Store, and that is the only thing Play Protect is remarking on.
4. Allow notifications when asked, so you hear about transfers in the
   background. Files land in `Downloads/HozaSend`, and tapping one in the app
   opens it.

## macOS — coming soon

1. **Unzip and drag `HozaSend.app` into Applications.**
2. **Right-click it → Open**, then **Open** again in the dialog. Double-clicking
   an unsigned app gets refused by Gatekeeper; right-click → Open is the way
   past it, and only needed the first time.
3. **Allow the local network prompt.** macOS asks once, and it is the whole
   game: declined, HozaSend opens but never finds anything. If you miss it,
   turn it back on in **System Settings → Privacy & Security → Local Network**.

Files land in `~/Downloads/HozaSend`, and the app can open the folder with the
file already selected.

## iOS — coming soon

An `.ipa` cannot simply be tapped like an APK. It needs sideloading —
AltStore, Sideloadly, or Xcode with your own Apple ID — and a free Apple ID
signature expires after **7 days**, after which it has to be re-signed.

1. **Sideload the `.ipa`** with your tool of choice.
2. **Trust the developer** under **Settings → General → VPN & Device
   Management**.
3. **Allow the local network prompt** on first launch.

Received files appear in the **Files** app under **On My iPhone → HozaSend**.
iOS has no shared Downloads folder, so every app keeps its own.

> **Discovery does not work on iOS yet.** Since iOS 14 Apple silently blocks
> the UDP broadcast HozaSend uses to find devices, unless the app carries an
> entitlement Apple grants on request. Everything else — pairing, transfer,
> verification — is the same code that runs everywhere else. The README
> explains the two ways out.

## Then

Put both devices on the **same Wi-Fi** (or the phone's hotspot) and open the
app on each. They find each other under **Nearby devices** — tap, check the
six-digit code matches, accept, and send. No internet needed at any point.

## If it goes wrong

| Problem | Fix |
|---|---|
| Missing `.dll` on Windows | The zip was not extracted, or the `.exe` was moved out of its folder |
| `VCRUNTIME140.dll` not found | Install the [VC++ runtime](https://aka.ms/vs/17/release/vc_redist.x64.exe) |
| Devices never see each other | Firewall, almost always — allow HozaSend on private networks. Then check both are on the same network, not a guest one |
| Nothing found on macOS | Local Network was declined. **System Settings → Privacy & Security → Local Network** → turn HozaSend on |
| macOS says the app "is damaged" | Gatekeeper on an unsigned app. Right-click → **Open** instead of double-clicking |
| Nothing found on iOS | Expected for now — Apple blocks the broadcast HozaSend discovers with. See the iOS section above |
| "Cannot receive" on home | Something else is using port 47821 |
| "App not installed" | An older HozaSend is present that was signed with a different key — uninstall it first. Android will not replace an app with one signed by another key |

The Android APK is signed with HozaSend's own release key, so updates install
over each other cleanly. Play Protect can still warn about it: that is about
the app not coming from the Play Store, not about the signature. The Windows
build is not yet code-signed, which is why SmartScreen warns about it.

There is no server, no account and nothing to upload to.

<!-- Relative on purpose: GitHub resolves this to this repository's own
     Releases page, so it survives a rename or a fork. -->
[releases]: ../../releases/latest
