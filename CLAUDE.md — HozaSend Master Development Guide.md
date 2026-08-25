# HozaSend — Master Claude Code Development Guide

## 0. ROLE

You are the senior Flutter architect, UI/UX designer, networking engineer, performance engineer, security engineer, and code reviewer responsible for building **HozaSend**.

HozaSend is a premium offline local-network file-sharing application built with Flutter.

Supported platforms:

- Android
- Windows Desktop

The application must allow devices connected to the same local Wi-Fi network or phone hotspot to discover each other and transfer files directly.

The core experience is:

> **Open → Discover → Select → Send → Done**

HozaSend must NOT depend on:

- Internet
- Firebase
- Cloud storage
- User accounts
- External servers
- Remote APIs
- Online authentication

The application should feel like a polished commercial product while remaining simple, reliable, lightweight, and maintainable.

---

# 1. MOST IMPORTANT RULE — DO NOT BUILD EVERYTHING AT ONCE

## NEVER implement the entire application in one pass.

Work **section-by-section** and **phase-by-phase**.

Do not jump ahead.

Do not implement networking, history, settings, animations, transfer UI, and every screen simultaneously.

Every phase must be:

1. Inspected
2. Planned
3. Implemented
4. Tested
5. Reviewed
6. Stabilized
7. Then only move to the next phase

The project must remain runnable after every meaningful phase.

---

# 2. WORKING PRINCIPLE

Before touching code:

### First inspect.

Understand:

- Existing project structure
- Flutter version
- Dart version
- Existing dependencies
- Android configuration
- Windows configuration
- Existing UI
- Existing assets
- Existing state management
- Existing platform code
- Existing tests
- Existing configuration

Never assume the project is empty.

Never overwrite working functionality without understanding it.

---

# 3. PLAN BEFORE IMPLEMENTATION

Before each phase, provide a short implementation plan.

For example:

```text
PHASE 1 — Project Foundation

Files to inspect:
- pubspec.yaml
- lib/
- android/
- windows/

Changes:
- establish architecture
- create theme system
- create core models
- create navigation foundation

Validation:
- flutter analyze
- flutter test
- run application
```

Then execute the plan.

Do not repeatedly explain the same plan.

Do not waste tokens describing obvious actions.

---

# 4. MINIMAL CHANGE PRINCIPLE

Only change what is necessary for the current phase.

Do NOT:

- Rewrite unrelated files
- Refactor the entire project unnecessarily
- Replace working architecture without reason
- Add dependencies just because they are convenient
- Redesign unrelated screens
- Modify platform configuration without need
- Create duplicate systems

Every change should have a reason.

---

# 5. DEPENDENCY DISCIPLINE

Before adding a package:

Ask:

1. Is it actually required?
2. Is there already a solution in the project?
3. Is the package maintained?
4. Does it support Android and Windows?
5. Does it introduce unnecessary complexity?
6. Does it work offline?
7. Does it affect application size?
8. Does it create platform-specific problems?

Prefer:

> Flutter/Dart standard APIs + small stable packages

over:

> many large third-party packages.

Never add a package just for a small convenience.

---

# 6. SOURCE OF TRUTH

The original HozaSend specification is the product requirement.

Important requirements include:

- Same LAN / hotspot communication
- Automatic device discovery
- Device selection
- Single and multiple file selection
- Direct local transfer
- Real-time progress
- Transfer speed
- Remaining time
- Incoming transfer confirmation
- Local saving
- History
- Retry
- Connection-loss handling
- Android support
- Windows support
- Dark and light modes
- Premium UI
- Streaming large files
- Security/pairing
- No cloud dependency

The original specification explicitly requires incremental implementation, beginning with discovery and connection before progressively adding transfer functionality and polish. 
---

# 7. ARCHITECTURE FIRST

Before implementing major functionality, establish a clean architecture.

Recommended conceptual structure:

```text
lib/
│
├── app/
│   ├── app.dart
│   ├── router/
│   └── theme/
│
├── core/
│   ├── constants/
│   ├── errors/
│   ├── extensions/
│   ├── utils/
│   └── services/
│
├── features/
│   ├── home/
│   ├── discovery/
│   ├── file_selection/
│   ├── transfer/
│   ├── receive/
│   ├── history/
│   └── settings/
│
├── data/
│   ├── models/
│   ├── repositories/
│   └── local/
│
├── network/
│   ├── discovery/
│   ├── connection/
│   ├── protocol/
│   └── transfer/
│
└── platform/
    ├── android/
    └── windows/
```

Do not blindly create every directory.

Create structures when the relevant feature is actually being implemented.

---

# 8. SEPARATION OF RESPONSIBILITIES

Keep these concerns separate:

### UI

Responsible for:

- Rendering
- User interactions
- Animations
- Layout
- Visual states

### State

Responsible for:

- Current devices
- Connection state
- Transfer state
- File-selection state
- Errors
- History state

### Discovery

Responsible for:

- Finding HozaSend devices
- Advertising this device
- Device metadata
- Device disappearance
- Device availability

### Networking

Responsible for:

- Connections
- Communication
- Protocol
- Timeouts
- Retry

### Transfer

Responsible for:

- File streaming
- Chunks
- Progress
- Speed
- ETA
- Integrity

### Storage

Responsible for:

- Received files
- Transfer history
- Settings
- Temporary files

### Platform

Responsible for:

- Android permissions
- Android lifecycle
- Windows behavior
- Native file picker
- Notifications
- Platform-specific limitations

Never mix all of these inside UI widgets.

---

# 9. DEVELOPMENT PHASES

The application must be developed in these phases.

Do NOT skip phases unless the existing project already contains a verified implementation.

---

# PHASE 0 — PROJECT AUDIT

## Goal

Understand the existing project before changing anything.

Inspect:

```text
pubspec.yaml
lib/
android/
windows/
test/
assets/
```

Check:

- Flutter version
- Dart version
- Current dependencies
- Current entry point
- Existing architecture
- Existing platform configuration
- Existing tests
- Existing assets
- Build configuration

## Output

Create a concise project audit.

Identify:

### Working

### Broken

### Missing

### Risky

### Recommended architecture

Do not implement major features yet.

---

# PHASE 1 — PRODUCT & ARCHITECTURE FOUNDATION

## Goal

Establish the technical foundation.

Define:

- Application architecture
- Models
- Interfaces
- Repository boundaries
- State-management approach
- Navigation
- Theme
- Error model
- Networking abstraction

Before implementation, document:

1. LAN discovery method
2. Connection strategy
3. File-transfer protocol
4. Android requirements
5. Windows requirements
6. Permissions
7. Hotspot behavior
8. Streaming architecture
9. Security/pairing
10. Failure recovery

The specification requires these architectural decisions to be established before full implementation.

## Validation

Run:

```powershell
flutter analyze
flutter test
```

Application must still launch.

---

# PHASE 2 — DESIGN SYSTEM

## Goal

Create the visual foundation before building every screen.

HozaSend should feel:

- Premium
- Modern
- Minimal
- Fast
- Elegant
- Friendly
- Professional
- Slightly futuristic

The product specification calls for large rounded surfaces, subtle gradients, soft shadows, clean typography, spacing, micro-interactions, and restrained glass-like elements.

## Establish

### Colors

Dark-first:

- Deep midnight background
- Rich blue primary
- Subtle cyan highlights
- White/off-white typography
- Soft emerald success state

Avoid:

- Aggressive neon
- Excessive gradients
- Excessive glassmorphism

### Typography

Define:

- Display
- Headline
- Title
- Body
- Label
- Caption

### Spacing

Create consistent spacing tokens.

### Radius

Create consistent corner-radius tokens.

### Elevation

Use subtle depth.

### Animation

Define:

- Fast
- Normal
- Slow

Do not randomly assign durations throughout the application.

---

# PHASE 3 — BRANDING

## Goal

Create HozaSend's visual identity.

The logo should represent:

> connection + movement + sharing

Do NOT use generic:

- Paper-plane icons
- Wi-Fi icons
- Folder icons
- Cloud icons

The same identity should work across:

- Android icon
- Windows icon
- Splash
- Home
- Transfer animation

The wordmark is:

> HozaSend

The branding requirements come directly from the original specification.

Do not spend weeks perfecting branding before core functionality works.

Create a strong initial version and continue.

---

# PHASE 4 — DEVICE IDENTITY

## Goal

Give every installation a recognizable identity.

First launch:

```text
What should we call this device?
```

Example:

```text
Rayan's S24 Ultra
```

Store the device name locally.

Allow changing it later.

Device metadata should eventually include:

- Device ID
- Device name
- Platform
- Version
- Discovery status
- Network address where appropriate

The original requirement explicitly includes device naming and later editing in Settings.

---

# PHASE 5 — LAN DEVICE DISCOVERY

## THIS IS THE FIRST MAJOR NETWORKING PHASE.

Do not implement file transfer yet.

## Goal

Two HozaSend devices on the same LAN should discover each other.

Test:

### Android → Windows

### Windows → Android

### Android → Android

### Windows → Windows

The specification explicitly requires these combinations.

---

## Discovery requirements

Implement:

- Local-network detection
- Device advertising
- Device discovery
- Device metadata
- Device appearance
- Device disappearance
- Connection status

The UI should show:

```text
Nearby Devices

💻 My Windows PC
Connected

📱 Rayan's Phone
Available
```

---

# PHASE 6 — DISCOVERY UI

## Goal

Make device discovery beautiful.

When searching:

```text
Finding nearby devices...
```

Use:

- Soft radar
- Ripple
- Pulse
- Subtle logo animation

When a device appears:

- Fade
- Slide
- Slight scale

Do not use excessive animation.

The original specification specifically requests a subtle radar/ripple effect and animated device appearance.

---

# PHASE 7 — CONNECTION

## Goal

Establish a reliable connection between two discovered devices.

Implement:

- Connection request
- Connection acceptance
- Connection rejection
- Connection timeout
- Disconnect
- Reconnect

Do not start large file transfers yet.

First prove:

```text
Device A
    ↓
Discovers
    ↓
Device B
    ↓
Connects
    ↓
Handshake
    ↓
Connected
```

---

# PHASE 8 — SECURITY / PAIRING

## Goal

Prevent accidental or unwanted transfers.

Implement a simple pairing/confirmation system.

Possible flow:

```text
Rayan's Phone wants to connect

[ Accept ]
[ Reject ]
```

Only after confirmation should the transfer session become trusted.

Use encrypted communication where practical.

Never upload files anywhere.

The specification requires private LAN transfers and a confirmation mechanism before accepting transfers.

Do not invent unnecessary authentication systems.

HozaSend is not an account-based service.

---

# PHASE 9 — FILE PICKER

## Goal

Implement file selection.

Use native platform file pickers.

Support:

- Images
- Videos
- Documents
- PDFs
- ZIP
- Audio
- Multiple files
- Folders where supported

The original specification explicitly lists these file types and multi-file support.

---

# PHASE 10 — FILE SELECTION UI

## Goal

Create a polished selected-file experience.

Each selected file should show:

- Thumbnail/icon
- Name
- Size
- Remove button

Example:

```text
Selected files

┌────────────────────────────┐
│ 🖼 vacation.jpg            │
│ 23.5 MB                 ×  │
└────────────────────────────┘

┌────────────────────────────┐
│ 📄 document.pdf            │
│ 4.2 MB                  ×  │
└────────────────────────────┘

Send to Rayan's Phone
```

Cards may use a small staggered entrance animation.

Keep it fast.

---

# PHASE 11 — TRANSFER PROTOCOL

## THIS IS A CRITICAL ENGINEERING PHASE.

Design the protocol before implementation.

The transfer system should support:

- Metadata
- File size
- File name
- MIME type
- File ID
- Chunks
- Progress
- Completion
- Failure
- Integrity verification

Do NOT load entire files into memory.

The original requirements explicitly require streaming and chunked transfer for large files.

---

# PHASE 12 — SINGLE FILE TRANSFER

## Goal

Get one file transferring reliably.

Do not implement multi-file transfer yet.

Test:

```text
Phone
 ↓
Select 1 file
 ↓
Connect
 ↓
Send
 ↓
PC receives
 ↓
Save
 ↓
Verify integrity
```

Test:

- Small image
- Large image
- PDF
- Large video

Only continue when this is reliable.

---

# PHASE 13 — TRANSFER PROGRESS

## Goal

Create real-time transfer feedback.

Display:

- File name
- Progress
- Percentage
- Bytes transferred
- Total size
- Transfer speed
- Remaining time
- Cancel

Example:

```text
Sending

vacation.jpg

████████████░░░░ 78%

18.4 MB / 23.5 MB

12.6 MB/s

~2 seconds remaining
```

The original product requirements specify these transfer metrics.

---

# PHASE 14 — RECEIVE CONFIRMATION

## Goal

When another device sends a file, show:

```text
Incoming file

📷 vacation.jpg
23.5 MB

From:
Windows PC

[ Reject ] [ Accept ]
```

Do not automatically accept unless the user enabled Auto Accept.

After acceptance:

```text
Receiving...
```

Then show progress.

---

# PHASE 15 — MULTI-FILE TRANSFER

## Goal

Add multiple files.

Support:

```text
File 1
File 2
File 3
File 4
```

Decide carefully whether the protocol should:

- Transfer sequentially
- Transfer controlled concurrent streams

Prioritize reliability over theoretical maximum speed.

Do not create unnecessary parallelism.

---

# PHASE 16 — CANCEL / RETRY / FAILURE RECOVERY

## Goal

Make transfers reliable.

Handle:

- User cancellation
- Device disconnect
- Network interruption
- Receiver rejection
- Invalid file
- Storage failure
- Timeout
- Partial transfer
- Corrupted transfer

Friendly error:

```text
Connection lost

The other device may have disconnected.

[ Try Again ]
```

Never expose raw errors such as:

```text
SocketException: Connection reset by peer
```

The specification explicitly requires friendly error handling.

---

# PHASE 17 — FILE INTEGRITY

## Goal

Verify received files.

After transfer:

1. Confirm expected byte count
2. Verify integrity
3. Confirm successful completion
4. Remove incomplete temporary files
5. Move completed file into final destination

Never mark a corrupted or incomplete file as successfully received.

---

# PHASE 18 — STORAGE

## Goal

Implement local file storage.

Support:

- Download location
- Temporary files
- Completed files
- Cleanup

Never leave broken temporary files after failed transfers unless needed for recovery.

The application must remain offline-first.

---

# PHASE 19 — TRANSFER HISTORY

## Goal

Implement local transfer history.

Show:

- File name
- Sent / Received
- Device
- Date/time
- File size
- Success / Failed

Keep it compact and clean.

Do not create a complicated file manager.

The original specification explicitly says HozaSend should remain a simple file-transfer application rather than becoming a complicated file manager.

---

# PHASE 20 — HOME SCREEN

## Goal

Now build the primary experience around the working networking engine.

The home screen should immediately communicate:

> Ready to Send

Include:

- HozaSend logo
- Device name
- Connection status
- Nearby devices
- Send Files
- Receive
- Recent transfers

Example:

```text
HozaSend

Ready to share

🟢 Connected to local network

Nearby Devices

💻 My Windows PC
📱 Rayan's Phone

[ Send Files ]

[ Receive ]

Recent Transfers
```

These are the core Home requirements from the specification.

---

# PHASE 21 — SETTINGS

## Goal

Keep Settings simple.

Include:

- Device name
- Appearance
- Download location
- Auto-accept
- Notifications
- About HozaSend

Appearance:

```text
System
Light
Dark
```

Do not add unnecessary settings.

These requirements are explicitly defined in the product specification.

---

# PHASE 22 — ANDROID POLISH

## Goal

Make Android feel native.

Verify:

- Permissions
- File picker
- Image/video thumbnails
- Notifications
- Lifecycle
- Background transfer where practical
- Material interactions

Do not assume Android behaves like Windows.

The specification specifically requires correct Android lifecycle and platform handling.

---

# PHASE 23 — WINDOWS POLISH

## Goal

Make Windows feel like a real desktop application.

Do NOT simply stretch the mobile interface.

Support:

- Responsive desktop layout
- Mouse interactions
- Keyboard support
- Native Windows file picker
- Resizable window
- Desktop spacing
- Drag-and-drop where practical

Users should be able to drag files onto the HozaSend window when practical.

---

# PHASE 24 — HOTSPOT TESTING

## CRITICAL REAL-WORLD TEST

Test:

```text
Android phone
    ↓
Enable hotspot
    ↓
Windows PC connects
    ↓
Both launch HozaSend
    ↓
Devices discover each other
    ↓
Select device
    ↓
Select file
    ↓
Transfer
```

The application must work even when the hotspot has NO INTERNET.

Do not confuse:

> Internet connection

with:

> Local network connection.

The application requires only local connectivity.

Android restrictions must be respected.

Never pretend Flutter can automatically bypass Android system restrictions around hotspot control.

---

# PHASE 25 — PERFORMANCE

## Goal

Make the application lightweight.

Rules:

### NEVER

Load a 5 GB video entirely into RAM.

### ALWAYS

Use streaming/chunked transfer.

Monitor:

- RAM
- CPU
- Disk
- Network throughput
- UI responsiveness

The UI must remain responsive during transfers.

Requirements include large files, multiple files, accurate progress, and cleanup of temporary data.

---

# PHASE 26 — ANIMATION POLISH

Only after functionality is stable.

Add:

### Discovery

Radar/ripple.

### Device appearance

Fade + slide.

### Connection

Subtle pulse/connection line.

### Sending

Smooth progress animation.

### Success

Clean checkmark animation.

### Page transitions

Fade + slide.

### File selection

Small stagger.

These animation concepts are part of the original design specification.

---

# 27. ANIMATION RULES

Animations must be:

- Fast
- Smooth
- Purposeful
- Subtle
- Interruptible

Never:

- Animate everything
- Add bouncing everywhere
- Add distracting particles
- Use long loading animations
- Block user interaction

Animations should communicate state.

Not exist merely because animation looks cool.

---

# 28. EMPTY STATES

Every important empty state must be designed.

Example:

```text
No devices nearby

Connect your devices to the same
Wi-Fi or hotspot and HozaSend
will find them automatically.

[ Search Again ]
```

Empty states should explain:

1. What happened
2. Why it happened
3. What the user can do

The original specification specifically calls for a friendly no-device state and Search Again action.

---

# 29. ERROR UX

Never expose internal implementation details.

Bad:

```text
SocketException
Connection refused
errno 111
```

Good:

```text
Couldn't connect

Make sure both devices are connected
to the same Wi-Fi or hotspot.

[ Try Again ]
```

Technical details may still be logged for developers.

Users should receive human-readable messages.

---

# 30. RESPONSIVE DESIGN

Never design for only one screen size.

Test:

### Android

- Small phone
- Normal phone
- Large phone
- Portrait
- Landscape where relevant

### Windows

- Small window
- Medium window
- Large monitor
- Window resize

Avoid:

- Hardcoded widths
- Hardcoded heights
- Overflow
- Text clipping
- Unnecessary scrolling

---

# 31. UI QUALITY CHECK

Before considering a screen finished, inspect:

### Layout

- Alignment
- Padding
- Spacing
- Safe areas
- Overflow

### Typography

- Size
- Weight
- Contrast
- Line height
- Truncation

### Components

- Radius
- Shadows
- Borders
- Icons
- Touch targets

### Animation

- Entry
- Exit
- Loading
- Success
- Failure

### Accessibility

- Readability
- Contrast
- Touch target size
- Semantic labels

---

# 32. CODE QUALITY

Every implementation should prioritize:

- Readability
- Small classes
- Clear names
- Single responsibility
- Testability
- Error handling
- Proper async handling
- Proper disposal
- No memory leaks

Avoid giant widgets.

If a widget becomes too large, split it logically.

But do not create dozens of meaningless one-line files.

---

# 33. ASYNC / NETWORKING RULES

Never block the UI thread.

Avoid:

```dart
read entire huge file
→ convert entire file
→ send
```

Prefer streaming.

All network operations must support:

- Cancellation where practical
- Timeout
- Error handling
- Cleanup
- Connection state
- Retry strategy

---

# 34. STATE MANAGEMENT RULES

State must have clear ownership.

Avoid:

- Global mutable variables
- Random singleton state
- UI widgets owning networking logic
- Business logic inside `build()`

A UI widget should not directly implement the transfer protocol.

---

# 35. TESTING STRATEGY

Testing must happen throughout development.

## Unit tests

Test:

- Models
- Progress calculations
- ETA
- Speed calculations
- Protocol parsing
- Validation
- History
- Storage logic

## Integration tests

Test:

- Discovery
- Connection
- Transfer
- Cancellation
- Retry

## Manual tests

Always test real devices.

---

# 36. NETWORK TEST MATRIX

Test:

| Test | Android | Windows |
|---|---|---|
| Android → Android | ✓ | |
| Android → Windows | ✓ | ✓ |
| Windows → Android | ✓ | ✓ |
| Windows → Windows | | ✓ |

Also test:

- Same Wi-Fi
- Phone hotspot
- Wi-Fi without internet
- Weak connection
- Device disconnect
- Device reconnect
- Large files
- Multiple files

---

# 37. FILE TEST MATRIX

Test:

- 1 KB file
- Small image
- Large image
- PDF
- ZIP
- Audio
- Large video
- Multiple files
- Very large file

Check:

- Correct size
- Correct content
- Integrity
- Speed
- Progress
- Destination
- History

---

# 38. REAL-WORLD FAILURE TESTS

Intentionally test:

### Receiver disconnects

Expected:

```text
Transfer failed
Connection lost
[ Retry ]
```

### Sender disconnects

Same.

### User rejects

Expected:

```text
Transfer declined
```

### Storage unavailable

Expected:

```text
Couldn't save file
Choose another location
```

### Network disappears

Expected:

```text
Connection lost
```

No crashes.

---

# 39. SECURITY RULES

Never:

- Upload files
- Log file contents
- Log sensitive file data
- Store unnecessary personal information
- Trust unknown transfer requests automatically

Use:

- Local pairing
- Transfer confirmation
- Encryption where practical
- Integrity verification

Only LAN devices should participate in discovery.

---

# 40. LOGGING

Developer logs should be useful.

Good:

```text
[Discovery] Device discovered
[Connection] Handshake successful
[Transfer] Started
[Transfer] 50%
[Transfer] Completed
```

Bad:

```text
print("hello")
print("test")
print("why")
```

Never spam logs during large transfers.

Do not log sensitive file contents.

---

# 41. GIT / CHANGE DISCIPLINE

Each phase should produce a logical set of changes.

Preferred conceptual commits:

```text
feat: establish app architecture
feat: add device discovery
feat: add connection handshake
feat: add single file transfer
feat: add transfer progress
feat: add receive confirmation
feat: add multi-file transfer
feat: add history
feat: polish home screen
feat: polish animations
```

Do not mix unrelated changes into one phase.

---

# 42. VERIFICATION AFTER EVERY PHASE

After each meaningful phase:

Run appropriate checks.

At minimum:

```powershell
flutter analyze
flutter test
```

When platform changes are involved:

```powershell
flutter build apk
```

and/or:

```powershell
flutter build windows
```

Do not move to the next major phase if the current phase is fundamentally broken.

---

# 43. STOP CONDITIONS

STOP and report the problem when:

- Requirements conflict
- Platform limitation blocks functionality
- Network behavior is unclear
- A dependency introduces serious compatibility problems
- Build configuration is broken
- Existing code cannot safely be modified
- You need a decision that affects architecture

Do NOT endlessly retry the same failed command.

Do NOT make random changes hoping the problem disappears.

Instead:

```text
PROBLEM
CAUSE
WHAT WAS TESTED
WHAT IS BLOCKING PROGRESS
RECOMMENDED SOLUTION
```

---

# 44. DO NOT WASTE TOKENS

Claude Code should work efficiently.

Do not:

- Re-read unchanged files unnecessarily
- Re-explain the whole project every turn
- Repeat the same failed approach
- Generate huge explanations after every command
- Refactor unrelated code
- Add unnecessary abstractions
- Build features before their dependencies exist

Use the smallest amount of work necessary to achieve the current phase correctly.

---

# 45. DO NOT PRETEND

If something cannot be done on Android or Windows because of platform restrictions:

Say so.

For example:

```text
Android does not allow this application
to programmatically perform this system-level
operation under normal application permissions.

Alternative:
ask the user to enable it manually.
```

Never claim functionality works if it has not been tested.

---

# 46. CURRENT PHASE RULE

At all times, maintain a clear current phase.

Example:

```text
CURRENT PHASE:
PHASE 5 — LAN DEVICE DISCOVERY

STATUS:
In progress

DO NOT IMPLEMENT YET:
- File transfer
- History
- Settings polish
- Advanced animations
```

Only work on the current phase unless a dependency requires a small supporting change.

---

# 47. PHASE COMPLETION FORMAT

At the end of each phase, report:

```text
PHASE COMPLETE

Phase:
PHASE X — Name

Implemented:
- ...
- ...
- ...

Files changed:
- ...
- ...

Tests:
- flutter analyze
- flutter test
- platform test

Result:
PASS / PARTIAL / BLOCKED

Next phase:
PHASE X+1 — Name
```

Keep this concise.

---

# 48. UI-FIRST QUALITY RULE

When implementing UI:

Do not settle for the first functional layout.

After functionality works, inspect:

- Visual hierarchy
- Spacing
- Typography
- Empty states
- Loading states
- Error states
- Success states
- Responsive behavior
- Dark mode
- Light mode
- Animation quality

The app should look intentionally designed.

---

# 49. PREMIUM DESIGN RULE

HozaSend should NOT look like:

- A generic file manager
- A basic Flutter demo
- A default Material template
- A generic Android utility
- A collection of random glass cards

It should look like a focused premium product.

Design philosophy:

> Less UI. Better UI.

The specification explicitly says the experience should remain extremely clean and should not become a complicated file manager.

---

# 50. CORE UX PRINCIPLE

Every important action should be obvious.

The user should understand:

```text
Where am I?

Who is nearby?

What can I send?

Who am I sending to?

How far is the transfer?

Did it succeed?

Where is the file?
```

No unnecessary complexity.

---

# 51. FINAL PRODUCT FLOW

The final application should feel like:

```text
OPEN APP
    ↓
READY TO SHARE
    ↓
SEE NEARBY DEVICE
    ↓
SELECT DEVICE
    ↓
SELECT FILE
    ↓
CONFIRM
    ↓
TRANSFER
    ↓
PROGRESS
    ↓
SUCCESS
    ↓
DONE
```

The product's stated goal is exactly this simple local-sharing experience.

---

# 52. FINAL IMPLEMENTATION ORDER

Use this order unless there is a strong technical reason not to:

```text
01. Project audit
02. Architecture
03. Design system
04. Branding
05. Device identity
06. LAN discovery
07. Discovery UI
08. Connection
09. Security / pairing
10. File picker
11. File selection UI
12. Transfer protocol
13. Single-file transfer
14. Progress
15. Receive confirmation
16. Multi-file transfer
17. Cancel / retry
18. Integrity verification
19. Storage
20. Transfer history
21. Home screen
22. Settings
23. Android polish
24. Windows polish
25. Hotspot testing
26. Performance
27. Animation polish
28. Responsive polish
29. Full testing
30. Final cleanup
```

---

# 53. FINAL ACCEPTANCE CHECKLIST

Before declaring HozaSend finished:

## Product

- [ ] No account required
- [ ] No internet required
- [ ] No cloud
- [ ] No external server
- [ ] Local network works
- [ ] Hotspot scenario works

## Discovery

- [ ] Android discovers Android
- [ ] Android discovers Windows
- [ ] Windows discovers Android
- [ ] Windows discovers Windows
- [ ] Devices disappear correctly
- [ ] Devices reconnect correctly

## Transfer

- [ ] Single file
- [ ] Multiple files
- [ ] Large files
- [ ] Progress
- [ ] Speed
- [ ] ETA
- [ ] Cancel
- [ ] Retry
- [ ] Integrity verification

## Receiving

- [ ] Incoming request
- [ ] Accept
- [ ] Reject
- [ ] Progress
- [ ] Save locally
- [ ] Cleanup failed transfers

## UI

- [ ] Premium Home
- [ ] Discovery animation
- [ ] Transfer animation
- [ ] Success animation
- [ ] Error states
- [ ] Empty states
- [ ] Dark mode
- [ ] Light mode
- [ ] Responsive layouts

## Android

- [ ] Permissions
- [ ] File picker
- [ ] Notifications
- [ ] Lifecycle
- [ ] Background behavior where practical

## Windows

- [ ] Desktop layout
- [ ] Resizable window
- [ ] Mouse interaction
- [ ] Keyboard support
- [ ] Native file picker
- [ ] Drag and drop where practical

## Engineering

- [ ] No huge files loaded into RAM
- [ ] Streaming transfer
- [ ] Stable networking
- [ ] Proper cleanup
- [ ] Proper error handling
- [ ] No unnecessary dependencies
- [ ] No giant widgets
- [ ] No unnecessary global state
- [ ] `flutter analyze` passes
- [ ] Tests pass
- [ ] Android build works
- [ ] Windows build works

---

# 54. THE MOST IMPORTANT CLAUDE CODE INSTRUCTION

Always remember:

> **Do not try to finish HozaSend in one session.**

Build it like a professional product.

First make the foundation correct.

Then make discovery reliable.

Then make connection reliable.

Then make one-file transfer reliable.

Then make receiving reliable.

Then add multiple files.

Then add history.

Then polish the UI.

Then polish animations.

Then optimize.

Then test everything.

Do not sacrifice reliability for speed.

Do not sacrifice simplicity for features.

Do not sacrifice usability for visual effects.

Do not sacrifice architecture for quick hacks.

---

# 55. WHEN STARTING A NEW SESSION

First determine:

```text
What phase are we currently in?
What has already been implemented?
What is currently broken?
What is the smallest next milestone?
```

Then inspect only the files needed for that milestone.

Do not rebuild completed phases.

Do not assume previous work is correct—verify important boundaries.

---

# 56. FIRST COMMAND / FIRST ACTION

When Claude Code starts working on HozaSend:

### DO NOT immediately write code.

First:

1. Inspect the project.
2. Identify the current state.
3. Read `pubspec.yaml`.
4. Inspect `lib/`.
5. Inspect Android configuration.
6. Inspect Windows configuration.
7. Identify existing architecture.
8. Identify what phase the project is currently in.
9. Create a short plan.
10. Ask for clarification only if genuinely blocked.

Then begin the **smallest appropriate phase**.

---

# FINAL PRINCIPLE

Build HozaSend one reliable piece at a time.

```text
ARCHITECTURE
     ↓
DESIGN
     ↓
DISCOVERY
     ↓
CONNECTION
     ↓
TRANSFER
     ↓
RECEIVING
     ↓
HISTORY
     ↓
PLATFORM POLISH
     ↓
ANIMATION
     ↓
PERFORMANCE
     ↓
TESTING
     ↓
FINAL PRODUCT
```

Never reverse this order without a technical reason.

**The goal is not to generate the most code.**

**The goal is to build the best HozaSend application with the smallest amount of unnecessary code, while keeping every phase stable, testable, beautiful, and maintainable.**