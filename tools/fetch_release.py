#!/usr/bin/env python3
"""Fetch usque release assets through the local proxy and verify SHA256.

Usage:
  python tools/fetch_release.py            # list assets only
  python tools/fetch_release.py --download mipsle arm64 amd64
"""
import hashlib
import json
import os
import sys
import urllib.request

TAG = "v4.2.1"
REPO = "Diniboy1123/usque"
PROXY = "http://192.168.1.127:1080"
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "dist")

os.makedirs(OUT, exist_ok=True)
opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({"http": PROXY, "https": PROXY})
)
opener.addheaders = [("User-Agent", "usque-deploy-guide")]


def get(url: str, dest: str | None = None) -> bytes:
    with opener.open(url, timeout=120) as r:
        data = r.read()
    if dest:
        with open(dest, "wb") as f:
            f.write(data)
    return data


def main() -> int:
    api = f"https://api.github.com/repos/{REPO}/releases/tags/{TAG}"
    rel = json.loads(get(api))
    print(f"tag={rel['tag_name']}  published={rel['published_at']}  assets={len(rel['assets'])}")
    assets = {a["name"]: a for a in rel["assets"]}
    for name in sorted(assets):
        a = assets[name]
        print(f"  {name:40s} {a['size']:>9d}  {a.get('digest') or ''}")

    # checksums.txt is authoritative
    txt = get(assets["checksums.txt"]["browser_download_url"], os.path.join(OUT, "checksums.txt"))
    sums = {}
    for line in txt.decode().splitlines():
        line = line.strip()
        if not line:
            continue
        digest, fname = line.split(None, 1)
        sums[fname.strip().lstrip("*")] = digest
    print(f"\nchecksums.txt entries: {len(sums)}")

    wanted = [a for a in sys.argv[1:] if a != "--download"]
    if not wanted:
        print("\n(pass --download <arch> ... to fetch, e.g. mipsle arm64 amd64)")
        return 0

    rc = 0
    for arch in wanted:
        name = f"usque_{TAG.lstrip('v')}_linux_{arch}.zip"
        if name not in assets:
            print(f"[MISS] {name} not present in release")
            rc = 1
            continue
        path = os.path.join(OUT, name)
        get(assets[name]["browser_download_url"], path)
        h = hashlib.sha256(open(path, "rb").read()).hexdigest()
        expect = sums.get(name)
        if expect and h == expect:
            print(f"[ OK ] {name}  sha256={h}  ({os.path.getsize(path)} bytes)")
        else:
            print(f"[FAIL] {name}  sha256={h} != {expect}")
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())