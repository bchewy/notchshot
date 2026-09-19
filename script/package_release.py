#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Package a clean, certificate-signed preview without building or installing it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile


class PackagingError(Exception):
    pass


ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOTS = {"Sources", "Tests", "script", "docs"}
SOURCE_FILES = {
    "Package.swift", "Package.resolved", "README.md", "LICENSE", "LICENSE-MIT",
    "LICENSING.md", "THIRD_PARTY_NOTICES.md", ".gitignore",
}
FORBIDDEN_SUFFIXES = {
    ".p12", ".pfx", ".key", ".pem", ".mobileprovision", ".keychain",
    ".keychain-db", ".cer", ".der", ".zip", ".dmg", ".pkg",
}


def run(*args, cwd=ROOT):
    completed = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, check=False)
    if completed.returncode:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise PackagingError(f"{Path(args[0]).name} failed: {detail or 'exit ' + str(completed.returncode)}")
    return completed.stdout


def git(*args):
    return run("git", *args)


def clean_revision():
    status = git("status", "--porcelain", "--untracked-files=all")
    if status.strip():
        raise PackagingError("Commit all source changes and untracked files before packaging (ignored work/outputs are allowed).")
    return git("rev-parse", "--verify", "HEAD").decode().strip()


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def bundle_identity(bundle, revision):
    try:
        with (bundle / "Contents/Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise PackagingError(f"Cannot read app Info.plist: {error}") from error
    version = info.get("CFBundleShortVersionString", "")
    build = info.get("CFBundleVersion", "")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", version):
        raise PackagingError("App version must be a safe semantic version such as 0.6.0.")
    if not isinstance(build, str) or not re.fullmatch(r"\d+", build):
        raise PackagingError("App build must be a numeric string.")
    if info.get("CFBundleIdentifier") != "com.bchewy.NotchShot" or info.get("CFBundleExecutable") != "NotchShot":
        raise PackagingError("Expected the com.bchewy.NotchShot app and NotchShot executable.")
    if info.get("NotchShotSourceDirty") is not False:
        raise PackagingError("The app must explicitly record NotchShotSourceDirty=false. Rebuild after committing.")
    if info.get("NotchShotSourceRevision") != revision:
        raise PackagingError("The app source revision does not match current HEAD. Stage a new build from the clean commit.")
    if info.get("NotchShotBuildChannel") != "Preview":
        raise PackagingError("Only a staged Preview build can be packaged. Run script/build_and_run.sh --stage-only.")
    executable = bundle / "Contents/MacOS/NotchShot"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise PackagingError("The app executable is missing or is not executable.")
    return {
        "version": version,
        "build": build,
        "bundle_identifier": info["CFBundleIdentifier"],
        "channel": info["NotchShotBuildChannel"],
        "source_revision": revision,
        "source_dirty": False,
        "executable_sha256": digest(executable),
    }


def verify_signature(bundle, certificates=None):
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle))
    details = subprocess.run(
        ["/usr/bin/codesign", "--display", "--verbose=4", str(bundle)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    description = (details.stdout + details.stderr).decode("utf-8", errors="replace")
    if details.returncode or "Signature=adhoc" in description or "Authority=" not in description:
        raise PackagingError("Public preview packaging requires a certificate-backed signature; ad-hoc or unsigned apps are refused.")
    if certificates is not None:
        certificates.mkdir()
        prefix = certificates / "cert"
        run("/usr/bin/codesign", "--display", f"--extract-certificates={prefix}", str(bundle))
        chain = []
        index = 0
        while Path(f"{prefix}{index}").is_file():
            chain.extend(["-c", f"{prefix}{index}"])
            index += 1
        if not chain:
            raise PackagingError("No embedded signing certificate chain was found.")
        run("/usr/bin/security", "verify-cert", "-p", "codeSign", "-R", "ocsp", "-R", "require", *chain)


def source_paths():
    files = [path.decode("utf-8") for path in git("ls-tree", "-r", "--name-only", "-z", "HEAD").split(b"\0") if path]
    selected = []
    for filename in files:
        path = Path(filename)
        if filename not in SOURCE_FILES and path.parts[0] not in SOURCE_ROOTS:
            continue
        if (path.suffix.lower() in FORBIDDEN_SUFFIXES
                or any(part.lower() in {".env", ".git", "work", "outputs", ".build", ".swiftpm", "signing"}
                       or part.lower().startswith(".env.") or part.lower().endswith(".app")
                       for part in path.parts)
                or path.name in {"id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"}):
            raise PackagingError(f"Excluded release/signing material is tracked in the source allowlist: {filename}")
        committed_content = git("show", "HEAD:" + filename)
        private_key_header = b"-----BEGIN " + b"(?:[A-Z0-9]+ )?" + b"PRIVATE KEY-----"
        if re.search(private_key_header, committed_content):
            raise PackagingError(f"Private signing material was detected in a source file: {filename}")
        selected.append(filename)
    required = {"Package.swift", "LICENSE", "LICENSE-MIT", "LICENSING.md", "THIRD_PARTY_NOTICES.md", "script/build_and_run.sh"}
    if not required.issubset(selected) or not any(path.startswith("Sources/") for path in selected):
        raise PackagingError("The committed source tree lacks required build sources or licenses.")
    return selected


def verify_zip(path):
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise PackagingError(f"Archive integrity check failed for {path.name}: {bad}")
        for member in archive.namelist():
            if member.startswith("/") or ".." in Path(member).parts:
                raise PackagingError(f"Unsafe archive member: {member}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app_bundle", type=Path, help="Existing staged, certificate-signed Preview .app")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "work/releases")
    args = parser.parse_args()
    bundle = args.app_bundle.expanduser().resolve()
    output = args.output_dir.expanduser().resolve()
    if not bundle.is_dir() or bundle.name != "NotchShot.app":
        raise PackagingError("Pass an existing NotchShot.app bundle.")
    if output == bundle or bundle in output.parents:
        raise PackagingError("The release directory cannot be inside the signed app bundle.")
    if output == ROOT or ROOT in output.parents:
        probe = (output / ".release-output-probe").relative_to(ROOT)
        if subprocess.run(["git", "check-ignore", "--quiet", str(probe)], cwd=ROOT).returncode:
            raise PackagingError("An output directory inside the checkout must be ignored by git (for example work/releases).")

    revision = clean_revision()
    identity = bundle_identity(bundle, revision)
    selected = source_paths()
    stem = f"NotchShot-{identity['version']}"
    names = [f"{stem}.zip", f"{stem}-source.zip", f"{stem}-SHA256SUMS.txt", f"{stem}-release.json"]
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() or (output / name).is_symlink() for name in names):
        raise PackagingError("Versioned release files already exist. They are immutable; choose an empty output directory or bump the app version.")

    # Produce and verify everything in scratch space; publish only complete artifacts.
    with tempfile.TemporaryDirectory(prefix=".notchshot-package-", dir=output) as temporary:
        scratch = Path(temporary)
        verify_signature(bundle, scratch / "certificates")
        app_zip, source_zip, checksums, metadata = [scratch / name for name in names]
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(bundle), str(app_zip))
        verify_zip(app_zip)
        extraction = scratch / "extracted"
        extraction.mkdir()
        run("/usr/bin/ditto", "-x", "-k", str(app_zip), str(extraction))
        extracted_app = extraction / "NotchShot.app"
        if bundle_identity(extracted_app, revision) != identity:
            raise PackagingError("The extracted app version, source identity, or executable hash differs from the input.")
        verify_signature(extracted_app)

        source_prefix = f"{stem}-source/"
        run("git", "archive", "--format=zip", f"--prefix={source_prefix}", f"--output={source_zip}", revision, "--", *selected)
        build_metadata = {**identity, "signature": "certificate-backed", "signature_validation": "codesign --verify --deep --strict", "certificate_validation": "security verify-cert -p codeSign -R ocsp -R require", "notarization": "not_checked"}
        with zipfile.ZipFile(source_zip, "a", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(source_prefix + "SOURCE_REVISION", revision + "\n")
            archive.writestr(source_prefix + "BUILD_METADATA.json", json.dumps(build_metadata, indent=2, sort_keys=True) + "\n")
        verify_zip(source_zip)
        with zipfile.ZipFile(source_zip) as archive:
            expected = {source_prefix + filename for filename in selected}
            actual = {name for name in archive.namelist() if not name.endswith("/")}
            if actual != expected | {source_prefix + "SOURCE_REVISION", source_prefix + "BUILD_METADATA.json"}:
                raise PackagingError("The source archive does not contain exactly the committed source allowlist plus build metadata.")
        hashes = {path.name: digest(path) for path in (app_zip, source_zip)}
        checksums.write_text("".join(f"{value}  {name}\n" for name, value in hashes.items()), encoding="utf-8")
        metadata.write_text(json.dumps({**build_metadata, "artifacts": hashes}, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        # Guard against source/bundle edits during compression or concurrent packagers.
        if clean_revision() != revision or bundle_identity(bundle, revision) != identity:
            raise PackagingError("Source or app identity changed during packaging; no release was published.")
        verify_signature(bundle)
        published = []
        try:
            for name in names:
                destination = output / name
                # Atomic creation without replacement, on this same filesystem.
                os.link(scratch / name, destination)
                published.append(destination)
        except OSError as error:
            for path in published:
                path.unlink()
            raise PackagingError(f"Could not publish immutable release artifacts: {error}") from error

    print(f"Verified preview {identity['version']} ({identity['build']}) from {revision}")
    for name in names:
        print(output / name)
    print("Certificate signature verified. Notarization was not assessed; this is a preview, not a notarized release.")


if __name__ == "__main__":
    try:
        main()
    except (PackagingError, OSError, zipfile.BadZipFile) as error:
        print(f"Packaging stopped: {error}", file=sys.stderr)
        sys.exit(1)
