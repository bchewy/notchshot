# NotchShot motion

This app uses a small native adaptation of [Emil Kowalski's skills](https://github.com/emilkowalski/skills), reviewed at commit `d23d7f88a2e21c9e4b1418c7abe420f5c1052ba7`:

- [Apple Design](https://github.com/emilkowalski/skills/blob/d23d7f88a2e21c9e4b1418c7abe420f5c1052ba7/skills/apple-design/SKILL.md): immediate response, current presentation values, velocity continuity, anchored movement, and reduced motion.
- [Review Animations](https://github.com/emilkowalski/skills/blob/d23d7f88a2e21c9e4b1418c7abe420f5c1052ba7/skills/review-animations/SKILL.md) and its standards: concise dropdown timing and scrutiny of interrupted or competing animations.

## Decisions

| Before | After | Why |
| --- | --- | --- |
| The notch settled in roughly 330 ms. | A critically damped spring targets a 250 ms settle from rest. | The guide's dropdown budget is 150–250 ms. Keep the requested fluid shape change concise. |
| Expanded controls ignored input below 85% open. | Visible controls accept input immediately. | Opening must not create an artificial input lock. The native window and clipping still bound reachable content. |
| A same-capture accessibility update could force the preview to full opacity. | Content refresh preserves the current entrance. | New capture data should not interrupt an unrelated visual transition. |
| The card had a separate 60 Hz timer and default window-show behavior. | Display-timed card motion owns its window transition. | Keep the card and notch on the display's cadence and avoid competing show animations. |

Retain the existing no-bounce spring, current-value/velocity reversals, top-center notch anchor, fixed-layout preview behind a reveal, and static Reduce Motion variant. The revised Appshot sequence uses a 460 ms window-flash/peel entrance, a 550 ms pause after context finishes, a 280 ms shelf preparation, and a 520 ms visible flight. The longer flight is deliberate: Brian requested a perceptible floating modal traveling from the captured app into the notch. A 140 ms overlap blends the arriving raster into the saved thumbnail. The pause can overlap the entrance; slow accessibility reads keep the preview visible until context is ready.

## Native adaptation

These are design guides, mostly illustrated with browser code. NotchShot remains SwiftUI/AppKit. Its actual window bounds must follow the visible notch so an invisible expanded window does not intercept clicks. The preview content stays at its final layout size while a changing mask reveals it; text is not squeezed on each frame. CSS, React, and a new animation runtime are not used.

The generic advice to remove all keyboard-triggered motion is overridden by Brian's explicit request for the Appshot card and a smoothly opening/collapsing notch. Keep that movement brief and interruptible. Do not add staggered controls, bounce, decorative blur, or a new gesture just to use more of the guide.

## Verification

Check native window movement, rapid reversal, same-capture screenshot-to-text refresh, automatic shelf landing, and visibility of the compact controls. Tests must include the store-to-native-window path, not just the spring equation. Geometry-only diagnostics are available through `NOTCHSHOT_GEOMETRY_LOG`. See [verification](VERIFICATION.md) for measured results and limits.

The upstream skill repository is MIT-licensed, copyright 2026 Emil Kowalski. This document summarizes principles and records native design decisions; no upstream runtime code or global skill installation is included.

## Appshot source-to-shelf sequence (0.3.1)

The supplied recording shows a window-scoped flash followed by a shrinking screenshot settling into a composer attachment. NotchShot adapts that spatial sequence to a notch shelf, with Brian's requested floating preview between capture and collection. The original app retains focus.

Actual capture-window bounds choose the source screen and preview center. A passive native raster canvas avoids reflowing SwiftUI text as the card changes size. The shelf reserves an incoming thumbnail, opens, scrolls that slot into view, and reports its native screen coordinates. The card then changes position and size together, staying opaque until arrival; a short overlap covers the SwiftUI thumbnail reveal.

Partial screenshot-to-AX updates do not replay the animation. Replacement, clear, dismissal, and drag cancel stale completions. Explicit collapse during collection saves the shot while leaving the notch closed. Reduce Motion shows the static preview and collects without spatial movement; turning it on mid-flight settles immediately. Missing destination geometry collects safely.

Apple references: [native view rasterization](https://developer.apple.com/documentation/appkit/nsview/cachedisplay(in:to:)), [window-to-screen conversion](https://developer.apple.com/documentation/appkit/nswindow/converttoscreen(_:)).

## Shelf-first presentation (0.4.0)

The app starts at the collapsed notch. The default shelf is 440 × 180 points; Settings is 440 × 440 and manually selected shot details are 440 × 480. An independent pair of size springs drives native width/height from their current values, while expansion progress drives the reveal. Page changes therefore animate even when the notch is already fully open. The top edge and hardware-notch center remain anchored.

Taking a capture no longer closes an already open notch. The receiving shelf opens and stays open after collection. Completed capture selection does not navigate into the detail page; clicking a thumbnail does. Explicit Settings/detail navigation or collapse during the preview, AX read, or flight takes precedence over delayed arrival. The result is saved quietly when necessary.


## Shelf hover previews (0.4.1)

Saved thumbnails gain a gentle mint highlight. After a 220 ms dwell, a passive 320 × 264-point panel fades in over 140 ms below the shelf. It shows the full screenshot fitted within its preview area or a bounded text excerpt, plus app/window identity, capture time, and available context. The notch remains 440 × 180 and hover does not change selection.

A small AppKit tracking view supplies the visible thumbnail geometry. The separate nonactivating child panel cannot become key or main and ignores mouse events, so clicking the shot still opens details. Exit, navigation, collapse, capture/import/drop, removal, and window geometry changes cancel the preview. Dwell callbacks check ownership, pointer location, and unchanged geometry. Reduce Motion shows the panel immediately after the same dwell without an entrance animation.


## Tighter collapsed footprint (0.4.2)

The native collapsed window now adds 36 points to the hardware notch geometry, down from 88. Each side indicator gets a 16-point lane and 2 points of outer padding. On this Mac the actual collapsed bounds change from 277 × 32 to 225 × 32. Hardware center/top anchoring stays the same. The viewfinder, status dot, and lane widths interpolate with the existing presentation progress to their expanded sizes; the shelf remains 440 × 180.

The shared collapsed-size helper drives both startup and subsequent native geometry, so there is no oversized invisible window covering nearby menu items. Native tests assert the width after layout at startup and after a settled close.
