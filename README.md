# Roblox Asset Downloader

Lädt Roblox-Assets per ID oder Link herunter: Models, Audio, Animationen, Accessories, Bilder und Meshes. Einzeln oder in Massen als ZIP. Läuft lokal auf deinem PC, ohne Werbung und ohne Limit.

## Voraussetzungen

- Windows mit [Python 3.10 oder neuer](https://www.python.org/downloads/) (bei der Installation „Add Python to PATH“ anhaken)
- Keine weiteren Pakete nötig

## Installation

Repo herunterladen: oben auf **Code → Download ZIP** klicken und entpacken. Oder:

```bash
git clone https://github.com/Emincan18/roblox-asset-downloader.git
```

## Login einrichten (einmalig)

Roblox gibt neue Assets nur an eingeloggte Accounts heraus. Das Tool nutzt dafür deinen eigenen Login-Cookie.

1. Am besten einen **Zweit-Account** anlegen und damit in Chrome oder Edge auf roblox.com einloggen.
2. `F12` drücken → Tab **Application** (deutsch „Anwendung“) → links **Cookies** → `https://www.roblox.com`.
3. Den Eintrag `.ROBLOSECURITY` suchen, in der Spalte **Value** doppelklicken, `Strg+A`, `Strg+C`.
4. Im Editor (Notepad) einfügen und als `cookie.txt` in diesen Ordner speichern. Beim Speichern **Dateityp: Alle Dateien** wählen, sonst entsteht `cookie.txt.txt`.

> **Achtung:** Mit dem Cookie kann man sich ohne Passwort in den Account einloggen. Gib ihn niemandem und lade ihn nirgends hoch. Wenn du dich mit dem Account im Browser ausloggst, wird der Cookie ungültig. Dann die Schritte wiederholen.

## Benutzen

### Webseite

`start.bat` doppelklicken. Der Browser öffnet `http://127.0.0.1:8765`.

- **Einzeln:** ID oder Link eingeben, auf **Download** klicken.
- **Bulk:** Viele IDs oder Links untereinander einfügen und auf **Alle als ZIP laden** klicken. Die ZIP enthält eine `report.csv`, die zeigt, was geklappt hat.

Oben auf der Seite steht, ob der Login aktiv ist.

### Roblox Studio Plugin

Kleines Fenster direkt in Studio: Asset laden, Vorschau ansehen, ins Spiel einfügen.

1. `plugin-installieren.bat` doppelklicken und Studio neu starten.
2. `start.bat` starten. Das Plugin redet mit diesem lokalen Server, er muss laufen.
3. In Studio: Tab **Plugins** → **Asset Downloader**. Beim ersten Laden fragt Studio, ob das Plugin `127.0.0.1` erreichen darf: **Allow**.
4. ID oder Link eingeben, **Laden** klicken.

- Models drehen sich in der Vorschau. Maus ziehen dreht, Mausrad zoomt. Animationen laufen auf einem Dummy (R6 oder R15, je nach Animation). Ist ein eigener Rig im Workspace ausgewählt, spielt sie auf dem.
- **Einfügen** setzt Models in den Workspace. Animationen landen in `AnimSaves` des ausgewählten Rigs (dann öffnet sie der Animation Editor), sonst in `ServerStorage`.
- Audio, Bilder und Meshes zeigen das Roblox-Vorschaubild.
- Jede geladene Datei liegt zusätzlich in `downloads/`.

### Kommandozeile

```bash
python roblox_asset_downloader.py ids.txt mein_model.rbxmx 507766388
```

Lädt alles nach `downloads/`. Mit `-o ORDNER` kannst du einen anderen Zielordner wählen. Ohne Argumente fragt das Script nach IDs.

### Nur IDs finden

`asset-id-extractor.html` im Browser öffnen. Die Seite findet Asset-IDs in Links, Scripts und `.rbxmx`/`.rbxlx`-Dateien, ohne etwas herunterzuladen.

## Gut zu wissen

- Erkannt werden IDs, `rbxassetid://`-Links, Catalog-, Library-, Bundle- und Creator-Store-Links.
- Dateien heißen `Name (ID).endung`. Die Endung wird am Inhalt erkannt (`.rbxm`, `.rbxmx`, `.ogg`, `.mp3`, `.png`, `.mesh` …).
- Viele Animationen und Sounds gibt Roblox nur im Kontext des Spiels heraus, das sie benutzen darf. Das Tool probiert automatisch die Spiele des Erstellers. Klappt es über ein Spiel, merkt es sich das in `places.txt` und nutzt es für alle weiteren Assets. Beim Bulk-Download bekommen Fehlschläge deshalb eine zweite Runde.
- Wenn trotzdem „Kein Zugriff“ kommt: Im Feld **Spiel** den Link des Spiels einfügen, aus dem die IDs stammen (Kommandozeile: `--place LINK`).
- „Von Roblox nicht freigegeben (moderiert)“ heißt, Roblox hat das Asset gesperrt. Das kann niemand mehr herunterladen.
- Binäre `.rbxm`/`.rbxl`-Dateien kann der ID-Extractor nicht lesen. In Studio als `.rbxmx`/`.rbxlx` speichern.

Nutze nur Assets, die du verwenden darfst. Die Rechte an fremden Assets liegen bei ihren Erstellern.
