#!/usr/bin/env python3
"""Retain entitlement metadata for AltStore to provision, then package an IPA.

Ad-hoc signatures carry the requested rights; they do not authorize installation
on an iPhone. AltStore must issue profiles and replace both signatures.
"""
import argparse
import hashlib
import json
import plistlib
import shutil
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path


def signed_entitlements(binary: Path) -> dict:
    data = binary.read_bytes()
    if struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("Expected a thin 64-bit device executable")
    count = struct.unpack_from("<I", data, 16)[0]
    position = 32
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, position)
        if command == 0x1D:  # LC_CODE_SIGNATURE
            offset, length = struct.unpack_from("<II", data, position + 8)
            signature = data[offset:offset + length]
            magic, total, blobs = struct.unpack_from(">III", signature)
            if magic != 0xFADE0CC0 or total > len(signature):
                raise ValueError("Invalid code-signature superblob")
            for index in range(blobs):
                slot, blob_offset = struct.unpack_from(">II", signature, 12 + 8 * index)
                if slot == 5:  # CSSLOT_ENTITLEMENTS
                    blob_magic, blob_length = struct.unpack_from(">II", signature, blob_offset)
                    if blob_magic != 0xFADE7171 or blob_offset + blob_length > total:
                        raise ValueError("Invalid XML entitlement blob")
                    return plistlib.loads(signature[blob_offset + 8:blob_offset + blob_length].rstrip(b"\0"))
        if size < 8:
            raise ValueError("Invalid Mach-O load command")
        position += size
    raise ValueError(f"Missing signed entitlement metadata: {binary.name}")


def package(app: Path, output: Path) -> dict:
    output = output.resolve(); output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sweep-package-") as temp:
        root = Path(temp); payload = root / "Payload"; payload.mkdir()
        copied = payload / app.name; shutil.copytree(app, copied, symlinks=True)
        bundles = [copied / "PlugIns/SweepShare.appex", copied]
        infos = [plistlib.loads((bundle / "Info.plist").read_bytes()) for bundle in bundles]
        group = infos[-1]["SweepAppGroupIdentifier"]
        if not group.startswith("group.") or any(info["SweepAppGroupIdentifier"] != group for info in infos):
            raise ValueError("App and extension must request the same group")
        if infos[0]["CFBundleShortVersionString"] != infos[1]["CFBundleShortVersionString"]:
            raise ValueError("App/extension versions differ")
        requested = {"com.apple.security.application-groups": [group]}
        entitlement_file = root / "entitlements.plist"
        entitlement_file.write_bytes(plistlib.dumps(requested))
        verified = []
        for bundle, info in zip(bundles, infos):
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none",
                            "--generate-entitlement-der", "--entitlements", str(entitlement_file), str(bundle)], check=True)
            actual = signed_entitlements(bundle / info["CFBundleExecutable"])
            if actual.get("com.apple.security.application-groups") != [group]:
                raise ValueError(f"Signed group declaration missing in {bundle.name}")
            verified.append({"bundle_id": info["CFBundleIdentifier"], "app_groups": actual["com.apple.security.application-groups"]})
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(copied)], check=True)
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(payload.rglob("*")):
                if file.is_file():
                    archive.write(file, file.relative_to(root).as_posix())
        with zipfile.ZipFile(output) as archive:
            if archive.testzip() is not None:
                raise ValueError("IPA CRC validation failed")
        digest = hashlib.sha256(output.read_bytes()).hexdigest()
        (output.parent / "SHA256.txt").write_text(f"{digest}  {output.name}\n")
        result = {"ipa": output.name, "version": infos[-1]["CFBundleShortVersionString"],
                  "build": infos[-1]["CFBundleVersion"], "sha256": digest, "bundles": verified,
                  "signing": "ad-hoc entitlement metadata only; AltStore signing and profiles required for installation"}
        (output.parent / "SIGNING-METADATA.json").write_text(json.dumps(result, indent=2) + "\n")
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(package(args.app, args.output), indent=2))
