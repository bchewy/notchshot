# Mint photographer mascot — 0.5.2 (build 28)

## Behavior

- Replaced the left viewfinder with a native mint photographer holding the selected Fujifilm camera. The existing X-T3, X100S, and F11 artwork now uses a shared decoded-image cache with the shutter picker.
- The decorative view derives idle, framing, holding, and shelving poses from the existing capture flags. Pending screenshot state takes precedence over ongoing text extraction, so the mascot can hold its print while accessibility work finishes. Landing makes the small print shrink/fade downward; returning to idle resets the pose. Hover adds a slight nod.
- The mascot draws at 14 points wide when collapsed and 26 when open, within the existing 16-to-40-point lane. It does not intercept input or add accessibility elements; the existing Open/Collapse button and right permission/progress indicator remain intact.
- Pose/hover motion is brief and respects Reduce Motion. There are no idle timers, new capture delays, extra sounds, capture-state mutations, or changes to the screenshot's native flight.

## Verification

- **295 existing regression tests passed with zero failures** (`work/mascot-qa/tests.log`, 11.845 seconds). Native panel motion, capture/landing, shelf interaction, copying, permissions, and packaging-resource tests remain green. No implementation-mirroring tests were added for the decorative poses.
- Rendered the actual SwiftUI component for all three cameras and four poses, plus actual-size14/26-point comparisons (`outputs/mascot-preview.png`). Independent visual review found no clipping or legibility blocker; framing raises the camera, holding shows a clear white print, and shelving stays inside bounds.
- Actual NotchRootView renders remain **225 × 32 collapsed** and **440 × 180 expanded**. Native installed UI screenshots confirmed the idle mascot fits both surfaces, with the existing open/collapse control and shelf controls still present. The live shelf had zero shots before updating, so no new captures required backup.
- Built, signed, certificate-verified, installed and confirmed running as **0.5.2 build 28** (`work/mascot-qa/install.log`). Captured the real collapsed and expanded app UI through CUA after installation. New capture/hover animation timing was checked in source and static poses; physical capture choreography was not exercised end to end in this pass.
- The code-native face reuses the previously generated camera artwork; no new image-generation model or external asset was used. The app/source archives are rebuilt and validated for ZIP integrity, extracted strict signature/version, and all three matching camera PNG and shutter WAV resources.

# Precise, responsive thumbnail hover — 0.5.1 (build 27)

## Fix

- Bound each thumbnail tracker to its own bounds and the visible scrolled region. A native regression fixture demonstrated the bug: AppKit returned a 300 × 200 visibleRect for a 72 × 38 view, allowing points outside the shot to participate in hover. `clipsToBounds` plus an explicit bounds/visibleRect intersection prevents neighboring trackers from overlapping.
- Reconcile pointer presence on mouse movement, enabling, attachment, and deferred tracking/layout changes. A missed entry or capture/expansion transition no longer requires another boundary crossing. Repeated movement within a tile leaves the current preview delay and copy registration intact.
- Reduce the preview dwell from 220 to 120 ms. Keep the existing fade and Reduce Motion behavior. Geometry changes immediately invalidate stale copy callbacks and re-evaluate the pointer after layout; native layout notifications defer SwiftUI state changes.
- Require the thumbnail's window to be the actual mouse target before acquiring hover/copy, so an overlapping popover or another window cannot activate the covered shot. Clicks still pass to the existing thumbnail/delete buttons.

## Verification

- **295 tests passed, zero failures or exclusions** (`work/hover-sensitivity-qa/tests.log`, 12.009 seconds). This also reruns and passes all native motion checks that timed out while the Mac was locked during 0.5.0 verification.
- Nine new noninteractive native tests cover eight edge/corner positions, movement after missed entry, enabling under a stationary pointer, geometry recovery, stale-copy rejection, repeated-movement idempotence, clipped thumbnails, stop/detach cancellation, and covered-window protection. Fake shortcut bindings prevent changing the real clipboard or taking a system shortcut during tests.
- Actual SwiftUI shelf rendering measured all three fixture anchors at **72 × 38 bounds and visibleRect**, with separate x positions 24, 103, and 182 (`work/hover-sensitivity-qa/render.log`). The rendered shelf remains 440 × 180; no enlargement was needed.
- Built, signed, certificate-verified, installed and confirmed running at **0.5.1 build 27** (`work/hover-sensitivity-qa/install.log`). The live shelf was empty before replacement, so no new captures required backup.
- Live updated Settings confirmed Accessibility and Screen Recording both Allowed; away-collapse remains enabled at 3 seconds, Shift + Shift remains enabled, and existing copy/paste/sound settings remain intact. Compact is the batch-context default. Physical pointer feel is not claimed as automated UI verification: CUA has no pointer-hover API and restores the pointer after clicks. Edge behavior is verified with native tracking tests and actual SwiftUI geometry.
- App and source archives are rebuilt and checked for ZIP integrity, extracted strict signature/version, and matching camera PNG/shutter WAV assets. Backups and signing/build scratch files remain excluded.

# Multi-shot selection and copy — 0.5.0 (build 26)

## Behavior

- Select, Command-click, Shift-click ranges, and All choose an ordered batch. Numbered badges match shelf order. Selection survives collapse; new arrivals do not join it automatically, and deletion reconciles it. Normal thumbnail clicks still open details outside selection mode.
- Copy N shots, hover Command-C, and focused shelf Command-C copy the batch. Focused Command-A selects all. Native text fields retain their own shortcuts. Empty selections and unfinished preparation do not overwrite the clipboard.
- Review context shows the exact copy text and validated screenshot count. Compact is the default: labeled excerpts, repeated long-line removal, at most 32,000 characters total / 6,000 per shot, and explicit omission markers. Full preserves complete source context. Original captures and exports are unchanged.
- Large text, tree work, and PNG validation run off the main actor. Superseded preparation cannot replace a newer selection. Compact scans bounded prefixes rather than allocating full source documents. Unavailable screenshots are numbered in the review, context, and status.
- Rich copy contains every valid screenshot followed by combined context. With Paste image, then text enabled, the next physical Command-V stages the ordered screenshots, then one context block. It checks clipboard ownership and destination focus between stages, cancels on intervening input, and does not replay images already sent. It never submits a message.
- Existing copy sound, smooth copy-collapse, away-collapse protection, and compact 440 × 180 shelf are retained. Dismissing the successful copy review does not cancel its close animation.

## Verification

- **270 tests passed, zero failures** after the final fixes (`work/batch-copy-qa/non-display-tests.log`). This includes all **55 new tests** for batch context, selection, rich clipboard, assisted paste, and the native text viewport.
- The initial full run executed 286 tests. One new exact-count test exposed a CRLF edge case; it was fixed and all 17 context tests passed. Six existing native motion tests timed out while the Mac was locked. The follow-up run excluded the 16 tests in the two motion suites and one native copy-collapse test; this is not a full-suite pass. Those checks require an unlocked display before rerunning.
- Compact preparation of two 10,034,000-byte text imports took **0.018 seconds** in the final passing run. Large work also has background preparation and stale-result protection.
- Actual SwiftUI shelf and review views were rendered and visually inspected with three harmless fixture shots: two images and one text-only shot. Numbered badges, exact context counts, wrapped text, and copy/review controls fit their compact layouts (`work/batch-copy-qa/batch-shelf.png`, `batch-review.png`). These are view renders, not live desktop interaction.
- Independent read-only review identified and then confirmed fixes for large-import main-thread work and inconsistent unavailable-image counts; follow-up found no remaining actionable findings in preparation cancellation, image consistency, or selection/paste flow.
- **Built, signed, certificate-verified, installed, and confirmed running** as 0.5.0 build 26 (`work/batch-copy-qa/install.log`). The pre-update ChatGPT capture CB17EA6A was exported to `outputs/Saved-before-update/NotchShot-2026-09-15T14-09-13Z-CB17EA6A`; its PNG and JSON were validated before replacement.
- Before the Mac locked, the export chooser remained open beyond the 3-second away delay and the export completed. This also verifies the previous release's export protection. The Mac then locked and the user was asked to unlock it; updated live shelf/settings, native destination paste, and physical staged-paste receipt remain pending. Existing permissions were verified before the update, not after it.
- Destination support remains app-dependent: a receiver may prefer plain text, reject multiple attachments, or impose length limits. Automated stage-order checks do not prove an app consumed every event. Use reviewed Compact context or Full deliberately; native rich copy and optional staged paste are both available.

# Auto-collapse when away — 0.4.14 (build 25)

## Behavior

- **Collapse when away** starts enabled with a **3-second** delay. Settings offers 2, 3, 5, or 10 seconds and an opt-out; these choices persist independently of collapse-after-copy.
- Presence over the panel, meaningful keyboard focus, native menu tracking, held mouse buttons, popovers, capture/arrival/import/drag, shortcut recording, and export presentation prevent an idle close. Returning cancels the countdown; leaving again grants the full delay. Navigation and new captures also restart it.
- A deadline re-samples native attention immediately before closing and rejects cancelled or superseded callbacks. Closing reuses the existing native spring and Reduce Motion behavior and retains the shelf contents.
- Native monitoring stops when collapsed, hidden, or disabled. The nonactivating panel's stale key-window state alone does not pin it open. Mouse/key releases do not cancel the separate successful-copy close.

## Verification

- **231 tests passed, zero failures** in 10.776 seconds (`work/auto-collapse-qa/tests.log`). The 23 new tests use a virtual clock for exact boundaries/cancellation and native window snapshots for pointer/focus/menu lifecycle behavior. Existing copy, capture, export, and native motion checks also passed.
- Read-only independent review found no actionable issues in cancellation, focus handling, lifecycle, popover protection, or copy-collapse compatibility.
- Built, signed, installed, certificate-verified, and confirmed running at 0.4.14 build 25 (`work/auto-collapse-qa/install.log`). Both existing capture permissions remain allowed in the live Settings UI.
- Live UI verified automatic collapse while away, opt-out holding Settings open past the delay, recording a shortcut holding it open, and cancelling recording releasing the stale key focus and allowing collapse. The 5-second choice selected correctly, then the final setting was restored to **enabled / 3 seconds**. The compact Settings page was visually inspected.
- UI automation restores the pointer after clicks and does not reliably trigger global shortcuts or open a real tracked menu. Pointer return, menu lifecycle, and capture/drag protection were verified through the native/virtual-clock checks; physical hover/menu behavior and the updated export chooser were not exercised end to end in this run. The export guard and existing export implementation were reviewed.
- The three pre-update captures were exported to `outputs/Saved-before-update`, with PNG and JSON validated: 3231604D, 751467B4, and 3372C08C (six files each). No existing capture was discarded without a verified local backup.
- Final app/source archives are checked for ZIP integrity; the extracted app's version, strict signature, three camera PNGs, and three distinct shutter WAVs are validated by `work/package-notchshot.py`. Backups and build/signing scratch files are excluded.

# Shift + Shift default — 0.4.13 (build 24)

- Left Shift + right Shift together is enabled by default for fresh preferences; explicit saved disabled choices still survive upgrades.
- The shelf visibly shows **⇧ + ⇧ to capture** and exposes the full left/right wording to accessibility and tooltips. Settings puts **Shift + Shift to capture** first, with the configurable keyboard combination under **Alternative shortcut**.
- Runtime hints follow actual gesture-monitor availability. An unavailable keyboard alternative no longer hides a working Shift gesture. Recorder/reopen transitions clear monitor availability.
- **30 focused shortcut checks passed** (`work/shift-default/tests.log`): gesture recognition, default/migration, custom alternative persistence, primary hint changes and availability fallback. The existing gesture detector was unchanged.
- Signed, installed, and verified running. Live shelf screenshot and Settings accessibility state verified the new hint and enabled toggle. New capture arrivals were observed during QA; no synthetic physical-gesture success is inferred from them.
- The pre-update 8D9D4F41 shot was exported and its PNG/JSON validated under `outputs/Saved-before-update`.

# Clipboard update — 0.4.12 (build 23)

## What changed

- Full-shot copy now offers a real image-plus-context document in native RTFD and self-contained HTML, alongside PNG/TIFF and exact plain text alternatives.
- Added **Paste image, then text** under Capture & copy. It is opt-in for fresh installs and was enabled through Settings on this Mac at the user's request. A full-shot copy arms the next physical ⌘V for two minutes; the helper posts image paste, waits 600 ms, then posts the exact context. It never submits a message. Copy again to repeat assisted paste.
- The helper cancels on clipboard replacement, destination app/window/field changes, intervening typing/clicking, a new capture, shortcut recording, setting disable, or shutdown. Rich clipboard restoration only happens while NotchShot still owns the clipboard. Ordinary image/text/tree copies cancel assistance.
- Keyboard callbacks do not run AX queries or large clipboard writes. AX lookup runs off the main event loop with bounded messaging timeouts; queued work checks generation and ownership again before acting.

## Verification

- **206 tests passed**, zero failures or skips (`work/clipboard-fix/final-tests.log`). Automated checks cover rich/native and plain receivers, exact image bytes and full context, HTML escaping, manual/automatic copy, preference persistence, shortcut conflicts, staged sequencing, expiry, asynchronous focus checks, cancellation, fallback and clipboard ownership.
- A real native ⌘V in TextEdit visibly inserted the harmless fixture image followed by all fixture text. ChatGPT web testing confirmed that ordinary rich and multi-item clipboard paste still chooses text, justifying the optional staged mode. All web test drafts/attachments were removed without submitting a message.
- The 0.4.12 build was signed, installed, and verified running by `script/build_and_run.sh --verify`. Both existing capture permissions remain allowed. The setting's enabled state was checked in the installed UI.
- Two pre-update captures were preserved and their PNG/JSON outputs validated under `outputs/Saved-before-update` (B45B2985 and 63A45E82).
- Physical staged-paste receipt is awaiting user confirmation; native UI automation does not reliably trigger global shortcuts. macOS event posting has no recipient acknowledgement, and apps must support image paste.

# NotchShot 0.4.11 verification — 15 September 2026

## Header feedback

- Replaced the persistent bottom result text in Settings and shot details with a compact **116 × 22-point header badge**. The shelf footer now contains only progress, shortcut, and permission guidance.
- Results use short labels such as **Copied**, **Exported**, and **Needs attention**. Success fades after 3 seconds, informational feedback after 5, and errors after 8, returning to **ON DEVICE**. Each repeated action gets a fresh event; expired messages do not replay on navigation or reopen.
- Clicking a badge opens its full message. Export notices include **Show in Finder**. An open popup retains its message and anchor until dismissed, including when the normal display time expires or newer feedback arrives. Movement respects Reduce Motion.

## Verification

- **173 tests passed**, zero failures/skips. Seven new checks cover expiry, repeated events, clearing, error precedence/full diagnostics, export destinations, and the existing hover-copy clipboard contract. Log: `work/header-notice/tests.log`.
- After preserving the inspected badge as the native popup's anchor, all **7 focused notice tests passed**. Log: `work/header-notice/final-notice-tests.log`.
- Signed and installed **0.4.11 build 22**, certificate trust and running-process verification passed. Log: `work/header-notice/final-install.log`.
- Actual SwiftUI shelf renders inspected at **440 × 180 points** for success, expired/idle, and error states. Header controls fit without resizing the panel; no bottom export message remains. Preview files: `outputs/Notification-shelf-exported.png`, `outputs/Notification-shelf-expired.png`, and `outputs/Notification-shelf-error.png`. These use a benign Notes fixture.
- Live verification reset the already-default shortcut to the same ⌘⇧2, producing real **Shortcut saved** feedback. Its popup opened with the full message, remained visible and accessible after expiry, and closing it returned the header to **ON DEVICE**. The original shortcut, Shift gesture, sound/copy preferences, and permissions remain in place.
- The live shelf was empty before both updates. App/source archives and the extracted app's signature, camera icons, and shutter resources were checked.

Export's Show in Finder uses its captured export URL; that URL is covered by model tests. A new live export was not needed for this UI change. The app remains development-signed and not notarized.

---

# NotchShot 0.4.10 verification — 15 September 2026

## Settings scrolling

- Hidden the Settings page's vertical scroll indicator using the native SwiftUI modifier. Mouse/trackpad scrolling remains available; no overlay scrollbar covers the controls.
- Built and installed **0.4.10 build 21** with valid signature, certificate trust, and running-process checks. Logs: `work/settings-scrollbar/build.log` and `work/settings-scrollbar/install.log`.
- Live Settings was scrolled down to the camera tiles and permissions, then back to the shortcut controls. Both positions were visually inspected: content moved normally, the scrollbar was absent, and the panel kept its compact size. The accessibility tree has no scrollbar node.
- Read-only review confirmed Settings has one scroll container and no AppKit visibility override. Captured text previews retain their separate scroll controls.
- Shelf was empty before restart. Saved camera, sound, volume, shortcut and copy preferences were retained. App/source archives and the extracted signature/resources were verified.

Validation was a build and live scrolling check for this presentation-only change; the full unit suite was not rerun.

---

# NotchShot 0.4.9 verification — 15 September 2026

## Camera shutter tiles

- The traditional dropdown and separate Preview button are replaced by three compact camera tiles: X-T3, X100S, and F11. Click selects and previews that camera's shutter; another click replays it. The saved default/previous choice is preserved.
- Original lens-facing camera illustrations were generated with the built-in image_gen tool after online reference research. Three transparent PNGs are bundled directly with the app and via SwiftPM for development. Assets and prompts: `outputs/Camera-icons`; source documentation: `docs/CAMERA_ICONS.md` and `docs/CAMERA_ICON_PROMPTS.md`.
- Mint border/checkmark identifies selection. Hover provides a subtle lift and scale; pressing dims/compresses the tile. Movement respects Reduce Motion. Buttons expose full camera names and selected state to accessibility. Hover does not play audio.

## Verification

- **166 tests passed**, zero failures/skips, including existing shutter selection, cache, playback, preferences, copy, navigation, and native animation checks. Log: `work/camera-tiles/tests.log`.
- Signed and installed **0.4.9 build 20**, certificate trust and running-process verification passed. Log: `work/camera-tiles/install.log`.
- Actual SwiftUI selector rendered at **412 × 138 points / 824 × 276 pixels**, inspected for visible artwork, equal tile sizing, labels, and selection. Preview: `outputs/Shutter-camera-selector.png`.
- Live Settings scrolled and visually inspected. All three camera images display in the compact panel, native selected state changed with each click, and clicking selected FinePix F11 again invoked its replay action. Final choice restored to FinePix F11; stored choice read back. Capture sound, Copy sound, 65% volume, collapse-after-copy, and capture permissions were retained.
- The shelf was empty before restart. Tile previews created no capture. Audio timbre was not assessed through the agent interface; playback wiring and native selection were checked.
- App/source archives checked; the extracted signed app includes all three distinct original camera PNGs and three shutter WAVs with matching hashes. No private capture backups or build/signing scratch data are in either archive.

The illustrations are stylized camera depictions. The app remains development-signed and not notarized.

---

# NotchShot 0.4.8 verification — 15 September 2026

## Collapse after copying

- Successful manual copies (hover ⌘C, Copy all, screenshot, text, or AX tree) show confirmation, wait 180 ms, and reuse the existing native spring to collapse. Shots remain saved. Reduce Motion continues to use the existing immediate geometry transition.
- **Collapse after copying** defaults on and persists. Copy sound can be muted independently. Automatic clipboard capture continues to respect **Open shelf after capture**.
- Repeated successful copies restart the delay. Opening another page, switching detail tabs or shots, closing/reopening, modifying history, or starting capture/import/drop/drag/shortcut recording cancels it. Missing content does not schedule a close; settings and active arrivals stay open.

## Verification

- **166 tests passed**, zero failures/skips. Twelve new tests cover all manual clipboard paths, exact hovered-shot data, persistence, mute independence, cancellation, automatic arrivals, rapid copies, and a hidden native panel animated back to compact centered bounds. Log: `work/copy-collapse/final-tests.log`.
- The first run exposed missing cancellation for an independently active landing state; that guard was added and the complete suite passed. Independent review also caught detail-tab navigation bypassing the delay cancellation, now handled in the tab action.
- Signed and installed **0.4.8 build 19** with certificate trust and running-process verification. Log: `work/copy-collapse/install.log`.
- Live Settings visually inspected at its existing compact size. **Collapse after copying** starts on; toggling off/on was observed and its saved value verified. FinePix F11, Copy sound, 65% volume, both Shift keys, and both Allowed permissions were retained. The app launched and was left collapsed.
- Existing shot BBDE4A92 was exported and its PNG/JSON validated in `outputs/Saved-before-update` before restart.
- The copy-to-native-animation path was verified using the actual hidden AppKit panel. The automation interface cannot hover, so physical hover ⌘C remains a separate user check.

The app remains development-signed and not notarized.

---

# NotchShot 0.4.7 verification — 15 September 2026

## Copy confirmation sound

- A short native macOS Tink chime plays after successful image, text, AX-tree, Copy all, hover ⌘C, and automatic clipboard writes. Missing/empty content stays silent; delayed shelf collection does not repeat an automatic copy or its sound.
- **Copy sound** defaults on and persists independently of Capture sound. The existing **Volume** controls both. No fourth shutter or downloaded asset is added; the app loads the system sound in place.

## Verification

- **154 tests passed**, zero failures/skips. Five new silent tests cover the real decodable 564 ms sound resource, restart/volume behavior, successful and unavailable copy paths, saved mute preferences, and automatic-copy deduplication. Log: `work/copy-sound/tests.log`.
- Signed and installed **0.4.7 build 18** with certificate trust and running-process checks. Log: `work/copy-sound/install.log`.
- Live app launched collapsed. Settings visually inspected: compact side-by-side Capture sound/Copy sound controls, Copy sound on, FinePix F11 retained, volume 65%, both capture permissions Allowed. Copy sound was toggled off and restored on through the actual UI.
- The three previous session shots F6966B76, 07C2F076, and 600DF2F5 were exported to `outputs/Saved-before-update`; their PNG and JSON files were validated before restart.
- Read-only second-agent review found no actionable issues. Physical hover/paste confirmation remains pending from the preceding release; no subjective hearing assessment is claimed through the automation interface.

The app remains development-signed and not notarized. All sound playback and clipboard operations are local.

---

# NotchShot 0.4.6 verification — 15 September 2026

## Quality-of-life controls

- Settings adds **Copy after capture** (off by default), **Open shelf after capture** (on), and **Volume** (65%). All choices persist. The Settings window keeps its existing size and scrolls to lower controls.
- Automatic copy uses the completed screenshot plus labeled accessibility text, OCR/imported text when present, and tree context. Partial screenshot callbacks do not copy. Collection does not overwrite the clipboard a second time.
- Turning off automatic shelf opening preserves a collapsed notch or a page the user has open, including rapid back-to-back captures. The card can fly into the compact notch; explicit Add to shelf and drops still open it.
- Hovering a saved thumbnail temporarily registers native **⌘C** for that exact shot. It does not select/open the shot or activate the app. Pointer exit, invalidation, removal, capture/import activity, hidden windows, and teardown release the registration. Conflicts preserve the existing shortcut and hide the copy hint.
- The passive hover preview shows **⌘C Copy shot** while the binding is available. Clipboard output uses standard PNG/TIFF and text representations, like Copy all; receiving apps choose a representation.

## Verification

- Full suite: **149 tests passed**, zero failures/skips. Includes six hover binding lifecycle/race tests, eight QOL clipboard/navigation/preferences tests, and three new playback volume tests. Log: `work/qol/tests.log`.
- After the final rapid-capture navigation fix, all **17 focused QOL/landing tests passed**. Log: `work/qol/final-flow-tests.log`.
- Signed and installed **0.4.6 build 17** with certificate trust and running-process checks. Log: `work/qol/final-install.log`.
- Live Settings and scrolling visually inspected. Auto-copy was off, automatic opening on, FinePix F11 selection retained, and both capture permissions Allowed. Native volume Increment changed 65% to 75%, stored preference read back as 0.75, and Decrement restored 65%.
- The previous session's ChatGPT shot 3F38C9C8 was exported and its PNG/JSON validated in `outputs/Saved-before-update`. The shelf was empty before the final restart.
- Physical hover-and-paste confirmation is pending user feedback. The available native automation interface has no hover action; programmatic tests verify exact-shot clipboard content and native registration ownership separately. No physical hover success is claimed yet.

The app remains development-signed and not notarized. Clipboard changes are local and automatic copying is opt-in.

---

# NotchShot 0.4.5 verification — 15 September 2026

## Selectable Fujifilm shutters

- Settings now offers **Fujifilm X-T3**, **Fujifilm X100S**, and **Fujifilm FinePix F11**, with Preview for the current choice. X-T3 is the default; selection is stored across launches.
- X100S (hmilleo, CC0) and FinePix F11 (Erdie, CC BY 4.0) were researched on their original Freesound pages and adapted into 520 ms / 590 ms feedback clips. Source links, credits, licenses, trim boundaries and hashes are in `docs/SHUTTER_SOUND.md` and bundled third-party notices.
- Each voice is loaded on selection and retained; switching stops the old sound, repeated playback restarts one voice, and a failed resource load keeps the existing playable voice. Automatic playback respects mute; explicit Preview works while muted.

## Checks

- **132 tests passed**, zero failures/skips. New checks cover resource selection, retained playback, preventing overlap, failed-load recovery, saved preferences and muted preview. All three WAVs decode to nonzero audio under one second. Log: `work/shutter-options/tests.log`.
- Signed and installed **0.4.5 build 15** with certificate trust and running-process verification. Log: `work/shutter-options/install.log`.
- All three app resource hashes match their source WAVs. Peak levels are -5 dBFS before the app's 0.65 playback volume; boundaries fade to zero. The sounds are distinct files, not renamed copies.
- Live Settings visually inspected at its existing compact size. Picker displayed all three models. X100S selected and Preview clicked; FinePix F11 was subsequently selected in the live app and its Preview clicked. The stored preference was read back as `fujifilm-finepix-f11`. Capture sound and both capture permissions remain enabled.
- No capture was made by Preview. Audible timbre was not assessed through the agent interface; source identity, waveform boundaries, decoded samples, playback calls, and visible selection were checked.
- All three session shots were exported and validated before restart: 746A165B, FAF4FFEE, 0C99DE2F in `outputs/Saved-before-update`.

The app remains development-signed and not notarized. All playback is local.

---

# NotchShot 0.4.4 verification — 15 September 2026

## Both Shift keys and individual removal

- Optional capture gesture is **left Shift + right Shift together**. It triggers once on the second physical press and rearms only after both are released. Repeated taps of one Shift do not capture.
- Settings says **Also use both Shift keys** and explains the chord. The menu has **Both Shift keys to capture**. Custom shortcuts remain available; old optional-gesture preferences migrate once.
- Every saved shelf thumbnail has a small top-right **×**. Removing the selected shot selects a neighbor; removing the last shot returns an open detail page to the shelf. Pending captures/imports stay valid. Exported files are untouched.

## Checks

- **128 tests passed**, zero failures/skips, including 17 physical-Shift state tests and 8 removal tests. Log: `work/both-shift-removal-tests.log`.
- Signed and installed **0.4.4 build 14**; signature, certificate trust, and running process verified. Log: `work/both-shift-removal-install.log`.
- Live Settings verified **Also use both Shift keys = 1**, correct explanatory text, and both capture permissions Allowed. The corrected build launched collapsed.
- Live removal observed: the app reported **Removed Cursor shot.** with zero saved shots. The final build retains this same removal implementation.
- Actual SwiftUI shelf rendered with two disposable local fixtures: **412 × 64 pt** content, clear × controls inside thumbnail corners, no label/header/neighbor overlap. Render: `work/shot-controls-qa/shelf-controls.png`.
- Before the first restart, capture CB90E255 was exported to `outputs/Saved-before-update` and its JSON/PNG validated. The shelf was observed empty before both restarts.
- Brian confirmed the physical left Shift + right Shift chord captures successfully. The running final build was then inspected with one ChatGPT shot, **931 accessibility elements**, and its **Remove ChatGPT shot from shelf** control. Screenshot and shelf appearance were visually checked. The user capture was retained.

The app remains development-signed and not notarized.

---

# NotchShot 0.4.3 verification — 15 September 2026

## Shutter sound

- Replaced macOS Tink with a 340 ms trim of a CC0 recording identified by its uploader as a Fujifilm X-T3. Source, editing details, and hashes: `docs/SHUTTER_SOUND.md`.
- Added a Settings Preview button. The capture-sound preference controls automatic playback; explicit audition does not alter that preference or create a capture.
- Retains a preloaded sound at volume 0.65; repeated playback stops and rewinds the same voice. Existing first-preview sound timing and partial/final deduplication remain in place.
- Direct `.app/Contents/Resources/CaptureShutter.wav` resource supports portable installs; SwiftPM also packages it for development and tests.

## Checks

- **114 tests passed**, zero failures/skips. Includes 3 silent sound tests: decoded nonzero audio with headroom, repeat playback, and preview while muted without changing preference/shelf state. Log: `work/shutter-audio/full-tests.log`.
- Signed and installed **0.4.3 build 12** with certificate validation and running-process confirmation. Log: `work/shutter-audio/install.log`.
- Asset: 48 kHz, mono, 16-bit PCM; 0.340 s; peak -5.00 dBFS; first/last samples zero. Processing evidence: `work/shutter-audio/processing.json`.
- Live Settings visually inspected; Fujifilm X-T3 label and Preview button are present. Preview was clicked in the running signed app; toggle remains enabled and no capture was created. Audible timbre was not assessable through the agent's audio input interface.
- Both capture permissions remain Allowed. Shelf was empty before restart, so no session captures were lost.

The app remains development-signed and not notarized. The sound plays locally without network access.

---

# NotchShot 0.4.2 verification — 15 September 2026

- Installed development-signed **0.4.2 build 11**; signature, certificate trust, and running process verified by `script/build_and_run.sh --verify`.
- Collapsed width reduced from 277 to **225 points** on this Mac, preserving 32-point height and hardware-notch anchoring. The native window bounds shrink along with the indicators.
- **111 tests passed**. After adding the final settled-width assertion, all **9 native/motion tests** passed again. Logs: `work/tight-notch-tests.log` and `work/tight-notch-native-tests.log`.
- Visually inspected before/after collapsed views in the installed app. Clicked the smaller camera tab by screen coordinate: shelf opened successfully. Collapsed it again and checked the final appearance.
- Live WindowServer bounds: shelf **440 × 180**, collapsed **225 × 32**, both anchored at the top. Evidence: `work/tight-notch-qa/expanded-geometry.txt` and `collapsed-geometry.txt`.
- Exported and validated all four session shots before restart: E2166F02, 5542B69C, A560F626, 28AF07DD in `outputs/Saved-before-update`.
- Brian reported the preceding hover-preview update looks good; no hover behavior was changed in this update.

Physical multi-display checks were not repeated. The app remains a local development-signed build without notarization.

---

# NotchShot 0.4.1 verification — 15 September 2026

## Implemented

- Saved shelf thumbnails gain a mint hover highlight and a larger preview after a 220 ms dwell.
- The 320 × 264-point preview includes app/window identity, capture time, screenshot, and context summary. Text-only shots show a bounded excerpt.
- Preview window is passive: no keyboard focus, no pointer interception, and no change to selection or the 440 × 180 shelf.
- Exit, navigation, collapse, new capture/import/drop, removal, and native geometry changes dismiss or cancel the preview. Reduced Motion skips its entrance fade.

## Checks

- `swift test --disable-sandbox --cache-path work/swift-cache`: **111 tests passed**, zero failures or skips. Evidence: `work/hover-tests.log`.
- `./script/build_and_run.sh --verify`: signed, certificate trust checked, installed version **0.4.1 build 10**, and running process confirmed. Evidence: `work/hover-install.log`.
- Native window tests confirm preview cannot become key/main or intercept clicks; geometry tests cover shelf separation and offset-display boundaries.
- Rendered and visually inspected the actual screenshot and text-only SwiftUI preview views at their target size. Local fixture renders: `work/hover-qa/preview-0.png` and `preview-1.png` (excluded from distributable archives).
- Running installed app verified with a compact 440 × 180 shelf. Automatic live pointer-hover confirmation remains unverified: the available native UI interface has no hover action, and its capture-shortcut/drag simulation did not produce a sample shot. User hover feedback was requested.
- All five pre-update shots were exported and their JSON/PNG files validated in `outputs/Saved-before-update` before restart.

The app remains a local development-signed build, without notarization. Physical multi-display and Reduce Motion system-setting changes were not repeated in this update.

---

# Version 0.4.0 verification — 2026-09-15 SGT

## Collapsed launch and compact shelf

- NotchShot now **starts collapsed**. Opening it shows the **440 × 180-point shot shelf**, with Settings and collapse controls. The large top Capture button is removed; capture remains available through the chosen hotkey and menu bar.
- A new Appshot/NotchShot opens and **stays on the shelf**, matching Brian's explicit preference. Capturing while the notch is open no longer forces a close/reopen cycle. The screenshot-card flight still lands at the shelf's measured thumbnail.
- Screenshot/Text/AX tree details open only after selecting a thumbnail. **Back** returns to the shelf. Settings is **440 × 440**, detail is **440 × 480**, and both resize through the existing anchored motion. Settings retains the custom shortcut recorder, double-Command option, capture sound, and permission controls.
- Explicit navigation during the preview delay, ongoing AX read, or flight overrides delayed arrival. A completed capture is saved without changing the chosen page or reopening a collapsed notch. Actionable status messages remain visible on shelf and settings.

## Verification

- **108 tests passed, zero failures, no skipped tests.** New coverage includes collapsed startup, shelf-only collection/import/drop navigation, explicit detail selection, delayed capture/navigation races, page size interpolation/reversal, and hidden native startup/page-resize behavior. Existing capture, copy/export, shortcut, geometry, and motion tests pass.
- Canonical build/sign/install completed for **0.4.0 build 9**. Strict signature and positive OCSP certificate checks passed with the existing identity. Confirmed the installed process at the stable output path; both capture permissions remain Allowed.
- Live startup showed only the collapsed tab. Opening showed the compact shelf with no Capture button. Settings, its shortcut recorder, both Allowed permissions, and its Back control were inspected. Live Finder and Brave captures were observed on the shelf without automatic detail navigation. Selecting the saved Finder shot opened its readable-text detail; Back returned to the compact shelf. The app was left collapsed.
- Geometry-only observations confirmed the four native sizes: **277 × 32** collapsed, **440 × 180** shelf, **440 × 440** settings, and **440 × 480** detail. The screen-top edge remained anchored and the center stayed pixel-aligned to the hardware notch. Exact counts are recorded in `work/shelf-first-qa/summary.json`.
- Before the update, the latest user capture was exported to `outputs/Saved-before-update/NotchShot-2026-09-15T08-44-35Z-28C49B56`. Its six files, both JSON documents, and PNG signature were validated. Previous exports remain intact and are excluded from downloadable archives.

Evidence: `work/shelf-first-tests.log`, `work/shelf-first-install.log`, live native UI observations, and geometry-only `work/shelf-first-qa`. Automated key delivery was inconsistent during simultaneous user interaction, so the live capture statement describes observed arrivals, not an independently isolated keyboard-event test. Physical multi-display changes and external Appshot drags were not repeated. Captures normally use the existing eight-shot/64 MiB image retention policy; a quiet arrival can temporarily retain the currently viewed shot alongside an oversized new shot until the next normal collection. The app remains a personal development-signed build, not notarized.

# Earlier 0.3.1 verification — 2026-09-15 SGT

## Appshot modal and shelf flight

- Compared the supplied 5.334-second recording and extracted transition frames. The reference shows a window flash and screenshot shrinking into a composer attachment; this update adapts it to the requested floating preview and top shelf.
- The captured window now flashes briefly and peels into a centered **268 × 218** floating preview. The notch opens a measured receiving slot before the card travels and shrinks into its **70 × 36** thumbnail. The card remains opaque throughout flight, with a short raster-to-thumbnail overlap at arrival.
- **89 tests passed, zero failures and no skipped tests.** Coverage includes source-window geometry on offset displays, actual hidden native window movement and raster snapshots, size interpolation, same-ID context updates, exact measured landing, cancellation/replacement, collapse without reopening, stale callbacks, and Reduce Motion including a mid-flight change.
- Built and installed **0.3.1, build 8**, using the existing signing identity. Strict signature and positive certificate OCSP checks passed. Confirmed the running process from the stable output app. Accessibility and Screen Recording remain Allowed.
- Two live Finder captures showed the floating screenshot modal and automatic shelf collection. Each retained **150 accessibility elements**. The finished compact screenshot preview and selected shelf thumbnail were inspected visually.
- Geometry-only logs on the live build show the actual source window **920 × 436** becoming the **268 × 218** preview, then a **70 × 36** thumbnail at AppKit **X560, Y807**. The first flight recorded **37 native frames**, **35 distinct sizes**, and stayed at alpha 1 through arrival. Its sampled flight duration was approximately **528 ms**.
- Preserved both existing ChatGPT captures before updating, in `outputs/Saved-before-update/NotchShot-2026-09-15T08-19-35Z-9F508E16` and `NotchShot-2026-09-15T08-17-23Z-223010B2`. Each export's six files, both JSON documents, and PNG signature were checked. Captures are excluded from the app/source ZIPs.

Evidence: `work/card-flight-tests.log`, `work/card-flight-install.log`, and geometry-only `work/card-flight-qa`. Animation timing is an adaptation of the video, not a claim of exact pixel-for-pixel reproduction. Live multi-display switching, audible sound delivery, and external Appshot dragging were not repeated; geometry, drag lifecycle, and import paths have automated coverage. The app remains a personal development-signed build, not notarized.

# Earlier 0.3.0 verification — 2026-09-15 SGT

## Configurable capture shortcuts

- Added a native click-to-record shortcut control in the notch settings, plus a menu-bar entry. Saved combinations reload across launches. Reset restores Command–Shift–2. Double Command is opt-in and off by default; explicit existing preferences are preserved.
- Recording suspends both global capture mechanisms. Bare or Shift-only keys are rejected; Escape, Tab, focus loss, leaving settings, and collapse end recording. Failed registrations preserve the previous saved shortcut and show the system result.
- **68 tests passed, zero failures, no skipped tests.** This includes 18 new model, native Carbon registration, recorder lifecycle, and store tests. Real exclusive registration collisions and release/recovery were exercised. The native motion test now waits for a visible native frame change, avoiding a subpixel first-tick rounding race; motion behavior is unchanged.
- The canonical script built, signed, strictly verified, checked the certificate with positive OCSP, installed, and launched **0.3.0 build 7** from the stable output bundle. Both Accessibility and Screen Recording stayed **Allowed**.
- Live settings inspection confirmed the recorder fits the existing **440 × 480** notch panel, the settings scroll, and double Command is unchecked. A bare N stayed in recording with an inline error; Escape restored capture availability without collapsing the notch.
- Recorded **Control–Option–N** through the native UI, confirmed the label updated, relaunched, and confirmed the same saved combination. A live key event then produced a ChatGPT screenshot/text/tree capture with **830 accessibility elements** and automatic shelf collection. Reset visibly restored Command–Shift–2. Collapsing during recording ended recording and restored the enabled capture control.
- Automated Command–Shift–2 event delivery was inconsistent after reset; native registration/reset checks passed, and a second capture was observed while that shortcut was active. The independently attributable live custom-hotkey result above uses Control–Option–N. OS registration conflicts are detected; app-local shortcut conflicts cannot all be enumerated.
- Before installing, the user's latest ChatGPT shot was exported to `outputs/Saved-before-update/NotchShot-2026-09-15T08-02-19Z-84B3E43F`. All six files, both JSON documents, and the PNG signature were checked. Existing exports remain intact and are excluded from both archives.

Evidence: `work/custom-shortcut-tests.log`, `work/custom-shortcut-install.log`, and live native UI observations. The app remains development-signed, not notarized. Existing motion, shelf, text/tree, import, and export tests passed; external Appshot drag and audio playback were not newly tested for this shortcut change.

# Earlier 0.2.3 verification — 2026-09-15 SGT

Applied [Emil Kowalski's Apple Design and Review Animations guidance](MOTION.md), adapted to SwiftUI/AppKit. The notch targets a 250 ms settle, visible controls respond while opening, and same-capture text updates preserve the card's entrance. The card now uses display-timed motion and disables AppKit's separate show animation.

## Verified

- **50 tests passed; zero failures or skipped tests.** New hidden native tests exercised same-ID entrance/landing continuity, display-tick intermediate frames, completion exactly once, dismissal, and replacement cancellation. The native notch observation, rapid-reversal, reduced-motion, and compact tree regressions also passed.
- Canonical staging, signing, strict verification, and positive certificate OCSP checks passed for **0.2.3, build 6**. The installed process runs from `outputs/NotchShot.app`. Existing permissions remained Allowed.
- Live Finder capture showed the thumbnail card, then automatically added it to the shelf. The compact preview showed **144 accessibility elements**. The shelf and footer remained visible.
- The final build measured **250.1–255.7 ms** for ordinary opening/collapse, including display cadence. External read-only sampling recorded **5,332 native notch frames** and **22 distinct intermediate sizes**. Dimensions stayed within **277–440 × 32–480**, the top stayed at **Y0**, and center error stayed at or below **0.5 logical point**.
- A rapid double-click safely coalesced to the latest expanded state. Reversal continuity is additionally covered by the motion-model tests and the earlier live motion pass. The app was left collapsed at **X617, Y0, 277 × 32**.
- The user's new capture was exported before the update into `outputs/Saved-before-update/NotchShot-2026-09-15T07-20-44Z-C6626744`. All six files were checked, including both JSON documents and the PNG signature. Previous exports remain intact. Private capture files are excluded from app/source archives.

Local evidence: `work/emil-motion-tests.log`, `work/emil-motion-install.log`, and geometry-only `work/emil-motion-qa`. Reduced Motion was tested by policy; the user's setting was not changed. Physical multi-display transitions, external Appshot drags, and audio delivery were not newly tested in this refinement.

# Earlier 0.2.2 verification — 2026-09-15 SGT

## Result

The installed dropdown is **440 × 480 logical points**, down from 560 × 680: **45% less area**. The shelf is 64 points tall. Capture warnings open from a small count button, leaving room for the screenshot, readable text, AX tree, and copy/export controls.

Opening and closing use one critically damped, display-timed transition. The native panel and SwiftUI reveal share the same presentation size. The expanded content keeps a fixed layout while it is clipped/revealed, preventing native text views from reflowing during animation. AppKit's separate show-window zoom is disabled. Rapid toggles preserve current motion or coalesce to the latest requested state. macOS Reduce Motion skips the movement.

## Checks on the final build

- **48 tests passed, zero failures, no skipped tests.** The suite includes a hidden native-panel integration test that changes the store, observes intermediate native/presentation dimensions, waits for collapse, and reopens to verify observation is re-armed. Seven motion tests cover intermediate frames, reversal continuity, rapid changes, display cadence, delayed frames, Reduce Motion, and notch anchoring.
- The large-tree regression retains a 131 KB data URL and 750 AX rows inside the new compact **412 × 110** native text viewport, with complete text, both scroll directions, selection, and a visible first glyph.
- The canonical build script signed and installed **0.2.2, build 5**. Strict signature and positive OCSP certificate checks passed. The same valid development identity was reused, and both Accessibility and Screen Recording remained **Allowed**. Shell syntax passed.
- Live capture of the task-owned Finder window showed the small screenshot card and its **Moving to shelf…** state, followed by automatic collection into the shelf. Screenshot, Text, and AX tree tabs were each visually checked at the compact size; the footer remained visible without overlap.
- Copy tree reported success. Capture notes opened in their popover and disappeared when the parent notch collapsed. Reopening retained the selected capture and preview state.
- Export through the native chooser restored the compact notch. All six exported files were checked: **2,498 × 872 PNG**, **988 readable characters**, and **142 AX nodes**, matching the UI. Both JSON files parsed. Evidence is in `work/live-qa/NotchShot-2026-09-15T07-09-41Z-7638C993` and is excluded from archives.

## Live motion evidence

- Read-only external `CGWindowListCopyWindowInfo` sampling of the final build recorded **3,243 native notch frames**, including **23 distinct intermediate sizes** during capture-triggered collapse and shelf-triggered opening. Width stayed within **277–440**, height within **32–480**; the top edge stayed at **Y0** throughout.
- The center stayed within **0.5 logical point** of the hardware notch's **755.5** center. AppKit rounds window edges to pixel-aligned native coordinates. Settled bounds were **X617, Y0, 277 × 32** closed and **X535, Y0, 440 × 480** open.
- Geometry-only display-tick logs on the final build measured ordinary opening/collapse in **0.322–0.351 seconds**. An earlier live pass of the same controller implementation also recorded a reversal **41 ms** after collapse began, preserving nonzero velocity and returning to the expanded endpoint. Rapid double clicks on the final build safely coalesced to the latest expanded state.
- Sampling code, raw geometry, and summary live under `work/motion-qa`. These contain window geometry only. A live check initially exposed a construction-time SwiftUI observer that retained the initial Boolean. Direct, re-armed store observation and the hidden native integration regression fixed that failure.
- The two previous in-memory Finder captures were exported before updates and retained under `work/live-qa`. User captures previously preserved in `outputs/Saved-before-update` remain intact.

## Limits

Reduce Motion behavior was verified through the motion policy test; the user's system setting was not changed. Physical multi-display switching was not exercised; anchoring has geometry regression coverage. The existing external Appshot drag and physical double-Command/audio limitations from the earlier verification remain unchanged. This is a personal development-signed app, not a notarized distribution build.

# Earlier 0.2.1 verification — 2026-09-15 SGT

## Build, signing, and checks

- `./script/build_and_run.sh --verify` passed: version 0.2.1 build 4 was signed, its certificate passed positive OCSP verification, and the running process was confirmed at `outputs/NotchShot.app`.
- The user's interactive login-keychain unlock restored signing. The existing valid 14 June Apple Development identity is now cached for updates. No new certificate was created, and no private key was exported or ACL/trust settings changed.
- The earlier 13 June signing certificate is revoked. The retired 0.1.1 archive remains under `work/retired-artifacts` and is excluded from deliverables.
- Full suite: **40 tests, zero failures**. Coverage includes double-Command cancellation, shelf lifecycle/races, image/text import pairing, temporary-file preservation, export, and notch geometry.
- The native tree-view regression hosts a 131 KB data URL plus 750 AX lines in a bounded viewport. It verifies complete retained text, read-only selection, both scroll directions, stable host dimensions, top-left position, and visible first text.
- The install script stages and verifies before stopping/replacing the app. Development certificate checks require positive OCSP status; explicitly annotated certificate errors are excluded from automatic selection. Shell syntax passed after the final script changes.

## Live verification

- Accessibility and Screen Recording both remained **Allowed** after the final signed update.
- Capturing the task-owned Finder `live-qa` window showed the small **NotchShot capture preview** card with its thumbnail and **Moving to shelf…** state. It then disappeared automatically and the shelf count increased from zero to one.
- The final screenshot preview was visually inspected: **1,840 × 872 PNG**. The expanded panel is now 560 × 680, giving the preview adequate space while keeping the notes and copy/export controls separate.
- The native accessibility tree was visibly populated and scrollable. Searching for `Notchi` displayed the expected image row; clearing search restored the full tree at the top.
- A final Finder capture export produced screenshot.png, accessibility.txt, accessibility-tree.txt, accessibility-tree.json, context.md, and metadata.json. The PNG header verified the dimensions; both JSON files parsed; recursive tree count was **138 nodes**, matching the UI; readable text was **643 characters**.
- Earlier 0.2 ChatGPT captures contained 729 AX elements and readable text. Their oversized SwiftUI tree exposed the blank-rendering issue fixed by the native text viewport.
- Final collapsed panel bounds were **X617, Y0, width277, height32** on the 1512 × 982 display. Its center, 755.5, matches the hardware notch center derived from the left/right safe areas.
- The user's two current ChatGPT shots were exported before the final relaunch into `outputs/Saved-before-update`; all six files for each were checked. The earlier preserved capture is also there. Capture files are excluded from app/source archives.

## Limits of these checks

- Automatic card appearance and shelf collection were verified live. Physical double-Command delivery and audible playback were not independently confirmed; the user's manual feedback was requested. The gesture recognizer has 12 passing tests.
- A native drag attempt through the UI automation tool did not establish successful cross-window delivery. External Appshot/image drop interoperability remains a manual check; the import service has nine passing tests. Images cannot supply a missing live AX tree.
- Tests and available permissions do not guarantee every app exposes complete accessibility content. Finder reported skipped elements where protected-content state could not be read; those notes are retained in the capture.
- This is a personal, locally development-signed app, not a notarized distribution build. Other Macs and display arrangements were not physically tested.

# Earlier 0.1.1 verification

Historical checks below preceded discovery that this build's signing certificate was revoked. That archive is no longer offered as the runnable app.


Checked on macOS 26.5.2 / Apple Silicon using Swift 6.3.3, 2026-09-15 SGT. Deployment minimum is macOS 15.

## Build and automated checks

- `./script/build_and_run.sh --verify`: build passed, signature validated, app launched, running process confirmed from the expected outputs bundle.
- `swift test --disable-sandbox --cache-path "$PWD/work/swift-cache"` with project-local module caches: 12 tests passed, zero failures.
- Window selection tests cover duplicate titles, geometry matching, absent AX, and refusing an unrelated window.
- Export tests cover separate export folders, preservation of previous files, JSON hierarchy, and partial captures without screenshot data.
- Tree tests cover indentation, editable metadata, protected-node formatting and exclusion of protected subtrees from readable text.
- Geometry tests cover physical notch safe areas, external display origins, and an actual NSPanel receiving late content resizes, frame changes, and origin changes.

## Live checks

- Both permissions remained Allowed after rebuilding and relaunching the final app with the export-focus fix.
- Both Accessibility and Screen Recording report Allowed inside NotchShot after replacing the stale ad-hoc entries with the current Apple Development-signed app. Toggling the old Screen Recording entry alone did not repair its identity.
- Captured the Notchi GitHub page in Brave using the notch Capture button: 3,024 × 1,896 PNG and 807 accessibility elements. The actual PNG was visually inspected and shows the intended browser window.
- AX tree preview is populated, preserves hierarchy and roles, and shows the page URL. Its warning summary and copy/export footer were visually inspected without overlap.
- Copy tree reported success in the app. Clipboard interoperability with receiving apps was not separately tested.
- Export through the native folder chooser produced screenshot.png, accessibility.txt, accessibility-tree.txt, accessibility-tree.json, context.md, and metadata.json. JSON was parsed and recursively counted: 807 nodes including AXWebArea and links. Readable text includes offscreen README sections (How it works and Community Ports). OCR was unnecessary for this capture.
- Local test evidence is in work/verification-captures and is excluded from distributable archives.
- Collapsed panel bounds were measured from the running app: X617, Y0, width277, height32 on a 1512 × 982 screen. Center755.5 matches the physical notch center derived from the left/right safe areas. Expanded bounds are centered on the same anchor.
- The final export-focus change passed build/tests and source review. Its second live chooser check was interrupted by a UI automation service timeout; the successful export above preceded that change.
- A synthetic shortcut sent through the UI automation tool did not trigger a capture; actual global keyboard delivery remains unverified. Registration succeeds and Capture button flow works.

## Fixes and limitations

The window now restores its notch center/top anchor after native resizing, including delayed hosting-view changes. Capture notes have a bounded summary with a Details popover. Permission setup distinguishes stale captures from currently missing permission and provides a reopen action. Export hides the notch while the native chooser is active and restores it when the chooser completes or is cancelled.

The build reuses an existing Apple Development identity so later builds have a stable designated requirement. This personal build is not notarized. Other macOS versions, apps with limited accessibility support, and other hardware/display arrangements have not been physically tested. Permissions and a successful build do not imply every app exposes a complete tree.
