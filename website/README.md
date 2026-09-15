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

## Sites deployment

The existing site is <https://notchshot.vercel.app>.
On the original development machine, `landing-page/` is its separate Sites
checkout and is ignored by the parent repository. `website/dist/` is the GitHub
source of truth. Copy its contents into that checkout's `dist/` before using
Sites to publish an update, preserving the checkout's `.openai/hosting.json` and
git metadata. From a fresh clone, use Sites to connect the static output to the
existing site; do not create a duplicate site.

Page source uses [MIT](LICENSE). Downloaded apps, source archives, media, and
third-party assets retain the licenses described in [LICENSING.md](../LICENSING.md).
