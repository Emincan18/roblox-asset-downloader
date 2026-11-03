"""Roblox Asset Downloader als lokale Webseite.

Start:  python roblox_asset_web.py   (oder start.bat doppelklicken)
Öffnet http://127.0.0.1:8765 im Browser. ID oder Link eingeben, Download klicken.

Neue und private Assets brauchen den eigenen .ROBLOSECURITY-Cookie in cookie.txt
neben diesem Script (siehe roblox_asset_downloader.py).
"""

import csv
import io
import json
import re
import urllib.parse
import urllib.request
import webbrowser
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from roblox_asset_downloader import extract_ids, fetch, fetch_many, guess_ext, load_cookie, parse_place

PORT = 8765
DOWNLOADS = Path(__file__).with_name("downloads")
ASSET_TYPES = {1: "Image", 2: "T-Shirt", 3: "Audio", 4: "Mesh", 8: "Hat", 10: "Model", 11: "Shirt", 12: "Pants",
               13: "Decal", 24: "Animation", 38: "Plugin", 40: "MeshPart", 41: "Hair", 42: "Face", 43: "Neck",
               44: "Shoulder", 45: "Front", 46: "Back", 47: "Waist", 61: "Emote", 62: "Video"}


def asset_info(asset_id):
    """Name und Typ für den Dateinamen. Ohne Treffer nur die ID."""
    try:
        url = f"https://economy.roblox.com/v2/assets/{asset_id}/details"
        with urllib.request.urlopen(url, timeout=10) as r:
            d = json.load(r)
        return d.get("Name") or "", ASSET_TYPES.get(d.get("AssetTypeId"), "")
    except Exception:
        return "", ""


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

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(url.query)
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
        else:
            self.error(404, "Nicht gefunden")

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if url.path not in ("/api/bulk", "/api/plugin-bulk", "/api/plugin-save"):
            return self.error(404, "Nicht gefunden")
        place = parse_place(urllib.parse.parse_qs(url.query).get("place", [""])[0])
        text = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "ignore")
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
        with ThreadPoolExecutor(max_workers=6) as pool:
            infos = list(pool.map(asset_info, ids))
        self.send(200, json.dumps([{"id": i, "name": n or i, "type": k} for i, (n, k) in zip(ids, infos)]).encode())

    def plugin_save(self, ids, place, folder):
        """Für das Studio-Plugin: Assets in downloads/ oder einen Unterordner davon speichern."""
        folder = re.sub(r'[\\/:*?"<>|]+', "", folder).strip(" .")[:60]  # kein Pfad raus aus downloads/
        out = DOWNLOADS / folder if folder else DOWNLOADS
        out.mkdir(parents=True, exist_ok=True)
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
    webbrowser.open(url)
    server.serve_forever()
