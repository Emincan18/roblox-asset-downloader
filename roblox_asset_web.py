"""Roblox Asset Downloader als lokale Webseite.

Start:  python roblox_asset_web.py   (oder start.bat doppelklicken)
Öffnet http://127.0.0.1:8765 im Browser. ID oder Link eingeben, Download klicken.

Neue und private Assets brauchen den eigenen .ROBLOSECURITY-Cookie in cookie.txt
neben diesem Script (siehe roblox_asset_downloader.py).
"""

import csv
import hashlib
import io
import json
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import webbrowser
import zipfile
import zlib
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from roblox_asset_downloader import extract_ids, fetch, fetch_many, guess_ext, load_cookie, parse_place

PORT = 8765
DOWNLOADS = Path(__file__).with_name("downloads")
ASSET_TYPES = {1: "Image", 2: "T-Shirt", 3: "Audio", 4: "Mesh", 8: "Hat", 10: "Model", 11: "Shirt", 12: "Pants",
               13: "Decal", 24: "Animation", 38: "Plugin", 40: "MeshPart", 41: "Hair", 42: "Face", 43: "Neck",
               44: "Shoulder", 45: "Front", 46: "Back", 47: "Waist", 61: "Emote", 62: "Video"}


@lru_cache(maxsize=4096)
def asset_details(asset_id):
    """Economy-Details eines Assets (Name, Typ, Ersteller), ohne Treffer ein leeres Dict."""
    try:
        url = f"https://economy.roblox.com/v2/assets/{asset_id}/details"
        with urllib.request.urlopen(url, timeout=10) as r:
            return json.load(r)
    except Exception:
        return {}


def bulk_details(ids):
    """Name, Typ und User-Ersteller für viele IDs über develop.roblox.com, 50 pro Anfrage (braucht cookie.txt).
    Fehlende IDs fehlen im Ergebnis; der Aufrufer fragt die einzeln über economy nach."""
    cookie = load_cookie()
    if not cookie:
        return {}

    def chunk(part):
        req = urllib.request.Request("https://develop.roblox.com/v1/assets?assetIds=" + ",".join(part),
                                     headers={"Cookie": ".ROBLOSECURITY=" + cookie, "User-Agent": "Roblox/WinInet"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.load(r).get("data", [])
        except Exception:
            return []

    out = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        for rows in pool.map(chunk, [ids[i:i + 50] for i in range(0, len(ids), 50)]):
            for d in rows:
                creator = d.get("creator") or {}
                out[str(d["id"])] = {"name": d.get("name") or str(d["id"]), "type": d.get("type") or "",
                                     "creator": creator.get("targetId") if creator.get("type") == "User" else None}
    return out


def asset_info(asset_id):
    """Name und Typ für den Dateinamen. Ohne Treffer nur die ID."""
    d = asset_details(asset_id)
    return d.get("Name") or "", ASSET_TYPES.get(d.get("AssetTypeId"), "")


def safe_name(name):
    return re.sub(r'[\\/:*?"<>|]+', "", name).strip(" .")[:60]  # kein Pfad raus aus downloads/


def safe_dir(folder):
    """downloads/ oder ein Unterordner davon, wird angelegt."""
    out = DOWNLOADS / safe_name(folder) if safe_name(folder) else DOWNLOADS
    out.mkdir(parents=True, exist_ok=True)
    return out


API_KEY_FILE = Path(__file__).with_name("apikey.txt")
OPEN_CLOUD = "https://apis.roblox.com/assets/v1/"


def open_cloud(path, key, body=None, ctype=None):
    req = urllib.request.Request(OPEN_CLOUD + path, data=body, headers={"x-api-key": key})
    if ctype:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        hint = {401: "API-Key ungültig oder abgelaufen", 403: "API-Key hat keine Assets-Rechte oder falsche IP"}.get(e.code, "")
        raise RuntimeError(f"Open Cloud HTTP {e.code} {hint}: {e.read().decode('utf-8', 'ignore')[:200]}")


# Endung aus guess_ext: (assetType für Open Cloud, Content-Type). Bilder laufen als Decal, siehe upload_asset.
UPLOAD_TYPES = {
    "png": ("Decal", "image/png"), "jpg": ("Decal", "image/jpeg"),
    "rbxm": ("Animation", "model/x-rbxm"), "rbxmx": ("Animation", "model/x-rbxmx"),
    "mesh": ("Mesh", "model/x-file-mesh-data"),
    "ogg": ("Audio", "audio/ogg"), "mp3": ("Audio", "audio/mpeg"), "wav": ("Audio", "audio/wav"), "flac": ("Audio", "audio/flac"),
}


def create_asset(asset_type, name, data, filename, ctype, user_id):
    """Lädt Bytes per Open Cloud (apikey.txt) unter dem eigenen Account hoch. Gibt die neue Asset-ID."""
    key = API_KEY_FILE.read_text("utf-8").strip() if API_KEY_FILE.is_file() else ""
    if not key:
        raise RuntimeError("apikey.txt fehlt. Siehe README: Hochladen einrichten")
    boundary = uuid.uuid4().hex
    request = json.dumps({"assetType": asset_type, "displayName": name[:50], "description": asset_type,
                          "creationContext": {"creator": {"userId": str(user_id)}}})
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n{request}\r\n'
            f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{filename}"\r\n'
            f'Content-Type: {ctype}\r\n\r\n').encode() + data + f"\r\n--{boundary}--\r\n".encode()
    op = open_cloud("assets", key, body, f"multipart/form-data; boundary={boundary}")
    for _ in range(30):  # Roblox verarbeitet den Upload asynchron
        if op.get("done"):
            break
        time.sleep(1)
        op = open_cloud(op["path"], key)
    if not op.get("done"):
        raise RuntimeError("Roblox braucht zu lange, gleich nochmal versuchen")
    if "response" not in op:
        raise RuntimeError(f"Roblox hat den Upload abgelehnt: {json.dumps(op.get('error', op))[:200]}")
    return str(op["response"]["assetId"])


# Schon hochgeladene Animationen (alte ID -> neue ID je User), damit nichts doppelt hochgeladen wird.
UPLOADS_FILE = Path(__file__).with_name("uploads.json")
UPLOADS_LOCK = threading.Lock()  # das Plugin lädt mehrere gleichzeitig hoch


def known_upload(cache_key):
    with UPLOADS_LOCK:
        try:
            return json.loads(UPLOADS_FILE.read_text("utf-8")).get(cache_key)
        except (OSError, ValueError):
            return None


def remember_upload(cache_key, new_id):
    with UPLOADS_LOCK:
        try:
            done = json.loads(UPLOADS_FILE.read_text("utf-8"))
        except (OSError, ValueError):
            done = {}
        done[cache_key] = new_id
        UPLOADS_FILE.write_text(json.dumps(done, indent=1), "utf-8")


def upload_animation_file(data, user_id, name=""):
    """Lädt eine KeyframeSequence, die das Plugin als .rbxm schickt, als eigene Animation hoch.
    Gleiche Datei wird nur einmal hochgeladen. Gibt die neue ID."""
    if not data.startswith(b"<roblox"):
        raise ValueError("Keine Roblox-Datei angekommen.")
    cache_key = f"{user_id}:sha1:{hashlib.sha1(data).hexdigest()}"
    new_id = known_upload(cache_key)
    if not new_id:
        new_id = create_asset("Animation", safe_name(name) or "Animation", data, "animation.rbxm", "model/x-rbxm", user_id)
        remember_upload(cache_key, new_id)
    return new_id


def upload_animation(asset_id, user_id, place=None, name=""):
    """Lädt eine fremde Animation herunter und als eigene Animation neu hoch. Gibt die neue ID."""
    cache_key = f"{user_id}:{asset_id}"
    if known_upload(cache_key):
        return known_upload(cache_key)
    data, err = fetch(asset_id, load_cookie(), place)
    if err:
        raise RuntimeError(err)
    ext = guess_ext(data)
    if ext not in ("rbxm", "rbxmx"):
        raise RuntimeError(f"Keine Animation ({ext})")
    title = safe_name(name) or safe_name(asset_info(asset_id)[0]) or "Animation"
    new_id = create_asset("Animation", title, data, f"animation.{ext}", "model/x-rbxm", user_id)
    remember_upload(cache_key, new_id)
    return new_id


def upload_asset(asset_id, user_id, place=None):
    """Lädt ein fremdes Bild, eine Animation, einen Sound oder ein Mesh herunter und unter dem eigenen
    Account neu hoch (Open Cloud, apikey.txt). Gibt die neue ID zurück, die in den Eigenschaften funktioniert."""
    data, err = fetch(asset_id, load_cookie(), place)
    if err:
        raise RuntimeError(err)
    ext = guess_ext(data)
    if ext in ("rbxm", "rbxmx") and b"KeyframeSequence" not in data and b"CurveAnimation" not in data:
        raise RuntimeError("Model, keine Animation: Models lädt das Plugin nicht neu hoch")
    if ext not in UPLOAD_TYPES:
        raise RuntimeError(f"Dieser Typ geht nicht hoch ({ext})")
    asset_type, ctype = UPLOAD_TYPES[ext]
    name = safe_name(asset_info(asset_id)[0]) or asset_type
    new_id = create_asset(asset_type, name, data, f"asset.{ext}", ctype, user_id)
    return new_id if asset_type != "Decal" else image_id(new_id)


def image_id(decal_id):
    # Open Cloud gibt die Decal-ID. Texturen brauchen die Bild-ID darin; die steht im Decal-Asset selbst.
    for _ in range(5):
        decal, err = fetch(decal_id, load_cookie())
        if not err:
            if guess_ext(decal) in ("png", "jpg"):
                return decal_id
            inner = [i for i in extract_ids(decal.decode("latin-1")) if i != decal_id]
            if inner:
                return inner[0]
        time.sleep(2)
    return decal_id


LOGO_FILE = Path(__file__).with_name("studio-plugin") / "logo.png"
_logo_cache = None


def png_rgba(data):
    """Liest ein 8-Bit-RGBA-PNG ohne Zusatzpakete. Gibt (Breite, Höhe, rohe RGBA-Bytes)."""
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        kind, chunk = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height = int.from_bytes(chunk[0:4], "big"), int.from_bytes(chunk[4:8], "big")
            if chunk[8] != 8 or chunk[9] != 6 or chunk[12] != 0:
                raise ValueError("Logo muss ein 8-Bit-RGBA-PNG ohne Interlacing sein")
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length
    raw, stride = zlib.decompress(idat), width * 4
    out, prev = bytearray(), bytearray(stride)
    for y in range(height):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out += line
        prev = line
    return width, height, bytes(out)


def plugin_logo():
    """Logo für den Kopf des Plugins als rohe Pixel (das Plugin zeichnet sie in ein EditableImage).
    So muss das Bild nicht zu Roblox hochgeladen werden. Einmal gelesen, dann aus dem Speicher."""
    global _logo_cache
    if _logo_cache is None:
        _logo_cache = png_rgba(LOGO_FILE.read_bytes())
    return _logo_cache


def file_name(asset_id, data, name=None):
    if name is None:
        name, _ = asset_info(asset_id)
    name = re.sub(r'[\\/:*?"<>|]+', "", name).strip()[:60]
    return f"{name} ({asset_id}).{guess_ext(data)}" if name else f"{asset_id}.{guess_ext(data)}"


class Handler(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="application/json", filename=None, extra=None):
        self.send_response(code)
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if filename:
            self.send_header("Content-Disposition", "attachment; filename*=UTF-8''" + urllib.parse.quote(filename))
            self.send_header("X-Filename", urllib.parse.quote(filename))
        self.end_headers()
        self.wfile.write(body)

    def error(self, code, msg):
        self.send(code, json.dumps({"error": msg}).encode())

    def foreign(self, path):
        """Plugin-Endpoints laden hoch und schreiben Dateien. Fremde Webseiten können den
        eigenen Header nicht mitschicken (Browser verlangt dafür CORS), also nur das Plugin."""
        if path.startswith("/api/plugin") and self.headers.get("X-Asset-Downloader") != "plugin":
            self.error(403, "Nur für das Studio-Plugin.")
            return True
        return False

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(url.query)
        if self.foreign(url.path):
            return
        if url.path == "/":
            self.send(200, PAGE.encode(), "text/html; charset=utf-8")
        elif url.path == "/api/status":
            self.send(200, json.dumps({"login": bool(load_cookie())}).encode())
        elif url.path == "/api/download":
            ids = extract_ids(q.get("q", [""])[0], bare=True)
            if not ids:
                return self.error(400, "Keine gültige Asset-ID gefunden.")
            data, err = fetch(ids[0], load_cookie(), parse_place(q.get("place", [""])[0]))
            if err:
                return self.error(502, err)
            self.send(200, data, "application/octet-stream", file_name(ids[0], data))
        elif url.path == "/api/plugin-upload":
            # Plugin: Bild, Animation, Sound oder Mesh unter eigenem Namen neu hochladen (Studio selbst darf das nicht).
            ids = extract_ids(q.get("q", [""])[0], bare=True)
            user = q.get("user", [""])[0]
            if not ids or not user.isdigit():
                return self.error(400, "ID oder User fehlt.")
            try:
                new_id = upload_asset(ids[0], user, parse_place(q.get("place", [""])[0]))
            except Exception as e:
                return self.error(502, str(e))
            self.send(200, json.dumps({"id": new_id}).encode())
        elif url.path == "/api/plugin-upload-anim":
            # Plugin: Animation unter eigenem Account neu hochladen. name = Name des Animation-Objekts.
            ids = extract_ids(q.get("q", [""])[0], bare=True)
            user = q.get("user", [""])[0]
            if not ids or not user.isdigit():
                return self.error(400, "ID oder User fehlt.")
            try:
                new_id = upload_animation(ids[0], user, parse_place(q.get("place", [""])[0]), q.get("name", [""])[0])
            except Exception as e:
                return self.error(502, str(e))
            self.send(200, json.dumps({"id": new_id}).encode())
        elif url.path == "/api/plugin":
            # Für die Vorschau im Studio-Plugin: liefert Bytes plus Name und Typ, speichert nichts.
            ids = extract_ids(q.get("q", [""])[0], bare=True)
            if not ids:
                return self.error(400, "Keine gültige Asset-ID gefunden.")
            data, err = fetch(ids[0], load_cookie(), parse_place(q.get("place", [""])[0]))
            if err:
                return self.error(502, err)
            name, kind = asset_info(ids[0])
            self.send(200, data, "application/octet-stream", file_name(ids[0], data, name),
                      {"X-Id": ids[0], "X-Name": urllib.parse.quote(name), "X-Type": kind, "X-Ext": guess_ext(data)})
        elif url.path == "/api/plugin-logo":
            try:
                width, height, pixels = plugin_logo()
            except (OSError, ValueError) as e:
                return self.error(404, str(e))
            self.send(200, pixels, "application/octet-stream", extra={"X-Width": str(width), "X-Height": str(height)})
        elif url.path == "/api/plugin-file":
            # Gegenstück zu plugin-store: Plugin holt eine gespeicherte Datei zurück (Senden an andere Place).
            path = safe_dir(q.get("folder", [""])[0]) / safe_name(q.get("file", [""])[0])
            if not path.is_file():
                return self.error(404, "Noch nichts gesendet.")
            self.send(200, path.read_bytes(), "application/octet-stream")
        else:
            self.error(404, "Nicht gefunden")

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if url.path not in ("/api/bulk", "/api/plugin-bulk", "/api/plugin-save", "/api/plugin-store", "/api/plugin-upload-anim-file"):
            return self.error(404, "Nicht gefunden")
        if self.foreign(url.path):
            return
        place = parse_place(urllib.parse.parse_qs(url.query).get("place", [""])[0])
        text = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "ignore")
        if url.path == "/api/plugin-upload-anim-file":
            # Plugin schickt eine KeyframeSequence als .rbxm (hex), die als eigene Animation hochgeladen wird.
            qs = urllib.parse.parse_qs(url.query)
            user = qs.get("user", [""])[0]
            if not user.isdigit():
                return self.error(400, "User fehlt.")
            try:
                new_id = upload_animation_file(bytes.fromhex(text.strip()), user, qs.get("name", [""])[0])
            except ValueError as e:
                return self.error(400, str(e) if "Roblox" in str(e) else "Datei kaputt angekommen.")
            except Exception as e:
                return self.error(502, str(e))
            return self.send(200, json.dumps({"id": new_id}).encode())
        if url.path == "/api/plugin-store":
            # Plugin schickt eine ganze VFX/Ordner-Auswahl als .rbxm (hex, weil Luau-Strings sonst nicht binär-sicher ankommen).
            folder = urllib.parse.parse_qs(url.query).get("folder", [""])[0]
            try:
                data = bytes.fromhex(text.strip())
            except ValueError:
                return self.error(400, "Datei kaputt angekommen.")
            file = safe_name(urllib.parse.parse_qs(url.query).get("file", [""])[0])
            path = safe_dir(folder) / (file or f"{safe_name(folder) or 'auswahl'}.rbxm")
            # Große Dateien kommen in Stücken: das erste überschreibt, die weiteren (append=1) hängen an.
            with open(path, "ab" if urllib.parse.parse_qs(url.query).get("append") else "wb") as f:
                f.write(data)
            return self.send(200, json.dumps({"path": str(path)}).encode())
        ids = extract_ids(text, bare=True)
        if ids and url.path == "/api/plugin-bulk":
            return self.plugin_bulk(ids)
        if ids and url.path == "/api/plugin-save":
            return self.plugin_save(ids, place, urllib.parse.parse_qs(url.query).get("folder", [""])[0])
        if not ids:
            return self.error(400, "Keine gültigen Asset-IDs gefunden.")
        results = fetch_many(ids, load_cookie(), place)
        buf, report = io.BytesIO(), io.StringIO()
        w = csv.writer(report)
        w.writerow(["id", "status", "datei / fehler"])
        ok = 0
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            for asset_id, data, err in results:
                if err:
                    w.writerow([asset_id, "fehler", err])
                    continue
                name = file_name(asset_id, data)
                z.writestr(name, data)
                w.writerow([asset_id, "ok", name])
                ok += 1
            z.writestr("report.csv", "﻿" + report.getvalue())  # BOM, damit Excel Umlaute erkennt
        self.send(200, buf.getvalue(), "application/zip", f"roblox-assets-{ok}.zip", {"X-Result": f"{ok}/{len(ids)}"})

    def plugin_bulk(self, ids):
        """Für das Studio-Plugin: nur Namen und Typen, damit die Liste schnell da ist.
        Vorschau und Download holt das Plugin erst auf Klick."""
        found = bulk_details(ids)
        missing = [i for i in ids if i not in found]
        with ThreadPoolExecutor(max_workers=6) as pool:
            for i, d in zip(missing, pool.map(asset_details, missing)):
                creator = d.get("Creator") or {}
                found[i] = {"name": d.get("Name") or i, "type": ASSET_TYPES.get(d.get("AssetTypeId"), ""),
                            "creator": creator.get("CreatorTargetId") if creator.get("CreatorType") == "User" else None}
        # creator: nur bei User-Assets gesetzt, damit das Plugin eigene Assets beim Neu-Hochladen überspringt.
        self.send(200, json.dumps([{"id": i, **found[i]} for i in ids]).encode())

    def plugin_save(self, ids, place, folder):
        """Für das Studio-Plugin: Assets in downloads/ oder einen Unterordner davon speichern."""
        out = safe_dir(folder)
        results = fetch_many(ids, load_cookie(), place)
        with ThreadPoolExecutor(max_workers=6) as pool:
            names = [n for n, _ in pool.map(asset_info, ids)]
        errors = []
        for (asset_id, data, err), name in zip(results, names):
            if err:
                errors.append({"id": asset_id, "error": err})
            else:
                (out / file_name(asset_id, data, name)).write_bytes(data)
        self.send(200, json.dumps({"saved": len(ids) - len(errors), "total": len(ids), "folder": str(out), "errors": errors}).encode())

    def log_message(self, *args):
        pass  # Konsole ruhig halten


PAGE = r"""<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Roblox Asset Downloader</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Familjen+Grotesk:wght@500;700&family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500&display=swap">
<style>
:root { --bg:#eef1f5; --panel:#fff; --fg:#18202b; --muted:#5d6878; --line:#d5dbe4; --accent:#0b6bcb; --accent-fg:#fff;
  --ok:#1f7a4a; --bad:#b4372f; --display:"Familjen Grotesk","Segoe UI",sans-serif; --body:"IBM Plex Sans","Segoe UI",sans-serif; --mono:"IBM Plex Mono",Consolas,monospace; }
@media (prefers-color-scheme: dark) { :root { --bg:#11161d; --panel:#19212b; --fg:#e4e9f0; --muted:#93a0b2; --line:#2b3542;
  --accent:#4ea1f3; --accent-fg:#0b1420; --ok:#5ccf8f; --bad:#f08077; color-scheme:dark; } }
body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.5 var(--body); }
.wrap { max-width:720px; margin:0 auto; padding:48px 16px; display:grid; gap:22px; }
h1 { font-family:var(--display); font-size:2.3rem; margin:0; line-height:1.1; }
.sub { color:var(--muted); margin:6px 0 0; }
.card { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:20px; display:grid; gap:12px; }
.label { font-size:.72rem; text-transform:uppercase; letter-spacing:.1em; color:var(--muted); }
.row { display:flex; gap:10px; flex-wrap:wrap; }
input, textarea { flex:1; min-width:0; font:14px var(--mono); background:var(--bg); color:var(--fg); border:1px solid var(--line); border-radius:8px; padding:12px; }
textarea { min-height:140px; resize:vertical; }
button { font:500 15px var(--body); background:var(--accent); color:var(--accent-fg); border:0; border-radius:8px; padding:12px 22px; cursor:pointer; }
button:disabled { opacity:.6; cursor:wait; }
:focus-visible { outline:2px solid var(--accent); outline-offset:2px; }
.msg { min-height:1.4em; font-size:.92rem; }
.msg.ok { color:var(--ok); } .msg.bad { color:var(--bad); }
.status { font-size:.85rem; color:var(--muted); }
.status b { color:var(--ok); } .status b.no { color:var(--bad); }
</style></head><body>
<div class="wrap">
  <header>
    <h1>Roblox Asset Downloader</h1>
    <p class="sub">Asset-ID oder Link eingeben und herunterladen. Models, Audio, Animationen, Accessories, Bilder und Meshes.</p>
    <p class="status" id="status"></p>
  </header>

  <div class="card">
    <label class="label" for="place">Spiel, aus dem die Assets stammen (optional)</label>
    <input id="place" placeholder="z. B. https://www.roblox.com/games/2809202155/..." autocomplete="off">
    <p class="status">Manche Animationen und Sounds gibt Roblox nur im Kontext ihres Spiels heraus. Ein Spiel, über das es einmal geklappt hat, merkt sich das Tool.</p>
  </div>

  <form class="card" id="one">
    <label class="label" for="q">Asset-ID oder Link</label>
    <div class="row">
      <input id="q" placeholder="z. B. 85757655830137" autocomplete="off" autofocus>
      <button id="oneBtn">Download</button>
    </div>
    <div class="msg" id="oneMsg"></div>
  </form>

  <form class="card" id="bulk">
    <label class="label" for="list">Bulk-Download: viele IDs oder Links, eine pro Zeile</label>
    <textarea id="list" placeholder="1843463175&#10;https://www.roblox.com/catalog/16630147/...&#10;rbxassetid://507766388"></textarea>
    <div class="row"><button id="bulkBtn">Alle als ZIP laden</button></div>
    <div class="msg" id="bulkMsg"></div>
  </form>
</div>
<script>
const $ = id => document.getElementById(id);
const place = () => "&place=" + encodeURIComponent($("place").value.trim());
try { $("place").value = localStorage.getItem("place") || ""; } catch {}
$("place").onchange = () => { try { localStorage.setItem("place", $("place").value.trim()); } catch {} };

fetch("/api/status").then(r => r.json()).then(s => {
  $("status").innerHTML = s.login
    ? "Login: <b>aktiv</b> (cookie.txt gefunden)"
    : 'Login: <b class="no">fehlt</b>. Neue Assets brauchen cookie.txt neben dem Script.';
});

async function save(res, msgEl, okText) {
  if (!res.ok) {
    const e = await res.json().catch(() => ({ error: "HTTP " + res.status }));
    msgEl.className = "msg bad"; msgEl.textContent = e.error; return;
  }
  const name = decodeURIComponent(res.headers.get("X-Filename") || "asset.bin");
  const a = document.createElement("a");
  a.href = URL.createObjectURL(await res.blob());
  a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
  msgEl.className = "msg ok"; msgEl.textContent = okText(name, res);
}

async function run(btn, msgEl, label, job) {
  btn.disabled = true; msgEl.className = "msg"; msgEl.textContent = label;
  try { await job(); } catch (e) { msgEl.className = "msg bad"; msgEl.textContent = "Server nicht erreichbar. Läuft roblox_asset_web.py?"; }
  btn.disabled = false;
}

$("one").onsubmit = e => {
  e.preventDefault();
  const q = $("q").value.trim();
  if (!q) return;
  run($("oneBtn"), $("oneMsg"), "Lade …", async () =>
    save(await fetch("/api/download?q=" + encodeURIComponent(q) + place()), $("oneMsg"), n => "Gespeichert: " + n));
};

$("bulk").onsubmit = e => {
  e.preventDefault();
  const text = $("list").value.trim();
  if (!text) return;
  run($("bulkBtn"), $("bulkMsg"), "Lade alle … (kann dauern)", async () =>
    save(await fetch("/api/bulk?x=1" + place(), { method: "POST", body: text }), $("bulkMsg"),
      (n, r) => (r.headers.get("X-Result") || "") + " geladen: " + n + " (Details in report.csv)"));
};
</script>
</body></html>"""


if __name__ == "__main__":
    # Windows erlaubt sonst einen zweiten Server auf demselben Port, der Anfragen abfängt.
    ThreadingHTTPServer.allow_reuse_address = False
    try:
        server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        webbrowser.open(f"http://127.0.0.1:{PORT}")
        raise SystemExit("Läuft schon in einem anderen Fenster. Browser wurde geöffnet.")
    url = f"http://127.0.0.1:{PORT}"
    print(f"Roblox Asset Downloader läuft auf {url}  (Strg+C beendet)")
    if "--no-browser" not in sys.argv:  # z. B. beim Neustart nur fürs Studio-Plugin
        webbrowser.open(url)
    server.serve_forever()
