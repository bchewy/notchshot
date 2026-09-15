# NotchShot website

A static landing page with the original demo video and the current 0.5.2 preview
downloads. No dependencies or build step.

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

The download ZIPs are intentionally checked in to preserve the complete static
site. They are release snapshots, not the development source of truth. When
publishing a new app build, update both the app and corresponding-source ZIPs,
their names in the page, and their notices together.

## Vercel deployment

Live site: <https://notchshot.vercel.app>

Vercel project `notchshot` in the `brianchew` team is connected to the private
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

Add a custom domain in the project's Vercel Domains settings and use the DNS
records Vercel supplies for that exact domain.

The previous Sites deployment and its separate ignored `landing-page/` checkout
are retained as a historical copy. `website/dist/` is the source of truth for
new changes.

Page source uses [MIT](LICENSE). Downloaded apps, source archives, media, and
third-party assets retain the licenses described in [LICENSING.md](../LICENSING.md).
