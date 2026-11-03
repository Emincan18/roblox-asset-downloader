--[[
	Roblox Asset Downloader als Studio-Plugin.
	Redet mit dem lokalen Server (start.bat), der die Assets von Roblox lädt.
	Vorschau für Models, Animationen, Meshes, Bilder und Audio, Einfügen ins Spiel,
	Herunterladen nach downloads/ und ein Korb, der alles gesammelt in einen Ordner lädt.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local SerializationService = game:GetService("SerializationService")
local AnimationClipProvider = game:GetService("AnimationClipProvider")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local AssetService = game:GetService("AssetService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local SERVER = "http://127.0.0.1:8765"
-- Webseiten können diesen Header nicht mitschicken, so nimmt der Server nur Anfragen vom Plugin an.
local PLUGIN_HEADERS = { ["X-Asset-Downloader"] = "plugin" }

local BG = Color3.fromRGB(20, 21, 26)
local CARD = Color3.fromRGB(30, 32, 40)
local FIELD = Color3.fromRGB(42, 45, 56)
local TEXT = Color3.fromRGB(235, 236, 240)
local MUTED = Color3.fromRGB(150, 154, 168)
local ACCENT = Color3.fromRGB(226, 60, 60)
local BLUE = Color3.fromRGB(60, 120, 210)
local GREEN = Color3.fromRGB(40, 150, 90)
local PURPLE = Color3.fromRGB(140, 90, 210)
local GREY = Color3.fromRGB(62, 65, 78)
local BAD = Color3.fromRGB(240, 120, 110)
local OK = Color3.fromRGB(110, 210, 150)

local toolbar = plugin:CreateToolbar("Asset Downloader")
local toggle = toolbar:CreateButton("Asset Downloader", "Roblox-Assets laden und ansehen", "")
toggle.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync("AssetDownloader",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 340, 620, 280, 420))
widget.Title = "Asset Downloader"
toggle.Click:Connect(function() widget.Enabled = not widget.Enabled end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function() toggle:SetActive(widget.Enabled) end)

-- UI ---------------------------------------------------------------------------------------

local function corner(inst, radius)
	Instance.new("UICorner", inst).CornerRadius = UDim.new(0, radius or 6)
	return inst
end

local function padding(inst, px)
	local p = Instance.new("UIPadding", inst)
	p.PaddingTop, p.PaddingBottom, p.PaddingLeft, p.PaddingRight = UDim.new(0, px), UDim.new(0, px), UDim.new(0, px), UDim.new(0, px)
	return p
end

local function vlist(inst, gap)
	local l = Instance.new("UIListLayout", inst)
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	return l
end

local function autoFrame()
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundTransparency = 1
	return f
end

local root = Instance.new("ScrollingFrame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = BG
root.BorderSizePixel = 0
root.ScrollBarThickness = 6
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
root.CanvasSize = UDim2.new()
root.Parent = widget
padding(root, 12)
vlist(root, 10)

-- add() legt Elemente in den aktuellen Container (Seite oder Karte), in der Reihenfolge des Aufrufs.
local container, order = root, 0
local currentPage = nil -- Seite des aktuellen Tabs; Karten kommen dort hinein
local function add(inst)
	order += 1
	inst.LayoutOrder = order
	inst.Parent = container
	return inst
end

local function label(text, color, size)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = Enum.Font.Gotham
	l.TextSize = size or 13
	l.TextColor3 = color or MUTED
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	return add(l)
end

local function input(placeholder)
	local t = Instance.new("TextBox")
	t.Size = UDim2.new(1, 0, 0, 34)
	t.BackgroundColor3 = FIELD
	t.BorderSizePixel = 0
	t.Font = Enum.Font.Code
	t.TextSize = 14
	t.TextColor3 = TEXT
	t.PlaceholderText = placeholder
	t.PlaceholderColor3 = MUTED
	t.Text = ""
	t.ClearTextOnFocus = false
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ClipsDescendants = true
	local p = Instance.new("UIPadding", t)
	p.PaddingLeft, p.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	return add(corner(t))
end

local function makeButton(text, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 34)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	return corner(b)
end

-- Rundes i neben einem Knopf. Klick klappt die Erklärung darunter auf und zu.
local function infoIcon(parent, hint, layoutOrder)
	local i = Instance.new("TextButton")
	i.Size = UDim2.new(0, 34, 0, 34)
	i.BackgroundColor3 = GREY
	i.Font = Enum.Font.GothamBold
	i.TextSize = 15
	i.TextColor3 = TEXT
	i.Text = "i"
	i.LayoutOrder = layoutOrder
	corner(i, 17)
	i.Parent = parent
	i.Activated:Connect(function() hint.Visible = not hint.Visible end)
	return i
end

local function hintLabel(parent, text)
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, 0, 0, 0)
	h.AutomaticSize = Enum.AutomaticSize.Y
	h.BackgroundColor3 = FIELD
	h.Font = Enum.Font.Gotham
	h.TextSize = 12
	h.TextColor3 = TEXT
	h.TextWrapped = true
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.Text = text
	h.LayoutOrder = 2
	h.Visible = false
	padding(h, 8)
	corner(h)
	h.Parent = parent
	return h
end

-- Zeile aus 1-2 Knöpfen plus i. Gibt (Zeile, Knopf1, Knopf2). Zeile.Visible blendet alles aus.
local function buttonRow(info, textA, colorA, textB, colorB)
	local wrap = add(autoFrame())
	vlist(wrap, 6)
	local line = Instance.new("Frame")
	line.Size, line.BackgroundTransparency, line.LayoutOrder = UDim2.new(1, 0, 0, 34), 1, 1
	line.Parent = wrap
	local h = Instance.new("UIListLayout", line)
	h.FillDirection, h.Padding, h.SortOrder = Enum.FillDirection.Horizontal, UDim.new(0, 6), Enum.SortOrder.LayoutOrder
	local a = makeButton(textA, colorA)
	a.LayoutOrder, a.Parent = 1, line
	local b = nil
	if textB then
		b = makeButton(textB, colorB)
		b.LayoutOrder, b.Parent = 2, line
		a.Size, b.Size = UDim2.new(0.5, -23, 1, 0), UDim2.new(0.5, -23, 1, 0)
	else
		a.Size = UDim2.new(1, -40, 1, 0)
	end
	infoIcon(line, hintLabel(wrap, info), 3)
	return wrap, a, b
end

-- Einzelner Knopf mit i. Knopf.Visible blendet auch das i aus.
local function button(text, color, info)
	local wrap, b = buttonRow(info, text, color)
	b:GetPropertyChangedSignal("Visible"):Connect(function() wrap.Visible = b.Visible end)
	return b
end

-- Karte mit Überschrift; folgende add()-Aufrufe landen darin.
local function card(title, subtitle)
	local c = Instance.new("Frame")
	c.Size = UDim2.new(1, 0, 0, 0)
	c.AutomaticSize = Enum.AutomaticSize.Y
	c.BackgroundColor3 = CARD
	corner(c, 10)
	padding(c, 12)
	vlist(c, 8)
	container = currentPage or container -- jede Karte direkt auf die Seite, nicht in die vorige Karte
	add(c)
	container = c
	label(title, TEXT, 16).Font = Enum.Font.GothamBold
	if subtitle then label(subtitle) end
	return c
end

-- Kopf -------------------------------------------------------------------------------------

label("Asset Downloader", TEXT, 22).Font = Enum.Font.GothamBlack
label("Assets laden, ansehen, sammeln und reparieren.")

local tabBar = add(Instance.new("Frame"))
tabBar.Size, tabBar.BackgroundColor3 = UDim2.new(1, 0, 0, 38), CARD
corner(tabBar, 10)
padding(tabBar, 3)
local tabList = Instance.new("UIListLayout", tabBar)
tabList.FillDirection, tabList.Padding, tabList.SortOrder = Enum.FillDirection.Horizontal, UDim.new(0, 3), Enum.SortOrder.LayoutOrder

-- Status gilt für alle Tabs, deshalb über den Seiten.
local status = label("Server muss laufen: start.bat doppelklicken.")
-- Neue IDs nach dem Hochladen, markierbar zum Kopieren.
local idsBox = input("")
idsBox.TextEditable, idsBox.MultiLine, idsBox.TextWrapped = false, true, true
idsBox.AutomaticSize, idsBox.Size = Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 34)
idsBox.Visible = false

local tabs, pages = {}, {}
-- Die Vorschau-Karte gibt es einmal; sie wandert zwischen Laden und Bulk (dort oben über der Liste).
local previewCard, previewOrder, bulkCard, bulkPreviewUsed
local function showTab(name)
	for n, page in pages do
		page.Visible = n == name
		tabs[n].BackgroundColor3 = n == name and ACCENT or CARD
		tabs[n].TextColor3 = n == name and Color3.new(1, 1, 1) or MUTED
	end
	if previewCard and name == "Laden" then
		previewCard.Parent, previewCard.LayoutOrder, previewCard.Visible = pages.Laden, previewOrder, true
	elseif previewCard and name == "Bulk" then
		previewCard.Parent, previewCard.LayoutOrder, previewCard.Visible = pages.Bulk, bulkCard.LayoutOrder - 1, bulkPreviewUsed == true
	end
	root.CanvasPosition = Vector2.zero
end

local function page(name, index)
	local t = makeButton(name, CARD)
	t.Size, t.LayoutOrder, t.TextSize = UDim2.new(1 / 6, -3, 1, 0), index, 11
	t.Parent = tabBar
	t.Activated:Connect(function() showTab(name) end)
	tabs[name] = t
	local p = autoFrame()
	vlist(p, 10)
	container = root
	add(p)
	pages[name] = p
	container, currentPage = p, p
	return p
end

-- Tab: Laden -------------------------------------------------------------------------------

page("Laden", 1)
card("Asset laden", "Animation, Model, VFX, Bild, Audio oder Mesh.")
local idBox = input("Asset-ID oder Link, z. B. 507766388")
local placeBox = input("Spiel-Link (optional, für gesperrte Assets)")
placeBox.Text = plugin:GetSetting("place") or ""
placeBox.FocusLost:Connect(function() plugin:SetSetting("place", placeBox.Text) end)
local loadBtn = button("Laden", ACCENT,
	"Gib eine Asset-ID oder einen Link ein und drück Laden. Du siehst dann Name, Typ und eine Vorschau. Gespeichert wird noch nichts.\n\nSpiel-Link: Manche Animationen und Sounds gibt Roblox nur im Kontext ihres Spiels heraus. Dann hier den Link des Spiels eintragen.")
local pickBtn = button("Aus Explorer-Auswahl", BLUE,
	"Klick im Explorer eine Animation, einen Sound, Emitter, Mesh oder ein Bild an und drück diesen Knopf. Die ID wird automatisch eingetragen und geladen.\n\nIst ein ganzer Ordner (z. B. eine VFX) ausgewählt, kommen alle IDs darin als Liste in den Tab Bulk.")

previewCard = card("Vorschau")
previewOrder = previewCard.LayoutOrder
local view = add(corner(Instance.new("ViewportFrame"), 8))
view.Size = UDim2.new(1, 0, 0, 240)
view.BackgroundColor3 = FIELD
view.Ambient = Color3.fromRGB(200, 200, 200)
view.LightColor = Color3.new(1, 1, 1)
local camera = Instance.new("Camera")
camera.FieldOfView = 40
camera.Parent = view
view.CurrentCamera = camera
-- Eigenes Feld statt Kind des ViewportFrames, damit es sicher gezeichnet wird.
local thumb = add(corner(Instance.new("ImageLabel"), 8))
thumb.Size = UDim2.new(1, 0, 0, 240)
thumb.BackgroundColor3 = FIELD
thumb.ScaleType = Enum.ScaleType.Fit
thumb.Visible = false
label("Maus ziehen dreht, Mausrad zoomt.")

local row, insertBtn, playBtn = buttonRow(
	"Platzieren setzt das Asset 12 Studs vor deine Kamera, mit allen Einstellungen und Unterordnern. Animationen kommen in AnimSaves des ausgewählten Rigs, sonst in ServerStorage.\n\nAbspielen startet Animation oder Sound. Bei VFX löst es die platzierten Emitter aus (erst Platzieren).",
	"Platzieren", BLUE, "Abspielen", GREY)
row.Visible = false
local row2, cartAddBtn, downloadBtn = buttonRow(
	"In den Korb merkt sich das Asset, du lädst später alles auf einmal herunter (Tab Korb).\n\nHerunterladen speichert sofort nach downloads/. Bei Models und VFX entsteht ein Ordner mit der .rbxm und allen Texturen.",
	"In den Korb", GREY, "Herunterladen", GREEN)
row2.Visible = false
local uploadBtn = button("Herunterladen unter meinem Namen", PURPLE,
	"Lädt zuerst alle Texturen unter deinem Roblox-Account hoch und speichert dann die Datei mit deinen neuen IDs. Auf Roblox steht danach \"Von\" und dein Name.\n\nBraucht einmalig apikey.txt (siehe README).")
uploadBtn.Visible = false
local savedLabel = label("")

-- Tab: Bulk --------------------------------------------------------------------------------

page("Bulk", 2)
bulkCard = card("Viele Assets auf einmal", "Eine ID oder ein Link pro Zeile.")
local bulkBox = input("507766388\n180435571\n...")
bulkBox.MultiLine, bulkBox.TextWrapped = true, true
bulkBox.TextYAlignment = Enum.TextYAlignment.Top
bulkBox.Size = UDim2.new(1, 0, 0, 110)
bulkBox:FindFirstChildOfClass("UIPadding").PaddingTop = UDim.new(0, 8)
local bulkBtn = button("Liste laden", ACCENT,
	"Zeigt zu jeder ID Name und Typ. Das geht schnell, weil noch nichts heruntergeladen wird.\n\nKlick auf einen Eintrag zeigt die Vorschau oben in diesem Tab. + legt ihn in den Korb.")
local bulkAllBtn = button("Ganze Liste in den Korb", GREY, "Legt alle Einträge der Liste auf einmal in den Korb.")
bulkAllBtn.Visible = false
-- Bulk-Ergebnisse. Vorschau lädt erst beim Anklicken, sonst laggt Studio bei vielen Assets.
local results = add(autoFrame())
vlist(results, 4)

-- Tab: Korb --------------------------------------------------------------------------------

page("Korb", 3)
card("Korb", "Sammle Assets beim Ansehen, lade sie dann zusammen in einen Ordner.")
local cartTitle = label("Korb ist leer", TEXT, 14)
local cartList = add(autoFrame())
vlist(cartList, 4)
local folderBox = input("Ordnername (leer = Korb + Datum)")
local cartBtn = button("Korb herunterladen", GREEN,
	"Speichert alles im Korb nach downloads/<Ordnername>/. Ohne Namen heißt der Ordner \"Korb\" plus Datum. Klappt alles, wird der Korb geleert.")
local cartUploadBtn = button("Herunterladen + Bilder hochladen", PURPLE,
	"Ein Knopf für beides: Speichert erst alles im Korb nach downloads/<Ordnername>/ (wie Korb herunterladen), dann lädt er alle Bilder im Korb unter deinem Namen hoch. Die neuen IDs erscheinen unten zum Kopieren. Braucht apikey.txt.")
folderBox.Visible, cartBtn.Visible, cartUploadBtn.Visible = false, false, false

-- Tab: VFX ---------------------------------------------------------------------------------

page("VFX", 4)
-- VFX-Werkzeuge für Objekte, die schon im Spiel sind (z. B. eine Aura mit mehreren Emittern).
card("VFX aus dem Spiel", "Erst die VFX oder den ganzen Ordner (z. B. Aura) im Explorer anklicken.")
local repairBtn = button("Reparieren und sichern", PURPLE,
	"Lädt jede Textur der Auswahl unter deinem Namen hoch und setzt die neuen IDs ein. Größe, Farben, Rotation und alle Einstellungen bleiben.\n\nDanach liegt alles in downloads/<Name>/: die VFX als .rbxm und jede Textur als Bild. Braucht apikey.txt.")
local saveSelBtn = button("Nur sichern (nichts hochladen)", GREY,
	"Speichert die Auswahl als .rbxm und alle Texturen als Bilder nach downloads/<Name>/. Lädt nichts hoch, die IDs bleiben die alten.")
local playSelBtn = button("Auswahl abspielen", BLUE,
	"Löst alle ParticleEmitter der Auswahl einmal aus (mit EmitCount und EmitDelay, falls gesetzt). Hit-VFX sieht man sonst nicht, weil sie nur per Script feuern.\n\nSpielt immer als Kopie 12 Studs vor deiner Kamera, egal ob die VFX im Workspace, in ReplicatedStorage oder in einem Script liegt. Das Original bleibt unverändert, du kannst beliebig oft abspielen.")
local vfxLabel = label("")

card("Zu anderer Place", "Auswahl in einer Place senden, in einer anderen Place empfangen. Beide brauchen dieses Plugin und start.bat.")
local _, sendBtn, receiveBtn = buttonRow("Senden speichert die Explorer-Auswahl beim lokalen Server (downloads/_senden/), mit dem Ordner, in dem jedes Objekt lag.\n\nEmpfangen in der anderen Place legt alles wieder in denselben Ordner, z. B. ReplicatedStorage > Anims. Fehlt der Ordner dort, landet es im nächsten vorhandenen Ordner darüber. Danach ist es ausgewählt, Strg+Z macht es rückgängig.\n\nGesendet bleibt gesendet, bis du etwas Neues sendest. Du kannst also in mehreren Places empfangen.",
	"Auswahl senden", ACCENT, "Hier empfangen", GREEN)
local _, sendPlaceBtn, receivePlaceBtn = buttonRow("Ganze Place senden nimmt alles mit: Workspace (mit Terrain), Lighting, ReplicatedFirst, ReplicatedStorage, ServerScriptService, ServerStorage, StarterGui, StarterPack, StarterPlayer, SoundService, Teams, Chat, TextChatService und MaterialService, samt Scripts. Dazu die Einstellungen von Lighting (Uhrzeit, Nebel, Farben …), Workspace (Schwerkraft …) und StarterPlayer (Laufen, Springen, Kamera).\n\nGanze Place empfangen ERSETZT den Inhalt dieser Place durch die gesendete. Deshalb zweimal klicken. Strg+Z macht es rückgängig.\n\nNur außerhalb vom Play-Test.",
	"Place senden", ACCENT, "Place empfangen", BAD)
local transferLabel = label("")

-- Tab: ClientFX ----------------------------------------------------------------------------

page("FX", 5)
card("ClientFX", "Effekte, die der Server per ClientFX an die Clients schickt und die ein Client-Script zeichnet.")
local fxScanBtn = button("ClientFX suchen", ACCENT,
	"Durchsucht alle Scripts der offenen Place nach ClientFX-Aufrufen wie ClientFX:FireAllClients(\"Stand Barrage\", ...).\n\nZu jedem Effekt siehst du, wo der Server ihn feuert (Server) und wo ein Client-Script ihn behandelt (Client). Klick darauf öffnet das Script an der Zeile.\n\nRot heißt: In dieser Place gibt es keinen Client-Code dafür. Vorlage legt dann ein LocalScript an, das schon auf den Effekt hört und die Parameter vom Server auflistet.\n\nPaket speichert alles zum Effekt (Scripts, passende Objekte, Assets) nach downloads/<Name>/.\n\nTesten: Siehe Karte Aufnahme unten. Im Play-Test die Attacke einmal benutzen, dann Wiederholen.")
label("Name des RemoteEvents (in YBA: ClientFX)")
local fxRemoteBox = input("ClientFX")
fxRemoteBox.Text = plugin:GetSetting("fxRemote") or "ClientFX"
fxRemoteBox.FocusLost:Connect(function() plugin:SetSetting("fxRemote", fxRemoteBox.Text) end)
local function remoteName()
	local n = fxRemoteBox.Text:match("^%s*(.-)%s*$")
	return n ~= "" and n or "ClientFX"
end
local fxFilter = input("Filtern, z. B. Barrage")
fxFilter.Visible = false
local fxList = add(autoFrame())
vlist(fxList, 4)

card("Aufnahme", "Zeichnet im Play-Test (F5) jeden echten ClientFX-Aufruf mit seinen Daten auf.")
local recInfo = label("1. F5 drücken.\n2. Im Spiel die Attacke normal benutzen (z. B. E für Barrage).\n3. Jeder Aufruf erscheint hier mit genau den Daten vom Server.\n4. Wiederholen feuert ihn nochmal über den Server, mit denselben Objekten und Werten. Geht, solange diese Objekte noch existieren.")
local recList = add(autoFrame())
vlist(recList, 4)

card("Vorschau im Spiel", "Dummy vor dir in der Welt: spielt die geladene Animation und die VFX-Objekte eines Effekts an ihm ab.")
label("1. Optional: Animation im Tab Laden oder Bulk laden.\n2. Effekt-Namen tippen und in der Liste anklicken. Die Vorschau startet sofort, auch ohne F5.")
local sceneFxBox = input("Effekt suchen, z. B. Barrage")
local sceneFxList = add(autoFrame())
vlist(sceneFxList, 4)
local _, sceneStartBtn, sceneStopBtn = buttonRow("Der Effekt-Code wird nicht ausgeführt: In Kopien fehlen ihm die Daten vom Server, deshalb bricht er fast immer ab.\n\nStattdessen liest das Plugin im Code, welche Objekte der Effekt benutzt (z. B. Client Assets > Whitesnake > DirectOrderThrow), setzt Kopien davon an den Dummy und löst ihre Partikel aus, mit EmitCount und EmitDelay.\n\nDu siehst Partikel, Modelle, Beams und Trails. Bewegungen, die der Code macht (fliegende Fäuste, Tweens), siehst du nicht.\n\nStart spielt den letzten Effekt nochmal. Stopp löscht Dummy und Kopien.",
	"Start", ACCENT, "Stopp", GREY)
local sceneLabel = label("")

-- Tab: Cutscene ----------------------------------------------------------------------------

page("Cutscene", 6)
card("Cutscene", "Cutscene-Script im Explorer anklicken (oder den Ordner, in dem es liegt).")
local csInfo = label("Noch nichts ausgewählt.")
local csList = add(autoFrame())
vlist(csList, 4)
local _, csDownloadBtn, csRepairBtn = buttonRow("Mein Account: lädt vorher jedes Bild der Cutscene (Texturen, Decals, Partikel) unter deinem Account neu hoch, setzt die neuen IDs in die Kopie ein, auch im Script-Code, und lädt dann alles herunter. Braucht apikey.txt. Animationen und Sounds behalten ihre alten IDs, die lädt der Server nicht hoch.\n\nSucht im Code der ausgewählten Scripts alles, was die Cutscene benutzt: Models, Rigs mit AnimationController oder Humanoid, Kameras, Parts, Animationen, Sounds, Remotes und Module. Module, die per require geladen werden, durchsucht es genauso mit.\n\nAlles landet in downloads/<Name>/: <Name>.rbxm mit den Ordnern Code und Objekte (in Studio per Rechtsklick > Insert from File einfügbar), code.lua zum Lesen und jede Animation, jeder Sound und jedes Bild als eigene Datei.\n\nKlick auf eine Zeile in der Liste zeigt das Objekt im Explorer.",
	"Herunterladen", ACCENT, "Mein Account", PURPLE)

showTab("Laden")
container = root

-- Vorschau ---------------------------------------------------------------------------------

local loaded = nil -- { id, objects = {Instance}, clip = KeyframeSequence/AnimationClip? }
local world, stepConn, track, animator

local function stopPreview()
	if stepConn then stepConn:Disconnect() stepConn = nil end
	if track then track:Stop(0) track = nil end
	animator = nil
	if loaded and loaded.sound then loaded.sound:Stop() end
	if world then world:Destroy() world = nil end
	playBtn.Text = "Abspielen"
end

-- Kamera kreist um das Ziel. Maus ziehen dreht, Mausrad zoomt.
local cam = { target = Vector3.zero, dist = 10, yaw = 0, pitch = 0.3, spin = false, drag = nil }

local function placeCamera()
	local dir = Vector3.new(math.sin(cam.yaw) * math.cos(cam.pitch), math.sin(cam.pitch), math.cos(cam.yaw) * math.cos(cam.pitch))
	camera.CFrame = CFrame.lookAt(cam.target + dir * cam.dist, cam.target)
end

-- facing: Kamera vor das Gesicht des Rigs stellen statt in den Rücken.
local function frameCamera(spin, facing)
	local cf, size = world:GetBoundingBox()
	cam.target, cam.dist, cam.pitch, cam.spin = cf.Position, math.max(size.Magnitude, 1) * 1.1, 0.3, spin
	local look = facing and facing.CFrame.LookVector or Vector3.zAxis
	cam.yaw = math.atan2(look.X, look.Z)
	placeCamera()
end

RunService.Heartbeat:Connect(function(dt)
	if world and cam.spin and not cam.drag then
		cam.yaw += dt * 0.6
		placeCamera()
	end
end)

view.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		cam.drag, cam.spin = input.Position, false
	end
end)
view.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and cam.drag then
		local d = input.Position - cam.drag
		cam.drag = input.Position
		cam.yaw -= d.X * 0.01
		cam.pitch = math.clamp(cam.pitch + d.Y * 0.01, -1.3, 1.3)
		placeCamera()
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		cam.dist = math.clamp(cam.dist * (input.Position.Z > 0 and 0.9 or 1.1), 1, 500)
		placeCamera()
	end
end)
view.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then cam.drag = nil end
end)
view.MouseLeave:Connect(function() cam.drag = nil end)

-- Rig für die Animation: ausgewähltes Model mit Humanoid, sonst ein Standard-Dummy.
local function makeRig(clip)
	for _, sel in Selection:Get() do
		local m = sel:IsA("Model") and sel or sel:FindFirstAncestorWhichIsA("Model")
		if m and m:FindFirstChildWhichIsA("Humanoid", true) then
			local ok, copy = pcall(function() return m:Clone() end)
			if ok and copy then return copy end
		end
	end
	local r6 = not clip or clip:FindFirstChild("Torso", true) ~= nil
	-- Farbiger Dummy, damit man Arme, Torso und Beine in der Bewegung auseinanderhält.
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(245, 215, 185)
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
	desc.TorsoColor = Color3.fromRGB(45, 125, 225)
	desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(235, 235, 240), Color3.fromRGB(235, 235, 240)
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc,
			r6 and Enum.HumanoidRigType.R6 or Enum.HumanoidRigType.R15)
	end)
	return ok and rig or nil
end

local function previewAnimation(clip)
	local rig = makeRig(clip)
	if not rig then
		status.Text = "Für die Vorschau einen Rig im Workspace auswählen (Avatar > Rig Builder), dann nochmal laden."
		return
	end
	rig.Parent = world
	if rig.PrimaryPart then rig.PrimaryPart.Anchored = true end
	frameCamera(false, rig.PrimaryPart)
	local holder = rig:FindFirstChildWhichIsA("Humanoid", true) or rig:FindFirstChildWhichIsA("AnimationController", true)
	animator = holder:FindFirstChildOfClass("Animator") or Instance.new("Animator", holder)
	local anim = Instance.new("Animation")
	anim.AnimationId = AnimationClipProvider:RegisterAnimationClip(clip)
	track = animator:LoadAnimation(anim)
	track.Looped = true
end

local function playToggle()
	local sound = loaded and loaded.sound
	if sound then
		if sound.IsPlaying then
			sound:Stop()
			playBtn.Text = "Abspielen"
		else
			SoundService:PlayLocalSound(sound) -- spielt auch im Edit-Modus
			playBtn.Text = "Stopp"
		end
		return
	end
	if not track then return end
	if stepConn then
		stepConn:Disconnect() stepConn = nil
		track:Stop(0)
		playBtn.Text = "Abspielen"
	else
		track:Play(0)
		stepConn = RunService.Heartbeat:Connect(function(dt) animator:StepAnimations(dt) end)
		playBtn.Text = "Stopp"
	end
end

local function showPreview()
	stopPreview()
	thumb.Image, thumb.Visible, view.Visible = "", false, true
	world = Instance.new("WorldModel")
	world.Parent = view
	local clip = loaded.clip
	if clip then
		previewAnimation(clip)
		if track then playToggle() end
		return
	end
	for _, obj in loaded.objects do
		pcall(function() obj:Clone().Parent = world end)
	end
	if #world:GetDescendants() > 0 and select(2, world:GetBoundingBox()).Magnitude > 0 then
		frameCamera(true)
	else
		-- Bild direkt anzeigen, Decal über seine Textur, sonst (Audio, Mesh) das Roblox-Vorschaubild.
		local decal = nil
		for _, obj in loaded.objects do
			if obj:IsA("Decal") then decal = obj break end
		end
		thumb.Image = loaded.kind == "Image" and "rbxassetid://" .. loaded.id
			or decal and decal.Texture
			or ("rbxthumb://type=Asset&id=%s&w=420&h=420"):format(loaded.id)
		thumb.Visible, view.Visible = true, false
	end
end

-- Laden und Einfügen -----------------------------------------------------------------------

local function urlDecode(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function header(res, name)
	for k, v in res.Headers do
		if k:lower() == name then return v end
	end
	return ""
end

local function load(q)
	if q:match("^%s*$") then return end
	loadBtn.Active, loadBtn.Text = false, "Lade …"
	status.TextColor3, status.Text = MUTED, "Lade … Hängt es? Plugins > Plugins verwalten > Asset Downloader: HTTP-Zugriff auf 127.0.0.1 erlauben."
	savedLabel.Text, row.Visible, row2.Visible, uploadBtn.Visible = "", false, false, false
	local url = ("%s/api/plugin?q=%s&place=%s"):format(SERVER, HttpService:UrlEncode(q), HttpService:UrlEncode(placeBox.Text))
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Headers = PLUGIN_HEADERS, Method ="GET" })
	loadBtn.Active, loadBtn.Text = true, "Laden"
	if not ok then
		status.TextColor3, status.Text = BAD, "Server nicht erreichbar. start.bat starten und HTTP-Zugriff fürs Plugin erlauben."
		return
	end
	if not res.Success then
		local okJson, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
		status.TextColor3, status.Text = BAD, okJson and body.error or ("HTTP " .. res.StatusCode)
		return
	end

	local id, kind, ext = header(res, "x-id"), header(res, "x-type"), header(res, "x-ext")
	local name = urlDecode(header(res, "x-name"))
	if loaded and loaded.sound then loaded.sound:Destroy() end
	loaded = { id = id, kind = kind, name = name ~= "" and name or id, objects = {} }
	if ext == "rbxm" or ext == "rbxmx" then
		local okDes, objs = pcall(SerializationService.DeserializeInstancesAsync, SerializationService, buffer.fromstring(res.Body))
		if okDes then
			loaded.objects = objs
			for _, obj in objs do
				if obj:IsA("AnimationClip") then loaded.clip = obj break end
				local inner = obj:FindFirstChildWhichIsA("AnimationClip", true)
				if inner then loaded.clip = inner break end
			end
		end
	end

	if ext == "mesh" then
		-- Rohe .mesh-Dateien kann Studio nicht aus Bytes lesen, also über die Asset-ID als MeshPart laden.
		local okMesh, part = pcall(AssetService.CreateMeshPartAsync, AssetService, "rbxassetid://" .. id)
		if not okMesh then
			part = Instance.new("Part")
			local mesh = Instance.new("SpecialMesh", part)
			mesh.MeshType, mesh.MeshId = Enum.MeshType.FileMesh, "rbxassetid://" .. id
		end
		part.Name, part.Anchored, part.Color = loaded.name, true, Color3.fromRGB(200, 200, 205)
		loaded.objects = { part }
	elseif kind == "Audio" or ext == "ogg" or ext == "mp3" or ext == "wav" or ext == "flac" then
		local sound = Instance.new("Sound")
		sound.Name, sound.SoundId = loaded.name, "rbxassetid://" .. id
		sound.Ended:Connect(function() playBtn.Text = "Abspielen" end)
		sound.Parent = widget
		loaded.sound, loaded.objects = sound, { sound }
	end

	status.TextColor3, status.Text = OK, ("%s: %s%s"):format(kind ~= "" and kind or "Asset", loaded.name, #loaded.objects == 0 and ext:match("^rbxm") and " (Vorschau nicht möglich)" or "")
	row2.Visible = true
	uploadBtn.Visible = kind == "Image" or #loaded.objects > 0
	insertBtn.Visible = #loaded.objects > 0
	for _, obj in loaded.objects do
		if obj:IsA("ParticleEmitter") or obj:FindFirstChildWhichIsA("ParticleEmitter", true) then loaded.vfx = true end
	end
	playBtn.Visible = loaded.clip ~= nil or loaded.sound ~= nil or loaded.vfx == true
	row.Visible = insertBtn.Visible or playBtn.Visible
	showPreview()
end

local function insert()
	if not loaded or #loaded.objects == 0 then return end
	local rec = ChangeHistoryService:TryBeginRecording("Asset einfügen")
	local placed = {}
	if loaded.clip then
		-- Animation in AnimSaves des ausgewählten Rigs, dann kann der Animation Editor sie öffnen.
		local target = game:GetService("ServerStorage")
		local sel = Selection:Get()[1]
		local rig = sel and (sel:IsA("Model") and sel or sel:FindFirstAncestorWhichIsA("Model"))
		if rig and rig:FindFirstChildWhichIsA("Humanoid", true) then
			local saves = rig:FindFirstChild("AnimSaves")
			if not saves then
				saves = Instance.new("ObjectValue")
				saves.Name = "AnimSaves"
				saves.Parent = rig
			end
			target = saves
		end
		local copy = loaded.clip:Clone()
		copy.Name = loaded.name
		copy.Parent = target
		table.insert(placed, copy)
	else
		-- Direkt vor die Kamera. Alle Eigenschaften und Attribute (z. B. EmitCount) kommen unverändert aus der Datei.
		local camCf = workspace.CurrentCamera.CFrame
		local pos = camCf.Position + camCf.LookVector * 12
		local holder = nil
		for _, obj in loaded.objects do
			local copy = obj:Clone()
			if copy:IsA("PVInstance") then
				copy.Parent = workspace
				pcall(function() copy:PivotTo(CFrame.new(pos) * copy:GetPivot().Rotation) end)
				table.insert(placed, copy)
			else
				-- Lose Attachments, Emitter oder Beams brauchen ein Teil, an dem sie hängen.
				if not holder then
					holder = Instance.new("Part")
					holder.Name, holder.Anchored, holder.CanCollide = loaded.name, true, false
					holder.Transparency, holder.Size, holder.CFrame = 1, Vector3.one, CFrame.new(pos)
					holder.Parent = workspace
					table.insert(placed, holder)
				end
				copy.Parent = holder
			end
		end
	end
	loaded.placed = placed
	Selection:Set(placed)
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	status.TextColor3, status.Text = OK, "Platziert in " .. placed[1].Parent:GetFullName()
end

-- VFX abspielen: Emitter der platzierten Kopie auslösen, mit EmitCount/EmitDelay-Attributen falls vorhanden.
local function emitIn(roots)
	local n = 0
	for _, root in roots do
		local list = root:GetDescendants()
		table.insert(list, root)
		for _, e in list do
			if e:IsA("ParticleEmitter") then
				local count, delay = e:GetAttribute("EmitCount") or 20, e:GetAttribute("EmitDelay") or 0
				task.delay(tonumber(delay) or 0, function() e:Emit(tonumber(count) or 20) end)
				n += 1
			end
		end
	end
	return n
end

local function emitVfx()
	if not loaded.placed then
		status.TextColor3, status.Text = BAD, "Erst Platzieren, dann Abspielen. Partikel zeigt Studio nur im Workspace."
		return
	end
	emitIn(loaded.placed)
end

-- Auswahl abspielen. Attachments und Emitter ohne Part zeigen nichts, deshalb hängen sie
-- in der Kopie an einem unsichtbaren Halter-Part.
local function isLoose(obj)
	return (obj:IsA("Attachment") and not obj.Parent:IsA("BasePart"))
		or ((obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam"))
			and not (obj.Parent:IsA("BasePart") or obj.Parent:IsA("Attachment")))
end

local function playSelection(outLabel)
	local sel = Selection:Get()
	if #sel == 0 then
		outLabel.TextColor3, outLabel.Text = BAD, "Erst die VFX im Explorer anklicken."
		return
	end
	-- Immer eine Kopie 12 Studs vor der Kamera: Die VFX muss weder im Workspace liegen,
	-- noch muss man zu ihr hinfliegen. Archivable = false, damit nichts davon gespeichert wird.
	local camCf = workspace.CurrentCamera.CFrame
	local cf = CFrame.new(camCf.Position + camCf.LookVector * 12)
	local preview = Instance.new("Model")
	preview.Name, preview.Archivable = "VFX Vorschau", false
	local holder = Instance.new("Part")
	holder.Name, holder.Anchored, holder.CanCollide, holder.CanQuery = "Halter", true, false, false
	holder.Transparency, holder.Size, holder.CFrame = 1, Vector3.one, cf
	local parts = Instance.new("Model")
	parts.Name = "Kopien"
	for _, root in sel do
		-- Ganzes Objekt kopieren, damit Beams und Trails ihre Attachments in der Kopie behalten.
		local copy = root:Clone()
		if not copy then continue end -- Archivable = false lässt sich nicht kopieren
		if isLoose(root) then
			copy.Parent = holder
			continue
		end
		copy.Parent = parts
		local list = copy:GetDescendants()
		table.insert(list, 1, copy)
		for _, obj in list do
			if obj:IsA("BasePart") then
				obj.Anchored, obj.CanCollide = true, false
			elseif obj ~= copy and isLoose(obj) then
				obj.Parent = holder
			end
		end
	end
	if parts:FindFirstChildWhichIsA("BasePart", true) then parts:PivotTo(cf) end
	parts.Parent, holder.Parent = preview, preview
	preview.Parent = workspace
	local n = emitIn({ preview })
	-- Kopie wieder weg, wenn die letzten Partikel verschwunden sind.
	local life = 3
	for _, e in preview:GetDescendants() do
		if e:IsA("ParticleEmitter") then
			life = math.max(life, (tonumber(e:GetAttribute("EmitDelay")) or 0) + e.Lifetime.Max)
		end
	end
	task.delay(math.min(life + 1, 30), function() preview:Destroy() end)
	outLabel.TextColor3 = n > 0 and OK or BAD
	outLabel.Text = n == 0 and "In der Auswahl sind keine ParticleEmitter."
		or ("%d Emitter ausgelöst. Spielt als Kopie vor deiner Kamera, das Original bleibt unverändert."):format(n)
end

local cart, bulkItems = {}, {}
-- Explorer-Auswahl hinter der Bulk-Liste bzw. dem Korb: gibt dem Ordner den Namen und kommt als .rbxm mit.
local bulkSource, cartSource

local function listButton(text, parent)
	local b = makeButton(text, FIELD)
	b.Parent = parent
	b.Font, b.TextSize = Enum.Font.Gotham, 13
	b.TextXAlignment, b.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd
	Instance.new("UIPadding", b).PaddingLeft = UDim.new(0, 8)
	return b
end

local function refreshCart()
	for _, child in cartList:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	for i, item in cart do
		local b = listButton(("x  %s: %s"):format(item.kind ~= "" and item.kind or "Asset", item.name), cartList)
		b.LayoutOrder = i
		b.Activated:Connect(function()
			table.remove(cart, table.find(cart, item))
			refreshCart()
		end)
	end
	cartTitle.Text = #cart == 0 and "Korb ist leer. Im Tab Laden \"In den Korb\" drücken." or ("%d im Korb. Eintrag anklicken entfernt ihn."):format(#cart)
	tabs.Korb.Text = #cart == 0 and "Korb" or ("Korb (%d)"):format(#cart)
	local images = 0
	for _, item in cart do
		if item.kind == "Image" then images += 1 end
	end
	folderBox.Visible, cartBtn.Visible, cartUploadBtn.Visible = #cart > 0, #cart > 0, images > 0
end

local function addToCart(id, name, kind)
	for _, item in cart do
		if item.id == id then return end
	end
	table.insert(cart, { id = id, name = name, kind = kind })
	refreshCart()
end

-- Knopftext mit Fortschritt, z. B. "Speichere 40% (4/10) …".
local function progress(verb, done, total)
	return ("%s %d%% (%d/%d) …"):format(verb, math.floor(done / total * 100), done, total)
end

-- Lädt die IDs neu von Roblox und speichert sie über den Server in downloads/ (oder downloads/<folder>).
-- In Paketen, damit der Knopf zeigt, wie weit es ist.
local SAVE_BATCH = 5
local function save(ids, folder, btn, idleText)
	btn.Active = false
	local url = ("%s/api/plugin-save?place=%s&folder=%s"):format(SERVER, HttpService:UrlEncode(placeBox.Text), HttpService:UrlEncode(folder))
	local r = { saved = 0, total = #ids, folder = folder, errors = {} }
	for first = 1, #ids, SAVE_BATCH do
		btn.Text = progress("Speichere", first - 1, #ids)
		local batch = table.move(ids, first, math.min(first + SAVE_BATCH - 1, #ids), 1, {})
		local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Headers = PLUGIN_HEADERS, Method ="POST", Body = table.concat(batch, "\n") })
		if not ok or not res.Success then
			btn.Active, btn.Text = true, idleText
			status.TextColor3, status.Text = BAD, "Speichern fehlgeschlagen. Läuft start.bat?"
			return nil
		end
		local part = HttpService:JSONDecode(res.Body)
		r.saved += part.saved
		r.folder = part.folder
		table.move(part.errors, 1, #part.errors, #r.errors + 1, r.errors)
	end
	btn.Active, btn.Text = true, idleText
	local lines = { ("%d/%d gespeichert in %s"):format(r.saved, r.total, r.folder) }
	for _, e in r.errors do
		table.insert(lines, ("%s: %s"):format(e.id, e.error))
	end
	savedLabel.Text = table.concat(lines, "\n")
	-- Status steht über allen Tabs, damit man das Ergebnis auch im Korb-Tab sieht.
	status.TextColor3, status.Text = #r.errors == 0 and OK or BAD, lines[1]
	return r
end

-- Textur-Eigenschaften, die VFX und Models benutzen.
local TEXTURE_PROPS = { ParticleEmitter = "Texture", Beam = "Texture", Trail = "Texture", Decal = "Texture",
	Texture = "Texture", MeshPart = "TextureID", SpecialMesh = "TextureId" }

-- Sammelt alle Textur-IDs in den Objekten: { [id] = { {obj, prop}, ... } }
local function collectTextures(roots)
	local found = {}
	local function visit(obj)
		local prop = TEXTURE_PROPS[obj.ClassName]
		if prop then
			local value = tostring(obj[prop])
			local id = value:match("rbxassetid://(%d+)") or value:match("[?&][iI][dD]=(%d+)")
			if id then
				found[id] = found[id] or {}
				table.insert(found[id], { obj, prop })
			end
		end
	end
	for _, r in roots do
		visit(r)
		for _, d in r:GetDescendants() do visit(d) end
	end
	return found
end

-- Lässt den Server das Bild unter deinem Account neu hochladen (Open Cloud; Studio selbst darf das noch nicht).
-- Gibt die neue Bild-ID oder nil, Fehler.
local function reupload(id)
	local url = ("%s/api/plugin-upload?q=%s&user=%d&place=%s"):format(SERVER, id,
		game:GetService("StudioService"):GetUserId(), HttpService:UrlEncode(placeBox.Text))
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Headers = PLUGIN_HEADERS, Method ="GET" })
	if not ok then return nil, "Server nicht erreichbar oder Zeitüberschreitung" end
	local okJson, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
	if not res.Success then return nil, okJson and body.error or ("HTTP " .. res.StatusCode) end
	return okJson and body.id or nil, "Antwort unlesbar"
end

-- Lädt jede Textur neu hoch und setzt die neuen IDs ein. Gibt Textzeilen für die Anzeige und ob alles klappte.
local function repairTextures(found, ids, btn)
	-- Schon reparierte IDs merken, damit dieselbe Textur nicht doppelt hochgeladen wird.
	local map = plugin:GetSetting("repaired") or {}
	local errors, done = {}, 0
	for i, id in ids do
		btn.Text = progress("Lade hoch", i - 1, #ids)
		if not map[id] then
			local newId, err = reupload(id)
			if newId then map[id] = newId else table.insert(errors, id .. ": " .. err) end
		end
	end
	plugin:SetSetting("repaired", map)
	local rec = ChangeHistoryService:TryBeginRecording("VFX-Texturen reparieren")
	for id, uses in found do
		if map[id] then
			for _, use in uses do
				use[1][use[2]] = "rbxassetid://" .. map[id]
				done += 1
			end
		end
	end
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	local lines = { ("%d von %d Texturen repariert (%d Stellen). Neue Bilder brauchen evtl. kurz für die Freigabe."):format(#ids - #errors, #ids, done) }
	for _, e in errors do table.insert(lines, e) end
	return lines, #errors == 0, map
end

-- Objekte sichern: optional Texturen unter eigenem Namen hochladen und IDs tauschen,
-- dann .rbxm + alle Texturen nach downloads/<name>/. Nach dem Hochladen tragen Datei und Bilder die neuen IDs.
-- Schreibt Bytes als Datei nach downloads/<folder>/<file> (leer = <folder>.rbxm). Hex, weil Luau-Strings
-- im HTTP-Body sonst nicht binär-sicher ankommen.
local HEX = {}
for i = 0, 255 do HEX[string.char(i)] = string.format("%02x", i) end

local function store(folder, file, bytes)
	local hex = bytes:gsub(".", HEX) -- Tabelle statt Funktion: bei ganzen Places (viele MB) deutlich schneller
	local url = ("%s/api/plugin-store?folder=%s&file=%s"):format(SERVER, HttpService:UrlEncode(folder), HttpService:UrlEncode(file))
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Headers = PLUGIN_HEADERS, Method ="POST", Body = hex })
	return ok and res.Success
end

local function backup(roots, name, repair, btn, idleText, outLabel)
	local found, ids = collectTextures(roots), {}
	for id in found do table.insert(ids, id) end
	btn.Active = false
	local lines, allOk, map = {}, true, {}
	if repair and #ids > 0 then lines, allOk, map = repairTextures(found, ids, btn) end

	btn.Text = "Speichere …"
	local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, roots)
	local stored = okSer and store(name, "", buffer.tostring(buf))
	table.insert(lines, stored and ("Gespeichert: downloads/%s/%s.rbxm"):format(name, name) or "Datei konnte nicht gespeichert werden. Läuft start.bat?")
	if #ids > 0 then
		local fileIds = {}
		for _, id in ids do table.insert(fileIds, map[id] or id) end
		local r = save(fileIds, name, btn, "Speichere …")
		table.insert(lines, r and ("%d/%d Texturen als Bild gespeichert."):format(r.saved, r.total) or "Texturen konnten nicht gespeichert werden.")
		allOk = allOk and r ~= nil and r.saved == r.total
	end
	btn.Active, btn.Text = true, idleText
	outLabel.TextColor3, outLabel.Text = (allOk and stored) and OK or BAD, table.concat(lines, "\n")
end

local function backupSelection(repair)
	local sel = Selection:Get()
	if #sel == 0 then
		vfxLabel.TextColor3, vfxLabel.Text = BAD, "Erst den VFX-Ordner im Explorer anklicken."
		return
	end
	saveSelBtn.Active, repairBtn.Active = false, false
	backup(sel, sel[1].Name, repair, repair and repairBtn or saveSelBtn,
		repair and "Reparieren und sichern" or "Nur sichern (nichts hochladen)", vfxLabel)
	saveSelBtn.Active, repairBtn.Active = true, true
end

local function loadBulk()
	local text = bulkBox.Text
	if text:match("^%s*$") or not bulkBtn.Active then return end
	bulkBtn.Active, bulkBtn.Text = false, "Lade Liste …"
	local url = ("%s/api/plugin-bulk?place=%s"):format(SERVER, HttpService:UrlEncode(placeBox.Text))
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Headers = PLUGIN_HEADERS, Method ="POST", Body = text })
	bulkBtn.Active, bulkBtn.Text = true, "Liste laden"
	if not ok or not res.Success then
		local okJson, body = pcall(HttpService.JSONDecode, HttpService, ok and res.Body or "")
		status.TextColor3, status.Text = BAD, okJson and body.error or "Server nicht erreichbar. start.bat starten."
		return
	end
	for _, child in results:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	bulkItems = HttpService:JSONDecode(res.Body)
	for i, item in bulkItems do
		local line = Instance.new("Frame")
		line.Size, line.BackgroundTransparency, line.LayoutOrder = UDim2.new(1, 0, 0, 34), 1, i
		line.Parent = results
		local b = listButton(("%s: %s"):format(item.type ~= "" and item.type or "Asset", item.name), line)
		b.Size = UDim2.new(1, -42, 1, 0)
		b.Activated:Connect(function()
			idBox.Text = item.id
			bulkPreviewUsed = true
			showTab("Bulk") -- Vorschau erscheint oben im Bulk-Tab, kein Tabwechsel
			load(item.id)
		end)
		local plus = makeButton("+", GREY)
		plus.Parent = line
		plus.Size, plus.Position = UDim2.new(0, 34, 1, 0), UDim2.new(1, -34, 0, 0)
		plus.Activated:Connect(function() addToCart(item.id, item.name, item.type) end)
	end
	bulkAllBtn.Visible = #bulkItems > 0
	status.TextColor3, status.Text = OK, ("%d Assets gefunden. Anklicken für Vorschau, + legt in den Korb."):format(#bulkItems)
end

loadBtn.Activated:Connect(function() if loadBtn.Active then load(idBox.Text) end end)
idBox.FocusLost:Connect(function(enter) if enter then load(idBox.Text) end end)
bulkBtn.Activated:Connect(loadBulk)

-- Eigenschaften, in denen Assets per ID stecken.
local ID_PROPS = { Animation = { "AnimationId" }, Sound = { "SoundId" }, ParticleEmitter = { "Texture" },
	Beam = { "Texture" }, Trail = { "Texture" }, Decal = { "Texture" }, Texture = { "Texture" },
	MeshPart = { "MeshId", "TextureID" }, SpecialMesh = { "MeshId", "TextureId" }, ImageLabel = { "Image" },
	ImageButton = { "Image" }, Shirt = { "ShirtTemplate" }, Pants = { "PantsTemplate" }, ShirtGraphic = { "Graphic" } }

-- Alle Asset-IDs in der Explorer-Auswahl und darunter, ohne Duplikate, in Explorer-Reihenfolge.
local function idsIn(roots)
	local ids, seen = {}, {}
	local function visit(obj)
		for _, prop in ID_PROPS[obj.ClassName] or {} do
			local value = tostring(obj[prop])
			local id = value:match("rbxassetid://(%d+)") or value:match("[?&][iI][dD]=(%d+)")
			if id and not seen[id] then
				seen[id] = true
				table.insert(ids, id)
			end
		end
	end
	for _, r in roots do
		visit(r)
		for _, d in r:GetDescendants() do visit(d) end
	end
	return ids
end

local function idsInSelection() return idsIn(Selection:Get()) end

-- ClientFX ---------------------------------------------------------------------------------

-- fx[name] = { server = { {script, line} }, client = { {script, line} } }
local fx = {}

local function scanFx()
	fx = {}
	local scripts = {}
	for _, obj in game:GetDescendants() do
		if obj:IsA("LuaSourceContainer") then
			local ok, src = pcall(function() return obj.Source end)
			if ok and src ~= "" then table.insert(scripts, { obj, src }) end
		end
	end
	-- 1. Server-Seite: X:FireAllClients("Name", …) bzw. X:FireClient(spieler, "Name", …), wobei X ClientFX ist
	-- oder eine Variable, der ClientFX zugewiesen wurde (dekompilierter Code: v21 = ClientFX). Auch über mehrere Zeilen.
	for _, s in scripts do
		local src = s[2]
		local remote = remoteName()
		if src:find(remote, 1, true) then
			local aliases = { [remote] = true }
			for a in src:gmatch("([%w_]+)%s*=%s*" .. remote:gsub("%p", "%%%0") .. "%f[^%w_]") do aliases[a] = true end
			local pos, line, counted = 1, 1, 1
			while true do
				local st, en, recv, args = src:find("([%w_%.]+)%s*:%s*Fire%a*Clients?%s*(%b())", pos)
				if not st then break end
				line += select(2, src:sub(counted, st):gsub("\n", ""))
				counted, pos = st + 1, en + 1
				local name = aliases[recv:match("([%w_]+)$")] and args:match("[\"']([^\"']+)[\"']")
				if name then
					fx[name] = fx[name] or { server = {}, client = {} }
					-- Parameter-Namen für die Vorlage: Tabelle direkt im Aufruf, sonst Zuweisungen an die Variable (v23.Origin = …).
					local keys, seenKey = fx[name].keys or {}, {}
					for _, k in keys do seenKey[k] = true end
					local tbl = args:match("%b{}")
					local var = not tbl and args:match(",%s*([%a_][%w_]*)%s*%)$")
					local scan = tbl or (var and src:sub(math.max(1, st - 3000), st):gsub(var .. "%.", "\0")) or ""
					for k in scan:gmatch((tbl and "([%a_][%w_]*)%s*=" or "\0([%a_][%w_]*)%s*=")) do
						if not seenKey[k] then seenKey[k] = true table.insert(keys, k) end
					end
					fx[name].keys = keys
					table.insert(fx[name].server, { s[1], line })
				end
			end
		end
	end
	-- 2. Client-Seite: Name als String in einem LocalScript/ModuleScript (ohne Fire), oder ein Modul mit dem Namen.
	for _, s in scripts do
		if not s[1]:IsA("Script") or s[1].RunContext == Enum.RunContext.Client then
			local n = 0
			for line in (s[2] .. "\n"):gmatch("(.-)\n") do
				n += 1
				if not line:find("Fire", 1, true) then
					for str in line:gmatch("[\"']([^\"']+)[\"']") do
						local entry = fx[str]
						if entry and #entry.client < 5 then table.insert(entry.client, { s[1], n }) end
					end
				end
			end
		end
		local entry = fx[s[1].Name]
		if entry and s[1]:IsA("ModuleScript") then table.insert(entry.client, 1, { s[1], 1 }) end
	end
	return #scripts
end

-- Alles zu einem Effekt aus der offenen Place: Scripts, in denen der Name vorkommt, Objekte mit passendem
-- Namen (z. B. BarrageTrail) und alle Asset-IDs darin. Landet in downloads/<Name>/.
local function exportPackage(name, btn)
	btn.Active, btn.Text = false, "…"
	local key = (name:match("([%w_]+)$") or name):lower() -- "Stand Barrage" -> "barrage"
	local scripts, objects, code, ids, seen = {}, {}, {}, {}, {}
	local function addId(id)
		if #id >= 5 and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	for _, obj in game:GetDescendants() do
		if obj:IsA("LuaSourceContainer") then
			local ok, src = pcall(function() return obj.Source end)
			if ok and (src:find('"' .. name .. '"', 1, true) or src:find("'" .. name .. "'", 1, true)) then
				table.insert(scripts, obj)
				table.insert(code, ("-- ===== %s (%s) =====\n%s"):format(obj:GetFullName(), obj.ClassName, src))
				for id in src:gmatch("rbxassetid://(%d+)") do addId(id) end
				for id in src:gmatch("[?&][iI][dD]=(%d+)") do addId(id) end
			end
		elseif #key >= 4 and #objects < 50 and obj.Name:lower():find(key, 1, true) then
			local inside = false
			for _, o in objects do
				if obj:IsDescendantOf(o) then inside = true break end
			end
			if not inside then table.insert(objects, obj) end
		end
	end

	-- Ein Ordner mit Code/ und Objekte/, so wie im Explorer.
	local pack = Instance.new("Folder")
	pack.Name = name
	for folderName, list in { Code = scripts, Objekte = objects } do
		local f = Instance.new("Folder")
		f.Name, f.Parent = folderName, pack
		for _, obj in list do
			local ok, copy = pcall(function() return obj:Clone() end)
			if ok and copy then copy.Parent = f end -- nicht archivierbare Objekte liefern nil
		end
	end
	for _, id in idsIn(objects) do addId(id) end

	local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, { pack })
	pack:Destroy()
	local lines = {
		("%d Scripts, %d Objekte, %d Asset-IDs gefunden."):format(#scripts, #objects, #ids),
		(okSer and store(name, "", buffer.tostring(buf))) and ("Gespeichert: downloads/%s/%s.rbxm"):format(name, name) or "Paket konnte nicht gespeichert werden. Läuft start.bat?",
	}
	if #code > 0 and store(name, "code.lua", table.concat(code, "\n\n")) then table.insert(lines, "Code zum Lesen: code.lua") end
	if #ids > 0 then
		local r = save(ids, name, btn, "…")
		if r then table.insert(lines, ("%d/%d Assets gespeichert."):format(r.saved, r.total)) end
	end
	if fx[name] and #fx[name].client == 0 then table.insert(lines, "Achtung: Client-Code für diesen Effekt fehlt in dieser Place.") end
	btn.Active, btn.Text = true, "Paket"
	status.TextColor3, status.Text = OK, table.concat(lines, "\n")
end

-- Pfad als Code, z. B. game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("ClientFX")
local function pathCode(inst)
	local chain, node = {}, inst
	while node.Parent and node.Parent ~= game do
		table.insert(chain, 1, (':WaitForChild("%s")'):format(node.Name))
		node = node.Parent
	end
	return ('game:GetService("%s")'):format(node.ClassName) .. table.concat(chain)
end

local renderFx -- weiter unten definiert, createTemplate braucht es schon

-- Fehlender Client-Effekt: LocalScript-Gerüst, das schon auf den Namen hört und die Parameter kennt.
local function createTemplate(name)
	local entry = fx[name]
	local remote = nil
	for _, obj in game:GetDescendants() do
		if obj.Name == remoteName() and obj:IsA("RemoteEvent") then remote = obj break end
	end
	local params = {}
	for _, k in entry.keys or {} do table.insert(params, ("\t-- data.%s"):format(k)) end
	local where = entry.server[1] and ("%s, Zeile %d"):format(entry.server[1][1]:GetFullName(), entry.server[1][2]) or "?"
	local source = table.concat({
		("-- Vorlage vom Asset Downloader für den Client-Effekt \"%s\"."):format(name),
		("-- Der Server feuert ihn hier: %s"):format(where),
		"-- Baue den Effekt unten ein. Läuft auf jedem Client, sobald der Server ClientFX feuert.",
		"",
		("local ClientFX = %s"):format(remote and pathCode(remote) or 'game:GetService("ReplicatedStorage"):WaitForChild("ClientFX") -- Pfad anpassen'),
		"",
		"ClientFX.OnClientEvent:Connect(function(name, data)",
		("\tif name ~= \"%s\" then return end"):format(name),
		"\t-- Parameter vom Server:",
		#params > 0 and table.concat(params, "\n") or "\t-- (keine gefunden, siehe Server-Aufruf)",
		"",
		"\t-- TODO: Effekt hier bauen",
		"end)",
		"",
	}, "\n")
	local rec = ChangeHistoryService:TryBeginRecording("ClientFX-Vorlage")
	local created = nil
	local ok, err = pcall(function()
		local s = Instance.new("LocalScript")
		created = s
		s.Name = "ClientFX " .. name
		s.Source = source
		s.Parent = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
		plugin:OpenScript(s)
	end)
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	if ok then
		table.insert(entry.client, { created, 1 })
		renderFx()
	end
	status.TextColor3 = ok and OK or BAD
	status.Text = ok and ("Vorlage angelegt: StarterPlayerScripts.ClientFX %s"):format(name)
		or ("Vorlage ging nicht: %s. Studio muss dem Plugin Script-Zugriff erlauben."):format(tostring(err))
end

function renderFx()
	for _, child in fxList:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local filter = fxFilter.Text:lower()
	local names = {}
	for name in fx do
		if filter == "" or name:lower():find(filter, 1, true) then table.insert(names, name) end
	end
	table.sort(names)
	for i, name in names do
		if i > 200 then break end -- shortcut: nur die ersten 200 zeigen, bei mehr Filter benutzen
		local entry = fx[name]
		local line = Instance.new("Frame")
		line.Size, line.BackgroundTransparency, line.LayoutOrder = UDim2.new(1, 0, 0, 30), 1, i
		line.Parent = fxList
		local title = listButton(name, line)
		title.Size = UDim2.new(1, -196, 1, 0)
		title.AutoButtonColor = false
		title.TextColor3 = #entry.client == 0 and BAD or TEXT
		local pack = makeButton("Paket", GREEN)
		pack.Size, pack.Position, pack.TextSize = UDim2.new(0, 56, 1, 0), UDim2.new(1, -192, 0, 0), 11
		pack.Parent = line
		pack.Activated:Connect(function() if pack.Active then exportPackage(name, pack) end end)
		local srv = makeButton(("Server %d"):format(#entry.server), GREY)
		srv.Size, srv.Position, srv.TextSize = UDim2.new(0, 64, 1, 0), UDim2.new(1, -132, 0, 0), 11
		srv.Parent = line
		srv.Activated:Connect(function() plugin:OpenScript(entry.server[1][1], entry.server[1][2]) end)
		local cli = makeButton(#entry.client > 0 and "Client" or "Vorlage", #entry.client > 0 and BLUE or PURPLE)
		cli.Size, cli.Position, cli.TextSize = UDim2.new(0, 64, 1, 0), UDim2.new(1, -64, 0, 0), 11
		cli.Parent = line
		cli.Activated:Connect(function()
			if entry.client[1] then
				plugin:OpenScript(entry.client[1][1], entry.client[1][2])
			else
				createTemplate(name)
			end
		end)
	end
end

fxScanBtn.Activated:Connect(function()
	fxScanBtn.Text = "Suche …"
	local count = scanFx()
	local total, missing = 0, 0
	for _, entry in fx do
		total += 1
		if #entry.client == 0 then missing += 1 end
	end
	fxScanBtn.Text = "ClientFX suchen"
	fxFilter.Visible = total > 0
	renderFx()
	status.TextColor3 = total > 0 and OK or BAD
	status.Text = total == 0 and ("Keine ClientFX-Aufrufe in %d Scripts gefunden."):format(count)
		or ("%d ClientFX gefunden, %d ohne Client-Code (rot). %d Scripts durchsucht."):format(total, missing, count)
end)
fxFilter:GetPropertyChangedSignal("Text"):Connect(renderFx)

pickBtn.Activated:Connect(function()
	local ids = idsInSelection()
	if #ids == 0 then
		status.TextColor3, status.Text = BAD, "In der Auswahl steckt keine Asset-ID. Klick z. B. eine Animation oder einen ParticleEmitter an."
	elseif #ids == 1 then
		idBox.Text = ids[1]
		load(ids[1])
	else
		local sel = Selection:Get()
		bulkBox.Text = table.concat(ids, "\n")
		bulkSource = { name = #sel == 1 and sel[1].Name or ("%s +%d"):format(sel[1].Name, #sel - 1), objects = sel, text = bulkBox.Text }
		showTab("Bulk")
		loadBulk()
	end
end)
cartAddBtn.Activated:Connect(function()
	if loaded then addToCart(loaded.id, loaded.name, loaded.kind) end
end)
downloadBtn.Activated:Connect(function()
	if not loaded or not downloadBtn.Active then return end
	-- Model/VFX: eigener Ordner mit der .rbxm und allen Texturen, die darin benutzt werden.
	local ids = { loaded.id }
	for id in collectTextures(loaded.objects) do table.insert(ids, id) end
	save(ids, #ids > 1 and loaded.name or "", downloadBtn, "Herunterladen")
end)
repairBtn.Activated:Connect(function() if repairBtn.Active then backupSelection(true) end end)
saveSelBtn.Activated:Connect(function() if saveSelBtn.Active then backupSelection(false) end end)
playSelBtn.Activated:Connect(function() playSelection(vfxLabel) end)

-- Zu anderer Place: Auswahl über den lokalen Server von einem Studio-Fenster ins andere.
local TRANSFER = "_senden"

sendBtn.Activated:Connect(function()
	local sel = Selection:Get()
	if #sel == 0 then
		transferLabel.TextColor3, transferLabel.Text = BAD, "Erst etwas im Explorer auswählen."
		return
	end
	local ok, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, sel)
	if not ok then
		transferLabel.TextColor3, transferLabel.Text = BAD, "Auswahl ließ sich nicht speichern: " .. tostring(buf)
		return
	end
	local parents = {}
	for _, obj in sel do table.insert(parents, obj.Parent and obj.Parent:GetFullName() or "") end
	sendBtn.Active, sendBtn.Text = false, "Sende …"
	local sent = store(TRANSFER, "auswahl.rbxm", buffer.tostring(buf)) and store(TRANSFER, "ziel.json", HttpService:JSONEncode(parents))
	sendBtn.Active, sendBtn.Text = true, "Auswahl senden"
	if sent then
		transferLabel.TextColor3, transferLabel.Text = OK, ("%d Objekt(e) gesendet. In der anderen Place: Hier empfangen."):format(#sel)
	else
		transferLabel.TextColor3, transferLabel.Text = BAD, "Senden fehlgeschlagen. Läuft start.bat?"
	end
end)

local function fetchSent(file)
	local url = ("%s/api/plugin-file?folder=%s&file=%s"):format(SERVER, TRANSFER, file)
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Headers = PLUGIN_HEADERS, Method = "GET" })
	return ok and res.Success and res.Body or nil
end

-- "ReplicatedStorage.Anims.Boxing" so weit auflösen, wie es diese Place hergibt.
local function deepestExisting(path)
	local at = game
	for _, part in path:split(".") do
		local nextInst = at:FindFirstChild(part)
		if not nextInst then break end
		at = nextInst
	end
	return at ~= game and at or workspace
end

receiveBtn.Activated:Connect(function()
	local data = fetchSent("auswahl.rbxm")
	if not data then
		transferLabel.TextColor3, transferLabel.Text = BAD, "Nichts zum Empfangen. Erst in der anderen Place senden, und läuft start.bat?"
		return
	end
	local okDes, objs = pcall(SerializationService.DeserializeInstancesAsync, SerializationService, buffer.fromstring(data))
	if not okDes then
		transferLabel.TextColor3, transferLabel.Text = BAD, "Gesendete Datei unlesbar: " .. tostring(objs)
		return
	end
	local okJson, parents = pcall(HttpService.JSONDecode, HttpService, fetchSent("ziel.json") or "")
	parents = okJson and parents or {}
	local rec = ChangeHistoryService:TryBeginRecording("Asset Downloader: Empfangen")
	local where = {}
	for i, obj in objs do
		local target = deepestExisting(parents[i] or "")
		obj.Parent = target
		where[target:GetFullName()] = true
	end
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	Selection:Set(objs)
	local list = {}
	for path in where do table.insert(list, path) end
	transferLabel.TextColor3, transferLabel.Text = OK, ("%d Objekt(e) empfangen in %s."):format(#objs, table.concat(list, ", "))
end)

-- Ganze Place: pro Dienst eine Datei, damit keine Anfrage riesig wird.
local PLACE_SERVICES = { "Workspace", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService",
	"ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "SoundService", "Teams", "Chat", "TextChatService",
	"MaterialService" }
-- Feste Kinder, die Studio selbst verwaltet: nicht löschen, Inhalt austauschen statt Objekt.
local FIXED = { StarterPlayerScripts = true, StarterCharacterScripts = true }
local SKIP = { Camera = true, Terrain = true }
-- Einstellungen der Dienste selbst. Reisen als Attribute an einem Ordner mit, weil Attribute Color3 & Co. können.
local SERVICE_PROPS = {
	Lighting = { "Ambient", "Brightness", "ClockTime", "ColorShift_Bottom", "ColorShift_Top", "EnvironmentDiffuseScale",
		"EnvironmentSpecularScale", "GlobalShadows", "OutdoorAmbient", "ShadowSoftness", "GeographicLatitude",
		"ExposureCompensation", "FogColor", "FogEnd", "FogStart" },
	Workspace = { "Gravity", "FallenPartsDestroyHeight", "AirDensity" },
	StarterPlayer = { "CameraMaxZoomDistance", "CameraMinZoomDistance", "CharacterWalkSpeed", "CharacterJumpPower",
		"CharacterJumpHeight", "CharacterUseJumpPower", "CharacterMaxSlopeAngle", "AutoJumpEnabled",
		"LoadCharacterAppearance", "HealthDisplayDistance", "NameDisplayDistance" },
}
local PROPS_NAME, TERRAIN_NAME = "__AssetDownloaderProps", "__AssetDownloaderTerrain"

sendPlaceBtn.Activated:Connect(function()
	if RunService:IsRunning() then
		transferLabel.TextColor3, transferLabel.Text = BAD, "Erst den Play-Test beenden."
		return
	end
	sendPlaceBtn.Active = false
	local sent, empty, failed, total = {}, {}, {}, 0
	for _, svcName in PLACE_SERVICES do
		sendPlaceBtn.Text = "Sende " .. svcName .. " …"
		local svc = game:FindFirstChildOfClass(svcName) or game:FindFirstChild(svcName)
		if svc then
			local roots, temp = {}, {}
			for _, child in svc:GetChildren() do
				if not (svc == workspace and SKIP[child.Name]) and child.Archivable then table.insert(roots, child) end
			end
			if SERVICE_PROPS[svcName] then
				local props = Instance.new("Folder")
				props.Name = PROPS_NAME
				for _, prop in SERVICE_PROPS[svcName] do
					pcall(function() props:SetAttribute(prop, svc[prop]) end)
				end
				table.insert(roots, props)
				table.insert(temp, props)
			end
			if svc == workspace and workspace.Terrain:CountCells() > 0 then
				local okT, region = pcall(function() return workspace.Terrain:CopyRegion(workspace.Terrain.MaxExtents) end)
				if okT and region then
					region.Name = TERRAIN_NAME
					table.insert(roots, region)
					table.insert(temp, region)
				end
			end
			local ok, buf = false, nil
			if #roots > 0 then ok, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, roots) end
			for _, t in temp do t:Destroy() end
			if #roots == 0 then
				table.insert(empty, svcName) -- leer heißt: in der Ziel-Place auch leeren, für 1:1
			elseif ok and store(TRANSFER, svcName .. ".rbxm", buffer.tostring(buf)) then
				table.insert(sent, svcName)
				total += #roots
			else
				table.insert(failed, svcName)
			end
		end
	end
	store(TRANSFER, "place.json", HttpService:JSONEncode({ services = sent, empty = empty }))
	sendPlaceBtn.Active, sendPlaceBtn.Text = true, "Place senden"
	if #failed == 0 then
		transferLabel.TextColor3 = OK
		transferLabel.Text = ("Ganze Place gesendet: %d Dienste, %d Objekte. In der anderen Place: Place empfangen."):format(#sent, total)
	else
		transferLabel.TextColor3 = BAD
		transferLabel.Text = ("Gesendet: %s. Fehlgeschlagen: %s. Läuft start.bat?"):format(table.concat(sent, ", "), table.concat(failed, ", "))
	end
end)

local confirmUntil = 0
receivePlaceBtn.Activated:Connect(function()
	if RunService:IsRunning() then
		transferLabel.TextColor3, transferLabel.Text = BAD, "Erst den Play-Test beenden."
		return
	end
	local okList, manifest = pcall(HttpService.JSONDecode, HttpService, fetchSent("place.json") or "")
	local services = okList and type(manifest) == "table" and manifest.services or {}
	local emptyServices = okList and type(manifest) == "table" and manifest.empty or {}
	if #services == 0 then
		transferLabel.TextColor3, transferLabel.Text = BAD, "Keine ganze Place gesendet. Erst in der anderen Place: Ganze Place senden."
		return
	end
	if os.clock() > confirmUntil then
		confirmUntil = os.clock() + 5
		receivePlaceBtn.Text = "Sicher? Nochmal klicken"
		transferLabel.TextColor3 = BAD
		transferLabel.Text = ("Ersetzt den Inhalt dieser Place (%s). Zum Bestätigen in 5 s nochmal klicken."):format(table.concat(services, ", "))
		task.delay(5, function() receivePlaceBtn.Text = "Place empfangen" end)
		return
	end
	confirmUntil = 0
	receivePlaceBtn.Active, receivePlaceBtn.Text = false, "Empfange …"
	local rec = ChangeHistoryService:TryBeginRecording("Asset Downloader: Ganze Place empfangen")
	local done, failed, total = {}, {}, 0
	for _, svcName in emptyServices do
		local svc = game:FindFirstChildOfClass(svcName) or game:FindFirstChild(svcName)
		if svc then
			for _, child in svc:GetChildren() do
				if not FIXED[child.ClassName] then pcall(child.Destroy, child) end
			end
		end
	end
	for _, svcName in services do
		local svc = game:FindFirstChildOfClass(svcName) or game:FindFirstChild(svcName)
		local data = svc and fetchSent(svcName .. ".rbxm")
		local okDes, objs = false, nil
		if data then okDes, objs = pcall(SerializationService.DeserializeInstancesAsync, SerializationService, buffer.fromstring(data)) end
		if not okDes then
			table.insert(failed, svcName)
		else
			-- Alten Inhalt weg, außer Kamera, Terrain und festen Containern.
			for _, child in svc:GetChildren() do
				if not (svc == workspace and SKIP[child.Name]) and not FIXED[child.ClassName] then pcall(child.Destroy, child) end
			end
			for _, obj in objs do
				if obj.Name == PROPS_NAME then
					for prop, value in obj:GetAttributes() do pcall(function() svc[prop] = value end) end
					obj:Destroy()
				elseif obj.Name == TERRAIN_NAME and obj:IsA("TerrainRegion") then
					workspace.Terrain:Clear()
					pcall(function() workspace.Terrain:PasteRegion(obj, obj.ExtentsMin, true) end)
					obj:Destroy()
				elseif FIXED[obj.ClassName] and svc:FindFirstChildOfClass(obj.ClassName) then
					local existing = svc:FindFirstChildOfClass(obj.ClassName)
					for _, old in existing:GetChildren() do pcall(old.Destroy, old) end
					for _, child in obj:GetChildren() do child.Parent = existing end
					obj:Destroy()
					total += 1
				else
					local okParent = pcall(function() obj.Parent = svc end)
					if okParent then total += 1 end
				end
			end
			table.insert(done, svcName)
		end
	end
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	receivePlaceBtn.Active, receivePlaceBtn.Text = true, "Place empfangen"
	transferLabel.TextColor3 = #failed == 0 and OK or BAD
	transferLabel.Text = ("Empfangen: %d Dienste, %d Objekte.%s Strg+Z macht es rückgängig. Speichern nicht vergessen.")
		:format(#done, total, #failed > 0 and (" Fehlgeschlagen: " .. table.concat(failed, ", ") .. ".") or "")
end)
bulkAllBtn.Activated:Connect(function()
	for _, item in bulkItems do addToCart(item.id, item.name, item.type) end
	-- Liste stammt unverändert aus der Explorer-Auswahl: Ordner danach benennen, .rbxm kommt beim Herunterladen dazu.
	if bulkSource and bulkSource.text == bulkBox.Text then
		cartSource = bulkSource
		if folderBox.Text:match("^%s*$") then folderBox.Text = bulkSource.name end
	end
end)
-- Bilder unter dem eigenen Account hochladen. Liste alt -> neu landet im Kopierfeld.
local function uploadImages(items, btn, idleText)
	local map = plugin:GetSetting("repaired") or {}
	local lines, okCount = {}, 0
	btn.Active = false
	for i, item in items do
		btn.Text = progress("Lade hoch", i - 1, #items)
		local newId, err = map[item.id], nil
		if not newId then newId, err = reupload(item.id) end
		if newId then
			map[item.id] = newId
			okCount += 1
			table.insert(lines, ("%s: rbxassetid://%s"):format(item.name, newId))
		else
			table.insert(lines, ("%s: Fehler, %s"):format(item.name, err))
		end
	end
	plugin:SetSetting("repaired", map)
	btn.Active, btn.Text = true, idleText
	idsBox.Text, idsBox.Visible = table.concat(lines, "\n"), true
	status.TextColor3, status.Text = okCount == #items and OK or BAD,
		("%d/%d Bilder unter deinem Namen hochgeladen. Neue IDs stehen im Feld unten."):format(okCount, #items)
end

uploadBtn.Activated:Connect(function()
	if not loaded or not uploadBtn.Active then return end
	if loaded.kind == "Image" then
		-- Erst unter deinem Namen hochladen, dann die neue ID herunterladen.
		uploadImages({ { id = loaded.id, name = loaded.name } }, uploadBtn, "Herunterladen unter meinem Namen")
		local newId = (plugin:GetSetting("repaired") or {})[loaded.id]
		if newId then save({ newId }, "", uploadBtn, "Herunterladen unter meinem Namen") end
	else
		-- Model/VFX: Texturen hochladen, IDs in einer Kopie tauschen, dann Ordner mit .rbxm und Bildern.
		local copies = {}
		for _, obj in loaded.objects do table.insert(copies, obj:Clone()) end
		backup(copies, loaded.name, true, uploadBtn, "Herunterladen unter meinem Namen", savedLabel)
	end
end)
-- Speichert den ganzen Korb nach downloads/<Ordner>/ (plus .rbxm der Auswahl). true, wenn alles klappte.
local function downloadCart(btn, idleText)
	local ids = {}
	for _, item in cart do table.insert(ids, item.id) end
	local folder = folderBox.Text:match("^%s*(.-)%s*$")
	local name = folder ~= "" and folder or "Korb " .. os.date("%Y-%m-%d %H-%M")
	local r = save(ids, name, btn, idleText)
	local rbxmOk = true
	if r and cartSource then
		local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, cartSource.objects)
		rbxmOk = okSer and store(name, "", buffer.tostring(buf))
		status.Text ..= rbxmOk and (" + %s.rbxm"):format(name) or " (.rbxm konnte nicht gespeichert werden)"
		if not rbxmOk then status.TextColor3 = BAD end
	end
	return r ~= nil and #r.errors == 0 and rbxmOk
end

local function clearCart()
	table.clear(cart)
	cartSource, folderBox.Text = nil, ""
	refreshCart()
end

cartUploadBtn.Activated:Connect(function()
	if #cart == 0 or not cartUploadBtn.Active then return end
	local images = {}
	for _, item in cart do
		if item.kind == "Image" then table.insert(images, item) end
	end
	-- Erst herunterladen, dann hochladen: Ein Knopf für beides. Korb erst danach leeren.
	local savedOk = downloadCart(cartUploadBtn, "Herunterladen + Bilder hochladen")
	local savedText = status.Text
	uploadImages(images, cartUploadBtn, "Herunterladen + Bilder hochladen")
	local uploadedOk = status.TextColor3 == OK
	status.Text = savedText .. "\n" .. status.Text
	status.TextColor3 = savedOk and uploadedOk and OK or BAD
	if savedOk and uploadedOk then clearCart() end
end)
cartBtn.Activated:Connect(function()
	if #cart == 0 or not cartBtn.Active then return end
	if downloadCart(cartBtn, "Korb herunterladen") then clearCart() end
end)
insertBtn.Activated:Connect(insert)
playBtn.Activated:Connect(function()
	if loaded and loaded.vfx and not loaded.clip then emitVfx() else playToggle() end
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function() if not widget.Enabled then stopPreview() end end)
plugin.Unloading:Connect(stopPreview)

-- Vorschau im Spiel -------------------------------------------------------------------------
-- Dummy im Workspace statt im Vorschaufenster, damit Effekt-Module ihn wie einen echten Charakter benutzen.
local scene = nil -- { rig, step, watch, added }

local function stopScene()
	if not scene then return end
	scene.watch:Disconnect()
	if scene.step then scene.step:Disconnect() end
	for _, inst in scene.added do
		if inst.Parent then pcall(inst.Destroy, inst) end
	end
	scene.rig:Destroy()
	scene = nil
	sceneLabel.TextColor3, sceneLabel.Text = MUTED, "Gestoppt, aufgeräumt."
end

-- Objekte, die ein Effekt-Modul benutzt, aus seinem Code lesen statt den Code auszuführen.
-- Erkennt Pfade wie u5.Whitesnake.DirectOrderThrow, ["Client Assets"]["The World"].X, :WaitForChild("X")
-- und "Particles/DebrisPunch". Ein Treffer zählt nur, wenn Eltern- und Kindname zusammen passen,
-- sonst käme bei "HitEffect" der von jedem Stand mit.
local PATH_ALIASES = { ClientAssets = "Client Assets", ClientAssetsPath = "Client Assets", workspace = "Workspace" }
local VISUAL = { "BasePart", "Model", "Folder", "Attachment", "ParticleEmitter", "Beam", "Trail" }
local MAX_DESCENDANTS = 200 -- ganze Stand-Ordner (tausende Teile) sind kein Effekt

local function isVisual(obj)
	for _, c in VISUAL do
		if obj:IsA(c) then return true end
	end
	return false
end

-- Zeigt das Objekt etwas? Ein Ordner voller Sounds zählt nicht.
local function hasVisual(obj)
	if obj:IsA("BasePart") or obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") then return true end
	for _, d in obj:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then return true end
	end
	return false
end

-- Alle sichtbaren Objekte der Place nach Namen, ohne Dummy und Vorschau-Kopien.
local function visualIndex()
	local byName = {}
	for _, obj in game:GetDescendants() do
		local ok, visual = pcall(isVisual, obj) -- manche Studio-Dienste sind gesperrt
		if ok and visual then
			byName[obj.Name] = byName[obj.Name] or {}
			table.insert(byName[obj.Name], obj)
		end
	end
	return byName
end

local function normalize(code)
	code = code:gsub(':WaitForChild%("([^"]+)"[^)]*%)', '["%1"]'):gsub(':FindFirstChild%("([^"]+)"[^)]*%)', '["%1"]')
		:gsub(':GetService%("([^"]+)"%)', '["%1"]')
	-- Namen mit Leerzeichen bleiben mit \1 statt Leerzeichen ein Wort, bis sie gesucht werden.
	return (code:gsub('%["([^"]+)"%]', function(n) return "." .. n:gsub(" ", "\1") end))
end

-- entry.text: der Code des Effekts; entry.source: das ganze Script, für Variablen von weiter oben.
local aliasCache = {} -- pro Script-Quelltext, damit große Scripts nicht für jeden Abschnitt neu gelesen werden

-- accept: welche Treffer zählen (Standard: nur, was etwas zeigt). maxDesc: größte erlaubte Objektgröße.
local function effectObjects(entry, byName, accept, maxDesc)
	accept, maxDesc = accept or hasVisual, maxDesc or MAX_DESCENDANTS
	local text = normalize(entry.text)
	local alias = aliasCache[entry.source]
	if not alias then
		alias = {}
		for name, rhs in normalize(entry.source):gmatch("local ([%w_]+) = ([^\n]+)") do
			alias[name] = rhs:match("([%w_\1]+)%s*%)*%s*$")
		end
		aliasCache[entry.source] = alias
	end
	local chains = {}
	for chain in text:gmatch("[%a_\1][%w_\1]*%.[%w_\1%.]+") do
		table.insert(chains, chain:split("."))
	end
	for path in text:gmatch('"([^"]+/[^"]+)"') do
		table.insert(chains, path:split("/"))
	end

	local found, seen = {}, {}
	local function add(obj)
		-- Ordner, in denen das Script selbst liegt, sind kein Teil des Effekts.
		local holdsScript = entry.script and entry.script:IsDescendantOf(obj)
		if obj and not seen[obj] and not holdsScript and #obj:GetDescendants() <= maxDesc and accept(obj) then
			seen[obj] = true
			table.insert(found, obj)
		end
	end
	for _, segs in chains do
		-- script.Parent.X direkt vom Script aus auflösen, Namen allein sagen da nichts.
		if segs[1] == "script" and entry.script then
			local node = entry.script
			for i = 2, #segs do
				local s = segs[i]:gsub("\1", " ")
				local nextNode = s == "Parent" and node.Parent or node:FindFirstChild(s)
				if not nextNode then break end
				node = nextNode
			end
			if node ~= entry.script then add(node) end
			continue
		end
		segs[1] = alias[segs[1]] or segs[1]
		for i, s in segs do
			s = s:gsub("\1", " ")
			segs[i] = PATH_ALIASES[s] or s
		end
		-- Von hinten das erste passende Paar nehmen: x.Obj.CFrame meint Obj, nicht CFrame.
		for i = #segs, 2, -1 do
			local hit = nil
			for _, obj in byName[segs[i]] or {} do
				if obj.Parent and obj.Parent.Name == segs[i - 1] and obj ~= entry.script
					and not (entry.script and entry.script:IsDescendantOf(obj))
					and #obj:GetDescendants() <= maxDesc and accept(obj) then
					hit = obj
					break
				end
			end
			if hit then
				add(hit)
				break
			end
		end
	end
	-- Kinder von Treffern fliegen raus, sonst gäbe es sie doppelt.
	local result = {}
	for _, obj in found do
		local inside = false
		for _, other in found do
			if other ~= obj and obj:IsDescendantOf(other) then inside = true break end
		end
		if not inside then table.insert(result, obj) end
	end
	return result
end

-- Kopien an den Dummy setzen, alles verankert. Lose Attachments, Emitter, Beams und Trails kommen an ein
-- unsichtbares Halter-Part im Dummy-Mittelpunkt, weil sie ohne Part nichts zeigen.
local function playObjects(objs, at)
	local placed, holder = {}, nil
	for _, obj in objs do
		local copy = obj:Clone()
		if copy:IsA("Folder") then
			local m = Instance.new("Model")
			m.Name = copy.Name
			for _, child in copy:GetChildren() do child.Parent = m end
			copy = m
		end
		if copy:IsA("BasePart") or copy:IsA("Model") then
			for _, p in copy:GetDescendants() do
				if p:IsA("BasePart") then p.Anchored, p.CanCollide = true, false end
			end
			if copy:IsA("BasePart") then
				copy.Anchored, copy.CanCollide, copy.CFrame = true, false, at
			elseif copy:FindFirstChildWhichIsA("BasePart", true) then
				copy:PivotTo(at)
			end
			copy.Parent = workspace
		else
			if not holder then
				holder = Instance.new("Part")
				holder.Name, holder.Transparency, holder.Size = "Vorschau-Halter", 1, Vector3.one
				holder.Anchored, holder.CanCollide, holder.CFrame = true, false, at
				holder.Parent = workspace
			end
			copy.Parent = holder
		end
		table.insert(placed, copy)
	end
	return emitIn(placed)
end

-- Effekte jeder Bauart finden, ohne Server-Code:
-- 1. ModuleScripts (ein Modul pro Effekt, z. B. EffectsFolder > Stand_Barrage)
-- 2. Abschnitte in Client-Scripts, die auf einen Effektnamen reagieren:
--    if name == "Stand Barrage" then …, ["Stand Barrage"] = function …, StandBarrage = function …
--    (z. B. ein großes ClientFX-Script wie in YBA). Der Abschnitt läuft bis zur nächsten solchen Stelle.
local SECTION_MARKERS = {
	'==%s*"([^"]+)"',
	'%[%s*"([^"]+)"%s*%]%s*=%s*function',
	'^%s*([%a_][%w_]*)%s*=%s*function',
}
local MAX_SECTION_LINES = 300

local function effectEntries()
	local entries = {}
	for _, obj in game:GetDescendants() do
		local ok, src = pcall(function() return obj:IsA("LuaSourceContainer") and obj.Source end)
		if ok and type(src) == "string" and src ~= "" then
			if obj:IsA("ModuleScript") then
				table.insert(entries, { name = obj.Name, script = obj, line = 1, text = src, source = src })
			end
			local lines = src:split("\n")
			local open = nil -- Abschnitt, der gerade läuft
			for n, line in lines do
				local name = nil
				for _, pattern in SECTION_MARKERS do
					name = line:match(pattern)
					if name then break end
				end
				if name or (open and n - open.line >= MAX_SECTION_LINES) then
					if open then
						open.text = table.concat(lines, "\n", open.line, n - 1)
						open = nil
					end
				end
				if name then
					open = { name = name, script = obj, line = n, source = src }
					table.insert(entries, open)
				end
			end
			if open then open.text = table.concat(lines, "\n", open.line, #lines) end
		end
	end
	-- 3. VFX-Objekte selbst, für Places ohne Effekt-Code (Kopien, in denen er auf dem Server lief):
	-- zu jedem Emitter, Beam und Trail das größte umgebende Objekt, das noch klein genug ist.
	local counts, seen = {}, {}
	local function size(obj)
		counts[obj] = counts[obj] or #obj:GetDescendants()
		return counts[obj]
	end
	for _, obj in game:GetDescendants() do
		local ok, fx = pcall(function()
			return (obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail"))
				and not obj:IsDescendantOf(workspace) and not obj:IsDescendantOf(Players)
		end)
		if ok and fx then
			local top = obj
			while top.Parent and top.Parent.Parent ~= game and isVisual(top.Parent) and size(top.Parent) <= MAX_DESCENDANTS do
				top = top.Parent
			end
			if not seen[top] then
				seen[top] = true
				table.insert(entries, { name = top.Name, object = top })
			end
		end
	end
	return entries
end

local lastEntry = nil

-- entry: Treffer aus der Suche. Ohne: im Explorer ausgewähltes ModuleScript, sonst nur die Animation.
local function startScene(entry)
	stopScene()
	local clip = loaded and loaded.clip
	if not entry then
		for _, sel in Selection:Get() do
			if sel:IsA("ModuleScript") then
				entry = { name = sel.Name, script = sel, line = 1, text = sel.Source, source = sel.Source }
				break
			end
		end
	end
	if not clip and not entry then
		sceneLabel.TextColor3, sceneLabel.Text = BAD, "Erst eine Animation laden oder oben einen Effekt suchen und anklicken."
		return
	end
	local byName = entry and not entry.object and visualIndex() -- vor dem Dummy, damit seine Teile nicht mitzählen
	local rig = makeRig(clip)
	if not rig then
		sceneLabel.TextColor3, sceneLabel.Text = BAD, "Dummy ließ sich nicht bauen."
		return
	end
	rig.Name = "Vorschau-Dummy"
	local cf = workspace.CurrentCamera.CFrame
	local pos = cf.Position + cf.LookVector * 12
	rig:PivotTo(CFrame.lookAt(pos, Vector3.new(cf.Position.X, pos.Y, cf.Position.Z)))
	if rig.PrimaryPart then rig.PrimaryPart.Anchored = true end

	scene = { rig = rig, added = {} }
	-- Alles, was die Vorschau neu in den Workspace legt, merken, damit Stopp es wieder entfernt.
	scene.watch = workspace.DescendantAdded:Connect(function(d)
		if not d:IsDescendantOf(rig) then table.insert(scene.added, d) end
	end)
	rig.Parent = workspace

	if clip then
		local holder = rig:FindFirstChildWhichIsA("Humanoid", true) or rig:FindFirstChildWhichIsA("AnimationController", true)
		local anim = Instance.new("Animation")
		anim.AnimationId = AnimationClipProvider:RegisterAnimationClip(clip)
		local animator = holder:FindFirstChildOfClass("Animator") or Instance.new("Animator", holder)
		local t = animator:LoadAnimation(anim)
		t.Looped = true
		t:Play(0)
		-- Im Edit-Modus laufen Animationen nur, wenn das Plugin sie weiterschiebt.
		if not RunService:IsRunning() then
			scene.step = RunService.Heartbeat:Connect(function(dt) animator:StepAnimations(dt) end)
		end
	end

	local text = clip and ("Animation " .. tostring(loaded.id)) or "Ohne Animation"
	if entry then
		lastEntry = entry
		local objs = entry.object and { entry.object } or entry.objs or effectObjects(entry, byName)
		if #objs == 0 then
			sceneLabel.TextColor3 = BAD
			sceneLabel.Text = ("%s · Im Code von %s (%s, Zeile %d) steht kein VFX-Objekt, das es in der Place gibt.")
				:format(text, entry.name, entry.script.Name, entry.line)
			return
		end
		local root = rig.PrimaryPart or rig:FindFirstChildWhichIsA("BasePart", true)
		local emitted = playObjects(objs, root.CFrame)
		local names = {}
		for i, obj in objs do
			if i > 6 then table.insert(names, "…") break end
			table.insert(names, obj.Name)
		end
		text = ("%s · %s: %d Objekte, %d Emitter (%s)"):format(text, entry.name, #objs, emitted, table.concat(names, ", "))
	end
	sceneLabel.TextColor3, sceneLabel.Text = OK, text
end

-- Einmal pro Fokus einlesen statt bei jedem Tastendruck, große Places haben tausende Scripts.
local fxEntries, fxIndex = {}, {}
sceneFxBox.Focused:Connect(function()
	fxEntries, fxIndex, aliasCache = effectEntries(), visualIndex(), {}
end)

local function renderFxSearch()
	for _, old in sceneFxList:GetChildren() do
		if old:IsA("GuiObject") then old:Destroy() end
	end
	local q = sceneFxBox.Text:lower():match("^%s*(.-)%s*$")
	if q == "" then return end
	local shown = 0
	-- VFX-Objekte und Effekt-Module zuerst, Abschnitte aus großen Scripts danach (dort steckt mehr Rauschen).
	local ordered = {}
	for _, entry in fxEntries do
		if entry.object or entry.line == 1 then table.insert(ordered, entry) end
	end
	for _, entry in fxEntries do
		if not (entry.object or entry.line == 1) then table.insert(ordered, entry) end
	end
	local checked = 0
	for _, entry in ordered do
		-- Code-Treffer nur zeigen, wenn darin ein VFX-Objekt steht. Sonst ist es z. B. nur eine Werte-Tabelle
		-- (Schaden, Knockback), die zufällig den Namen enthält.
		local visible = false
		if entry.name:lower():find(q, 1, true) then
			if entry.object then
				visible = true
			elseif checked < 80 then -- shortcut: höchstens 80 Code-Treffer prüfen, sonst hängt das Tippen
				checked += 1
				entry.objs = entry.objs or effectObjects(entry, fxIndex)
				visible = #entry.objs > 0
			end
		end
		if visible then
			shown += 1
			if shown > 15 then break end -- shortcut: max 15 Treffer, genauer tippen grenzt ein
			local where = entry.object and ("VFX in " .. entry.object.Parent.Name)
				or entry.line > 1 and ("%s:%d"):format(entry.script.Name, entry.line)
				or entry.script.Parent.Name
			local b = listButton(entry.name .. "   ·  " .. where, sceneFxList)
			b.LayoutOrder = shown
			b.Activated:Connect(function() startScene(entry) end)
		end
	end
	if shown == 0 then label("Kein Effekt mit VFX-Objekten unter diesem Namen.", BAD).Parent = sceneFxList end
end
sceneFxBox:GetPropertyChangedSignal("Text"):Connect(renderFxSearch)

sceneStartBtn.Activated:Connect(function() startScene(lastEntry) end)
sceneStopBtn.Activated:Connect(stopScene)
plugin.Unloading:Connect(stopScene)

-- Cutscene ---------------------------------------------------------------------------------
-- Was ein Cutscene-Script braucht, steht in seinem Code: Pfade zu Objekten, require(...) auf Module und
-- Asset-IDs. Gesucht wird wie bei den Effekten, aber jede Objektart zählt und Module werden mit durchsucht.
do -- eigener Block: hält die Zahl der Top-Level-Variablen unter Luaus Grenze von 200
	local CUTSCENE_MAX_DESCENDANTS = 2000 -- ganze Maps nicht mitnehmen, Cutscene-Sets schon
	local CUTSCENE_MAX_DEPTH = 4 -- require-Ketten so tief verfolgen

	local function anyInstance(obj)
		return not obj:IsA("LuaSourceContainer") or obj:IsA("ModuleScript")
	end

	local function indexAll()
		local byName = {}
		for _, obj in game:GetDescendants() do
			local ok, name = pcall(function() return obj.Name end)
			if ok then
				byName[name] = byName[name] or {}
				table.insert(byName[name], obj)
			end
		end
		return byName
	end

	local function cutsceneScripts()
		local scripts, seen = {}, {}
		for _, sel in Selection:Get() do
			local list = sel:GetDescendants()
			table.insert(list, 1, sel)
			for _, obj in list do
				if obj:IsA("LuaSourceContainer") and not seen[obj] then
					seen[obj] = true
					table.insert(scripts, obj)
				end
			end
		end
		return scripts
	end

	-- Gibt Scripts (Auswahl plus benutzte Module), Objekte und Asset-IDs zurück.
	local function cutsceneDeps(selected)
		local byName = indexAll()
		local scripts, objects, ids = {}, {}, {}
		local seenScript, seenObj, seenId = {}, {}, {}
		local function addId(id)
			if #id >= 5 and not seenId[id] then
				seenId[id] = true
				table.insert(ids, id)
			end
		end
		local queue = {}
		for _, s in selected do table.insert(queue, { s, 0 }) end
		while #queue > 0 do
			local s, depth = table.unpack(table.remove(queue, 1))
			if not seenScript[s] then
				seenScript[s] = true
				table.insert(scripts, s)
				local ok, src = pcall(function() return s.Source end)
				src = ok and src or ""
				for id in src:gmatch("rbxassetid://(%d+)") do addId(id) end
				for id in src:gmatch("[?&][iI][dD]=(%d+)") do addId(id) end
				for id in src:gmatch("[Ii]d%s*=%s*(%d+)") do addId(id) end -- AnimationId = 123, SoundId = 123
				local entry = { name = s.Name, script = s, line = 1, text = src, source = src }
				for _, obj in effectObjects(entry, byName, anyInstance, CUTSCENE_MAX_DESCENDANTS) do
					if obj:IsA("ModuleScript") then
						if depth < CUTSCENE_MAX_DEPTH then table.insert(queue, { obj, depth + 1 }) end
					elseif not seenObj[obj] then
						seenObj[obj] = true
						table.insert(objects, obj)
					end
				end
			end
		end
		-- Objekte, die in einem anderen gefundenen Objekt stecken, nur einmal.
		local top = {}
		for _, obj in objects do
			local inside = false
			for _, other in objects do
				if other ~= obj and obj:IsDescendantOf(other) then inside = true break end
			end
			if not inside then table.insert(top, obj) end
		end
		for _, id in idsIn(top) do addId(id) end
		return scripts, top, ids
	end

	local csCurrent = nil -- { scripts, objects, ids }

	local function refreshCutscene()
		for _, old in csList:GetChildren() do
			if old:IsA("GuiObject") then old:Destroy() end
		end
		local selected = cutsceneScripts()
		if #selected == 0 then
			csCurrent = nil
			csInfo.TextColor3, csInfo.Text = MUTED, "Kein Script ausgewählt. Cutscene-Script oder seinen Ordner im Explorer anklicken."
			return
		end
		local scripts, objects, ids = cutsceneDeps(selected)
		csCurrent = { scripts = scripts, objects = objects, ids = ids }
		csInfo.TextColor3 = TEXT
		csInfo.Text = ("%d Scripts (davon %d Module über require), %d Objekte, %d Asset-IDs.")
			:format(#scripts, #scripts - #selected, #objects, #ids)
		local order = 0
		local function row(text, obj)
			order += 1
			if order > 60 then return end -- shortcut: Liste kappt bei 60 Zeilen, heruntergeladen wird trotzdem alles
			local b = listButton(text, csList)
			b.LayoutOrder = order
			if obj then b.Activated:Connect(function() Selection:Set({ obj }) end) end
		end
		for _, s in scripts do row(("%s  ·  %s"):format(s.Name, s.ClassName), s) end
		for _, obj in objects do
			local rig = obj:FindFirstChildWhichIsA("AnimationController", true) or obj:FindFirstChildWhichIsA("Humanoid", true)
			row(("%s  ·  %s%s"):format(obj:GetFullName(), obj.ClassName, rig and ", Rig" or ""), obj)
		end
		if #ids > 0 then row(("%d Asset-IDs: %s"):format(#ids, table.concat(ids, ", "):sub(1, 120))) end
	end

	Selection.SelectionChanged:Connect(function()
		if pages.Cutscene.Visible then refreshCutscene() end
	end)
	tabs.Cutscene.Activated:Connect(refreshCutscene)

	local function downloadCutscene(repair, btn, idleText)
		if not csCurrent then
			status.TextColor3, status.Text = BAD, "Erst ein Cutscene-Script im Explorer anklicken."
			return
		end
		local name = csCurrent.scripts[1].Name -- der Server entfernt Zeichen, die in Ordnernamen nicht gehen
		btn.Active, btn.Text = false, "Lade herunter …"
		local pack = Instance.new("Folder")
		pack.Name = name
		local code = {}
		for folderName, list in { Code = csCurrent.scripts, Objekte = csCurrent.objects } do
			local f = Instance.new("Folder")
			f.Name, f.Parent = folderName, pack
			for _, obj in list do
				local ok, copy = pcall(function() return obj:Clone() end)
				if ok and copy then copy.Parent = f end -- nicht archivierbare Objekte liefern nil
			end
		end
		-- Unter eigenem Namen: Bilder in der Kopie neu hochladen und alte IDs überall ersetzen, auch im Code.
		local lines, map, allOk = {}, {}, true
		if repair then
			local found, texIds = collectTextures({ pack }), {}
			-- Nur IDs aus Textur-Eigenschaften: Bei IDs, die nur im Code stehen, weiß niemand, ob es Bilder sind.
			for id in found do table.insert(texIds, id) end
			if #texIds > 0 then lines, allOk, map = repairTextures(found, texIds, btn) end
			for _, s in pack:GetDescendants() do
				if s:IsA("LuaSourceContainer") then
					pcall(function()
						s.Source = s.Source:gsub("rbxassetid://(%d+)", function(id) return map[id] and ("rbxassetid://" .. map[id]) end)
					end)
				end
			end
		end
		for _, s in pack:GetDescendants() do
			if s:IsA("LuaSourceContainer") then
				local ok, src = pcall(function() return s.Source end)
				if ok then table.insert(code, ("-- ===== %s (%s) =====\n%s"):format(s:GetFullName(), s.ClassName, src)) end
			end
		end
		btn.Text = "Speichere …"
		local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, { pack })
		pack:Destroy()
		local stored = okSer and store(name, "", buffer.tostring(buf))
		table.insert(lines, stored and ("Gespeichert: downloads/%s/%s.rbxm"):format(name, name)
			or "Cutscene konnte nicht gespeichert werden. Läuft start.bat?")
		if #code > 0 and store(name, "code.lua", table.concat(code, "\n\n")) then table.insert(lines, "Code zum Lesen: code.lua") end
		if #csCurrent.ids > 0 then
			-- Hochgeladene Bilder unter der neuen ID speichern, den Rest (Animationen, Sounds) unter der alten.
			local fileIds = {}
			for _, id in csCurrent.ids do table.insert(fileIds, map[id] or id) end
			local r = save(fileIds, name, btn, "Speichere …")
			if r then table.insert(lines, ("%d/%d Assets gespeichert (Animationen, Sounds, Bilder)."):format(r.saved, r.total)) end
			allOk = allOk and r ~= nil and r.saved == r.total
		end
		btn.Active, btn.Text = true, idleText
		status.TextColor3, status.Text = (allOk and stored) and OK or BAD, table.concat(lines, "\n")
	end

	csDownloadBtn.Activated:Connect(function() downloadCutscene(false, csDownloadBtn, "Herunterladen") end)
	csRepairBtn.Activated:Connect(function() downloadCutscene(true, csRepairBtn, "Mein Account") end)
end

-- Aufnahme im Play-Test --------------------------------------------------------------------
-- Studio lädt das Plugin im Play-Test einmal auf dem Server und einmal auf dem Client.
-- Client: hört auf das ClientFX-Remote und listet jeden echten Aufruf mit seinen Daten.
-- Server: Kanal, über den der Client einen aufgenommenen Aufruf 1:1 erneut an alle feuern lässt.
local REPLAY = "AssetDownloaderReplay"

if RunService:IsRunning() and RunService:IsServer() then
	-- Test-Spawn: Kopien ohne Server-Scripts lassen nie eine Figur erscheinen (dunkler Bildschirm, keine Bewegung).
	-- Hat ein Spieler nach 5 s keine Figur, lädt das Plugin sie. Nur im Studio-Play-Test, die Place bleibt unverändert.
	local function ensureCharacter(player)
		task.wait(5)
		if player.Parent and not player.Character then
			pcall(function() player:LoadCharacter() end)
			print(("[Asset Downloader] Test-Spawn: Figur für %s geladen, weil die Place keine gespawnt hat."):format(player.Name))
		end
	end
	Players.PlayerAdded:Connect(ensureCharacter)
	for _, player in Players:GetPlayers() do task.spawn(ensureCharacter, player) end

	local channel = Instance.new("RemoteEvent")
	channel.Name = REPLAY
	channel.Parent = game:GetService("ReplicatedStorage")
	channel.OnServerEvent:Connect(function(_, name, ...)
		for _, obj in game:GetDescendants() do
			if obj.Name == name and obj:IsA("RemoteEvent") and obj ~= channel then
				obj:FireAllClients(...)
				return
			end
		end
	end)
end

if RunService:IsRunning() and RunService:IsClient() then
	task.spawn(function()
		local name, remote = remoteName(), nil
		repeat -- Remotes kommen beim Client erst nach und nach an
			for _, obj in game:GetDescendants() do
				if obj.Name == name and obj:IsA("RemoteEvent") then remote = obj break end
			end
			if not remote then task.wait(1) end
		until remote
		local channel = game:GetService("ReplicatedStorage"):WaitForChild(REPLAY, 30)
		recInfo.TextColor3, recInfo.Text = OK, ("Aufnahme läuft auf %s. Benutze jetzt eine Attacke."):format(remote:GetFullName())

		local function describe(v)
			if typeof(v) == "Instance" then return v:GetFullName() end
			if type(v) ~= "table" then return tostring(v) end
			local parts = {}
			for k, x in v do
				table.insert(parts, ("%s = %s"):format(tostring(k), typeof(x) == "Instance" and x:GetFullName() or tostring(x)))
			end
			table.sort(parts)
			return "{ " .. table.concat(parts, ", ") .. " }"
		end

		local count = 0
		remote.OnClientEvent:Connect(function(...)
			local args = table.pack(...)
			count += 1
			local entry = autoFrame()
			entry.LayoutOrder = -count -- neueste oben
			vlist(entry, 2)
			local line = Instance.new("Frame")
			line.Size, line.BackgroundTransparency, line.LayoutOrder = UDim2.new(1, 0, 0, 30), 1, 1
			line.Parent = entry
			local title = listButton(("%d. %s"):format(count, tostring(args[1])), line)
			title.Size, title.AutoButtonColor = UDim2.new(1, -104, 1, 0), false
			local again = makeButton("Wiederholen", BLUE)
			again.Size, again.Position, again.TextSize = UDim2.new(0, 100, 1, 0), UDim2.new(1, -100, 0, 0), 12
			again.Parent = line
			again.Activated:Connect(function()
				if channel then channel:FireServer(remote.Name, table.unpack(args, 1, args.n)) end
			end)
			local details = {}
			for i = 2, args.n do table.insert(details, describe(args[i])) end
			local info = Instance.new("TextLabel")
			info.Size, info.AutomaticSize, info.BackgroundTransparency = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y, 1
			info.Font, info.TextSize, info.TextColor3, info.TextWrapped = Enum.Font.Code, 11, MUTED, true
			info.TextXAlignment, info.LayoutOrder = Enum.TextXAlignment.Left, 2
			info.Text = #details > 0 and table.concat(details, "\n") or "(keine Daten)"
			info.Parent = entry
			entry.Parent = recList
			-- shortcut: nur die letzten 40 Aufrufe behalten, sonst wird die Liste bei Barrage (10 pro Sekunde) riesig
			for _, old in recList:GetChildren() do
				if old:IsA("GuiObject") and old.LayoutOrder > -count + 39 then old:Destroy() end -- ältere haben größere Werte
			end
		end)
	end)
end
