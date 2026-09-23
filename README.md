# NotchShot

**A little context. From any app.**

NotchShot is a local macOS utility that captures an app window, its readable
text, and its accessibility tree, then keeps the result in a small shelf in
your notch. Copy one shot or several into your next conversation.

[Website and demo](https://notchshot.com) ·
[User guide](docs/USER_GUIDE.md) · [Licensing](LICENSING.md)

## What it does

- Capture with **left Shift + right Shift together**, or a configurable shortcut.
- Collect screenshots, accessibility text, and optional on-device OCR.
- Preview, select, copy, import, and export shots from a compact notch shelf.
- Choose screenshot + AX tree (default), image only, or AX tree only for copying.
- Copy full accessibility trees or clearly marked compact tree excerpts.
- Assist image-then-text pasting into apps that accept only one clipboard format.
- Customize shutter sounds, automatic copying, and gentle auto-collapse behavior.
- Pick Mint, Sky, Lavender, Rose, Peach, or Gold in Appearance settings.
- Optionally follow your pointer to the active display, keeping the same shelf.
- Stay current on the Stable or Nightly channel, with signature-verified automatic updates.

The app has no account, cloud service, or AI dependency. Its only network access
is an optional update check against GitHub Releases. Captures remain in
memory until you copy or export them. Capture coverage and paste support vary
by destination app.

## Build and run

Requires **macOS 15+** and **Swift 6**. Building needs only the Xcode Command Line
Tools. Download **0.7.0** from
[GitHub Releases](https://github.com/bchewy/notchshot/releases/tag/v0.7.0); from
this release on, NotchShot keeps itself up to date. It targets Apple silicon and
is not notarized. See the [release notes](docs/releases/0.7.0.md) for changes and
verification limits.

```sh
git clone https://github.com/bchewy/notchshot.git
cd notchshot
./script/build_and_run.sh --verify
```

The script builds and signs `outputs/NotchShot.app`, using an available Apple
Development identity or ad-hoc signing. Signing material stays outside git.
Grant **Accessibility** and **Screen Recording** when prompted, then capture
another app. The utility starts collapsed and has no Dock icon.

For a compile-only check without installing or launching:

```sh
swift build --disable-sandbox
```

## Development

```sh
swift test --disable-sandbox
bash -n script/build_and_run.sh
```

Running the tests needs full Xcode, because XCTest ships only with Xcode. The
Command Line Tools alone can build the app but cannot compile the test target.
GitHub Actions runs the build and the suite on every push and pull request
(`.github/workflows/tests.yml`). The same suite gates the signed nightly builds
of `main` and the stable releases published from `v*` tags; see
[releasing](docs/RELEASING.md).

The current suite has **414 tests**, covering the capture entry path, capture
formatting, clipboard preparation, selection, shortcuts, shelf motion, and
auto-collapse, plus theme preferences, display following, and update verification.
See [verification notes](docs/VERIFICATION.md) for the historical checks and
[the user guide](docs/USER_GUIDE.md) for permissions and signing troubleshooting.

| Path | Contents |
| --- | --- |
| `Sources/NotchShot/` | SwiftUI/AppKit app, capture services, and bundled assets |
| `Tests/NotchShotTests/` | Swift test suite |
| `script/` | Build, sign, run, and debug helper |
| `docs/` | Usage, research, design, provenance, and verification notes |
| `website/` | Complete static landing page, demo, and preview downloads |

Build caches, local captures, signing material, scratch outputs, and the separate
Sites deployment checkout are ignored. The original development workspace and
its live app remain intact.

## Website

The landing page is plain HTML and CSS. See [website/README.md](website/README.md)
for local preview and Vercel publishing instructions.

## License and credits

The **combined application is GPL-3.0-only** because its notch panel and display
geometry adapt [Notchi](https://github.com/sk-ruban/notchi). Our independent
original code and website source are also available under **MIT**. This is not
an MIT-only application; see [LICENSING.md](LICENSING.md) for exact file scopes.

Shutter recordings retain their CC0 or CC BY 4.0 terms. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for sources and attribution.
NotchShot is an independent project, not an OpenAI or Fujifilm product.
