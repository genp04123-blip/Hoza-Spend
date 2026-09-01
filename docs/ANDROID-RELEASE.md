# Releasing HozaSend for Android

How the signed release APK is built, verified and distributed for **direct
install (sideloading)** — not Google Play.

---

## 1. What the release is signed with

Android has no certificate authority for sideloaded apps. There is nothing to
buy and nobody to validate you. What makes an update *the same app* as the
version already on someone's phone is simply that both were signed by the same
private key. That key is the identity.

| | |
|---|---|
| **Keystore** | `%USERPROFILE%\.keystores\hozasend-release.jks` |
| **Format** | PKCS12 (the standard; JKS is the old proprietary one) |
| **Key** | RSA 2048, `SHA384withRSA` |
| **Alias** | `hozasend` |
| **Subject** | `CN=Rahoz Osman Salim, O=HozaSend` |
| **Valid until** | 16 January 2054 |
| **Configured by** | `android/key.properties` (git-ignored) |
| **Created by** | `android/tool/new_release_keystore.ps1` |

The keystore lives **outside the repository** on purpose, so that no
`.gitignore` mistake can commit it. `.gitignore` also excludes `key.properties`,
`*.jks`, `*.keystore`, `*.p12` as a second line of defence.

> ### Back it up. Now, if you have not.
>
> Copy **both** the `.jks` file and the password from `android/key.properties`
> somewhere off this machine — a password manager, an encrypted archive, a
> second drive.
>
> There is no recovery. If the key is lost, every existing user has to
> uninstall and reinstall by hand, losing their settings, because Android
> refuses to replace an app with one signed by a different key. If the key
> *leaks*, anyone can publish an "update" that Android will install straight
> over the real app.

---

## 2. Building the signed APK

```powershell
powershell -ExecutionPolicy Bypass -File android\tool\build_release_apk.ps1
```

That builds, verifies the signature, and copies the result into `dist\` with a
version in the filename and a SHA-256 checksum printed.

Or use Flutter directly:

```powershell
flutter build apk --release
```

### Where the APK lands

| What | Path |
|---|---|
| **Flutter's output** | `build\app\outputs\flutter-apk\app-release.apk` |
| **Copied for release** | `dist\HozaSend-<version>.apk` |
| App bundle (Play only, unused here) | `build\app\outputs\bundle\release\app-release.aab` |

The default is one **universal APK** containing all three architectures
(`armeabi-v7a`, `arm64-v8a`, `x86_64`). That is deliberate for sideloading: one
file that installs on any phone, so nobody has to work out what CPU their
device has before they can download anything. It costs roughly 10–15 MB over a
per-architecture build.

If download size matters more than that, add `-SplitPerAbi` (or
`flutter build apk --release --split-per-abi`) — but then you have to tell each
user which of the three files to take, and most will guess wrong.

### There is no debug fallback

The old `android/app/build.gradle.kts` contained the Flutter template's
`signingConfig = signingConfigs.getByName("debug")`, which silently signed
*release* builds with the debug key. The debug key ships with every copy of the
Android SDK on earth, so anything signed with it can be replaced by anyone.

That is gone. A release build with no keystore now **fails** with an
explanation rather than quietly producing something that looks fine.

---

## 3. Verifying before you publish

```powershell
powershell -ExecutionPolicy Bypass -File android\tool\verify_apk.ps1
```

It checks:

1. The APK verifies at all (`apksigner verify`).
2. It is signed with **v1, v2 and v3** schemes — v1 is what Android 6 and
   below check, v2 arrived in Android 7, v3 in Android 9. A sideloaded APK
   meets all of them in the wild.
3. It is **not** signed with the Android debug key.
4. The certificate's SHA-256 fingerprint **matches this project's keystore** —
   compared by fingerprint, not by name, because names are not unique and are
   trivially forged.
5. The manifest is right: application id, version, launcher icon, not
   debuggable, and the full merged permission list including anything a plugin
   added without being asked.

Any failure exits non-zero, so it can gate a release.

---

## 4. Installing it on a phone

### Over USB

```powershell
adb install -r "dist\HozaSend-1.0.0.apk"
```

`-r` replaces an existing install, keeping its data. It only works if the
installed copy was signed with the same key — which is the whole point of
§1.

### By hand

1. Copy the `.apk` to the phone (USB, a cloud drive, or send it with HozaSend
   from another device).
2. Tap it in the Files app.
3. Android asks whether to allow installs from that app — the Files app or the
   browser you downloaded with. Allow it for that app, then press back.
4. Play Protect may say *"Unsafe app blocked"* or *"App scan recommended"*.
   Choose **More details → Install anyway**.

### What users will see, and why

The APK is properly signed, but signed is not the same as *known*. Play Protect
warns about any app that did not come from the Play Store and that Google has
not seen before, regardless of how it was signed. There is no certificate you
can buy that removes this, and nothing in the app should try to work around it —
the warning is Android telling the truth about where the file came from.

What genuinely reduces it over time is the same thing that works on Windows:
publish consecutive releases signed with **the same key**, so the signing
identity accumulates a history.

Two permissions attract particular attention, both declared and both used:

- **`REQUEST_INSTALL_PACKAGES`** — so a received `.apk` can be handed to the
  system installer when the user taps it. HozaSend never installs anything
  itself; the system prompt does, and only if the user agrees.
- **`FOREGROUND_SERVICE_DATA_SYNC`** — so a transfer survives the user
  switching to another app.

---

## 5. Shipping a new version

Android refuses to install an APK whose `versionCode` is not **greater** than
the installed one. Both values come from one line in `pubspec.yaml`:

```yaml
version: 1.0.0+1
#        ^^^^^ ^
#        |     versionCode  -> must increase every single release
#        versionName        -> what users see
```

So `1.0.1+2`, then `1.1.0+3`, and so on. Never reuse a build number.

---

## 6. Building releases in CI

`.github/workflows/release.yml` signs Android builds when four repository
secrets are present. Without them the job **fails** rather than falling back to
the debug key.

Produce the base64 of the keystore:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.keystores\hozasend-release.jks")) | Set-Clipboard
```

Then add, under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the string just copied |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` from `android/key.properties` |
| `ANDROID_KEY_ALIAS` | `hozasend` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` from `android/key.properties` (same value) |

The workflow decodes the keystore to a path outside the checkout, verifies the
password before Gradle ever runs, builds, verifies the signature, and shreds
the keystore afterwards.

---

## 7. What else changed for the release

| Area | Before | Now |
|---|---|---|
| Application id | `com.example.hoza_send` | `com.rahozosman.hozasend` |
| Kotlin package | `com.example.hoza_send` | `com.rahozosman.hozasend` |
| Release signing | the **debug** key | the release keystore, v1+v2+v3 |
| Code shrinking | off | R8 + resource shrinking, rules in `android/app/proguard-rules.pro` |
| `allowBackup` | on (default) | `false` |
| `pubspec` description | "A new Flutter project." | the real one |

The application id matches the Microsoft Store identity already configured in
`pubspec.yaml` (`rahozosman.hozasend`), so the publisher is the same across
Windows and Android.

**The application id is permanent.** Android identifies an app by that string
plus its signing key. Changing either makes it a different app that cannot be
installed over the existing one.

### Why Dart obfuscation is not used

`--obfuscate --split-debug-info` is a normal part of "optimise the release
build", but it is left off here on purpose: `PreferencesService` persists the
theme setting by its enum `.name`, and Dart obfuscation has a history of
rewriting exactly those strings — which would silently reset saved settings
between builds. The Java and Kotlin half is still shrunk and optimised by R8,
and the Dart half is AOT-compiled into `libapp.so` either way.
