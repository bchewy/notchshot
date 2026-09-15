# Appshots research and NotchShot implementation

Research checked on 15 September 2026. NotchShot is a personal macOS utility built with SwiftPM, SwiftUI, and AppKit; its deployment target is macOS 15.

## What Appshots does

OpenAI describes Appshots as an on-demand attachment of the frontmost app window: a screenshot plus text that the app exposes through Accessibility. Available text can extend beyond the visible scroll area. Its macOS permissions are Screen & System Audio Recording and Accessibility. Some apps and websites, including Google Workspace surfaces, may provide only a screenshot rather than their full document text. These are public product behaviors, not a description of Codex's private implementation. [Official Appshots documentation](https://learn.chatgpt.com/docs/appshots)

NotchShot implements this general interaction independently: capture the current app, inspect the image and available text in a notch panel, then explicitly copy or export the result. It does not require an AI provider, account, or network connection.

## Native capture design

| Responsibility | Public API and implementation choice |
| --- | --- |
| Identify the current app | [`NSWorkspace.frontmostApplication`](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication). Remember the target before opening the preview so the utility does not capture itself. |
| Capture one window | [`SCShareableContent`](https://developer.apple.com/documentation/screencapturekit/scshareablecontent), [`SCContentFilter(desktopIndependentWindow:)`](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)), and [`SCScreenshotManager`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager). The single-image API is available from macOS 14; this app targets macOS 15. |
| Read available window content | `AXUIElementCreateApplication`, the focused-window attribute, and [`AXUIElementCopyAttributeValue`](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue). Read the selected window's role tree and text without performing accessibility actions. |
| Bound AX work | [`AXUIElementSetMessagingTimeout`](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) plus application limits. Run the full traversal off the main actor. |
| Recover visible text when AX is limited | Vision [`VNRecognizeTextRequest`](https://developer.apple.com/documentation/vision/vnrecognizetextrequest) on the screenshot. OCR runs locally and remains separate from Accessibility text. |
| Check permissions | [`CGPreflightScreenCaptureAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()) and [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions). Request access through the app's setup controls. |

Apple's [ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) and [WWDC23 screenshot API introduction](https://developer.apple.com/videos/play/wwdc2023/10136/) support the single-window approach. There is no need to create a continuous recording stream for each still image. A system picker is another supported selection model and grants access to the explicitly selected content for its session; NotchShot instead uses its foreground-window workflow. [Apple privacy session](https://developer.apple.com/videos/play/wwdc2023/10053/)

## Limits that shape the app

1. **Accessibility is not a universal document API.** Apps may omit attributes, expose only controls, or return an incomplete tree. The app reports missing or limited results; it does not infer a complete document from a successful API call. Apple documents unsupported attributes, absent values, invalid elements, and messaging failures in the [AX read API](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue).
2. **Text and pixels cover different areas.** AX text can include off-screen content exposed by the selected window. OCR can recognize only text present in the captured pixels and can make mistakes. Both sources have separate labels and exports. [Appshots behavior](https://learn.chatgpt.com/docs/appshots), [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
3. **Large or unresponsive AX trees need limits.** The implementation stops at 1,500 nodes, depth 40, 250,000 text characters, or a six-second traversal budget, with a 0.12-second timeout for individual AX calls. The wall-clock budget is checked between synchronous calls, so a final in-flight call may finish after that budget. Truncation is reported. [AX messaging timeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)
4. **Window selection can change during capture.** The target process and focused window are resolved before the first suspension. Window matching can still fail if a window closes or moves between Spaces; that produces a partial result or an actionable error rather than a different app's capture. [Foreground-app definition](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication), [window content filters](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:))
5. **Permissions are independent.** Screenshot permission does not grant AX text access. Either source may be available without the other. macOS may require a relaunch after Screen Recording approval; the app displays the current state. [Apple capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
6. **Protected content may be absent.** Secure or protected AX nodes are omitted by the reader. Video or other protected pixels may be excluded by macOS or the source application, so capturing every app cannot mean capturing all of its content. [Apple protected-video capture behavior](https://developer.apple.com/documentation/avfoundation/avplayer/allowscaptureofclearkeyvideo)
7. **A shortcut does not require a general keystroke recorder.** Command–Shift–2 uses a registered global shortcut. Double Command uses passive local/global NSEvent monitors with Accessibility permission: only Command transitions and whether other key/mouse activity invalidates the gesture are processed, never typed characters. The app does not request Input Monitoring. Shortcut registration failures still need handling; Apple has changed accepted modifier combinations across macOS releases. [Apple engineer discussion of registered hotkeys](https://developer.apple.com/forums/thread/763878)

## Notchi reuse and provenance

The base reference is [sk-ruban/notchi](https://github.com/sk-ruban/notchi), revision [`e873da231340b3a5094c59ce7cb0ec2809d88ed1`](https://github.com/sk-ruban/notchi/tree/e873da231340b3a5094c59ce7cb0ec2809d88ed1), licensed GPL-3.0-only.

`NotchPanel.swift` adapts its borderless, nonactivating floating panel and Spaces behavior. `NotchGeometry.swift` adapts its public display and safe-area geometry. The capture engine, inspection views, and export workflow are new work. Notchi's private bezel lookup, agent integrations, network clients, mascot assets, and updater are not included. See `THIRD_PARTY_NOTICES.md` and `LICENSE` for attribution and license terms.

## Local data behavior

The app retains up to eight shots in memory. Copy and export are explicit actions; export supports PNG, Markdown, plain text, and JSON. There is no background recording, automatic upload, AI request, or account integration. Captures may contain sensitive window text and images; the preview is the place to inspect exactly what will be copied or exported.

This research establishes the API choices and practical limits. Build success and automated checks are separate from live Screen Recording and Accessibility permission verification on the user's Mac.

## Permission identity during development

The initial ad-hoc signature used a code-hash designated requirement. Changing the binary changes that identity, which can invalidate privacy grants even if the app remains listed in System Settings. The build now reuses an existing Apple Development certificate when available; the local Mac has such an identity. Apple confirms this development-signing distinction in its [ScreenCaptureKit permission discussion](https://developer.apple.com/forums/thread/819406) and [code-signing requirements technote](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). The one-time transition from the old signature can still require replacing its permission entry.


## Screenshot card and shelf reference (0.2)

The supplied recording is 5.334 seconds at 1152×720/30 fps. It shows a window flash beginning around 2.467s, a screenshot shrinking into Codex's composer around 2.667–2.80s, and a settled thumbnail by roughly 3.0s. Its dark card has an app icon/name and a close affordance. The recording does not demonstrate a notch or completed drag; those are requested additions. Brian explicitly chose automatic collection into the notch shelf.

The implementation shows an early screenshot while AX reading completes, plays macOS Tink at half volume, then collects the complete capture after a short preview and landing animation. A native NSPanel owns the temporary card; a narrow NSView bridge carries a typed drag payload (local capture UUID, PNG, and text). A registered drop destination on the notch hosting view handles both collapsed and expanded states. Native payloads keep the original AX tree; external image/text drops are labeled according to their actual source.

Public API references: [NSEvent monitoring](https://developer.apple.com/documentation/appkit/nsevent), [starting a native drag](https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:)), [drag completion](https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession(_:endedat:operation:)).
