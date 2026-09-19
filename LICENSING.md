# Licensing

NotchShot combines original MIT-licensed code with code adapted from Notchi.
The **combined macOS application is GPL-3.0-only**, under [LICENSE](LICENSE).
It is not an MIT-only application.

## Original work: MIT

[LICENSE-MIT](LICENSE-MIT) applies to Brian Chew's original code and documentation
in this repository, including:

- `Package.swift`, `Tests/`, and `script/`.
- Swift files in `Sources/NotchShot/`, except the two GPL-derived files below.
- Original project documentation and portable development configuration.
- Original landing-page HTML and CSS in `website/dist/`.

This additional grant allows the independent original portions to be reused
under MIT. It does not change the GPL terms of the combined application or grant
rights to third-party material. Existing third-party notices must be retained.

## Notchi-derived code: GPL-3.0-only

These files retain their GPL SPDX identifiers and upstream attribution:

- `Sources/NotchShot/Support/NotchPanel.swift`
- `Sources/NotchShot/Support/NotchGeometry.swift`

They adapt [Notchi](https://github.com/sk-ruban/notchi), revision
`e873da231340b3a5094c59ce7cb0ec2809d88ed1`, by sk-ruban and contributors.
See [third-party notices](THIRD_PARTY_NOTICES.md).

## Assets and release snapshots

- X-T3 and X100S shutter recordings are CC0. The FinePix F11 recording is
  CC BY 4.0. Their authors, sources, and modifications are recorded in
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Camera illustrations are generated assets; their provenance is recorded in
  [docs/CAMERA_ICONS.md](docs/CAMERA_ICONS.md). They are not official Fujifilm assets.
- Demo video, poster, and other media are separate from the MIT source-code grant.
- `website/dist/downloads/` contains immutable preview distributions with paired
  GPL source archives and attribution. The original 0.5.2 snapshots retain their
  original licensing; the additional MIT grant does not relabel those files.

Repository visibility does not change these licenses.
