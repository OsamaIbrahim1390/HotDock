# Demo video — recording script

A shot-by-shot plan for a ~2 minute demo. Timings are a guide, not a stopwatch.

**Total: about 2:05.** Record in one pass if you can; a single unbroken take of software that
visibly works is more convincing than a cut-together one.

---

## Step 0 — before you record (do not skip)

HotDock marks its windows `NSWindowSharingType.none`, which asks macOS to keep them out of
screen captures. On macOS 15+ that request is usually ignored, which is why the overlay shows
up in recordings — but **verify it on your machine before recording the whole thing**:

1. Start a 5-second screen recording (QuickTime → File → New Screen Recording, or `⇧⌘5`).
2. Reveal the overlay during it.
3. Play it back. **Is the card in the recording?**

If it isn't, your macOS honours the flag and you cannot screen-record the overlay. Film the
laptop with a phone on a small tripod instead — for a notch app that arguably looks better
anyway, since it shows the card in its real place under the camera.

### What a recording will expose

A screen recording captures everything on screen, not just HotDock. Before you record, and
again before you publish, check for:

- The **script** you load — use a written-for-the-demo one, not a real interview script.
- The **notes** you type and any pinned note left from earlier sessions.
- The **Spotify track** playing, which is your listening history.
- Menu bar icons, notification banners, browser tabs, window titles, filenames in Finder,
  and your **wallpaper**.
- The notes browser window, which lists **every past session title**.

Easiest approach: make a fresh session, load a throwaway script, and clear pinned notes before
you start. The same applies to `docs/screenshot.png`.

### Setup

- Overlay size **560×190**, font size **19** (bigger than your usual 13 — it needs to read on
  a phone screen). Settings → Script → Text size.
- Load a script with a few `#` headings so section jumps are visible.
- Spotify running with a track that has **recognisable album art** and is **paused** at the
  start, so the record visibly starts spinning on camera.
- Quit anything with notifications. Do Not Disturb on.
- Clean desktop, neutral wallpaper.

---

## Shot 1 — the hook (0:00–0:12)

**On screen:** A plain desktop. Nothing visible but the Siri glow around the notch. Move the
cursor slowly up into the notch — the card slides down.

> "This is a teleprompter that lives in the notch of your MacBook. It's hidden until you
> reach for it, and when you're reading from it your eyes are right next to the camera —
> not halfway down the screen."

**Hold** on the revealed card for two seconds before moving on.

---

## Shot 2 — reading from it (0:12–0:35)

**On screen:** Click ▶. Let the script scroll for a few seconds. Move the cursor over the text
— it pauses. Move away — it resumes. Two-finger scroll back up a little.

> "Press play and it scrolls at whatever pace you set. Hover the text and it pauses so you
> can catch up. Scroll it by hand if you need to go back. The bar on the right shows how much
> you've got left."

---

## Shot 3 — the drawer (0:35–0:55)

**On screen:** Click ☰. Drag the speed slider — the scroll visibly changes pace. Drag the text
size slider. Drag the overlay size control to make the card bigger, then press ↺ to reset.

> "Speed, text size and the size of the whole card are all live. If you ever shrink it too
> far, there's a reset — here, and in the menu bar."

---

## Shot 4 — notes (0:55–1:25)

**On screen:** Click ✎. The script becomes a blank editor. Type something short and specific
— *"ask about the migration timeline"* — press return. The note appears pinned under the
script. Click the pinned note; it reopens for editing. Add a word, return. Hover it and click
✕ to unpin.

> "The pencil turns the card into a notepad. Type, hit return, and it's saved and timestamped
> — grouped into a session, so an interview's notes stay together. The most recent one stays
> pinned under the script, which is handy for a name or a number you can't afford to get
> wrong. Click it to edit it, or unpin it when you're done."

**Then:** menu bar → Browse Notes… Show the session list and the search field for two seconds.

> "They're plain Markdown files on your Mac, and they can mirror into the Notes app."

---

## Shot 5 — Spotify (1:25–1:50)

**On screen:** Click ♪. The player column appears with the record stopped. Click the record —
it starts spinning and the music starts. Hover for previous/next. Nudge the volume slider.

> "There's an optional Spotify player. The album art is the record, and it only turns while
> something's playing. It talks to the Spotify app on your Mac — no account, no web API."

---

## Shot 6 — the honest bit (1:50–2:05)

**On screen:** The README's screen-sharing section, or a Zoom window sharing a single window.

> "One thing to be straight about: HotDock asks macOS to keep its windows out of screen
> captures, but on recent macOS that request is often ignored. So share a single window, not
> your whole screen — and test it on a real call before you rely on it. The README explains
> exactly how."

**End on** the notch with the glow, cursor moving away, card sliding up.

---

## Recording notes

- **Record at 1080p or higher.** The card is small; detail matters.
- **Move the cursor slowly.** Every interaction here is cursor-driven and fast movement reads
  as jitter.
- Leave a beat of stillness after each action so the viewer sees the result.
- If narrating live is awkward, record the screen silently and add voiceover after. The script
  above is written to be read aloud at a normal pace.

## Publishing it

GitHub does not host video from the repo well — a committed `.mp4` won't play inline and
bloats every clone.

**Do this instead:** open a new issue in your repo, drag the `.mp4` into the comment box, and
wait for it to upload. GitHub gives you a `user-images.githubusercontent.com` URL. Copy it,
close the issue without submitting, and put the URL on its own line in `README.md`:

```markdown
https://user-images.githubusercontent.com/.../hotdock-demo.mp4
```

A bare video URL on its own line renders as an inline player. Attach the same file to your
Release as well, so it survives independently of the issue.

**Also take a still** of the revealed card for `docs/screenshot.png` — the README already
references it.
