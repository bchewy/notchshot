# NotchShot website

A static landing page with a scroll-driven capture walkthrough, the original
demo video, and the 0.6.0 preview downloads. No dependencies or build step.
A source update alone does not replace the downloadable app; each preview is packaged and verified separately.

## Preview locally

From the repository root:

```sh
python3 -m http.server 4175 --bind 127.0.0.1 --directory website/dist
```

Open <http://127.0.0.1:4175>.

## Contents

- `dist/index.html`, `dist/style.css`, and `dist/story.js`: page source.
- `dist/assets/`: demo video and poster.
- `dist/downloads/`: immutable preview app, corresponding source, and notices.

The checked-in release files are:

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

The illustrative Notes window shrinks to a screenshot card and follows a curved
path into the notch shelf. Native scrolling controls the reversible sequence;
the three step buttons provide keyboard-accessible shortcuts. The real recording
remains below the illustration and loads only when played.

`prefers-reduced-motion` switches to a compact static shelf. Without JavaScript,
the static shelf, explanation, video, and downloads remain available. No animation
library, scroll interception, external fonts, or runtime dependencies are used.

For visual changes, check the capture, floating-card, and landing states on desktop
and mobile; scroll backward; exercise the step buttons and skip link; and verify
reduced motion and JavaScript-disabled rendering. Keep the download archives
unchanged for website-only updates.

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
