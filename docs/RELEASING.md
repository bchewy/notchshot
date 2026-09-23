# Releasing

NotchShot publishes two update channels from GitHub Releases. The app's updater
reads release tags, so the tag names are the contract:

| Channel | Tag | Built from | Published by |
| --- | --- | --- | --- |
| Stable | `v1.2.3` | a commit on `main` | `.github/workflows/release.yml`, when you push the tag |
| Nightly | `nightly-<build>` (prerelease) | `main` | `.github/workflows/nightly.yml`, daily at 18:00 UTC when `main` changed |

Both workflows run the full test suite (`tests.yml`) first, then build, sign,
and package with the same scripts used locally. Nightly keeps the newest seven
nightly releases and deletes older ones with their tags.

## Version and build numbers

`APP_VERSION` in `script/build_and_run.sh` is the marketing version. The build
number is `git rev-list --count HEAD`, so every build of `main` is numbered above
the one before it (0.6.0 was build 29). The updater installs only a higher build
number than the one running, so:

- Stable tags must point at commits on `main`; the release workflow refuses others.
- Staging refuses shallow clones, which would count too few commits.
- Nightly builds share `APP_VERSION` until you bump it. Bump it at the start of a
  cycle so nightlies read as the upcoming version.

## One-time setup: signing secrets

The updater accepts only builds that satisfy the running app's designated
requirement: the same bundle identifier and the same signing certificate. This is
also what keeps Accessibility and Screen Recording permissions across updates.
CI therefore signs with the same Apple Development certificate as local releases.

1. In Keychain Access, export the valid **Apple Development: …** certificate
   together with its private key as a `.p12`, with a strong password. Do not
   export the revoked one with the same name.
2. Add two repository secrets (Settings → Secrets and variables → Actions):
   - `NOTCHSHOT_SIGNING_P12_BASE64`: the output of `base64 -i certificate.p12`
   - `NOTCHSHOT_SIGNING_P12_PASSWORD`: the export password
3. Delete the exported `.p12` file.

`script/ci_signing_keychain.sh` imports the certificate into a temporary keychain
for each run and deletes it afterwards. Until both secrets exist, the nightly
workflow skips publishing with a warning, and a tag push fails before building.
Pull requests from forks cannot read repository secrets, but any workflow pushed
by someone with write access can. Keep write access limited to people you would
trust with the certificate.

When the certificate is renewed, update both secrets. A renewed certificate
with the same name still satisfies the designated requirement. Moving to a
different certificate type, such as Developer ID, changes the requirement, so
installed copies need one manual reinstall to follow.

## Publishing a stable release

1. On `main`, set `APP_VERSION` in `script/build_and_run.sh` to the new version
   and add `docs/releases/VERSION.md`. The release uses it as its notes; without
   it, GitHub generates notes.
2. Commit, push, and wait for the Tests workflow to pass.
3. Tag and push:

   ```sh
   git tag v0.7.0
   git push origin v0.7.0
   ```

The release workflow checks that the tag matches `APP_VERSION`, sits on `main`,
and names a release that does not exist yet. It then tests, builds, signs,
packages, and publishes. Stable-channel installs pick the release up within
about six hours. Update the website download links separately, after the release
assets are live.

## Nightly builds

Nothing is required once the secrets exist. To publish one immediately, run
**Nightly** from the Actions tab on `main`. A run is skipped when
`nightly-<build>` already exists for the current commit count.

## Packaging locally

Commit the reviewed app changes before staging a release. The build records its
source commit in the signed app, and the packager refuses modified or untracked
source files. Ignored build outputs in `work/` and `outputs/` are permitted.

```sh
./script/build_and_run.sh --stage-only
python3 script/package_release.py work/staged/NotchShot.app
```

`--stage-only` builds and verifies a Stable release bundle without replacing or
restarting the installed app. Set `NOTCHSHOT_BUILD_CHANNEL=Nightly` to stage a
nightly instead. Approve the macOS Keychain prompt if signing asks for access. A
signing failure must be resolved before packaging; do not substitute an ad-hoc
signature.

The packager accepts an existing signed bundle and never builds, installs,
launches, uploads, or changes it. It lays out the disk image with `dmgbuild`,
installed on first use into `work/dmg-tools` from the exact hash-pinned wheels
in `script/dmg/requirements.txt` (this needs network access once). To change the
image's background, edit and run `swift script/dmg/make_background.swift`. Use `--output-dir /path/to/empty-directory` to
choose another destination. Within this checkout, that directory must be ignored
by git. It creates these immutable files in `work/releases/` by default (nightly
names add `-nightly.BUILD` after the version):

- `NotchShot-VERSION.zip`: the app bundle. The updater installs from this.
- `NotchShot-VERSION.dmg`: the same app beside an Applications link, for people
  to drag into place. The packager mounts it read-only and checks that it shows
  only those two items and that the app matches the input exactly.
- `NotchShot-VERSION-source.zip`: the exact committed app source, tests, resources,
  build scripts, documentation, and licenses, plus `SOURCE_REVISION` and
  `BUILD_METADATA.json`.
- `NotchShot-VERSION-SHA256SUMS.txt`: SHA-256 hashes of the ZIP files and disk image.
- `NotchShot-VERSION-release.json`: version, build, channel, source identity,
  verification methods, and artifact hashes. The updater reads this manifest.

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
Keep known verification gaps in release notes. Publish the matching app ZIP and
source ZIP together; update the website download link only after both files and
their checksums are available at the intended release URLs.
