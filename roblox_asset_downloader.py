"""Roblox Asset Bulk Downloader.

Findet Asset-IDs in Text, Links und Dateien und lädt die Assets herunter.

Nutzung:
    python roblox_asset_downloader.py ids.txt mein_model.rbxmx
    python roblox_asset_downloader.py "rbxassetid://1843463175" 507766388
    python roblox_asset_downloader.py            (dann IDs/Links einfügen)

Optionen:
    -o ORDNER   Zielordner (Standard: downloads)
    --bare      Auch lose Zahlen (6-19 Ziffern) als IDs nehmen

Neue und private Assets brauchen einen Login. Dafür den eigenen .ROBLOSECURITY-Cookie
in cookie.txt neben diesem Script speichern oder die Umgebungsvariable ROBLOSECURITY
setzen (am besten von einem Zweit-Account).
"""

import argparse
import csv
import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# Gleiche Regeln wie im Asset ID Extractor (Artifact). Spezifische Muster zuerst.
RULES = [
    r"rbxassetid://(\d+)",
    r"rbxthumb://[^\s\"'<]*?id=(\d+)",
    r"roblox\.com/(?:v1/)?asset/?\?[^\s\"'<]*?\bid=(\d+)",
    r"roblox\.com/(?:catalog|library|bundles)/(\d+)",
    r"create\.roblox\.com/(?:store|marketplace)/asset/(\d+)",
    r"<url>\s*(\d+)\s*</url>",
    r"\b(?:AnimationId|SoundId|MeshId|TextureId?|Image|Texture|ShirtTemplate|PantsTemplate|Graphic)\b\D{0,20}?(\d{5,19})",
]
BARE = r"\b(\d{6,19})\b"

# Dateityp anhand der ersten Bytes erkennen.
MAGIC = [
    (b"OggS", "ogg"),
    (b"ID3", "mp3"),
    (b"\xff\xfb", "mp3"),
    (b"\xff\xf3", "mp3"),
    (b"\x89PNG", "png"),
    (b"\xff\xd8", "jpg"),
    (b"GIF8", "gif"),
    (b"DDS ", "dds"),
    (b"<roblox!", "rbxm"),
    (b"<roblox", "rbxmx"),
    (b"version ", "mesh"),
    (b"fLaC", "flac"),
]

URL = "https://assetdelivery.roblox.com/v1/asset/?id={}"


def extract_ids(text, bare=False):
    ids = {}  # dict behält die Reihenfolge und entfernt Duplikate
    for rule in RULES:
        for m in re.finditer(rule, text, re.IGNORECASE):
            ids.setdefault(m.group(1), None)
    if bare:
        for m in re.finditer(BARE, text):
            ids.setdefault(m.group(1), None)
    return list(ids)


def guess_ext(data):
    if data[:4] == b"RIFF":
        return "webp" if data[8:12] == b"WEBP" else "wav"
    for magic, ext in MAGIC:
        if data.startswith(magic):
            return ext
    return "bin"


def load_cookie():
    """Cookie aus Umgebungsvariable ROBLOSECURITY oder cookie.txt neben dem Script."""
    cookie = os.environ.get("ROBLOSECURITY", "").strip()
    file = Path(__file__).with_name("cookie.txt")
    if not cookie and file.is_file():
        cookie = file.read_text("utf-8").strip()
    return cookie.removeprefix(".ROBLOSECURITY=")


def creator_places(asset_id):
    """Place-IDs der Spiele des Asset-Erstellers (Gruppe oder User), höchstens 5."""
    try:
        with urllib.request.urlopen(f"https://economy.roblox.com/v2/assets/{asset_id}/details", timeout=10) as r:
            creator = json.load(r)["Creator"]
        kind = "groups" if creator["CreatorType"] == "Group" else "users"
        url = f"https://games.roblox.com/v2/{kind}/{creator['CreatorTargetId']}/games?accessFilter=2&limit=10"
        with urllib.request.urlopen(url, timeout=10) as r:
            return [g["rootPlace"]["id"] for g in json.load(r)["data"]][:5]
    except Exception:
        return []


def fetch(asset_id, cookie):
    """Lädt ein Asset. Gibt (bytes, None) oder (None, Fehlertext) zurück."""
    data, error = fetch_once(asset_id, cookie)
    if error and cookie and "Kein Zugriff" in error:
        # Gesperrte Animationen/Audios gibt Roblox im Kontext eines Spiels des Erstellers heraus.
        for place_id in creator_places(asset_id):
            data, retry_error = fetch_once(asset_id, cookie, place_id)
            if not retry_error:
                return data, None
    return data, error


def fetch_once(asset_id, cookie, place_id=None):
    req = urllib.request.Request(URL.format(asset_id), headers={"User-Agent": "Roblox/WinInet"})
    if cookie:
        req.add_header("Cookie", ".ROBLOSECURITY=" + cookie)
    if place_id:
        req.add_header("Roblox-Place-Id", str(place_id))
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            break
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 3:  # Rate-Limit: kurz warten, dann nochmal
                time.sleep(2 ** attempt * 2)
                continue
            reason = {401: "Login nötig (cookie.txt fehlt oder abgelaufen)", 403: "Kein Zugriff (Login fehlt oder Asset ist gesperrt)", 404: "Nicht gefunden"}.get(e.code, f"HTTP {e.code}")
            return None, reason
        except Exception as e:  # Netzwerkfehler sollen nicht den ganzen Bulk-Lauf stoppen
            return None, str(e)
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    return data, None


def download(asset_id, out_dir, cookie):
    data, error = fetch(asset_id, cookie)
    if error:
        return asset_id, "fehler", error, ""
    path = out_dir / f"{asset_id}.{guess_ext(data)}"
    path.write_bytes(data)
    return asset_id, "ok", f"{len(data):,} Bytes", path.name


def main():
    ap = argparse.ArgumentParser(description="Roblox-Assets per ID oder Link in Massen herunterladen.")
    ap.add_argument("inputs", nargs="*", help="Dateien, Links oder IDs")
    ap.add_argument("-o", "--out", default="downloads")
    ap.add_argument("--bare", action="store_true")
    args = ap.parse_args()

    parts = []
    for item in args.inputs:
        p = Path(item)
        if item.isdigit():  # reine Zahl als Argument ist immer eine ID
            parts.append("rbxassetid://" + item)
        else:
            parts.append(p.read_text("utf-8", errors="ignore") if p.is_file() else item)
    if not args.inputs:
        print("IDs oder Links einfügen. Leere Zeile startet den Download:")
        for line in sys.stdin:
            if not line.strip():
                break
            parts.append(line)
    text = "\n".join(parts)
    # Beim Einfügen sind lose Zahlen pro Zeile normal, also dort immer mitnehmen.
    ids = extract_ids(text, args.bare or not args.inputs)
    if not ids:
        sys.exit("Keine Asset-IDs gefunden.")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    cookie = load_cookie()
    print(f"{len(ids)} IDs gefunden. Lade nach {out_dir.resolve()} ...")

    ok = 0
    with ThreadPoolExecutor(max_workers=6) as pool, open(out_dir / "report.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "status", "info", "datei"])
        for row in pool.map(lambda i: download(i, out_dir, cookie), ids):
            w.writerow(row)
            ok += row[1] == "ok"
            print(f"  {row[0]:>14}  {row[1]:6}  {row[3] or row[2]}")
    print(f"Fertig: {ok}/{len(ids)} geladen. Liste: {out_dir / 'report.csv'}")


if __name__ == "__main__":
    assert extract_ids("rbxassetid://123456 roblox.com/catalog/77777/x rbxassetid://123456") == ["123456", "77777"]
    assert guess_ext(b"OggS....") == "ogg" and guess_ext(b"<roblox!x") == "rbxm"
    main()
