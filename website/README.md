# NotchShot website

A static landing page with the original demo video, prepared for the 0.6.0
preview. No dependencies or build step. Publish the matching release assets
before deploying this page; its new download links require those assets.

## Preview locally

From the repository root:

```sh
python3 -m http.server 4175 --bind 127.0.0.1 --directory website/dist
```

Open <http://127.0.0.1:4175>.

## Contents

- `dist/index.html` and `dist/style.css`: page source.
- `dist/assets/`: demo video and poster.
- `dist/downloads/`: immutable preview app, corresponding source, and notices.

The page links to versioned assets on the [GitHub release](https://github.com/bchewy/notchshot/releases/tag/v0.6.0):

- [NotchShot 0.6.0 app](https://github.com/bchewy/notchshot/releases/download/v0.6.0/NotchShot-0.6.0.zip)
- [Corresponding source](https://github.com/bchewy/notchshot/releases/download/v0.6.0/NotchShot-0.6.0-source.zip)

Check matching copies of both ZIPs into `dist/downloads/` when publishing, to
preserve the complete static site. Until that step, this directory retains the
earlier 0.5.2 snapshots. These are immutable releases, not the development source
of truth. App and source archives must describe the same source revision; the
copies on GitHub and in the static site must have matching checksums.

When publishing an update, build and verify the app and corresponding-source
ZIPs first. Publish both GitHub release assets, check their downloaded checksums,
then update the page links, paired static copies, and notices together. Keep the
preview and notarization information accurate. A source commit alone does not
update the downloadable app.

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
