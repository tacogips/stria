#!/usr/bin/env python3
"""Assign the exported Stria build to its existing internal TestFlight group."""
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def encoded(value):
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def token():
    if os.environ.get("APP_STORE_CONNECT_API_KEY_TYPE") != "individual":
        raise SystemExit("This task requires the project's individual App Store Connect API key.")
    payload = {"aud": "appstoreconnect-v1", "sub": "user", "iat": int(time.time()), "exp": int(time.time()) + 600}
    header = {"alg": "ES256", "kid": os.environ["APP_STORE_CONNECT_API_KEY_ID"], "typ": "JWT"}
    message = encoded(json.dumps(header).encode()) + "." + encoded(json.dumps(payload).encode())
    with tempfile.NamedTemporaryFile(mode="w", suffix=".p8") as stream:
        stream.write(os.environ["APP_STORE_CONNECT_API_PRIVATE_KEY"].replace("\\n", "\n"))
        stream.flush()
        signature = subprocess.run(["openssl", "dgst", "-sha256", "-sign", stream.name],
                                   input=message.encode(), capture_output=True, check=True).stdout
    position = 2 + (signature[1] & 127) if signature[1] & 128 else 2
    parts = []
    for _ in range(2):
        assert signature[position] == 2
        length = signature[position + 1]
        position += 2
        parts.append(int.from_bytes(signature[position:position + length], "big").to_bytes(32, "big"))
        position += length
    return message + "." + encoded(b"".join(parts))


def request(path, method="GET", body=None):
    headers = {"Authorization": "Bearer " + token(), "Content-Type": "application/json"}
    req = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/" + path,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            data = response.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as error:
        raise SystemExit(f"App Store Connect request failed: HTTP {error.code}") from None


def main():
    ipas = list((ROOT / ".build/ios-release/export").glob("*.ipa"))
    assert len(ipas) == 1, "Expected exactly one IPA"
    with zipfile.ZipFile(ipas[0]) as archive:
        names = [name for name in archive.namelist() if name.count("/") == 2 and name.endswith(".app/Info.plist")]
        assert len(names) == 1, "Expected app metadata"
        info = plistlib.loads(archive.read(names[0]))
    version, number = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    apps = request("apps?filter[bundleId]=me.tacogips.stria.mobile")["data"]
    assert len(apps) == 1, "Expected Stria's App Store Connect record"
    app = apps[0]["id"]
    response = request(f"builds?filter[app]={app}&filter[version]={number}&include=preReleaseVersion&limit=100")
    versions = {item["id"]: item["attributes"]["version"] for item in response.get("included", [])
                if item["type"] == "preReleaseVersions"}
    builds = [item for item in response["data"] if
              versions.get(item["relationships"]["preReleaseVersion"]["data"]["id"]) == version]
    assert len(builds) == 1, "Exact exported version/build not found"
    build = builds[0]
    assert build["attributes"]["processingState"] == "VALID", "Build processing incomplete"
    assert build["attributes"].get("usesNonExemptEncryption") is False, "Export compliance incomplete"
    groups = [item for item in request(f"apps/{app}/betaGroups")["data"]
              if item["attributes"]["name"] == "Stria Internal" and item["attributes"]["isInternalGroup"]]
    assert len(groups) == 1, "Expected existing internal tester group"
    group = groups[0]
    assigned = request(f"betaGroups/{group['id']}/builds?limit=100")["data"]
    if not any(item["id"] == build["id"] for item in assigned):
        request(f"builds/{build['id']}/relationships/betaGroups", "POST",
                {"data": [{"type": "betaGroups", "id": group["id"]}]})
        assigned = request(f"betaGroups/{group['id']}/builds?limit=100")["data"]
    assert any(item["id"] == build["id"] for item in assigned), "Exact group relationship unverified"
    print(f"TestFlight verified: {version} ({number}), VALID, compliance complete, Stria Internal")
    print("Automatic distribution:", group["attributes"].get("hasAccessToAllBuilds", False))
    print("Verified at:", datetime.now(timezone.utc).isoformat())


if __name__ == "__main__":
    main()
