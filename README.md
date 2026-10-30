# HotDock

A teleprompter that lives in your MacBook's notch.

Read a script while you present, with your eyes next to the camera instead of down the screen.
Take timestamped notes without leaving what you're doing. Control Spotify from the same card.

Menu bar only — no Dock icon, no window in your way.

---

## What it does

**Teleprompter.** Paste or load a script; it scrolls under the notch at a speed you set. Hover
the text to pause and catch up. Scroll it by hand with two fingers. Markdown headings (`# Like
this`) become jump targets.

**Quick notes.** Hit the pencil and the script turns into a blank editor in the same card.
Press return and the note is saved, timestamped, and grouped into a session. The most recent
note stays pinned under the script so a name or a number you must not get wrong stays in view.

**Spotify.** An optional column showing the album art as a spinning record, with transport
controls and volume. Talks to the Spotify app on your Mac, not to Spotify's servers.
**Off until you switch it on** in Settings → Spotify mini player, so it never asks for
permission you did not ask for.

**It hides.** By default the card is tucked behind the notch and slides down when you move the
cursor into it. A Siri-coloured outline around the notch tells you it's running.

## Requirements

- A Mac with a notch (works without one, see below)
- macOS 14 or later
- Spotify desktop app, only if you want the mini player

On a Mac with no notch, the overlay anchors to the top centre of the screen instead. Everything
else works the same.

## Install

Download the `.dmg` from [Releases](../../releases) and drag HotDock to Applications.

> [!IMPORTANT]
> **The first launch will be blocked.** macOS will say *"Apple could not verify HotDock is free
> of malware."* This app is not notarized — that requires a paid Apple Developer account.
>
> On **macOS 15 and later**, Control-click → Open no longer works. Do this instead:
>
> 1. Double-click HotDock and click **Done** on the warning. This attempt is what makes the
>    next step appear — skipping it means there is nothing to approve.
> 2. Open **System Settings → Privacy & Security** and scroll down to **Security**.
> 3. Next to *"HotDock was blocked to protect your Mac"*, click **Open Anyway**.
> 4. Authenticate, then click **Open Anyway** once more.
>
> The button only appears for a short while after the blocked attempt. If it has gone, just
> double-click the app again to bring it back.
>
> Or, from Terminal: `xattr -d com.apple.quarantine /Applications/HotDock.app`
>
> If you would rather not trust a stranger's binary, that is reasonable — build it from source
> instead. It takes about a minute and skips all of this.

### Build from source

```sh
git clone https://github.com/OsamaIbrahim1390/HotDock
cd HotDock
./make.sh run
```

That's it — no Xcode project to open, no dependencies to fetch. `make.sh` compiles with Swift
Package Manager, assembles a real `.app`, signs it and launches it.

| Command | What it does |
|---|---|
| `./make.sh run` | build and (re)launch |
| `./make.sh stop` | quit it |
| `./make.sh install` | copy to `/Applications` |
| `./make.sh dmg` | build a release disk image into `dist/` |
| `./make.sh identity` | show which signing identity will be used |

Building it yourself also avoids the Gatekeeper prompt entirely.

## Using it

Move your cursor **into the notch** and the card slides down. Move away and it slides back.
Prefer it always on screen? Settings → Reveal → Always Visible.

The card has three columns: the **script**, a narrow strip of **controls**, and the optional
**player**.

| Button | |
|---|---|
| ▶ / ⏸ | play and pause the script |
| ↺ | back to the top |
| ✎ | turn the card into a note editor |
| ☰ | drawer: speed, text size, overlay size, loading a script |
| ♪ | show or hide the player — **only appears once the Spotify player is switched on** |

**Scrolling.** Hover the text to pause. Two-finger scroll over it to move by hand. Drag the
scrollbar to scrub — its length also shows how much of the script is left.

**Loading a script.** Open the drawer → *Open text file…* for a `.txt` or `.md`, or *Load from
Notes…* to pull one straight out of the Notes app.

**Notes.** Press ✎, type, press return. `⇧↩` for a new line, `esc` to cancel. Click a pinned
note to edit it; hover it and press ✕ to unpin. Emptying a note and saving deletes it.
Sessions start automatically when you start a script, or from the menu bar.

Everything else lives in **Settings** (`⌘,` from the menu bar): typeface, line spacing,
opacity, how eagerly the card reveals itself, and the notch glow.

### If you lose the overlay

Shrunk it too far, or it ended up off-screen after a display change? The menu bar has
**Reset Overlay Size** and **Reposition Overlay**. Those work no matter what state the card is
in.

## Permissions

HotDock asks for nothing at launch. Each permission is requested the first time you use the
feature that needs it, and the rest of the app works without it.

| Permission | Needed for | If you say no |
|---|---|---|
| Automation → Notes | Loading a script from Notes; mirroring notes into Notes | Notes stay in local files only |
| Automation → Spotify | The mini player | The player column doesn't appear |

Notes are **always** written to a local file first, before any attempt to copy them into the
Notes app. Denying automation can cost you the copy in Notes, never the note itself.

## Privacy

- Scripts and notes are plain files in `~/Library/Application Support/HotDock/`. Not iCloud,
  not synced, not sent anywhere.
- **One network request exists in the whole app**: fetching album artwork from Spotify's image
  CDN, and only while the mini player is switched on. Images are held in memory and never
  written to disk.
- No analytics, no telemetry, no crash reporting, no update checks.
- The Spotify and Notes features talk only to those apps on your Mac, through Apple Events.
- There is a local debug log at `~/Library/Application Support/HotDock/hotdock.log`, capped at
  512 KB. It records window geometry and feature state. Delete it whenever you like.

## Screen sharing — read this before you rely on it

Every window HotDock creates is marked `NSWindowSharingType.none`, which asks the window server
to keep it out of screen captures.

> [!WARNING]
> **On macOS 15 and later this is not reliable.** ScreenCaptureKit — which current Zoom,
> Microsoft Teams, Google Meet in Chrome, and QuickTime all use — captures windows marked
> `.none` anyway. See [Apple Developer Forums 792152](https://developer.apple.com/forums/thread/792152),
> [tauri#14200](https://github.com/tauri-apps/tauri/issues/14200) and
> [WebRTC 41480865](https://issues.webrtc.org/41480865).
>
> The flag is still set, because it costs nothing and is honoured by the older capture path.
> **But do not treat it as protection.**

**What actually works: share a single window, never your whole screen.** HotDock's overlay is
not part of any other app's window, so a single-window share cannot include it.

### Before a real call

1. Start a test call and share **the specific window** you plan to share — not Entire Screen.
2. Check the self-view, or better, look at a second device joined to the same call.
3. Reveal the overlay and confirm it is not visible to the other side.
4. Repeat after updating Zoom, Teams, Chrome or macOS. Capture behaviour changes between
   versions; a result from last month is not evidence about this month.

If you need a guarantee, don't use an overlay — use a second device.

## Not built yet

Global keyboard shortcuts, a saved script library, panic-hide, presentation mode, a built-in
screen-capture test, and voice-synced scrolling. The code has seams for these but they are not
implemented — don't expect them from this version.

## Licence

MIT. See [LICENSE](LICENSE).
