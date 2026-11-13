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

`start.bat` doppelklicken. Der Browser öffnet `http://127.0.0.1:47651`.

Einmalig für Meshes als OBJ/GLB (neue Meshes sind Draco-komprimiert): `python -m pip install DracoPy`.

- **Einzeln:** ID oder Link eingeben, auf **Download** klicken.
- **Bulk:** Viele IDs oder Links untereinander einfügen und auf **Alle als ZIP laden** klicken. Die ZIP enthält eine `report.csv`, die zeigt, was geklappt hat.

Oben auf der Seite steht, ob der Login aktiv ist.

### Roblox Studio Plugin

Fenster direkt in Studio mit mehreren Tabs. Neben jedem Knopf erklärt ein **i**, was er macht.

1. `plugin-installieren.bat` doppelklicken und Studio neu starten.
2. `start.bat` starten. Das Plugin redet mit diesem lokalen Server, er muss laufen.
   Nach einem `git pull`: altes `start.bat`-Fenster schließen, `start.bat` neu öffnen und Studio neu starten. Der Server kopiert dabei das neue Plugin selbst in Studios Plugin-Ordner.
3. In Studio: Tab **Plugins** → **Asset Downloader**. Beim ersten Laden fragt Studio, ob das Plugin `127.0.0.1` erreichen darf: **Allow**.

**Laden**
- ID oder Link eingeben und **Laden**, oder im Explorer etwas anklicken und **Aus Explorer-Auswahl**. Die ID wird dann automatisch übernommen. Eine Animationsdatei ohne ID (KeyframeSequence, z. B. per Insert from File eingefügt) kommt direkt in die Vorschau.
- Vorschau: Models und Meshes drehen sich (Maus ziehen dreht, Mausrad zoomt). Animationen laufen auf einem farbigen Dummy oder dem ausgewählten Rig. Bilder werden angezeigt, Audio hat **Abspielen**.
- **Platzieren** setzt das Asset vor die Kamera, mit allen Einstellungen. Animationen landen in `AnimSaves` des ausgewählten Rigs, sonst in `ServerStorage`.
- **Abspielen**: Animationen laufen auf einem Dummy 12 Studs vor deiner Kamera (ist ein Rig ausgewählt, auf einer Kopie davon). Nochmal drücken entfernt ihn. Bei VFX löst es die Emitter aus.
- **Herunterladen** speichert nach `downloads/`. Models und VFX bekommen einen Ordner mit `.rbxm` und allen Texturen.
- **Herunterladen unter meinem Namen** lädt die Texturen erst unter deinem Account hoch und speichert dann mit deinen neuen IDs.

**Bulk:** Viele IDs untereinander, **Liste laden**. Klick auf einen Eintrag zeigt die Vorschau oben im Bulk-Tab, `+` legt ihn in den Korb.

**Korb:** Beim Ansehen sammeln, dann **Korb herunterladen** nach `downloads/<Ordnername>/`. **Bilder im Korb hochladen** lädt sie unter deinem Namen hoch.

**VFX** (für Effekte, die schon im Spiel sind, z. B. eine Aura): Ordner im Explorer anklicken, dann
- **Reparieren und sichern**: Texturen unter deinem Namen hochladen, IDs tauschen, alles nach `downloads/<Name>/`.
- **Nur sichern**: `.rbxm` und Texturen speichern, ohne Hochladen.
- **Auswahl abspielen**: Emitter auslösen. Lose Attachments kommen dafür an ein unsichtbares Teil.

**Animations-Ordner** (Tab VFX): Ordner mit Animationen anklicken, z. B. einen ganzen Charakter wie `Anubis`.
- **Herunterladen** speichert alles als eine Datei `downloads/<Name>/<Name>.rbxm`, mit allen Unterordnern und Namen wie im Explorer (z. B. `Anubis > Attack > M1`). Jede Animation liegt dort als KeyframeSequence mit ihrem Namen, ohne Asset-ID, wie aus dem Animation Editor. In einer anderen Place: Rechtsklick > Insert from File.
- **Unter meiner ID** bei einem Ordner mit KeyframeSequences (z. B. aus Herunterladen eingefügt): lädt alle auf einmal unter deinem Account hoch. Danach steckt jede in einer Animation mit deiner neuen ID, gleicher Name, gleicher Ort. Kein Rechtsklick > Save to Roblox pro Animation.
- **Unter meiner ID** bei Animationen aus einem Spiel (fremde IDs) lädt jede Animation (und Bilder) unter deinem Account hoch. In der Datei bleiben die Animation-Objekte mit deinen neuen IDs, jeweils mit der KeyframeSequence darin. Datei: `downloads/<Name> (meine IDs)/`. Schon hochgeladene Animationen merkt sich der Server in `uploads.json`. Braucht `apikey.txt` mit Assets Read + Write.

**Cutscene:** Cutscene-Script im Explorer anklicken.
- **Herunterladen** speichert alles, was die Cutscene braucht, nach `downloads/<Name>/` und zeigt dabei Prozent. Jede Animation steckt zusätzlich als KeyframeSequence in ihrem Animation-Objekt, damit die Cutscene in jeder Place läuft.
- **Abspielen**: Cutscene-Script oder den eingefügten Download-Ordner anklicken. Die Kamera fliegt wie im Spiel mit, jedes Rig spielt seine Animation. Geht im Edit-Modus und im Play-Test.
- **Beim Play-Test** merkt sich die angeklickte Cutscene. Jeder Play-Test spielt sie dann einmal ab, sobald deine Figur da ist.
- Nicht nachgebaut werden Effekte, die der Code zu bestimmten Zeitpunkten auslöst (Partikel-Bursts, Sounds, Bildschirm-Effekte).

**Variablennamen aufräumen** (Tab Credits): Dekompilierter Code nummeriert Variablen durch (`v12`, `u28`, `p51`, `Vector2_new_ret`). Der Knopf gibt ihnen Namen aus dem Code (`local v5 = script.Cam:Clone()` wird `camClone`, Klassen-Tabellen bekommen den Script-Namen, Methoden-Parameter heißen `self`), aus Schleifen (`index`, `item`, `child`), aus der Verwendung (`player`, `connection`, `part` …) und sonst `arg`/`value`. Im Code bleibt kein Nummern-Name übrig. Strings, Kommentare und Felder bleiben unangetastet. Scripts, die danach nicht mehr kompilieren würden, bleiben, wie sie waren. Ausgewählte Scripts oder die ganze Place, Strg+Z macht es rückgängig.

#### Hochladen unter deinem Namen einrichten (einmalig)

**Reparieren und sichern** und **Unter meinem Namen hochladen** laden Texturen in deinen eigenen Account hoch. Roblox Studio darf das selbst noch nicht, deshalb macht es der Server über die offizielle Open Cloud API. Dafür braucht er einen API-Key von dem Account, unter dessen Namen die Bilder erscheinen sollen.

1. Mit diesem Account auf [create.roblox.com/dashboard/credentials](https://create.roblox.com/dashboard/credentials) gehen → **API-Schlüssel erstellen**.
2. Unter **Zugriffsberechtigungen** die API **Assets** hinzufügen und **Read** und **Write** anhaken.
3. Unter **Sicherheit** bei IP-Adressen `0.0.0.0/0` eintragen (oder deine eigene IP). Ablaufdatum nach Wunsch.
4. **Speichern und Schlüssel generieren**, den Schlüssel kopieren.
5. Im Editor einfügen und als `apikey.txt` in diesen Ordner speichern (Dateityp: Alle Dateien).

> **Achtung:** Mit dem API-Key kann man in deinem Namen Assets hochladen. Gib ihn niemandem.

In Studio muss derselbe Account eingeloggt sein, denn das Plugin schickt die User-ID von Studio mit.

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
- Meshes kommen zusätzlich als `.obj` und `.glb`. Beide öffnen Blender und Roblox Studio (Import 3D). OBJ hat Form, UVs und Normalen; GLB hat dazu Knochen und Gewichte, falls das Mesh geriggt ist. Neue Meshes (Version 7.00) brauchen dafür das Python-Paket `DracoPy`; ohne es bleibt nur die `.mesh`.
- Viele Animationen und Sounds gibt Roblox nur im Kontext des Spiels heraus, das sie benutzen darf. Das Tool probiert automatisch die Spiele des Erstellers, bei Gruppen auch private Test-Places, bei Usern auch die Spiele ihrer eigenen Gruppen. Klappt es über ein Spiel, merkt es sich das in `places.txt` und nutzt es für alle weiteren Assets. Beim Bulk-Download bekommen Fehlschläge deshalb eine zweite Runde.
- Wenn trotzdem „Kein Zugriff“ kommt: Im Feld **Spiel** den Link des Spiels einfügen, aus dem die IDs stammen (Kommandozeile: `--place LINK`).
- „Privates Audio“ heißt, der Ersteller hat das Audio privat gestellt. Roblox gibt es nur ihm oder Spielen, die er freigegeben hat, auch im Spielkontext nicht. Das lässt sich nicht herunterladen.
- „Von Roblox nicht freigegeben (moderiert)“ heißt, Roblox hat das Asset gesperrt. Das kann niemand mehr herunterladen.
- Binäre `.rbxm`/`.rbxl`-Dateien kann der ID-Extractor nicht lesen. In Studio als `.rbxmx`/`.rbxlx` speichern.

Nutze nur Assets, die du verwenden darfst. Die Rechte an fremden Assets liegen bei ihren Erstellern.
