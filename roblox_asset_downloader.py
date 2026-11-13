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


def get_json(url):
    """GET mit kurzer Wartezeit bei Rate-Limit (429). Gibt None bei Fehler."""
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=10) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code != 429:
                return None
            time.sleep(2 ** attempt)
        except Exception:
            return None
    return None


def games_of(kind, owner_id):
    """Root-Place-IDs aller Spiele einer Gruppe oder eines Users. Gruppen: accessFilter=1 liefert auch
    private Test-Places. Der User-Endpoint kennt nur 2 (öffentlich), 1 gibt HTTP 501."""
    access = 1 if kind == "groups" else 2
    d = get_json(f"https://games.roblox.com/v2/{kind}/{owner_id}/games?accessFilter={access}&limit=50&sortOrder=Desc")
    return [g["rootPlace"]["id"] for g in (d or {}).get("data", []) if g.get("rootPlace")]


def creator_places(asset_id):
    """Place-IDs, in deren Kontext Roblox ein gesperrtes Asset herausgeben könnte: Spiele des Erstellers.
    Gehört das Asset einem User, auch die Spiele der Gruppen, die er besitzt (oft liegt das Spiel dort)."""
    d = get_json(f"https://economy.roblox.com/v2/assets/{asset_id}/details")
    creator = (d or {}).get("Creator") or {}
    owner = creator.get("CreatorTargetId")
    if not owner:
        return []
    if creator.get("CreatorType") == "Group":
        return games_of("groups", owner)[:25]
    places = games_of("users", owner)
    roles = get_json(f"https://groups.roblox.com/v2/users/{owner}/groups/roles") or {}
    for entry in roles.get("data", []):
        if entry.get("role", {}).get("rank") == 255:  # 255 = Besitzer der Gruppe
            places += games_of("groups", entry["group"]["id"])
    return list(dict.fromkeys(places))[:25]


PLACES_FILE = Path(__file__).with_name("places.txt")
NOT_APPROVED = "Von Roblox nicht freigegeben (moderiert)"
PRIVATE_AUDIO = "Privates Audio"


def load_places():
    try:
        return [int(x) for x in PLACES_FILE.read_text("utf-8").split() if x.isdigit()]
    except OSError:
        return []


# Spiele, über die schon einmal ein gesperrtes Asset geladen wurde. Werden zuerst probiert.
KNOWN_PLACES = load_places()


def remember_place(place_id):
    if place_id in KNOWN_PLACES:
        KNOWN_PLACES.remove(place_id)
    KNOWN_PLACES.insert(0, place_id)
    del KNOWN_PLACES[20:]
    try:
        PLACES_FILE.write_text("\n".join(map(str, KNOWN_PLACES)), "utf-8")
    except OSError:
        pass


def parse_place(text):
    """Place-ID aus Zahl oder Spiel-Link wie roblox.com/games/2809202155/..."""
    m = re.search(r"games/(\d+)", text or "") or re.fullmatch(r"\s*(\d+)\s*", text or "")
    return int(m.group(1)) if m else None


def fetch(asset_id, cookie, place_id=None):
    """Lädt ein Asset. Gibt (bytes, None) oder (None, Fehlertext) zurück."""
    data, error = fetch_once(asset_id, cookie)
    if error and cookie and error.startswith("Kein Zugriff"):
        # Gesperrte Animationen/Audios gibt Roblox nur im Kontext eines Spiels heraus, das sie nutzen darf.
        tried = set()
        for candidates in ([place_id] if place_id else [], list(KNOWN_PLACES), creator_places(asset_id)):
            for place in candidates:
                if place in tried:
                    continue
                tried.add(place)
                data, retry_error = fetch_once(asset_id, cookie, place)
                if not retry_error:
                    remember_place(place)
                    return data, None
        details = get_json(f"https://economy.roblox.com/v2/assets/{asset_id}/details") or {}
        if details.get("AssetTypeId") == 3:
            # Private Audios gibt Roblox auch im Spielkontext nicht heraus, nur dem Besitzer und freigegebenen Spielen.
            # Fängt bewusst nicht mit "Kein Zugriff" an, sonst bekäme es im Bulk eine sinnlose zweite Runde.
            return None, (f"{PRIVATE_AUDIO} (Ersteller: {(details.get('Creator') or {}).get('Name', '?')}). "
                          "Roblox gibt es nur dem Besitzer oder Spielen, die er freigegeben hat.")
        if place_id is None:
            error += ". Tipp: Link des Spiels angeben, aus dem die ID stammt."
    return data, error


def fetch_many(ids, cookie, place_id=None):
    """Lädt viele Assets parallel. Fehlschläge bekommen eine zweite Runde,
    weil andere Assets inzwischen ein passendes Spiel gefunden haben können."""
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = dict(zip(ids, pool.map(lambda i: fetch(i, cookie, place_id), ids)))
    retry = [i for i, (_, err) in results.items() if err and err.startswith("Kein Zugriff") and KNOWN_PLACES]
    if retry:
        with ThreadPoolExecutor(max_workers=6) as pool:
            results.update(zip(retry, pool.map(lambda i: fetch(i, cookie, place_id), retry)))
    return [(i, *results[i]) for i in ids]


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
            if b"not approved" in e.read():
                return None, NOT_APPROVED
            reason = {401: "Login nötig (cookie.txt fehlt oder abgelaufen)", 403: "Kein Zugriff (Login fehlt oder Asset ist gesperrt)", 404: "Nicht gefunden"}.get(e.code, f"HTTP {e.code}")
            return None, reason
        except Exception as e:  # Netzwerkfehler sollen nicht den ganzen Bulk-Lauf stoppen
            return None, str(e)
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    return data, None


def main():
    ap = argparse.ArgumentParser(description="Roblox-Assets per ID oder Link in Massen herunterladen.")
    ap.add_argument("inputs", nargs="*", help="Dateien, Links oder IDs")
    ap.add_argument("-o", "--out", default="downloads")
    ap.add_argument("--bare", action="store_true")
    ap.add_argument("--place", help="Spiel-Link oder Place-ID, aus dem die Assets stammen")
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
    with open(out_dir / "report.csv", "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["id", "status", "info", "datei"])
        for asset_id, data, error in fetch_many(ids, cookie, parse_place(args.place)):
            if error:
                row = [asset_id, "fehler", error, ""]
            else:
                path = out_dir / f"{asset_id}.{guess_ext(data)}"
                path.write_bytes(data)
                from roblox_mesh import extra_files  # Meshes zusätzlich als OBJ und GLB
                for extra, extra_data in extra_files(data, path.name):
                    (out_dir / extra).write_bytes(extra_data)
                row = [asset_id, "ok", f"{len(data):,} Bytes", path.name]
                ok += 1
            w.writerow(row)
            print(f"  {row[0]:>14}  {row[1]:6}  {row[3] or row[2]}")
    print(f"Fertig: {ok}/{len(ids)} geladen. Liste: {out_dir / 'report.csv'}")


if __name__ == "__main__":
    assert extract_ids("rbxassetid://123456 roblox.com/catalog/77777/x rbxassetid://123456") == ["123456", "77777"]
    assert guess_ext(b"OggS....") == "ogg" and guess_ext(b"<roblox!x") == "rbxm"
    assert parse_place("https://www.roblox.com/games/2809202155/YBA") == 2809202155 and parse_place("") is None
    main()
