"""Roblox Asset Downloader als lokale Webseite.

Start:  python roblox_asset_web.py   (oder start.bat doppelklicken)
Öffnet http://127.0.0.1:47651 im Browser. ID oder Link eingeben, Download klicken.

Neue und private Assets brauchen den eigenen .ROBLOSECURITY-Cookie in cookie.txt
neben diesem Script (siehe roblox_asset_downloader.py).
"""

import csv
import hashlib
import io
import json
import os
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

from roblox_asset_downloader import extract_ids, fetch, fetch_many, guess_ext, ids_in_model, load_cookie, parse_place
from roblox_mesh import convert, extra_files

PORT = 47651  # 8765 benutzt das Blender-MCP-Addon, dann landeten Browser und Plugin bei Blender.
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


_auth = {"time": 0.0, "user": None, "cookie": None}


def auth_user():
    """Eingeloggter Roblox-User aus cookie.txt ({id, name}) oder None, wenn der Cookie fehlt oder abgelaufen ist.
    60 Sekunden gemerkt, damit die Webseite nicht bei jedem Aufruf Roblox fragt."""
    cookie = load_cookie()
    if cookie == _auth["cookie"] and time.time() - _auth["time"] < 60:
        return _auth["user"]
    user = None
    if cookie:
        req = urllib.request.Request("https://users.roblox.com/v1/users/authenticated",
                                     headers={"Cookie": ".ROBLOSECURITY=" + cookie, "User-Agent": "Roblox/WinInet"})
        try:
            with urllib.request.urlopen(req, timeout=10) as res:
                d = json.load(res)
                user = {"id": d.get("id"), "name": d.get("name")}
        except Exception:
            user = None
    _auth.update(time=time.time(), user=user, cookie=cookie)
    return user


def thumbnail(asset_id):
    """Vorschaubild-URL von Roblox (420x420), sonst None."""
    url = f"https://thumbnails.roblox.com/v1/assets?assetIds={asset_id}&returnPolicy=PlaceHolder&size=420x420&format=Png"
    try:
        with urllib.request.urlopen(url, timeout=10) as res:
            rows = json.load(res).get("data") or []
        return rows[0].get("imageUrl") if rows and rows[0].get("state") == "Completed" else None
    except Exception:
        return None


def zip_results(results, first=()):
    """ZIP aus (id, data, err)-Ergebnissen plus report.csv; Meshes zusätzlich als OBJ und GLB.
    first: (name, bytes)-Paare, die vorne in die ZIP kommen (z. B. das Model selbst). Gibt (bytes, ok)."""
    buf, report = io.BytesIO(), io.StringIO()
    w = csv.writer(report)
    w.writerow(["id", "status", "datei / fehler"])
    ok = 0
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in first:
            z.writestr(name, data)
        for asset_id, data, err in results:
            if err:
                w.writerow([asset_id, "fehler", err])
                continue
            name = file_name(asset_id, data, asset_info(asset_id)[0])
            z.writestr(name, data)
            for extra, extra_data in extra_files(data, name):  # Meshes zusätzlich als OBJ und GLB
                z.writestr(extra, extra_data)
            w.writerow([asset_id, "ok", name])
            ok += 1
        z.writestr("report.csv", "\ufeff" + report.getvalue())  # BOM, damit Excel Umlaute erkennt
    return buf.getvalue(), ok


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
        elif url.path == "/logo.png":
            self.send(200, LOGO_FILE.read_bytes(), "image/png") if LOGO_FILE.is_file() else self.error(404, "Kein Logo")
        elif url.path == "/api/status":
            try:
                import DracoPy  # noqa: F401
                draco = True
            except ImportError:
                draco = False
            user = auth_user()
            # login bleibt für ältere Plugins: nur "cookie.txt ist da". user sagt, ob Roblox den Cookie annimmt.
            self.send(200, json.dumps({"login": bool(load_cookie()), "user": user, "draco": draco,
                                       "apikey": API_KEY_FILE.is_file()}).encode())
        elif url.path == "/api/info":
            # Webseite: Name, Typ, Ersteller und Vorschaubild zu einer ID.
            ids = extract_ids(q.get("q", [""])[0], bare=True)
            if not ids:
                return self.error(400, "Keine gültige Asset-ID gefunden.")
            d = asset_details(ids[0])
            creator = (d.get("Creator") or {}).get("Name")
            self.send(200, json.dumps({"id": ids[0], "name": d.get("Name") or ids[0], "type": ASSET_TYPES.get(d.get("AssetTypeId"), ""),
                                       "creator": creator, "thumb": thumbnail(ids[0])}).encode())
        elif url.path == "/api/download":
            ids = extract_ids(q.get("q", [""])[0], bare=True)
            if not ids:
                return self.error(400, "Keine gültige Asset-ID gefunden.")
            data, err = fetch(ids[0], load_cookie(), parse_place(q.get("place", [""])[0]))
            if err:
                return self.error(502, err)
            name = file_name(ids[0], data, asset_info(ids[0])[0])
            wanted = q.get("format", [""])[0]
            if wanted in ("obj", "glb"):
                # Mesh als OBJ oder GLB statt .mesh (Blender, Studio > Import 3D)
                try:
                    obj, glb = convert(data, name.rsplit(".", 1)[0])
                except Exception as e:
                    return self.error(422, f"Kein umwandelbares Mesh ({e})")
                stem = name.rsplit(".", 1)[0]
                return self.send(200, obj.encode() if wanted == "obj" else glb, "application/octet-stream", f"{stem}.{wanted}")
            self.send(200, data, "application/octet-stream", name, {"X-Ext": guess_ext(data)})
        elif url.path == "/api/model":
            # Webseite: eine oder mehrere IDs (Models, Meshes, Texturen gemischt) -> eine ZIP. Models werden aufgeklappt:
            # alles, was darin steckt, kommt mit. Meshes zusätzlich als OBJ/GLB.
            ids = extract_ids(q.get("q", [""])[0], bare=True)
            if not ids:
                return self.error(400, "Keine gültige Asset-ID gefunden.")
            place = parse_place(q.get("place", [""])[0])
            results = fetch_many(ids, load_cookie(), place)
            inner, seen = [], set(ids)
            for _, data, err in results:
                if not err and guess_ext(data) in ("rbxm", "rbxmx"):
                    for i in ids_in_model(data):
                        if i not in seen:
                            seen.add(i)
                            inner.append(i)
            if inner:
                results += fetch_many(inner, load_cookie(), place)
            if len(ids) == 1 and not results[0][2]:
                zip_name = file_name(ids[0], results[0][1], asset_info(ids[0])[0]).rsplit(".", 1)[0] + ".zip"
            else:
                zip_name = f"roblox-assets-{len(results)}.zip"
            body, ok = zip_results(results)
            self.send(200, body, "application/zip", zip_name, {"X-Result": f"{ok}/{len(results)}"})
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
        body, ok = zip_results(fetch_many(ids, load_cookie(), place))
        self.send(200, body, "application/zip", f"roblox-assets-{ok}.zip", {"X-Result": f"{ok}/{len(ids)}"})

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
        errors, files = [], {}
        for (asset_id, data, err), name in zip(results, names):
            if err:
                errors.append({"id": asset_id, "error": err})
            else:
                target = file_name(asset_id, data, name)
                (out / target).write_bytes(data)
                files[asset_id] = [target]
                for extra, extra_data in extra_files(data, target):  # Meshes zusätzlich als OBJ und GLB
                    (out / extra).write_bytes(extra_data)
                    files[asset_id].append(extra)
        # files: welche Datei(en) zu welcher ID gehören, damit das Plugin eine model.json mit echten Dateinamen schreibt
        self.send(200, json.dumps({"saved": len(ids) - len(errors), "total": len(ids), "folder": str(out), "errors": errors,
                                   "files": files}).encode())

    def log_message(self, *args):
        pass  # Konsole ruhig halten


PAGE = r"""<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Stealmaxxing · Roblox Asset Downloader</title>
<link rel="icon" href="/logo.png">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;800&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
:root { color-scheme: dark;
  --bg:#000; --card:#1a1415; --field:#2b2022; --line:#40282b; --text:#fff; --muted:#b09ea0;
  --accent:#e21b26; --accent-hi:#ff3540; --thumb:#7a161e; --grey:#3e2e30; --ok:#30d158; --bad:#ff9f0a;
  --font:"Inter",system-ui,"Segoe UI",sans-serif; --mono:"JetBrains Mono",Consolas,monospace; }
* { box-sizing:border-box; }
[hidden] { display:none !important; }
body { margin:0; background:var(--bg); color:var(--text); font:15px/1.5 var(--font); -webkit-font-smoothing:antialiased; }
.wrap { max-width:760px; margin:0 auto; padding:24px 16px 64px; display:grid; gap:14px; }
.logo { width:100%; max-width:560px; justify-self:center; display:block; aspect-ratio:760/348; object-fit:contain; }
.logo-text { display:none; text-align:center; font-weight:800; font-size:2.4rem; color:var(--accent); letter-spacing:.04em; }
.pills { display:flex; flex-wrap:wrap; gap:8px; justify-content:center; }
.pill { display:inline-flex; align-items:center; gap:6px; background:var(--card); border:1px solid var(--line); border-radius:999px;
  padding:5px 12px; font-size:.82rem; color:var(--muted); }
.pill b { color:var(--text); font-weight:600; }
.dot { width:8px; height:8px; border-radius:50%; background:var(--muted); }
.dot.ok { background:var(--ok); } .dot.bad { background:var(--bad); }
.tabs { position:relative; display:flex; background:var(--card); border-radius:11px; padding:3px; }
.tabs button { flex:1; position:relative; z-index:1; background:none; border:0; color:var(--muted); font:600 14px var(--font);
  padding:9px 4px; border-radius:8px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:6px; transition:color .2s; }
.tabs button[aria-selected=true] { color:var(--text); }
.tabs .thumb { position:absolute; top:3px; bottom:3px; left:3px; background:var(--thumb); border-radius:8px;
  transition:transform .38s cubic-bezier(.22,1,.36,1), width .38s cubic-bezier(.22,1,.36,1); }
@media (prefers-reduced-motion:reduce) { .tabs .thumb { transition:none; } }
.page { display:none; gap:14px; animation:in .3s ease-out; } .page.on { display:grid; }
@keyframes in { from { opacity:0; transform:translateY(6px); } to { opacity:1; transform:none; } }
@media (prefers-reduced-motion:reduce) { .page { animation:none; } }
.card { background:var(--card); border-radius:16px; padding:18px; display:grid; gap:12px; }
.card h2 { margin:0; font-size:1.05rem; font-weight:800; }
.card p.sub { margin:-6px 0 0; color:var(--muted); font-size:.88rem; }
.row { display:flex; gap:8px; flex-wrap:wrap; }
.row > input { flex:1 1 220px; }
input, textarea { min-width:0; width:100%; font:14px var(--mono); background:var(--field); color:var(--text); border:1px solid transparent;
  border-radius:10px; padding:11px 12px; }
input::placeholder, textarea::placeholder { color:#86777a; }
textarea { min-height:130px; resize:vertical; }
input:focus, textarea:focus { border-color:var(--accent); outline:none; }
.btn { font:600 14px var(--font); border:0; border-radius:10px; padding:11px 18px; cursor:pointer; color:#fff; background:var(--grey);
  display:inline-flex; align-items:center; justify-content:center; gap:8px; transition:background .15s, transform .1s; }
.btn:hover { background:#52393c; } .btn:active { transform:scale(.98); }
.btn.main { background:var(--accent); } .btn.main:hover { background:var(--accent-hi); }
.btn:disabled { opacity:.55; cursor:wait; transform:none; }
.btn.wide { width:100%; }
:focus-visible { outline:2px solid var(--accent-hi); outline-offset:2px; }
svg.i { width:17px; height:17px; flex:none; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
.msg { min-height:1.2em; font-size:.9rem; color:var(--muted); white-space:pre-line; }
.msg.ok { color:var(--ok); } .msg.bad { color:var(--bad); }
details.place summary { cursor:pointer; color:var(--muted); font-size:.88rem; list-style:none; display:flex; align-items:center; gap:6px; }
details.place summary::-webkit-details-marker { display:none; }
details.place[open] summary { margin-bottom:10px; }
.preview { display:grid; grid-template-columns:180px 1fr; gap:16px; align-items:start; }
@media (max-width:560px) { .preview { grid-template-columns:1fr; } }
.media { aspect-ratio:1; background:var(--field); border-radius:12px; overflow:hidden; display:grid; place-items:center; color:var(--muted); font-size:.85rem; }
.media img { width:100%; height:100%; object-fit:contain; }
.media model-viewer { width:100%; height:100%; --poster-color:transparent; }
.media audio { width:92%; }
.meta { display:grid; gap:6px; min-width:0; }
.meta .name { font-size:1.15rem; font-weight:800; overflow-wrap:anywhere; }
.badge { display:inline-block; background:var(--thumb); color:#fff; border-radius:6px; padding:1px 8px; font-size:.78rem; font-weight:600; }
.meta .small { color:var(--muted); font-size:.85rem; font-family:var(--mono); }
.actions { display:flex; flex-wrap:wrap; gap:8px; margin-top:6px; }
.list { display:grid; gap:6px; max-height:420px; overflow:auto; }
.item { display:grid; grid-template-columns:auto 1fr auto; gap:10px; align-items:center; background:var(--field); border-radius:10px; padding:9px 12px; }
.item input { width:auto; accent-color:var(--accent); }
.item .n { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.item .t { color:var(--muted); font-size:.8rem; font-family:var(--mono); }
.item.done .t { color:var(--ok); } .item.fail .t { color:var(--bad); }
.listhead { display:flex; justify-content:space-between; align-items:center; color:var(--muted); font-size:.85rem; }
.link { background:none; border:0; color:var(--accent-hi); font:600 .85rem var(--font); cursor:pointer; padding:0; }
ul.facts { margin:0; padding-left:18px; color:var(--muted); font-size:.88rem; display:grid; gap:2px; }
.spin { animation:spin 1s linear infinite; } @keyframes spin { to { transform:rotate(360deg); } }
</style></head><body>
<div class="wrap">
  <img class="logo" src="/logo.png" alt="Stealmaxxing" onerror="this.style.display='none'; document.querySelector('.logo-text').style.display='block'">
  <div class="logo-text">STEALMAXXING</div>
  <div class="pills" id="pills"><span class="pill"><span class="dot"></span>Prüfe Server …</span></div>

  <div class="tabs" role="tablist" id="tabs"><div class="thumb" id="thumb"></div></div>

  <details class="place card">
    <summary><svg class="i" viewBox="0 0 24 24"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>
      Spiel-Link für gesperrte Assets (optional)</summary>
    <input id="place" placeholder="z. B. https://www.roblox.com/games/2809202155/..." autocomplete="off">
    <p class="sub" style="margin:0">Manche Animationen und Sounds gibt Roblox nur im Kontext ihres Spiels heraus. Ein Spiel, über das es einmal geklappt hat, merkt sich das Tool.</p>
  </details>

  <!-- Laden -->
  <section class="page" data-tab="Laden">
    <form class="card" id="loadForm">
      <h2>Asset laden</h2>
      <p class="sub">ID oder Link einfügen. Meshes drehen sich in 3D, Sounds spielen, Bilder erscheinen.</p>
      <div class="row">
        <input id="q" placeholder="z. B. 85757655830137" autocomplete="off" autofocus>
        <button class="btn main" id="loadBtn"><svg class="i" viewBox="0 0 24 24"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>Laden</button>
      </div>
      <div class="msg" id="loadMsg"></div>
    </form>
    <div class="card" id="previewCard" hidden>
      <div class="preview">
        <div class="media" id="media"></div>
        <div class="meta">
          <div class="name" id="pName"></div>
          <div><span class="badge" id="pType"></span></div>
          <div class="small" id="pInfo"></div>
          <div class="actions" id="pActions"></div>
          <div class="msg" id="pMsg"></div>
        </div>
      </div>
    </div>
  </section>

  <!-- Bulk -->
  <section class="page" data-tab="Bulk">
    <div class="card">
      <h2>Viele Assets auf einmal</h2>
      <p class="sub">Eine ID oder ein Link pro Zeile. Meshes kommen zusätzlich als OBJ und GLB.</p>
      <textarea id="list" placeholder="1843463175&#10;https://www.roblox.com/catalog/16630147/...&#10;rbxassetid://507766388"></textarea>
      <button class="btn main wide" id="listBtn"><svg class="i" viewBox="0 0 24 24"><path d="M3 12h.01M3 18h.01M3 6h.01M8 12h13M8 18h13M8 6h13"/></svg>Liste laden</button>
      <div class="msg" id="listMsg"></div>
    </div>
    <div class="card" id="bulkCard" hidden>
      <div class="listhead"><span id="bulkCount"></span><button class="link" id="toggleAll">Alle abwählen</button></div>
      <div class="list" id="bulkList"></div>
      <div class="row">
        <button class="btn main" id="zipBtn"><svg class="i" viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/></svg>Als ZIP</button>
        <input id="folder" placeholder="Ordnername (leer = downloads/)" style="flex:1 1 180px">
        <button class="btn" id="saveBtn"><svg class="i" viewBox="0 0 24 24"><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/></svg>In Ordner speichern</button>
      </div>
      <div class="msg" id="bulkMsg"></div>
    </div>
  </section>

  <!-- Model -->
  <section class="page" data-tab="Model">
    <form class="card" id="modelForm">
      <h2>Ganzes Model herunterladen</h2>
      <p class="sub">Model-ID, oder die IDs aus dem Plugin (Mesh, Texturen …) einfach alle hier rein. Du bekommst eine ZIP mit allem; Models werden aufgeklappt.</p>
      <div class="row">
        <input id="mq" placeholder="Model-ID oder mehrere IDs" autocomplete="off">
        <button class="btn main" id="modelBtn"><svg class="i" viewBox="0 0 24 24"><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/></svg>Alles als ZIP</button>
      </div>
      <ul class="facts">
        <li>das Model als .rbxm (Studio: Rechtsklick › Insert from File)</li>
        <li>jedes Mesh als .obj und .glb (Blender oder Studio › Import 3D, .glb mit Knochen)</li>
        <li>Texturen, Sounds und Animationen, dazu report.csv</li>
      </ul>
      <div class="msg" id="modelMsg"></div>
    </form>
  </section>

  <!-- Hochladen -->
  <section class="page" data-tab="Hochladen">
    <div class="card">
      <h2>Unter meinem Account hochladen</h2>
      <p class="sub">Fremde Bilder, Sounds, Meshes und Animationen laufen in deinem Spiel nicht. Hier lädst du sie unter deinem Account neu hoch und bekommst die neuen IDs. Braucht apikey.txt.</p>
      <textarea id="upList" placeholder="Eine ID pro Zeile"></textarea>
      <button class="btn main wide" id="upBtn"><svg class="i" viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m17 8-5-5-5 5"/><path d="M12 3v12"/></svg>Hochladen</button>
      <div class="msg" id="upMsg"></div>
      <div class="list" id="upResults"></div>
      <button class="btn" id="copyBtn" hidden><svg class="i" viewBox="0 0 24 24"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>Neue IDs kopieren (alt → neu)</button>
    </div>
  </section>
</div>
<script>
const $ = id => document.getElementById(id);
const H = { "X-Asset-Downloader": "plugin" }; // gleiche Seite, darf die Plugin-Endpunkte nutzen
const placeQ = () => "&place=" + encodeURIComponent($("place").value.trim());
let status = {};
try { $("place").value = localStorage.getItem("place") || ""; } catch {}
$("place").onchange = () => { try { localStorage.setItem("place", $("place").value.trim()); } catch {} };

// Tabs mit gleitendem Daumen wie im Plugin
const TABS = { Laden: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4|m7 10 5 5 5-5|M12 15V3", Bulk: "M3 12h.01M3 18h.01M3 6h.01M8 12h13M8 18h13M8 6h13",
  Model: "M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z|m3.3 7 8.7 5 8.7-5|M12 22V12",
  Hochladen: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4|m17 8-5-5-5 5|M12 3v12" };
const icon = d => '<svg class="i" viewBox="0 0 24 24">' + d.split("|").map(p => '<path d="' + p + '"/>').join("") + "</svg>";
for (const name in TABS) {
  const b = document.createElement("button");
  b.type = "button"; b.setAttribute("role", "tab"); b.innerHTML = icon(TABS[name]) + "<span>" + name + "</span>"; b.dataset.tab = name;
  b.onclick = () => show(name);
  $("tabs").appendChild(b);
}
function show(name) {
  document.querySelectorAll(".tabs button").forEach(b => b.setAttribute("aria-selected", b.dataset.tab === name));
  document.querySelectorAll(".page").forEach(p => p.classList.toggle("on", p.dataset.tab === name));
  const b = document.querySelector('.tabs button[data-tab="' + name + '"]');
  $("thumb").style.width = b.offsetWidth + "px";
  $("thumb").style.transform = "translateX(" + (b.offsetLeft - 3) + "px)";
  try { localStorage.setItem("tab", name); } catch {}
}
window.addEventListener("resize", () => show(document.querySelector(".tabs button[aria-selected=true]").dataset.tab));
let startTab = "Laden"; try { startTab = TABS[localStorage.getItem("tab")] ? localStorage.getItem("tab") : "Laden"; } catch {}
show(startTab);

function say(el, text, kind) { el.className = "msg" + (kind ? " " + kind : ""); el.textContent = text; }
async function errorText(res) { const e = await res.json().catch(() => ({})); return e.error || ("HTTP " + res.status); }
function busy(btn, on, text) {
  if (on) { btn.dataset.html = btn.innerHTML; btn.disabled = true;
    btn.innerHTML = '<svg class="i spin" viewBox="0 0 24 24"><path d="M21 12a9 9 0 1 1-6.22-8.56"/></svg>' + text; }
  else { btn.disabled = false; btn.innerHTML = btn.dataset.html; }
}
function saveBlob(blob, name) {
  const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 8000);
}
const fileName = res => decodeURIComponent(res.headers.get("X-Filename") || "asset.bin");

// Status oben: Login wirklich gültig, DracoPy, API-Key
async function loadStatus() {
  try { status = await (await fetch("/api/status")).json(); } catch { $("pills").innerHTML = '<span class="pill"><span class="dot bad"></span>Server nicht erreichbar: start.bat starten</span>'; return; }
  const pill = (ok, label, text) => '<span class="pill"><span class="dot ' + (ok ? "ok" : "bad") + '"></span>' + label + " <b>" + text + "</b></span>";
  $("pills").innerHTML =
    pill(!!status.user, "Login", status.user ? status.user.name : (status.login ? "abgelaufen: cookie.txt erneuern" : "fehlt: cookie.txt")) +
    pill(status.draco, "Meshes", status.draco ? "OBJ + GLB" : "pip install DracoPy") +
    pill(status.apikey, "Hochladen", status.apikey ? "bereit" : "apikey.txt fehlt");
}
loadStatus();

// Laden
let viewerReady;
function viewer() { return viewerReady ||= import("https://unpkg.com/@google/model-viewer@3.5.0/dist/model-viewer.min.js"); }
let current = null;
$("loadForm").onsubmit = async e => {
  e.preventDefault();
  const q = $("q").value.trim(); if (!q) return;
  busy($("loadBtn"), true, "Lade …"); say($("loadMsg"), "");
  try {
    const infoRes = await fetch("/api/info?q=" + encodeURIComponent(q));
    if (!infoRes.ok) { say($("loadMsg"), await errorText(infoRes), "bad"); return; }
    const info = await infoRes.json();
    const res = await fetch("/api/download?q=" + encodeURIComponent(q) + placeQ());
    if (!res.ok) { say($("loadMsg"), await errorText(res), "bad"); showPreview(info, null); return; }
    current = { info, blob: await res.blob(), name: fileName(res), ext: res.headers.get("X-Ext") || "" };
    showPreview(info, current);
  } catch { say($("loadMsg"), "Server nicht erreichbar. Läuft start.bat?", "bad"); }
  finally { busy($("loadBtn"), false); }
};
function btn(text, path, main, onclick) {
  const b = document.createElement("button"); b.type = "button"; b.className = "btn" + (main ? " main" : "");
  b.innerHTML = icon(path) + text; b.onclick = () => onclick(b); return b;
}
const DL = "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4|m7 10 5 5 5-5|M12 15V3";
async function showPreview(info, file) {
  $("previewCard").hidden = false;
  $("pName").textContent = info.name; $("pType").textContent = info.type || (file ? file.ext.toUpperCase() : "Asset");
  $("pInfo").textContent = "ID " + info.id + (info.creator ? " · von " + info.creator : "");
  say($("pMsg"), file ? "" : "Nur die Infos: Datei selbst nicht ladbar (siehe oben).", file ? "" : "bad");
  const media = $("media"); media.innerHTML = "";
  const actions = $("pActions"); actions.innerHTML = "";
  const thumb = () => { media.innerHTML = info.thumb ? '<img alt="" src="' + info.thumb + '">' : "Keine Vorschau"; };
  if (!file) { thumb(); return; }
  actions.append(btn("Herunterladen", DL, true, () => saveBlob(file.blob, file.name)));
  if (file.ext === "mesh") {
    for (const fmt of ["obj", "glb"]) actions.append(btn(fmt.toUpperCase(), DL, false, b => downloadUrl(b, "/api/download?format=" + fmt + "&q=" + info.id + placeQ())));
    media.textContent = "3D-Vorschau lädt …";
    try {
      await viewer();
      const glb = await fetch("/api/download?format=glb&q=" + info.id + placeQ());
      if (!glb.ok) throw 0;
      const mv = document.createElement("model-viewer");
      mv.src = URL.createObjectURL(await glb.blob()); mv.setAttribute("camera-controls", ""); mv.setAttribute("auto-rotate", "");
      mv.setAttribute("shadow-intensity", "0.6"); mv.setAttribute("exposure", "1.1"); mv.alt = info.name;
      media.innerHTML = ""; media.append(mv);
    } catch { thumb(); }
  } else if (["png", "jpg", "webp"].includes(file.ext)) {
    media.innerHTML = '<img alt="">'; media.firstChild.src = URL.createObjectURL(file.blob);
  } else if (["ogg", "mp3", "wav", "flac"].includes(file.ext)) {
    media.innerHTML = "<audio controls></audio>"; media.firstChild.src = URL.createObjectURL(file.blob);
  } else {
    thumb();
  }
  if ((info.type === "Model" || file.ext === "rbxm" || file.ext === "rbxmx") && !/Animation|Emote/.test(info.type))
    actions.append(btn("Model komplett (ZIP)", TABS.Model, false, b => downloadUrl(b, "/api/model?q=" + info.id + placeQ(), $("pMsg"))));
}
async function downloadUrl(b, url, msgEl) {
  busy(b, true, "Lade …");
  try {
    const res = await fetch(url);
    if (!res.ok) { say(msgEl || $("pMsg"), await errorText(res), "bad"); return; }
    saveBlob(await res.blob(), fileName(res));
    const r = res.headers.get("X-Result");
    say(msgEl || $("pMsg"), "Gespeichert: " + fileName(res) + (r ? " (" + r + " Assets darin)" : ""), "ok");
  } catch { say(msgEl || $("pMsg"), "Server nicht erreichbar.", "bad"); }
  finally { busy(b, false); }
}

// Bulk
let bulk = [];
$("listBtn").onclick = async () => {
  const text = $("list").value.trim(); if (!text) return;
  busy($("listBtn"), true, "Lade Liste …"); say($("listMsg"), "");
  try {
    const res = await fetch("/api/plugin-bulk?x=1" + placeQ(), { method: "POST", headers: H, body: text });
    if (!res.ok) { say($("listMsg"), await errorText(res), "bad"); return; }
    bulk = await res.json();
    $("bulkList").innerHTML = "";
    for (const it of bulk) {
      const row = document.createElement("label"); row.className = "item";
      row.innerHTML = '<input type="checkbox" checked><span class="n"></span><span class="t"></span>';
      row.querySelector(".n").textContent = it.name; row.querySelector(".t").textContent = (it.type || "Asset") + " · " + it.id;
      it.row = row; $("bulkList").append(row);
    }
    $("bulkCard").hidden = false; count();
  } catch { say($("listMsg"), "Server nicht erreichbar. Läuft start.bat?", "bad"); }
  finally { busy($("listBtn"), false); }
};
const chosen = () => bulk.filter(it => it.row.querySelector("input").checked);
function count() { $("bulkCount").textContent = chosen().length + " von " + bulk.length + " ausgewählt"; }
$("bulkList").onchange = count;
$("toggleAll").onclick = () => {
  const on = chosen().length < bulk.length; bulk.forEach(it => it.row.querySelector("input").checked = on);
  $("toggleAll").textContent = on ? "Alle abwählen" : "Alle auswählen"; count();
};
$("zipBtn").onclick = async () => {
  const ids = chosen().map(it => it.id); if (!ids.length) return;
  busy($("zipBtn"), true, "Lade " + ids.length + " …");
  try {
    const res = await fetch("/api/bulk?x=1" + placeQ(), { method: "POST", body: ids.join("\n") });
    if (!res.ok) { say($("bulkMsg"), await errorText(res), "bad"); return; }
    saveBlob(await res.blob(), fileName(res));
    say($("bulkMsg"), (res.headers.get("X-Result") || "") + " geladen. Details in report.csv.", "ok");
  } catch { say($("bulkMsg"), "Server nicht erreichbar.", "bad"); }
  finally { busy($("zipBtn"), false); }
};
$("saveBtn").onclick = async () => {
  const ids = chosen().map(it => it.id); if (!ids.length) return;
  busy($("saveBtn"), true, "Speichere …");
  try {
    const res = await fetch("/api/plugin-save?folder=" + encodeURIComponent($("folder").value.trim()) + placeQ(), { method: "POST", headers: H, body: ids.join("\n") });
    if (!res.ok) { say($("bulkMsg"), await errorText(res), "bad"); return; }
    const r = await res.json();
    const failed = Object.fromEntries(r.errors.map(e => [e.id, e.error]));
    for (const it of chosen()) {
      it.row.classList.toggle("fail", !!failed[it.id]); it.row.classList.toggle("done", !failed[it.id]);
      it.row.querySelector(".t").textContent = failed[it.id] || ((r.files[it.id] || []).length + " Datei(en)");
    }
    say($("bulkMsg"), r.saved + "/" + r.total + " gespeichert in " + r.folder, r.errors.length ? "bad" : "ok");
  } catch { say($("bulkMsg"), "Server nicht erreichbar.", "bad"); }
  finally { busy($("saveBtn"), false); }
};

// Model
$("modelForm").onsubmit = e => {
  e.preventDefault();
  const q = $("mq").value.trim(); if (!q) return;
  say($("modelMsg"), "Lade Model und alles darin … (kann dauern)");
  downloadUrl($("modelBtn"), "/api/model?q=" + encodeURIComponent(q) + placeQ(), $("modelMsg"));
};

// Hochladen
let mapping = [];
$("upBtn").onclick = async () => {
  const ids = [...new Set(($("upList").value.match(/\d{5,19}/g) || []))]; if (!ids.length) return;
  if (!status.user) { say($("upMsg"), "Erst einloggen: cookie.txt ist abgelaufen oder fehlt.", "bad"); return; }
  if (!status.apikey) { say($("upMsg"), "apikey.txt fehlt (Open Cloud, Assets Read + Write).", "bad"); return; }
  mapping = []; $("upResults").innerHTML = ""; $("copyBtn").hidden = true;
  busy($("upBtn"), true, "Lade hoch …");
  let done = 0;
  for (const id of ids) {
    const row = document.createElement("div"); row.className = "item";
    row.innerHTML = '<span></span><span class="n"></span><span class="t">läuft …</span>'; row.querySelector(".n").textContent = id;
    $("upResults").append(row);
    try {
      const res = await fetch("/api/plugin-upload?q=" + id + "&user=" + status.user.id + placeQ(), { headers: H });
      if (res.ok) { const r = await res.json(); mapping.push(id + " → " + r.id); row.classList.add("done"); row.querySelector(".t").textContent = "→ " + r.id; }
      else { row.classList.add("fail"); row.querySelector(".t").textContent = await errorText(res); }
    } catch { row.classList.add("fail"); row.querySelector(".t").textContent = "Server nicht erreichbar"; }
    say($("upMsg"), ++done + " von " + ids.length);
  }
  say($("upMsg"), mapping.length + " von " + ids.length + " hochgeladen.", mapping.length === ids.length ? "ok" : "bad");
  $("copyBtn").hidden = !mapping.length;
  busy($("upBtn"), false);
};
$("copyBtn").onclick = () => navigator.clipboard.writeText(mapping.join("\n")).then(() => say($("upMsg"), "Kopiert.", "ok"));
</script>
</body></html>"""


def install_plugin():
    """Kopiert das Studio-Plugin aus dem Repo in Studios Plugin-Ordner, wenn es dort fehlt oder veraltet ist.
    So reicht nach einem git pull ein Neustart von start.bat, plugin-installieren.bat muss niemand mehr klicken."""
    source = Path(__file__).with_name("studio-plugin") / "AssetDownloader.lua"
    roots = [Path(p) / "Roblox" for p in [os.environ.get("LOCALAPPDATA")] if p] + [Path.home() / "Documents" / "Roblox"]
    for root in roots:
        if not root.is_dir():
            continue
        target = root / "Plugins" / "AssetDownloader.lua"
        new = source.read_bytes()
        if target.is_file() and target.read_bytes() == new:
            return
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(new)
        print(f"Studio-Plugin aktualisiert ({target}). Roblox Studio neu starten, damit es geladen wird.")
        return


if __name__ == "__main__":
    try:
        install_plugin()
    except OSError as e:
        print(f"Plugin konnte nicht installiert werden: {e}")
    try:
        import DracoPy  # noqa: F401
    except ImportError:
        print("Hinweis: Neue Meshes kommen erst als OBJ/GLB, wenn DracoPy installiert ist: python -m pip install DracoPy")
    # Windows erlaubt sonst einen zweiten Server auf demselben Port, der Anfragen abfängt.
    ThreadingHTTPServer.allow_reuse_address = False
    try:
        server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        try:  # Läuft dort wirklich dieser Server oder ein fremdes Programm?
            ours = b"Roblox Asset Downloader" in urllib.request.urlopen(f"http://127.0.0.1:{PORT}", timeout=3).read()
        except Exception:
            ours = False
        if not ours:
            raise SystemExit(f"Port {PORT} ist von einem anderen Programm belegt. Das Programm schließen und start.bat neu öffnen.")
        if "--no-browser" not in sys.argv:
            webbrowser.open(f"http://127.0.0.1:{PORT}")
        raise SystemExit("Läuft schon in einem anderen Fenster. Browser wurde geöffnet.\n"
                         "Nach einem Update das alte Fenster schließen und start.bat neu öffnen, sonst läuft die alte Version.")
    url = f"http://127.0.0.1:{PORT}"
    print(f"Roblox Asset Downloader läuft auf {url}  (Strg+C beendet)")
    if "--no-browser" not in sys.argv:  # z. B. beim Neustart nur fürs Studio-Plugin
        webbrowser.open(url)
    server.serve_forever()
