# NotchShot website

A static landing page with a scroll-driven capture walkthrough, an interactive
feature grid, and the original demo video. Downloads point at the signed
release on GitHub. No dependencies or build step.

## Preview locally

From the repository root:

```sh
python3 -m http.server 4175 --bind 127.0.0.1 --directory website/dist
```

Open <http://127.0.0.1:4175>.

## Contents

- `dist/index.html`, `dist/style.css`, and `dist/site.js`: page source.
- `dist/assets/`: demo video and poster.
- `dist/downloads/`: the license and credits the page links to, plus the
  immutable 0.5.2 and 0.6.0 preview archives kept for existing links.

Since 0.7.0, the page links straight to the release assets on GitHub
(`NotchShot-VERSION.zip`, `-source.zip`, and `-SHA256SUMS.txt`), which CI
publishes and signs. Installed copies update themselves, so a new release only
needs the version in the page's links and requirement lines bumped. The
retained static preview files are:

- `dist/downloads/NotchShot-0.6.0.zip`
- `dist/downloads/NotchShot-0.6.0-source.zip`
- `dist/downloads/NotchShot-0.6.0-SHA256SUMS.txt`
- `dist/downloads/NotchShot-0.6.0-release.json`

Preview 0.6.0 (build 29) was built from source commit
`5fd8876c4e9dbc1eaba4b4dd215965db6b5f6f77`. The source ZIP records that same
revision in `SOURCE_REVISION` and `BUILD_METADATA.json`. The release JSON records
the executable hash and paired archive hashes. The matching assets are available
on [GitHub Releases](https://github.com/bchewy/notchshot/releases/tag/v0.6.0).

These are immutable releases, not the development source of truth. Keep their
links and the page's version/features aligned with the published app until the
next release is signed and verified. The original 0.5.2 downloads remain intact.
App and source archives must describe the same source revision; copies on GitHub
and the static site must have matching checksums. To verify the local pair:

```sh
cd website/dist/downloads
shasum -a 256 -c NotchShot-0.6.0-SHA256SUMS.txt
```

When publishing an update, follow [the release procedure](../docs/RELEASING.md)
to build and verify the app and corresponding-source ZIPs first. Publish both
GitHub release assets with their checksum file and release metadata, check their
downloaded checksums, then update the page links, paired static copies, and
notices together. After deploying, verify the downloads served by notchshot.com
against those same checksums. Keep the preview and notarization information
accurate; 0.6.0 is a certificate-signed preview and is not notarized.

## Scroll walkthrough

A pinned, four-chapter story: both Shift keys press and the notch's aperture
shuts like a shutter; the Notes window becomes a card while its accessibility
tree unfolds beside it; the card arcs into the opening shelf; and History
searches for it. Native scrolling drives everything. `site.js` smooths the
story's progress with a spring, so motion glides on a notchy wheel without
intercepting scroll. The rail buttons jump to each chapter, and the aperture is
drawn with the same geometry as the app.

The rest of the page adds a scroll-velocity app marquee, a bento grid (the
Appearance card lets visitors switch marks and recolor the page), a film frame
that scales in as it arrives, and a closing call to action. One
`requestAnimationFrame` loop runs only while something moves; a full scroll
through the story holds 60 fps in headless Chrome.

`prefers-reduced-motion` shows the chapters as a summary above a composed static
shelf, stops the marquee, and drops every transition. Without JavaScript the
same static composition, video controls, and downloads remain, and nothing stays
hidden if `site.js` fails to load. No animation library, scroll interception,
external fonts, or runtime dependencies are used.

For visual changes, check each chapter on desktop, tablet, and phone widths;
scroll backward; exercise the rail and skip link; and verify reduced motion and
JavaScript-disabled rendering.

## Vercel deployment

Live site: <https://notchshot.com>

`www.notchshot.com` permanently redirects to the apex domain. Both domains are
assigned to production in the Vercel project; Vercel manages DNS and HTTPS.
The fallback deployment alias is <https://notchshot.vercel.app>.

Vercel project `notchshot` in the `brianchew` team is connected to the public
`bchewy/notchshot` GitHub repository. Pushes to `main` deploy production updates.

Project settings are checked into the repository-root `vercel.json`:

- Root directory: repository root.
- Framework: Other.
- Build and install commands: empty; no build is needed.
- Output directory: `website/dist`.

`.vercelignore` permits only the static website and its deployment configuration
in CLI uploads. Swift sources, local captures, build caches, and credentials are
excluded. `.vercel/` and local environment files remain outside git.

To deploy manually, run from the repository root after signing in to Vercel:

```sh
npx vercel link --scope brianchew --project notchshot
npx vercel deploy --prod --scope brianchew
```

Manage the connected domain and its redirect in the project's Vercel Domains
settings. Additional domain changes should use the DNS records Vercel supplies
for the exact domain.

The previous Sites deployment and its separate ignored `landing-page/` checkout
are retained as a historical copy. `website/dist/` is the source of truth for
new changes.

Page source uses [MIT](LICENSE). Downloaded apps, source archives, media, and
third-party assets retain the licenses described in [LICENSING.md](../LICENSING.md).
