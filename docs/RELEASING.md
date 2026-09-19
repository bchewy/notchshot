# Packaging a preview

Commit the reviewed app changes before staging a release. The build records its
source commit in the signed app, and the packager refuses modified or untracked
source files. Ignored build outputs in `work/` and `outputs/` are permitted.

```sh
./script/build_and_run.sh --stage-only
python3 script/package_release.py work/staged/NotchShot.app
```

`--stage-only` builds and verifies the Preview bundle without replacing or
restarting the installed app. Approve the macOS Keychain prompt if signing asks
for access. A signing failure must be resolved before packaging; do not substitute
an ad-hoc signature.

The packager accepts an existing signed bundle and never builds, installs,
launches, uploads, or changes it. Use `--output-dir /path/to/empty-directory` to
choose another destination. Within this checkout, that directory must be ignored
by git. It creates these immutable files in `work/releases/` by default:

- `NotchShot-VERSION.zip`: the app bundle.
- `NotchShot-VERSION-source.zip`: the exact committed app source, tests, resources,
  build scripts, documentation, and licenses, plus `SOURCE_REVISION` and
  `BUILD_METADATA.json`.
- `NotchShot-VERSION-SHA256SUMS.txt`: SHA-256 hashes of both ZIP files.
- `NotchShot-VERSION-release.json`: version, build, source identity, verification
  methods, and artifact hashes.

The source ZIP excludes the website, its existing downloads and demo media,
local build products, caches, and signing material. It preserves the GPL license
for the combined application, the MIT grant for independent original portions,
and all third-party notices. See [LICENSING.md](../LICENSING.md).

Packaging verifies certificate-backed signing, including the embedded public
certificate chain and required OCSP status. It checks ZIP integrity, extracts the
app, and verifies its signature, version, source revision, and executable hash
against the input. The checkout and input bundle are checked again before output
files are published. Existing versioned files are never overwritten.

These checks do **not** establish notarization or replace manual app testing.
Keep known verification gaps in preview release notes. Publish the matching app
ZIP and source ZIP together; update the website download link only after both
files and their checksums are available at the intended release URLs.
