#!/usr/bin/env python3
"""Push AppStoreMedia/<lang>/ to App Store Connect (screenshots + app preview).

Credentials live outside the repository — by default
~/.appstoreconnect/sparktread.env with ASC_ISSUER_ID, ASC_KEY_ID, ASC_P8.
The ES256 token is signed with the `openssl` CLI, so this script needs no
third-party packages (the machine has neither PyJWT nor cryptography).

    python3 Tools/StoreMedia/asc_upload.py inspect            # read-only
    python3 Tools/StoreMedia/asc_upload.py upload --replace    # writes

6.9" media goes to APP_IPHONE_67 / IPHONE_67: App Store Connect files the
6.9-inch sizes (1320x2868 here) under the 6.7 enum — there is no …_69.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "io.icell.sparktread"
SCREENSHOT_DISPLAY_TYPE = "APP_IPHONE_67"
PREVIEW_TYPE = "IPHONE_67"
REPO = Path(__file__).resolve().parents[2]
MEDIA = REPO / "AppStoreMedia"


# --- credentials and token ---------------------------------------------------

def load_credentials(env_path: Path) -> tuple[str, str, Path]:
    values: dict[str, str] = {}
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"').strip("'")
    missing = [k for k in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_P8") if not values.get(k)]
    if missing:
        sys.exit(f"{env_path}: missing {', '.join(missing)}")
    p8 = Path(os.path.expanduser(values["ASC_P8"]))
    if not p8.is_file():
        sys.exit(f"private key not found: {p8}")
    return values["ASC_ISSUER_ID"], values["ASC_KEY_ID"], p8


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """ECDSA DER SEQUENCE{INTEGER r, INTEGER s} -> the 64-byte r||s JWS wants."""
    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("not a DER integer")
        length = der[index + 1]
        value = der[index + 2 : index + 2 + length].lstrip(b"\x00")
        parts.append(value.rjust(32, b"\x00"))
        index += 2 + length
    return b"".join(parts)


def make_token(issuer: str, key_id: str, p8: Path) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode())
        for part in (header, payload)
    ).encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(p8), "-binary"],
        input=signing_input, capture_output=True, check=True,
    ).stdout
    return f"{signing_input.decode()}.{b64url(der_to_raw(der))}"


class Client:
    """Minimal ASC client; the token is refreshed well inside its 20-min cap."""

    def __init__(self, issuer: str, key_id: str, p8: Path) -> None:
        self._issuer, self._key_id, self._p8 = issuer, key_id, p8
        self._token = ""
        self._token_born = 0.0

    @property
    def token(self) -> str:
        if not self._token or time.time() - self._token_born > 600:
            self._token = make_token(self._issuer, self._key_id, self._p8)
            self._token_born = time.time()
        return self._token

    def request(self, method: str, path: str, body: dict | None = None) -> dict:
        url = path if path.startswith("http") else f"{API}{path}"
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"Bearer {self.token}")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise SystemExit(f"{method} {url} -> {error.code}\n{detail}") from None

    def all_pages(self, path: str) -> list[dict]:
        items: list[dict] = []
        while path:
            page = self.request("GET", path)
            items.extend(page.get("data", []))
            path = page.get("links", {}).get("next", "")
        return items

    def put_bytes(self, operation: dict, chunk: bytes) -> None:
        request = urllib.request.Request(operation["url"], data=chunk,
                                        method=operation.get("method", "PUT"))
        for header in operation.get("requestHeaders", []):
            request.add_header(header["name"], header["value"])
        try:
            urllib.request.urlopen(request).read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise SystemExit(f"upload chunk -> {error.code}\n{detail}") from None


# --- helpers -----------------------------------------------------------------

def md5_hex(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def find_version(client: Client, version_string: str) -> dict:
    apps = client.request("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}").get("data", [])
    if not apps:
        sys.exit(f"no app record for {BUNDLE_ID} — create it on the website first")
    app = apps[0]
    print(f"app: {app['attributes']['name']}  (id {app['id']})")
    versions = client.all_pages(
        f"/v1/apps/{app['id']}/appStoreVersions"
        f"?filter[platform]=IOS&filter[versionString]={version_string}"
    )
    if not versions:
        have = [v["attributes"]["versionString"]
                for v in client.all_pages(f"/v1/apps/{app['id']}/appStoreVersions?limit=20")]
        sys.exit(f"no iOS version {version_string}; the record has: {', '.join(have) or '(none)'}")
    version = versions[0]
    print(f"version {version['attributes']['versionString']}  "
          f"state {version['attributes'].get('appStoreState')}  (id {version['id']})")
    return version


def match_locales(dirs: list[str], asc_locales: list[str]) -> dict[str, str]:
    """AppStoreMedia/<dir> -> the version's locale ('en' -> 'en-US', 'es' -> 'es-MX')."""
    pairs: dict[str, str] = {}
    for name in dirs:
        if name in asc_locales:
            pairs[name] = name
            continue
        candidates = [loc for loc in asc_locales
                      if loc == name or loc.split("-")[0] == name.split("-")[0]]
        if len(candidates) == 1:
            pairs[name] = candidates[0]
        elif not candidates:
            print(f"  ! {name}: no matching localization in the version — skipped")
        else:
            sys.exit(f"{name}: ambiguous, the version has {candidates}; "
                     f"rename the folder to the one you want")
    return pairs


def wait_for_delivery(client: Client, kind: str, asset_id: str, label: str) -> str:
    """Poll until Apple finishes processing; returns the final state."""
    for _ in range(60):
        attributes = client.request("GET", f"/v1/{kind}/{asset_id}")["data"]["attributes"]
        state = (attributes.get("assetDeliveryState") or {})
        if state.get("state") in ("COMPLETE", "FAILED"):
            if state.get("state") == "FAILED":
                print(f"    ! {label}: FAILED {state.get('errors')}")
            return state.get("state", "?")
        time.sleep(5)
    print(f"    ! {label}: still processing after 5 min")
    return "PENDING"


def upload_asset(client: Client, kind: str, path: Path, relationship: dict) -> str:
    """Reserve, PUT every operation, then commit with the checksum."""
    reserved = client.request("POST", f"/v1/{kind}", {
        "data": {
            "type": kind,
            "attributes": {"fileSize": path.stat().st_size, "fileName": path.name},
            "relationships": relationship,
        }
    })["data"]
    blob = path.read_bytes()
    operations = reserved["attributes"].get("uploadOperations") or []
    for operation in operations:
        offset, length = operation.get("offset", 0), operation.get("length", len(blob))
        client.put_bytes(operation, blob[offset : offset + length])
    client.request("PATCH", f"/v1/{kind}/{reserved['id']}", {
        "data": {
            "type": kind,
            "id": reserved["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": md5_hex(path)},
        }
    })
    return reserved["id"]


# --- commands ----------------------------------------------------------------

def localizations(client: Client, version_id: str) -> list[dict]:
    return client.all_pages(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")


def command_inspect(client: Client, version_string: str) -> None:
    version = find_version(client, version_string)
    locs = localizations(client, version["id"])
    print(f"\nlocalizations ({len(locs)}):")
    for loc in sorted(locs, key=lambda l: l["attributes"]["locale"]):
        locale = loc["attributes"]["locale"]
        shots = client.all_pages(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
        previews = client.all_pages(f"/v1/appStoreVersionLocalizations/{loc['id']}/appPreviewSets")
        counts = []
        for group in shots:
            members = client.all_pages(f"/v1/appScreenshotSets/{group['id']}/appScreenshots")
            counts.append(f"{group['attributes']['screenshotDisplayType']}x{len(members)}")
        for group in previews:
            members = client.all_pages(f"/v1/appPreviewSets/{group['id']}/appPreviews")
            counts.append(f"preview {group['attributes']['previewType']}x{len(members)}")
        print(f"  {locale:8} {', '.join(counts) if counts else '(no media)'}")
    folders = sorted(p.name for p in MEDIA.iterdir() if p.is_dir())
    print(f"\nlocal folders: {', '.join(folders)}")
    print("mapping:", match_locales(folders, [l["attributes"]["locale"] for l in locs]))


def ensure_set(client: Client, kind: str, parent_id: str, attributes: dict,
               existing: list[dict], key: str) -> dict:
    for group in existing:
        if group["attributes"][key] == attributes[key]:
            return group
    return client.request("POST", f"/v1/{kind}", {
        "data": {
            "type": kind,
            "attributes": attributes,
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": parent_id}}},
        }
    })["data"]


def command_upload(client: Client, version_string: str, replace: bool,
                   only: list[str], skip_previews: bool) -> None:
    version = find_version(client, version_string)
    state = version["attributes"].get("appStoreState")
    if state not in (None, "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                     "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"):
        sys.exit(f"version state {state} is not editable — stopping before any write")
    locs = localizations(client, version["id"])
    by_locale = {l["attributes"]["locale"]: l for l in locs}
    folders = sorted(p.name for p in MEDIA.iterdir() if p.is_dir())
    if only:
        folders = [f for f in folders if f in only]
    mapping = match_locales(folders, list(by_locale))

    for folder, locale in mapping.items():
        loc_id = by_locale[locale]["id"]
        print(f"\n== {folder} -> {locale}")

        shots = sorted((MEDIA / folder / "iphone").glob("*.png"))
        sets = client.all_pages(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
        group = ensure_set(client, "appScreenshotSets", loc_id,
                           {"screenshotDisplayType": SCREENSHOT_DISPLAY_TYPE},
                           sets, "screenshotDisplayType")
        current = client.all_pages(f"/v1/appScreenshotSets/{group['id']}/appScreenshots")
        if current and replace:
            for member in current:
                client.request("DELETE", f"/v1/appScreenshots/{member['id']}")
            print(f"  removed {len(current)} existing screenshot(s)")
        elif current:
            print(f"  {len(current)} screenshot(s) already there — pass --replace to overwrite")
            shots = []
        ids = []
        for path in shots:
            asset_id = upload_asset(client, "appScreenshots", path, {
                "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": group["id"]}}})
            ids.append(asset_id)
            print(f"  + {path.name}  {wait_for_delivery(client, 'appScreenshots', asset_id, path.name)}")
        if ids:  # pin the slot order to the file names
            client.request("PATCH", f"/v1/appScreenshotSets/{group['id']}/relationships/appScreenshots",
                           {"data": [{"type": "appScreenshots", "id": i} for i in ids]})

        if skip_previews:
            continue
        video = MEDIA / folder / "preview_iphone.mp4"
        if not video.is_file():
            print("  ! no preview_iphone.mp4")
            continue
        preview_sets = client.all_pages(f"/v1/appStoreVersionLocalizations/{loc_id}/appPreviewSets")
        preview_group = ensure_set(client, "appPreviewSets", loc_id,
                                   {"previewType": PREVIEW_TYPE},
                                   preview_sets, "previewType")
        current = client.all_pages(f"/v1/appPreviewSets/{preview_group['id']}/appPreviews")
        if current and replace:
            for member in current:
                client.request("DELETE", f"/v1/appPreviews/{member['id']}")
            print(f"  removed {len(current)} existing preview(s)")
        elif current:
            print("  preview already there — pass --replace to overwrite")
            continue
        asset_id = upload_asset(client, "appPreviews", video, {
            "appPreviewSet": {"data": {"type": "appPreviewSets", "id": preview_group["id"]}}})
        print(f"  + {video.name}  {wait_for_delivery(client, 'appPreviews', asset_id, video.name)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["inspect", "upload"])
    parser.add_argument("--version", default="0.1.0")
    parser.add_argument("--env", default="~/.appstoreconnect/sparktread.env")
    parser.add_argument("--replace", action="store_true",
                        help="delete the media already in a set before uploading")
    parser.add_argument("--only", default="", help="comma-separated folder names")
    parser.add_argument("--skip-previews", action="store_true")
    args = parser.parse_args()

    issuer, key_id, p8 = load_credentials(Path(os.path.expanduser(args.env)))
    client = Client(issuer, key_id, p8)
    if args.command == "inspect":
        command_inspect(client, args.version)
    else:
        command_upload(client, args.version, args.replace,
                       [s for s in args.only.split(",") if s], args.skip_previews)


if __name__ == "__main__":
    main()
