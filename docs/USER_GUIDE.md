# NotchShot

A local macOS notch utility for capturing the active app's screenshot, readable accessibility text, and accessibility tree. Inspired by Appshots, with the notch panel adapted from [Notchi](https://github.com/sk-ruban/notchi).

## Run

Requires macOS 15 or newer and Xcode Command Line Tools / Swift 6 to build.

```sh
./script/build_and_run.sh --verify
```

The runnable bundle is `outputs/NotchShot.app`. The Codex Run action uses the same script. This is a deliberate menu bar utility with no Dock icon. By default, the panel uses the built-in screen when available, otherwise the main display. Settings can make it follow your pointer to another display, where it becomes a top-center island if there is no hardware notch.

## Use

1. Launch the app and use its Enable buttons to grant **Accessibility** and **Screen & System Audio Recording** in macOS System Settings. Screen recording is used for still images; the app records no audio.
2. Focus any app window, then press **left Shift + right Shift together (⇧ + ⇧)**, or choose Capture app from the menu bar. The default gesture is enabled automatically. To configure an alternative, open notch settings (sliders icon) and use **Alternative shortcut**. The captured window gives a brief flash, then its screenshot shrinks into a floating preview over the app. The notch opens a receiving slot and the card flies into that slot once its text and tree are ready, leaving the shelf open. An already open shelf stays open during capture. Your selected Fujifilm shutter accompanies it when Capture sound is enabled.
3. Drag an Appshot, local image, or text onto the notch to add it to the shelf. Hovering over the collapsed notch opens the drop area. Hover a saved thumbnail for a larger screenshot and app/window details without changing your selection. While hovering, press **⌘C** to copy that exact shot using your **Copy content** preference (screenshot + AX tree by default). Move away to return ⌘C to the active app. Click it to inspect **Screenshot**, **Text**, or **AX tree**. Copy each separately, or use **Copy shot** with your preferred content. Rich-text editors can paste the screenshot followed by context in one document. Enable **Paste image, then text** for chat composers that choose only one clipboard format.
4. **Export** creates a new folder containing `screenshot.png` when available, `context.md`, `accessibility.txt`, `accessibility-tree.txt`, `accessibility-tree.json`, `metadata.json`, `ocr.txt` when available, and `imported-text.txt` when text accompanies a drop.
5. Press Escape to collapse the notch; click it to reopen. While shots are on the shelf, the right side of the notch shows how many. To clear them all, open the shelf and click the **trash** button in its header, beside Settings. It removes pending shots too and keeps copied content available to paste, and it appears only while there are shots. The menu bar provides capture, permission settings, and Quit.

NotchShot **starts collapsed**. The collapsed window fits the hardware notch plus 36 points for small side indicators (225 × 32 on this Mac), leaving more space for menu bar items. Click it to open the compact **440 × 180-point shot shelf**. By default, new captures open this shelf; they do not open the detail view. The shelf stays open while you use it and gently collapses after three seconds away. Select a thumbnail to inspect screenshot, text, and AX tree in a **440 × 480-point** detail page, or open **Settings** at **440 × 440**. Back returns to the shelf. All size changes use the short, interruptible animation and respect macOS **Reduce Motion**. Capture notes remain available beside the capture title in details.

## Colors and appearance

Open **Settings → Appearance** and choose **Mint**, **Sky**, **Lavender**, **Rose**, **Peach**, or **Gold**. The labeled color swatches preview each option; a checkmark shows the selected theme. Changes apply immediately to the aperture, shelf selection, buttons, scrollbar, and floating previews, and the choice is remembered after restarting. Mint is the default. The dark notch background stays consistent with the hardware notch.

## Following your active screen

Enable **Settings → Display → Follow active screen** to move the notch to the display containing your pointer. The pointer must settle there for about half a second, so briefly crossing another screen does not move the notch. This setting is off by default and is remembered after restarting; turning it off returns the notch to the built-in or main display once you finish interacting with it.

Moving preserves the shelf, selection, and current page. The notch stays put while you capture, drag, use its keyboard controls, hold a mouse button, open a menu/popover, or choose an export folder. Capture cards land on the notch's current display. Disconnecting that display moves the notch to an available one. Movement uses a brief fade and respects **Reduce Motion**. No additional macOS permission is required.

## Aperture

A six-blade aperture in your selected theme color sits in the left notch lane. It closes like a shutter when a capture begins, stays half-closed while the screenshot's text and tree are read, and reopens as the shot joins the shelf. Hovering turns the blades slightly.

The aperture stays inside the existing 16-point collapsed lane and grows with the open strip. Motion is brief and driven by existing capture state, with no idle animation loop; Reduce Motion switches states immediately. The right lane shows how many shots are on the shelf, a spinner while capturing, or the permission indicator when the shelf is empty. The notch dimensions stay the same.

## Copy several shots

Choose **Select** in the shot shelf, then click thumbnails to toggle them. **⌘-click** also starts selection; **⇧-click** extends a range. **All** selects the current shelf, and **Done** returns to opening individual shots. Numbered mint badges show the copy order, matching the shelf from left to right. New arrivals do not join an existing selection automatically.

Use **Copy N shots**, or hover a thumbnail and press **⌘C**, to copy the selection. When the shelf owns keyboard focus, **⌘A** selects all shots and **⌘C** copies them. In selection mode, hovering an unselected thumbnail still copies the chosen batch; with no shots selected it does not take over Copy. Collapsing preserves your selection and shots.

**Review context** shows the exact prepared text, screenshot count, and any unavailable screenshots. **Compact** is the default for batches: it preserves an indented excerpt of each accessibility tree and explicitly marks shortened trees. Repeated nodes are kept because they may represent different controls. It uses at most **32,000 characters total / 6,000 per shot**, shared fairly across the selection. **Full** includes each shot's complete accessibility hierarchy. Change this in the review or **Settings → Multi-shot context**. Originals and exports are unchanged. Large context and image validation are prepared in the background; copying waits until the reviewed snapshot is ready.

A normal paste offers one rich document with all valid screenshots in shelf order, followed by one numbered context block. For chat composers, select **Screenshot + AX tree** and enable **Paste image, then text**: the next **⌘V** pastes each screenshot separately, then the combined context. Allow roughly 0.6 seconds per screenshot before typing. The sequence stops if you switch app/window/field, type/click, copy something else, or start another paste; it never submits a message. Image-only and plain-text destinations choose which formats they support, and each app sets its own attachment and text limits. Text-only batches use ordinary paste.

## Capture preferences

**Collapse when away** defaults on with a **3-second** delay. Settings lets you turn it off or choose **2, 3, 5, or 10 seconds**. Moving back into the notch cancels the countdown; leaving again starts the full delay. The notch stays open while you use the keyboard, select text, read a popover, track a menu, drag, record a shortcut, capture/import, or choose an export folder. New shots and navigation restart the delay. Closing retains every shot and uses the existing smooth animation with Reduce Motion support. Attention monitoring sleeps when neither auto-collapse nor display following needs it, and while the notch is hidden or the displays are asleep.

Settings → **Capture & copy → Copy content** offers **Screenshot + AX tree** (Both, the default), **Image only**, and **AX tree only**. This choice is saved and applies to hover **⌘C**, **Copy shot**, multi-shot selection, and automatic copy. Explicit **Copy image**, **Copy text**, and **Copy tree** buttons keep their named behavior. Image-only copy never includes accessibility text; AX-tree-only copy never includes image data. A shot with no usable image cannot replace the clipboard in Image only mode.

Settings provides **Copy after capture** (off by default), **Open shelf after capture** (on by default), **Copy sound** (on by default), **Collapse after copying** (on by default), and **Volume** (65% by default). Automatic copy uses your selected Copy content as soon as capture finishes; later collection does not overwrite the clipboard a second time. With automatic shelf opening off, the card flies into the collapsed notch and the shot stays saved. An already-open shelf or page stays open. Explicit drops and Add to shelf still open it.

After a successful manual copy (hover **⌘C** or any Copy button), the notch waits briefly for confirmation, then smoothly collapses. **Collapse after copying** starts on; turn it off to keep the shelf or detail page open. Opening another page or shot, capturing, importing, or starting a drop cancels a pending collapse. Automatic copying still follows **Open shelf after capture**.

A short macOS chime confirms successful copies, including automatic copying, image, text, and tree. **Copy sound** controls this independently of the capture shutter; **Volume** controls both. Missing or empty content stays silent.

Thumbnail hover responds across the full visible tile, including its edges, and shows its preview after 120 ms. Tracking stays inside each thumbnail, recovers after layout or capture transitions, and leaves clipped or covered tiles inactive.

Outside selection mode, hover **⌘C** copies the hovered shot without activating the notch or opening details. In selection mode it copies the chosen batch. The shortcut exists only over a valid saved thumbnail; navigation, removal, capture activity, or pointer exit releases it. If another global shortcut owns ⌘C, the hover hint is hidden and that shortcut is preserved. With **Paste image, then text** enabled, the next ⌘V pastes the image or images, followed by their context.

Your alternative keyboard shortcut is saved across launches. Include Command, Option, or Control with a key; Escape or Tab cancels recording. **Reset** restores the alternative to ⌘⇧2. If macOS reports a registration conflict, the previous shortcut is retained. Some app-local shortcuts cannot be detected in advance.

**Shift + Shift** is the default capture gesture. Press **left Shift + right Shift together**; use **Shift + Shift to capture** in Settings to turn it off. It captures once; release both before trying again. Typing, other modifiers, and mouse actions cancel the gesture. This replaces the old double Command option; upgrading preserves explicit enabled/disabled choices. The shelf shows **⇧ + ⇧ to capture** while its monitor is available; otherwise it shows the configured alternative. The menu bar also has a **Capture sound** toggle. Settings offers three illustrated camera tiles for **Fujifilm X-T3**, **Fujifilm X100S**, and **Fujifilm FinePix F11**. Click a camera to select and preview its shutter; click the selected tile to replay. Mint selection and a gentle hover lift make the choice visible. Keyboard and accessibility controls remain native, and hover/press movement respects Reduce Motion. Selection is saved across launches, with X-T3 as the default. The recordings, licenses, credits, and processing are documented in [shutter sound notes](SHUTTER_SOUND.md).

Click the **×** at the top right of a shelf thumbnail to remove that shot. Captures stay in memory until explicitly exported or copied. The session keeps at most eight captures, also trimming older images when their combined PNG size exceeds 64 MB. Quit or Clear session captures removes the in-app history. Removing shots does not delete exported files or copied clipboard data. If a capture finishes while you are viewing another shot, both are preserved; this can temporarily exceed the image budget until the next normal collection. There is no server, account, background screenshot loop, or AI dependency. The only network access is the optional update check described below; captures never leave your Mac.

## Updates

Release builds keep themselves current from [GitHub Releases](https://github.com/bchewy/notchshot/releases). Open **Settings → Updates** to choose a channel:

- **Stable** follows tagged releases (`v1.2.3`). This is the default for stable downloads.
- **Nightly** follows the newest daily build of `main` (`nightly-<build>`), and also takes a stable release when it is newer. This is the default for nightly downloads.

**Install updates automatically** is on by default. NotchShot checks GitHub shortly after launch and then about every six hours. A newer build downloads in the background and must pass every check before it can run: its checksum must match the release manifest, its version and build must match that release, and its code signature must satisfy the same designated requirement as the running app, with certificate revocation checked. Because Accessibility and Screen Recording access are tied to that same signature, permissions carry over. Anything that fails is discarded.

A verified update installs only when nothing would be lost: the shelf is empty, the notch is closed, and no capture, copy, or paste is in progress. NotchShot then swaps in the new app and reopens within a second. Otherwise the update waits and installs when you quit. **Restart to update** installs it immediately, and clears the shelf like any restart. Updates never install an older build, so switching from Nightly to Stable keeps your nightly until a newer stable release is published.

Turn automatic updates off to stop all background network access. **Check now**, or **Check for updates…** in the menu bar, still checks on request, and **Restart to update** installs what it finds. Checks send an ordinary anonymous HTTPS request with the app version; no captures, settings, or identifiers are sent.

Local builds from `script/build_and_run.sh` never update themselves. NotchShot also can't update when it runs from a quarantined download location (move it to Applications first) or from a folder you can't write to; Settings explains which applies.

## Action feedback

A small header badge briefly confirms copy, export, and other actions, then returns to **ON DEVICE**. Click it for full details and **Show in Finder** on exports. Success lasts 3 seconds, informational notices 5 seconds, and errors 8 seconds. Reading a detail popover keeps it open; changing pages does not revive an expired notice. The bottom of Settings and shot details is free of persistent status messages.

## Text and tree behavior

A NotchShot card retains its complete screenshot, text, and tree when moved into the shelf. External drops preserve the image and plain text actually supplied by the source; a PNG/JPEG alone cannot carry a live accessibility tree. Supported local images are PNG, JPEG, TIFF, HEIC, and HEIF, with a 32 MiB combined input limit and 40 megapixel limit. For multi-item drops, the first supported image item is imported together with that same item's context.

The tree records nested roles, titles/descriptions, values, URLs, placeholders, help, and editable markers, similar to the supplied Appshots example. It reads the focused window, including off-screen text only when the app exposes it. It does not scroll pages or inspect every window. Text recognition from the screenshot is labeled separately from accessibility text; OCR cannot recover off-screen content or a missing accessibility hierarchy.

Some apps expose sparse or protected content. Permissions, app-specific accessibility behavior, time limits, and traversal limits can yield partial captures. The preview and export report capture notes. Secure accessibility fields are skipped; this is not a guarantee that ordinary visible text elsewhere in a window is sensitive-data-free.

## Development

- `swift test --disable-sandbox` — focused formatter, selection, and export checks.
- `./script/build_and_run.sh --build-only` — build and sign without launching.
- `./script/build_and_run.sh --logs` — launch and inspect unified logs.
- `./script/build_and_run.sh --debug` — launch the bundle and attach LLDB.

The build stages and verifies the complete signed replacement before stopping or replacing the installed app; a failed build or signature leaves the prior version in place. Development-signed builds also require a positive certificate revocation check before installation, so that step needs Apple's certificate status service to be reachable. This checks the signing certificate and does not require notarization.

The build reuses an existing Apple Development signing identity when available and caches its public fingerprint in `work/signing-identity.txt`. You can override it with `NOTCHSHOT_SIGNING_IDENTITY`. If a saved identity becomes inaccessible, the script stops before changing the installed app rather than silently switching identity. With no development identity, it falls back to ad-hoc signing, which can require re-enabling privacy permissions after changed builds. The app is not notarized. Keep it at one stable path when granting permissions.

If System Settings shows Accessibility enabled but the app reports it disabled, use **Reopen** in the permission panel. When replacing an older ad-hoc build with a development-signed build, remove the old NotchShot entry and add the current app once in both permission panes. Existing captures retain their original content; capture again after granting access.

See [motion design notes](MOTION.md), [research notes](RESEARCH.md) and [Notchi attribution](../THIRD_PARTY_NOTICES.md).

## Paste a complete shot

With **Screenshot + AX tree** selected, **Copy shot**, hover **⌘C**, and automatic copy include a rich document containing the screenshot followed by its accessibility tree and window/app header. Duplicated flat text and OCR are excluded from this clipboard text; they remain available through **Copy text** and export. If capture omitted or truncated accessibility content, a short incompleteness notice stays with the copied tree, including in Compact mode. Detailed capture notes remain in the viewer and exports. If no tree is available, the copy says so explicitly instead of presenting OCR or imported text as accessibility data. Native RTFD and self-contained HTML retain the original PNG; plain-text and PNG/TIFF alternatives remain available for other apps.

For chat composers, select **Screenshot + AX tree** and enable **Paste image, then text** in Settings → Capture & copy. Copy a shot, focus the destination, and press **⌘V within two minutes**. NotchShot pastes the image, pauses briefly, then pastes its accessibility tree into the same field. Wait a moment before typing. The helper handles one paste per copy and never presses Return or submits a message. Copy the shot again to repeat the assisted paste.

The helper uses the existing Accessibility permission. It stops if you change the clipboard, switch destination app/window/field, or type/click during the sequence. Individual **Copy image**, **Copy text**, and **Copy tree** remain ordinary copies. The helper is disabled for Image only and AX tree only; switching Copy content cancels a pending assisted paste. Disable the setting to use rich copy alone. Multiple images in Image only mode remain one rich document; the destination must support that format to paste all images. An app must support image paste; macOS cannot confirm that an app has consumed a clipboard item, so the delay is a compatibility measure rather than a guarantee for every destination.
