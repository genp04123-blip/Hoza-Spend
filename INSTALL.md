# Installing HozaSend

Get the newest build from the [**Releases page**][releases], under **Assets**:

| Device | File |
|---|---|
| Windows 10 / 11 (64-bit) | the **`.zip`** |
| Android 7.0 or newer | the **`.apk`** |

You need both — HozaSend talks to another copy of itself, not to a website.

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
3. **Install**. If Play Protect complains, tap **Install anyway** — the app
   just does not come from the Play Store.
4. Allow notifications when asked, so you hear about transfers in the
   background. Files land in `Downloads/HozaSend`, and tapping one in the app
   opens it.

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
| "Cannot receive" on home | Something else is using port 47821 |
| "App not installed" | Uninstall the older HozaSend first |

Both builds are unsigned, which is the only reason Windows and Android warn
about them. There is no server, no account and nothing to upload to.

<!-- Relative on purpose: GitHub resolves this to this repository's own
     Releases page, so it survives a rename or a fork. -->
[releases]: ../../releases/latest
