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

local SERVER = "http://127.0.0.1:47651"
-- Webseiten können diesen Header nicht mitschicken, so nimmt der Server nur Anfragen vom Plugin an.
local PLUGIN_HEADERS = { ["X-Asset-Downloader"] = "plugin" }

-- Farben wie das Stealmaxxing-Logo: schwarzer Grund, dunkle Flächen mit einem Hauch Rot, genau ein roter Akzent.
local BG = Color3.fromRGB(0, 0, 0)
local CARD = Color3.fromRGB(26, 20, 21) -- #1A1415
local FIELD = Color3.fromRGB(43, 32, 34) -- #2B2022, Felder und Listenzeilen in Karten
local LINE = Color3.fromRGB(64, 40, 43) -- #40282B, Trennlinien
local TEXT = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(176, 158, 160) -- #B09EA0, gut lesbar auf CARD
local ACCENT = Color3.fromRGB(226, 27, 38) -- #E21B26, Rot aus dem Logo, nur Hauptaktion und Auswahl
local GREY = Color3.fromRGB(62, 46, 48) -- #3E2E30, Nebenaktionen
-- Früher eigene Farben je Knopf. Jetzt sind alle Nebenaktionen gleich, damit Rot eine Bedeutung behält.
local BLUE, GREEN, PURPLE = GREY, GREY, GREY
-- Fehler in Orange: Rot ist schon der Akzent, sonst sähe jede Hauptaktion wie ein Fehler aus.
local BAD = Color3.fromRGB(255, 159, 10) -- #FF9F0A
local OK = Color3.fromRGB(48, 209, 88) -- #30D158
local FONT = {
	regular = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular),
	medium = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	bold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold),
	heavy = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
}

local toolbar = plugin:CreateToolbar("Stealmaxxing")
local toggle = toolbar:CreateButton("Stealmaxxing", "Assets, VFX und Cutscenes aus jedem Spiel holen", "")
toggle.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync("AssetDownloader",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 390, 680, 360, 440))
widget.Title = "Stealmaxxing"
toggle.Click:Connect(function() widget.Enabled = not widget.Enabled end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function() toggle:SetActive(widget.Enabled) end)

-- UI ---------------------------------------------------------------------------------------

local function corner(inst, radius)
	Instance.new("UICorner", inst).CornerRadius = UDim.new(0, radius or 8)
	return inst
end

local function stroke(inst, color)
	local s = Instance.new("UIStroke", inst)
	s.Color, s.Thickness, s.ApplyStrokeMode = color or LINE, 1, Enum.ApplyStrokeMode.Border
	return s
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
root.ScrollBarThickness = 4
root.ScrollBarImageColor3 = ACCENT
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
root.CanvasSize = UDim2.new()
root.Parent = widget
padding(root, 14)
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
	l.FontFace = FONT.regular
	l.TextSize = size or 14
	l.LineHeight = 1.1
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
	t.FontFace = FONT.regular
	t.TextSize = 14
	t.TextColor3 = TEXT
	t.PlaceholderText = placeholder
	t.PlaceholderColor3 = MUTED
	t.Text = ""
	t.ClearTextOnFocus = false
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ClipsDescendants = true
	local p = Instance.new("UIPadding", t)
	p.PaddingLeft, p.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	-- Fokusring in Akzentfarbe nur beim Tippen, wie bei macOS.
	local s = stroke(t, ACCENT)
	s.Thickness, s.Enabled = 2, false
	t.Focused:Connect(function() s.Enabled = true end)
	t.FocusLost:Connect(function() s.Enabled = false end)
	return add(corner(t, 10))
end

local function makeButton(text, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 34)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = FONT.bold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	return corner(b, 10)
end

-- Rundes i neben einem Knopf. Klick klappt die Erklärung darunter auf und zu.
local function infoIcon(parent, hint, layoutOrder)
	local i = Instance.new("TextButton")
	i.Size = UDim2.new(0, 34, 0, 34)
	i.BackgroundColor3 = FIELD
	i.FontFace = FONT.bold
	i.TextSize = 15
	i.TextColor3 = MUTED
	i.Text = "?"
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
	h.FontFace = FONT.regular
	h.TextSize = 13
	h.LineHeight = 1.15
	h.TextColor3 = TEXT
	h.TextWrapped = true
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.Text = text
	h.LayoutOrder = 2
	h.Visible = false
	padding(h, 12)
	corner(h, 10)
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
	corner(c, 14)
	padding(c, 16)
	vlist(c, 10)
	container = currentPage or container -- jede Karte direkt auf die Seite, nicht in die vorige Karte
	add(c)
	container = c
	local t = label(title, TEXT, 16)
	t.FontFace = FONT.bold
	if subtitle then label(subtitle, MUTED, 13) end
	return c
end

-- Kopf -------------------------------------------------------------------------------------

do
	-- Logo über die ganze Breite. Die Pixel kommen vom lokalen Server (studio-plugin/logo.png) und werden in ein
	-- EditableImage gezeichnet: So muss das Bild nicht zu Roblox hochgeladen und moderiert werden.
	local head = add(Instance.new("ImageLabel"))
	head.Name, head.BackgroundTransparency = "Logo", 1
	head.Size, head.ScaleType = UDim2.new(1, 0, 0, 150), Enum.ScaleType.Fit
	local ratio = Instance.new("UIAspectRatioConstraint", head)
	ratio.AspectRatio, ratio.DominantAxis = 760 / 348, Enum.DominantAxis.Width
	-- Solange das Logo lädt oder der Server nicht läuft: Name in Rot.
	local fallback = Instance.new("TextLabel")
	fallback.Size, fallback.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	fallback.FontFace, fallback.TextSize, fallback.TextColor3 = FONT.heavy, 30, ACCENT
	fallback.Text = "STEALMAXXING"
	fallback.Parent = head
	-- Wächter statt einmaligem Laden: Läuft der Server beim Studio-Start noch nicht, wird es weiter versucht.
	-- Verschwindet das Bild (EditableImage freigegeben), wird es aus den gemerkten Pixeln neu gezeichnet.
	task.spawn(function()
		local img, pixels, w, h -- img bleibt hier stark referenziert, sonst kann Luau es wegräumen
		while true do
			local content = head.ImageContent
			if not (img and content.SourceType == Enum.ContentSourceType.Object and content.Object == img) then
				if not pixels then
					local ok, res = pcall(HttpService.RequestAsync, HttpService,
						{ Url = SERVER .. "/api/plugin-logo", Headers = PLUGIN_HEADERS, Method = "GET" })
					if ok and res.Success then
						local size = {}
						for k, v in res.Headers do size[k:lower()] = tonumber(v) end
						if size["x-width"] and size["x-height"] and #res.Body == size["x-width"] * size["x-height"] * 4 then
							w, h, pixels = size["x-width"], size["x-height"], buffer.fromstring(res.Body)
						end
					end
				end
				if pixels then
					local okImg, newImg = pcall(AssetService.CreateEditableImage, AssetService, { Size = Vector2.new(w, h) })
					if okImg and newImg then
						newImg:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
						img = newImg
						ratio.AspectRatio = w / h
						head.ImageContent = Content.fromObject(img)
					end
				end
			end
			fallback.Visible = not (img and head.ImageContent.Object == img)
			task.wait(img and 5 or 3)
		end
	end)
end

-- Tabs als Segmented Control wie bei iOS: ein Daumen gleitet unter den gewählten Namen.
local tabBar = add(Instance.new("Frame"))
tabBar.Size, tabBar.BackgroundColor3 = UDim2.new(1, 0, 0, 34), CARD
corner(tabBar, 9)
do
	local thumb = Instance.new("Frame")
	thumb.Name, thumb.BackgroundColor3, thumb.BorderSizePixel = "Thumb", Color3.fromRGB(122, 22, 30), 0 -- dunkles Logo-Rot
	corner(thumb, 7)
	thumb.Parent = tabBar
	local track = Instance.new("Frame")
	track.Name, track.BackgroundTransparency = "Track", 1
	track.Size, track.Position = UDim2.new(1, -4, 1, -4), UDim2.fromOffset(2, 2)
	local l = Instance.new("UIListLayout", track)
	l.FillDirection, l.SortOrder, l.HorizontalFlex = Enum.FillDirection.Horizontal, Enum.SortOrder.LayoutOrder, Enum.UIFlexAlignment.Fill
	track.Parent = tabBar
end

-- Status gilt für alle Tabs, deshalb über den Seiten.
local status = label("Server muss laufen: start.bat doppelklicken.", MUTED, 13)
-- Neue IDs nach dem Hochladen, markierbar zum Kopieren.
local idsBox = input("")
idsBox.TextEditable, idsBox.MultiLine, idsBox.TextWrapped = false, true, true
idsBox.AutomaticSize, idsBox.Size = Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 34)
idsBox.Visible = false

local tabs, pages = {}, {}
-- Die Vorschau-Karte gibt es einmal; sie wandert zwischen Laden und Bulk (dort oben über der Liste).
local previewCard, previewOrder, bulkCard, bulkPreviewUsed
local SMOOTH = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function moveThumb(animate)
	local b = tabs[tabBar:GetAttribute("Shown")]
	if not b or b.AbsoluteSize.X == 0 then return end
	local goal = { Position = UDim2.fromOffset(b.AbsolutePosition.X - tabBar.AbsolutePosition.X, 2), Size = UDim2.new(0, b.AbsoluteSize.X, 1, -4) }
	if animate then
		game:GetService("TweenService"):Create(tabBar.Thumb, SMOOTH, goal):Play()
	else
		tabBar.Thumb.Position, tabBar.Thumb.Size = goal.Position, goal.Size
	end
end
tabBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() task.defer(moveThumb, false) end)

local function showTab(name)
	local TweenService = game:GetService("TweenService")
	local okMotion, reduced = pcall(function() return game:GetService("GuiService").ReducedMotionEnabled end)
	local before = tabBar:GetAttribute("Shown")
	local animate = widget.Enabled and before ~= nil and before ~= name and not (okMotion and reduced)
	tabBar:SetAttribute("Shown", name)
	for n, page in pages do
		page.Parent.Visible = n == name
		local goal = { TextColor3 = n == name and TEXT or MUTED }
		if animate then TweenService:Create(tabs[n], TweenInfo.new(0.2), goal):Play() else tabs[n].TextColor3 = goal.TextColor3 end
	end
	moveThumb(animate)
	if animate then
		-- Neue Seite kommt aus der Richtung des Tabs und blendet über eine schwarze Fläche ein.
		local p = pages[name]
		p.Position = UDim2.fromOffset(tabs[name].LayoutOrder > tabs[before].LayoutOrder and 28 or -28, 0)
		TweenService:Create(p, SMOOTH, { Position = UDim2.new() }):Play()
		local fade = widget:FindFirstChild("Fade")
		if not fade then
			fade = Instance.new("Frame")
			fade.Name, fade.BackgroundColor3, fade.BorderSizePixel, fade.ZIndex = "Fade", BG, 0, 5
			fade.Parent = widget
		end
		local y = tabBar.AbsolutePosition.Y + tabBar.AbsoluteSize.Y + root.CanvasPosition.Y + 6
		fade.Position, fade.Size = UDim2.fromOffset(0, y), UDim2.new(1, 0, 1, -y)
		fade.BackgroundTransparency, fade.Visible = 0, true
		local tw = TweenService:Create(fade, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
		tw.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then fade.Visible = false end
		end)
		tw:Play()
	end
	root.CanvasPosition = Vector2.zero
end

-- Neuer Tab: Segment im Control und eine Seite. Die Seite steckt in einem Halter, damit sie beim
-- Wechsel seitlich hereingleiten kann, ohne dass die Liste der anderen Elemente springt.
local function page(name, index)
	local t = Instance.new("TextButton")
	t.LayoutOrder, t.Text, t.BackgroundTransparency, t.AutoButtonColor = index, name, 1, false
	t.Size, t.AutomaticSize = UDim2.fromScale(0, 1), Enum.AutomaticSize.X
	t.FontFace, t.TextSize, t.TextColor3, t.ZIndex = FONT.bold, 12, MUTED, 2
	local pad = Instance.new("UIPadding", t)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 3), UDim.new(0, 3)
	t.Parent = tabBar.Track
	t.Activated:Connect(function() showTab(name) end)
	tabs[name] = t
	local holder = autoFrame()
	container = root
	add(holder)
	local p = autoFrame()
	vlist(p, 12)
	p.Parent = holder
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
	"Klick im Explorer eine Animation, einen Sound, Emitter, Mesh oder ein Bild an und drück diesen Knopf. Die ID wird automatisch eingetragen und geladen.\n\nEine Animationsdatei ohne ID (KeyframeSequence, z. B. per Insert from File eingefügt) kommt direkt in die Vorschau.\n\nIst ein ganzer Ordner (z. B. eine VFX) ausgewählt, kommen alle IDs darin als Liste in den Tab Bulk.")

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
	"Platzieren setzt das Asset 12 Studs vor deine Kamera, mit allen Einstellungen und Unterordnern. Animationen kommen in AnimSaves des ausgewählten Rigs, sonst in ServerStorage.\n\nAbspielen: Animationen laufen auf einem Dummy 12 Studs vor deiner Kamera (ist ein Rig ausgewählt, auf einer Kopie davon). Nochmal drücken entfernt ihn. Sounds spielen ab. Bei VFX löst es die platzierten Emitter aus (erst Platzieren).",
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
card("VFX und Models aus dem Spiel", "Erst die VFX, das Model oder den ganzen Ordner (z. B. Aura) im Explorer anklicken.")
local repairBtn = button("Reparieren und sichern", PURPLE,
	"Lädt jede Textur der Auswahl unter deinem Namen hoch und setzt die neuen IDs ein. Größe, Farben, Rotation und alle Einstellungen bleiben.\n\nDanach liegt alles in downloads/<Name>/: die VFX als .rbxm und jede Textur als Bild. Braucht apikey.txt.")
local saveSelBtn = button("Nur sichern (nichts hochladen)", GREY,
	"Speichert die Auswahl als .rbxm nach downloads/<Name>/ und daneben jedes Asset, das darin steckt: alle Meshes, Texturen, SurfaceAppearance-Bilder, Sounds und Animationen. Ein Model aus vielen Meshes also mit einem Klick. Lädt nichts hoch, die IDs bleiben die alten.")
local playSelBtn = button("Auswahl abspielen", BLUE,
	"Löst alle ParticleEmitter der Auswahl einmal aus (mit EmitCount und EmitDelay, falls gesetzt). Hit-VFX sieht man sonst nicht, weil sie nur per Script feuern.\n\nSpielt immer als Kopie 12 Studs vor deiner Kamera, egal ob die VFX im Workspace, in ReplicatedStorage oder in einem Script liegt. Das Original bleibt unverändert, du kannst beliebig oft abspielen.")
local vfxLabel = label("")

card("Animations-Ordner", "Ordner mit Animationen im Explorer anklicken, z. B. Anubis mit Abilities und Attack.")
-- Eine Tabelle statt mehrerer locals: Luau erlaubt höchstens 200 lokale Variablen pro Funktion.
local animUi = {}
animUi.row, animUi.save, animUi.upload = buttonRow("Herunterladen speichert die Auswahl als eine Datei nach downloads/<Name>/<Name>.rbxm, mit allen Unterordnern und Namen genau wie im Explorer (z. B. Anubis > Abilities > Barrage, Anubis > Attack > M1).\n\nIn der Datei liegt jede Animation als KeyframeSequence mit ihrem Namen, ohne Asset-ID, so wie aus dem Animation Editor gespeichert. So kannst du sie in jeder Place ansehen und bearbeiten. Lässt sich eine nicht laden, bleibt sie als Animation mit ID drin und steht in der Fehlerliste.\n\nUnter meiner ID, Ordner mit KeyframeSequences (z. B. aus Herunterladen eingefügt): lädt alle auf einmal unter deinem Account hoch. Danach steckt jede KeyframeSequence in einer Animation mit deiner neuen ID, gleicher Name, gleicher Ort. Kein Rechtsklick > Save to Roblox pro Animation nötig. Strg+Z macht es rückgängig.\n\nUnter meiner ID, Ordner mit Animationen aus einem Spiel (fremde IDs): lädt jede Animation unter deinem Account hoch (und Bilder, falls welche drin sind) und speichert eine Datei, in der die Animation-Objekte deine neuen IDs haben, jeweils mit der KeyframeSequence darin. Dann laufen die Animationen in deinen eigenen Spielen. Datei: downloads/<Name> (meine IDs)/. Schon hochgeladene Animationen werden nicht doppelt hochgeladen. Braucht apikey.txt mit Assets Read + Write.\n\nIn der anderen Place: Rechtsklick > Insert from File und die .rbxm wählen.",
	"Herunterladen", GREEN, "Unter meiner ID", PURPLE)
animUi.label = label("")

card("Zu anderer Place", "Auswahl in einer Place senden, in einer anderen Place empfangen. Beide brauchen dieses Plugin und start.bat.")
local sendBtn, receiveBtn = select(2, buttonRow("Senden speichert die Explorer-Auswahl beim lokalen Server (downloads/_senden/), mit dem Ordner, in dem jedes Objekt lag.\n\nEmpfangen in der anderen Place legt alles wieder in denselben Ordner, z. B. ReplicatedStorage > Anims. Fehlt der Ordner dort, landet es im nächsten vorhandenen Ordner darüber. Danach ist es ausgewählt, Strg+Z macht es rückgängig.\n\nGesendet bleibt gesendet, bis du etwas Neues sendest. Du kannst also in mehreren Places empfangen.",
	"Auswahl senden", ACCENT, "Hier empfangen", GREEN))
local sendPlaceBtn, receivePlaceBtn = select(2, buttonRow("Ganze Place senden nimmt alles mit: Workspace (mit Terrain), Lighting, ReplicatedFirst, ReplicatedStorage, ServerScriptService, ServerStorage, StarterGui, StarterPack, StarterPlayer, SoundService, Teams, Chat, TextChatService und MaterialService, samt Scripts. Dazu die Einstellungen von Lighting (Uhrzeit, Nebel, Farben …), Workspace (Schwerkraft …) und StarterPlayer (Laufen, Springen, Kamera).\n\nGanze Place empfangen ERSETZT den Inhalt dieser Place durch die gesendete. Deshalb zweimal klicken. Strg+Z macht es rückgängig.\n\nNur außerhalb vom Play-Test.",
	"Place senden", ACCENT, "Place empfangen", BAD))
local transferLabel = label("")

-- Tab: ClientFX ----------------------------------------------------------------------------

page("FX", 5)
card("ClientFX", "Effekte, die der Server per ClientFX an die Clients schickt und die ein Client-Script zeichnet.")
local fxScanBtn = button("ClientFX suchen", ACCENT,
	"Durchsucht alle Scripts der offenen Place nach Effekt-Aufrufen wie ClientFX:FireAllClients(\"Stand Barrage\", ...).\n\nJedes Spiel nennt sein Remote anders. Gibt es unter dem eingetragenen Namen nichts, probiert das Plugin jedes RemoteEvent der Place und nimmt das mit den meisten Effekten.\n\nZu jedem Effekt siehst du, wo der Server ihn feuert (Server) und wo ein Client-Script ihn behandelt (Client). Klick darauf öffnet das Script an der Zeile.\n\nRot heißt: In dieser Place gibt es keinen Client-Code dafür. Vorlage legt dann ein LocalScript an, das schon auf den Effekt hört und die Parameter vom Server auflistet.\n\nPaket speichert alles zum Effekt (Scripts, passende Objekte, Assets) nach downloads/<Name>/.\n\nTesten: Siehe Karte Aufnahme unten. Im Play-Test die Attacke einmal benutzen, dann Wiederholen.")
label("Name des Effekt-RemoteEvents. Leer lassen oder falsch: das Plugin findet es beim Suchen selbst.")
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
local sceneStartBtn, sceneStopBtn = select(2, buttonRow("Der Effekt-Code wird nicht ausgeführt: In Kopien fehlen ihm die Daten vom Server, deshalb bricht er fast immer ab.\n\nStattdessen liest das Plugin im Code, welche Objekte der Effekt benutzt (z. B. Client Assets > Whitesnake > DirectOrderThrow), setzt Kopien davon an den Dummy und löst ihre Partikel aus, mit EmitCount und EmitDelay.\n\nDu siehst Partikel, Modelle, Beams und Trails. Bewegungen, die der Code macht (fliegende Fäuste, Tweens), siehst du nicht.\n\nStart spielt den letzten Effekt nochmal. Stopp löscht Dummy und Kopien.",
	"Start", ACCENT, "Stopp", GREY))
local sceneLabel = label("")

-- Tab: Cutscene ----------------------------------------------------------------------------

page("Cutscene", 6)
card("Cutscene", "Cutscene-Script im Explorer anklicken (oder den Ordner, in dem es liegt).")
local csInfo = label("Noch nichts ausgewählt.")
local csList = add(autoFrame())
vlist(csList, 4)
local csDownloadBtn, csRepairBtn = select(2, buttonRow("Mein Account: lädt vorher jedes Bild der Cutscene (Texturen, Decals, Partikel) unter deinem Account neu hoch, setzt die neuen IDs in die Kopie ein, auch im Script-Code, und lädt dann alles herunter. Braucht apikey.txt. Animationen und Sounds behalten ihre alten IDs, die lädt der Server nicht hoch.\n\nSucht im Code der ausgewählten Scripts alles, was die Cutscene benutzt: Models, Rigs mit AnimationController oder Humanoid, Kameras, Parts, Animationen, Sounds, Remotes und Module. Module, die per require geladen werden, durchsucht es genauso mit.\n\nAlles landet in downloads/<Name>/: <Name>.rbxm mit den Ordnern Code und Objekte (in Studio per Rechtsklick > Insert from File einfügbar), code.lua zum Lesen und jede Animation, jeder Sound und jedes Bild als eigene Datei.\n\nJede Animation steckt zusätzlich als KeyframeSequence in ihrem Animation-Objekt. Damit läuft die Cutscene mit Abspielen in jeder Place, auch wenn Roblox die Original-ID dort sperrt.\n\nKlick auf eine Zeile in der Liste zeigt das Objekt im Explorer.",
	"Herunterladen", ACCENT, "Mein Account", PURPLE))
-- Eine Tabelle statt mehrerer locals: Luau erlaubt höchstens 200 lokale Variablen pro Funktion.
local csPlay = {}
csPlay.row, csPlay.play, csPlay.auto = buttonRow("Abspielen: Cutscene im Explorer anklicken (das Cutscene-Script aus dem Spiel oder den eingefügten Download-Ordner) und drücken. Die Kamera fliegt wie im Spiel mit, jedes Rig spielt seine Animation, danach ist alles wieder wie vorher. Klappt im Edit-Modus und im Play-Test. Nochmal drücken stoppt.\n\nWer spielt was: Die Kamera-Animation (Camera) läuft auf dem Kamera-Rig (Cam, CameraRig …), jede andere Animation auf dem Rig mit passendem Namen. Spieler-Animationen (Player, CloneAnim …) laufen auf einem Dummy, im Play-Test auf deiner Figur. Hängt die Kamera am Spieler (z. B. Barrage-Finisher), steht sie an deiner Figur bzw. am Dummy.\n\nBeim Play-Test: merkt sich die angeklickte Cutscene. Jeder Play-Test (F5) spielt sie dann einmal ab, sobald deine Figur da ist. Nochmal drücken schaltet es aus.\n\nNicht nachgebaut: Effekte, die der Code zu bestimmten Zeitpunkten auslöst (Partikel-Bursts, Sounds, Bildschirm-Effekte).",
	"Abspielen", BLUE, "Beim Play-Test: aus", GREY)
csPlay.label = label("")

-- Tab: Credits -----------------------------------------------------------------------------

do -- eigener Block: hält die Zahl der Top-Level-Variablen unter Luaus Grenze von 200
	page("Credits", 7)
	card("Credits entfernen", "Entfernt in der ganzen Place Dekompilier-Hinweise, Discord-Links, Credits und Lizenzen.")
	local creditsBtn = button("Credits löschen", BAD, "Script-Code: löscht jeden Kommentar, in dem Credits, Lizenzen, Discord, Decompiler-Hinweise (Saved by, Script path, Decompile time, -- Line:, -- upvalues:) oder Copyright stehen. Discord-Links in Strings fliegen auch raus. Der restliche Code bleibt, wie er ist.\n\nObjekte (VFX, Models, GUIs): Discord-Links und „Made by …“ aus Namen, Texten und Attributen. StringValues und Scripts, die nur Credits enthalten (Credits, License), werden gelöscht. README-Scripts immer, auch das von SaveInstance direkt unter game.\n\nZum Bestätigen zweimal klicken. Strg+Z macht alles rückgängig.")
	local creditsLabel = label("")

	card("Kamera reparieren", "Wenn die Kamera nach dem Laden einer kopierten Place festhängt.")
	local _, cameraBtn, cameraNewBtn = buttonRow("Zurücksetzen: CameraType auf Fixed (so braucht Studio sie beim Bearbeiten), CameraSubject leer, Sichtfeld 70. Gespeicherte Places haben oft die Kamera vom Spiel mit CameraType Scriptable, dann bewegt sie sich nicht.\n\nNeu anlegen: löscht die Kamera, Studio legt sofort eine frische an. Für den Fall, dass Zurücksetzen nicht reicht.",
		"Zurücksetzen", ACCENT, "Neu anlegen", GREY)
	local cameraLabel = label("")
	cameraBtn.Activated:Connect(function()
		local cam = workspace.CurrentCamera
		cam.CameraType, cam.CameraSubject, cam.FieldOfView = Enum.CameraType.Fixed, nil, 70
		cameraLabel.TextColor3, cameraLabel.Text = OK, "Kamera zurückgesetzt. Hängt sie noch: Neu anlegen."
	end)
	cameraNewBtn.Activated:Connect(function()
		local old = workspace.CurrentCamera
		old:Destroy()
		-- Studio legt die neue Kamera erst nach ein paar Frames an.
		local t0 = os.clock()
		while (workspace.CurrentCamera == old or not workspace.CurrentCamera) and os.clock() - t0 < 1 do task.wait() end
		local ok = workspace.CurrentCamera ~= old and workspace.CurrentCamera ~= nil
		cameraLabel.TextColor3 = ok and OK or BAD
		cameraLabel.Text = ok and "Neue Kamera angelegt." or "Keine Kamera mehr da. Studio neu laden."
	end)

	-- Kleingeschrieben gesucht, als Lua-Muster. Ein Treffer in einem Kommentar löscht den ganzen Kommentar.
	local COMMENT_MARKERS = { "discord", "saved by", "saveinstance", "decompil", "script path:", "filteringenabled",
		"sourceassetid", "source from the asset", "join to copy", "credit", "made by", "created by", "scripted by",
		"written by", "modeled by", "author", "©", "copyright", "%(c%) %d", "licen[sc]e", "permission is hereby granted",
		"all rights reserved", "spdx", "https?://", "original asset", "original module", "^%-%-%s*line: %d", "^%-%-%s*upvalues:", "^%-%-%s*types:",
		-- Kopfzeilen anderer Decompiler und Saver (Konstant, Synapse, Medal, Oracle, unluau, Dex …)
		"luau version", "types version", "time taken:", "decompiled on", "script hash", "bytecode", "disassembl",
		"executor:", "synapse", "konstant", "unluau", "oracle", "medal", "%f[%a]dex%f[%A]", "t%.me/", "guilded%.gg" }
	-- Für Namen, Texte und Werte strenger: dort heißt „Credits“ oft Spielwährung, und „created by your stand“ ist Spieltext.
	local TEXT_MARKERS = { "discord", "^%s*made by", "^%s*created by", "^%s*scripted by", "^%s*credits? to", "join to copy",
		"saveinstance", "decompil", "t%.me/", "guilded%.gg/" }
	-- Namen ohne Leer- und Sonderzeichen kleingeschrieben: "!README!", "Read_Me", "CREDITS.txt" treffen alle.
	local CREDIT_NAMES = { credits = true, credit = true, creditstxt = true, license = true, licence = true, licensetxt = true,
		author = true, authors = true }
	local function plainName(name) return (name:lower():gsub("[^%w]", "")) end
	local LINKS = { "https?://[%w%.]*discord%.gg/[%w%-_]*", "discord%.gg/[%w%-_]*",
		"https?://[%w%.]*discord%w*%.com/invite/[%w%-_]*", "discord%w*%.com/invite/[%w%-_]*",
		"https?://t%.me/[%w%-_/]*", "https?://[%w%.]*guilded%.gg/[%w%-_/]*" }

	local function matchesAny(text, markers)
		local low = text:lower()
		for _, m in markers do
			if low:find(m) then return true end
		end
		return false
	end

	-- Credit-Sätze in Texten, die Spieler lesen (Item-Beschreibungen, GUIs). Lua-Muster auf dem kleingeschriebenen Satz.
	-- Nur eindeutige Formen: "made by dwarves" mitten in Spieltext bleibt, "Made by X." als eigener Satz geht.
	local CREDIT_SENTENCE = { "^%s*credits?%f[%A]", "credits? to%f[%A]", "credits?%s*:", "^%s*made by", "^%s*thanks to",
		"^%s*huge thanks", "^%s*special thanks", "thanks to @", "made by @", "by @[%w_]", "artpiece", "artwork by", "art by",
		"sprite work by", "concept by", "modell?ed by", "animated by", "music by", "song by", "animation made by",
		"model made by", "map made by", "originally made by", "edited by", "edit by" }

	-- Schneidet Credit-Sätze aus einem Text. Sätze enden an Zeilenumbrüchen (echt oder als \n im Code) und an ". ! ?".
	-- Endet ein Credit-Satz mit ":", ist er eine Überschrift ("Credits:"), dann geht alles danach mit.
	local function stripCredits(text)
		local lower = text:lower()
		if not (lower:find("credit", 1, true) or lower:find("thanks", 1, true) or lower:find(" by", 1, true)
			or lower:find("artpiece", 1, true) or lower:find("^made by")) then
			return text, 0
		end
		local marked = text:gsub("\\n", "\\n\1"):gsub("\n", "\n\1"):gsub("([%.!%?]+%s)", "%1\1")
		local kept, count = {}, 0
		for piece in (marked .. "\1"):gmatch("([^\1]*)\1") do
			local low = piece:lower()
			local first = nil
			for _, m in CREDIT_SENTENCE do
				local p = low:find(m)
				if p and (not first or p < first) then first = p end
			end
			if first then
				count += 1
				-- "GOAT | Pose Credit: …" behält "GOAT": zurück bis zum letzten Trenner. Ohne Trenner geht der ganze Satz.
				local prefix = piece:sub(1, first - 1):match("^(.*)[|;,%(%[]") or piece:sub(1, first - 1):match("^(.*)%s%-%s")
				if prefix and prefix:find("%w") then table.insert(kept, (prefix:gsub("[%s|%-,:;]+$", ""))) end
				if piece:gsub("\\n", ""):match(":%s*$") then break end
			else
				table.insert(kept, piece)
			end
		end
		if count == 0 then return text, 0 end
		-- Übrige Leerzeichen und \n am Ende weg, sonst endet "I'LL CRUSH YOU!!!\n\n" mit Leerzeilen.
		local result, before = table.concat(kept), nil
		repeat
			before = result
			result = result:gsub("%s+$", ""):gsub("\\n$", "")
		until result == before
		return result, count
	end

	-- Ersteller-Tags in Instanznamen und Animations-Markern ("MiH Cam by X", "Camera - by @X", "Keyframe (made by X)").
	-- Namen sind kein Spieltext, darum lockerer als CREDIT_SENTENCE: alles ab dem Tag geht, ohne Rest heißt die Instanz wie ihre Klasse.
	local function stripTag(text)
		local low, first = text:lower(), nil
		-- "Credits" fehlt mit Absicht: als Name ist das oft Spielwährung (leaderstats). "Lobby:" trifft dank %f nicht.
		-- () markiert, wo geschnitten wird: "MiH Cam by X" behält "MiH Cam".
		for _, m in { "made%s*by%f[%A]", "created%s*by%f[%A]", "animated%s*by%f[%A]", "%f[%a]anim%a*%s+()by%f[%A]",
			"%f[%a]cam%a*%s+()by%f[%A]", "cutscene%s+()by%f[%A]", "scripted%s*by%f[%A]", "coded%s*by%f[%A]", "edited%s*by%f[%A]",
			"%f[%a]v?fx%s+()by%f[%A]", "%f[%a]by%s*[@:]", "^%s*by%s", "[%-|%(%[]%s*by%s", "_by_%w", "discord", "t%.me/", "guilded%.gg/" } do
			local s, _, cut = low:find(m)
			local p = cut or s
			if p and (not first or p < first) then first = p end
		end
		if not first then return text, false end
		return (text:sub(1, first - 1):gsub("[%s|%-,:;%(%[_]+$", "")), true
	end

	local function stripLinks(text)
		local count = 0
		for _, p in LINKS do
			local n
			text, n = text:gsub(p, "")
			count += n
		end
		return text, count
	end

	-- Geht den Code einmal durch, damit -- in einem String nicht als Kommentar zählt. Gibt (Code, Kommentare, Links, Credit-Sätze).
	local function cleanSource(src)
		local out, i, n, comments, links, credits = {}, 1, #src, 0, 0, 0
		local function keep(s)
			local cleaned, c = stripLinks(s)
			links += c
			-- Credit-Sätze nur im Inneren von "…", '…' und [[…]]; `…` nicht, dort könnten {Ausdrücke} zerschnitten werden.
			local open, body, close = nil, nil, nil
			local q = cleaned:sub(1, 1)
			if (q == '"' or q == "'") and #cleaned >= 2 and cleaned:sub(-1) == q then
				open, body, close = q, cleaned:sub(2, -2), q
			else
				local eq = cleaned:match("^%[(=*)%[")
				if eq and cleaned:sub(-(#eq + 2)) == "]" .. eq .. "]" then
					open, body, close = "[" .. eq .. "[", cleaned:sub(#eq + 3, -(#eq + 3)), "]" .. eq .. "]"
				end
			end
			if body then
				local stripped, k = stripCredits(body)
				-- Endet der Rest auf \, würde er das schließende Anführungszeichen schlucken: dann lieber nichts ändern.
				if k > 0 and not stripped:match("\\$") then
					credits += k
					cleaned = open .. stripped .. close
				end
			end
			table.insert(out, cleaned)
		end
		while i <= n do
			local j = src:find("[\"'`%-%[]", i)
			if not j then table.insert(out, src:sub(i)) break end
			table.insert(out, src:sub(i, j - 1))
			local c = src:sub(j, j)
			if c == '"' or c == "'" or c == "`" then
				local k = j + 1
				while k <= n do
					local d = src:sub(k, k)
					if d == "\\" then k += 2 elseif d == c or d == "\n" then break else k += 1 end
				end
				keep(src:sub(j, k))
				i = k + 1
			elseif c == "[" then
				local eq = src:match("^%[(=*)%[", j)
				if eq then
					local _, e = src:find("]" .. eq .. "]", j, true)
					e = e or n
					keep(src:sub(j, e))
					i = e + 1
				else
					table.insert(out, c)
					i = j + 1
				end
			elseif src:sub(j, j + 1) == "--" then
				local eq = src:match("^%-%-%[(=*)%[", j)
				local e
				if eq then
					local _, close = src:find("]" .. eq .. "]", j, true)
					e = close or n
				else
					e = (src:find("\n", j, true) or n + 1) - 1
				end
				local comment = src:sub(j, e)
				if matchesAny(comment, COMMENT_MARKERS) then
					comments += 1
					-- Steht der Kommentar allein in seiner Zeile, geht die ganze Zeile samt Umbruch.
					local ls = j
					while ls > 1 and src:sub(ls - 1, ls - 1) ~= "\n" do ls -= 1 end
					local alone = src:sub(ls, j - 1):match("^[ \t]*$") ~= nil
					out[#out] = out[#out]:gsub("[ \t]*$", "")
					if alone and src:sub(e + 1, e + 1) == "\n" then e += 1 end
				else
					table.insert(out, comment)
				end
				i = e + 1
			else
				table.insert(out, c)
				i = j + 1
			end
		end
		return (table.concat(out):gsub("^[ \t\r\n]*\n", "")), comments, links, credits
	end

	local function cleanPlace()
		local r = { scripts = 0, comments = 0, links = 0, credits = 0, objects = 0, deleted = 0, skipped = 0 }
		local doomed, all = {}, {}
		for _, svc in game:GetChildren() do
			-- SaveInstance legt sein README direkt unter game, nicht in einen Dienst.
			if svc:IsA("LuaSourceContainer") or svc:IsA("ValueBase") then table.insert(all, svc) end
			-- CoreGui hält Studios und dieses Plugin-Fenster, das nicht anfassen.
			local ok, list = pcall(function() return svc.ClassName ~= "CoreGui" and svc:GetDescendants() or {} end)
			if ok then table.move(list, 1, #list, #all + 1, all) end
		end
		-- Erst die Namen: Scripts greifen oft per ["camera by kitsun2"] darauf zu, darum gehen die neuen Namen
		-- unten auch in jeden String im Code. Gleicher alter Name gibt überall denselben neuen, Geschwister bleiben eindeutig.
		local renamed, newName = {}, {}
		for count, obj in all do
			if count % 2000 == 0 then task.wait() end
			pcall(function()
				local old = obj.Name
				local name, hit = stripTag((stripLinks(old)))
				if not (hit or matchesAny(old, TEXT_MARKERS)) then return end
				if not newName[old] then
					local base = (name:find("%S") and not matchesAny(name, TEXT_MARKERS)) and name or obj.ClassName
					local pick, n = base, 1
					while obj.Parent and obj.Parent:FindFirstChild(pick) do n += 1 pick = base .. n end
					newName[old] = pick
				end
				obj.Name = newName[old]
				renamed[obj] = true
			end)
		end
		local function renameInCode(src)
			for old, new in newName do
				local pat, rep = old:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"), new:gsub("%%", "%%%%")
				src = src:gsub('"' .. pat .. '"', '"' .. rep .. '"'):gsub("'" .. pat .. "'", "'" .. rep .. "'")
			end
			return src
		end
		for count, obj in all do
			if count % 500 == 0 then task.wait() end
			pcall(function()
				local isCreditName = CREDIT_NAMES[plainName(obj.Name)]
				local isReadme = plainName(obj.Name):match("^readme") ~= nil -- README, !README!, Read_Me, README.txt, ReadMeFirst
				local changed = false
				if isReadme and (obj:IsA("LuaSourceContainer") or obj:IsA("ValueBase")) then
					table.insert(doomed, obj) -- READMEs immer weg, egal was drinsteht
					return
				end
				if obj:IsA("LuaSourceContainer") then
					local src = obj.Source
					local cleaned, comments, links, credits = cleanSource(src)
					if next(newName) then cleaned = renameInCode(cleaned) end
					if isCreditName and not cleaned:find("%S") then
						table.insert(doomed, obj)
						return
					end
					-- Sicherheitsnetz für jedes Spiel: kompilierte der Code vorher und danach nicht mehr, bleibt er, wie er war.
					local okBefore, before = pcall(loadstring, src)
					local okAfter, after = pcall(loadstring, cleaned)
					if cleaned ~= src and okBefore and before and not (okAfter and after) then
						r.skipped += 1
						return
					end
					if cleaned ~= src then
						-- .Source = geht nur bis 200000 Zeichen, große Module wie FunctionLibrary scheitern sonst still
						game:GetService("ScriptEditorService"):UpdateSourceAsync(obj, function() return cleaned end)
						r.scripts += 1
						r.comments += comments
						r.links += links
						r.credits += credits
					end
				elseif obj:IsA("StringValue") and (isCreditName or matchesAny(obj.Value, TEXT_MARKERS)) then
					table.insert(doomed, obj)
					return
				elseif obj:IsA("StringValue") then
					local text, k = stripCredits(obj.Value)
					if k > 0 then obj.Value, changed, r.credits = text, true, r.credits + k end
				elseif obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
					if matchesAny(obj.Text, TEXT_MARKERS) then
						local text = stripLinks(obj.Text)
						obj.Text = matchesAny(text, TEXT_MARKERS) and "" or text
						changed = true
					end
					local text, k = stripCredits(obj.Text)
					if k > 0 then obj.Text, changed, r.credits = text, true, r.credits + k end
				end
				if obj:IsA("KeyframeMarker") then
					local value, hit = stripTag(obj.Value)
					if hit then obj.Value, changed = value, true end
				end
				if renamed[obj] then changed = true end
				for key, value in obj:GetAttributes() do
					if CREDIT_NAMES[plainName(key)] or (type(value) == "string" and matchesAny(value, TEXT_MARKERS)) then
						obj:SetAttribute(key, nil)
						changed = true
					elseif type(value) == "string" then
						local text, k = stripCredits(value)
						if k > 0 then obj:SetAttribute(key, text) changed, r.credits = true, r.credits + k end
					end
				end
				if changed then r.objects += 1 end
			end)
		end
		for _, obj in doomed do
			if pcall(obj.Destroy, obj) then r.deleted += 1 end
		end
		return r
	end

	local creditsConfirmUntil = 0
	creditsBtn.Activated:Connect(function()
		if RunService:IsRunning() then
			creditsLabel.TextColor3, creditsLabel.Text = BAD, "Erst den Play-Test beenden."
			return
		end
		if os.clock() > creditsConfirmUntil then
			creditsConfirmUntil = os.clock() + 5
			creditsBtn.Text = "Sicher? Nochmal klicken"
			task.delay(5, function() creditsBtn.Text = "Credits löschen" end)
			return
		end
		creditsConfirmUntil = 0
		creditsBtn.Active, creditsBtn.Text = false, "Lösche …"
		local rec = ChangeHistoryService:TryBeginRecording("Asset Downloader: Credits löschen")
		local ok, r = pcall(cleanPlace)
		if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
		creditsBtn.Active, creditsBtn.Text = true, "Credits löschen"
		if ok then
			creditsLabel.TextColor3 = OK
			creditsLabel.Text = ("%d Scripts bereinigt (%d Kommentare, %d Links, %d Credit-Sätze), %d Objekte geändert, %d gelöscht.%s Strg+Z macht es rückgängig.")
				:format(r.scripts, r.comments, r.links, r.credits, r.objects, r.deleted,
					r.skipped > 0 and (" %d Scripts nicht angefasst, sie wären sonst kaputt gegangen."):format(r.skipped) or "")
		else
			creditsLabel.TextColor3, creditsLabel.Text = BAD, "Fehler: " .. tostring(r)
		end
	end)

	-- Variablennamen aufräumen ----------------------------------------------------------------
	-- Decompiler kennen die echten Namen nicht und nummerieren: v12, u28, p51, os_clock_ret. Der Knopf leitet
	-- aus dem Code einen lesbaren Namen ab (local v5 = script.Cam:Clone() -> camClone) und ersetzt nur echte
	-- Code-Stellen: keine Strings, keine Kommentare, keine Felder wie obj.v1. Ein neuer Name kommt nie vor, wenn es
	-- ihn im Script schon gibt.
	do
		card("Variablennamen aufräumen", "Macht dekompilierten Code lesbar: v12, u28, p51 bekommen Namen aus dem Code.")
		local renameBtn = button("Variablennamen aufräumen", PURPLE, "Dekompilierter Code nummeriert Variablen durch (v1, u28, p51, Vector2_new_ret). Dieser Knopf gibt ihnen Namen, die aus dem Code folgen:\n\nlocal v5 = script.Cam:Clone() wird camClone\nlocal u3 = game:GetService(\"Players\") wird Players\nlocal v9 = Instance.new(\"Part\") wird part\nRenderStepped:Connect(function(p51) wird dt, PlayerAdded wird player, InputBegan wird input, gameProcessed\n\nWo sich kein Name ableiten lässt, bleibt der alte. Strings, Kommentare und Felder (obj.v1) bleiben unangetastet, und ein neuer Name wird nie gewählt, wenn er im Script schon vorkommt. Kompiliert ein Script danach nicht mehr, bleibt es, wie es war.\n\nSind im Explorer Scripts oder Ordner ausgewählt, nur diese, sonst die ganze Place. Zum Bestätigen zweimal klicken. Strg+Z macht alles rückgängig.")
		local renameLabel = label("")

		local KEYWORDS = {}
		for _, k in { "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil",
			"not", "or", "repeat", "return", "then", "true", "until", "while", "continue", "export", "type", "self" } do
			KEYWORDS[k] = true
		end
		-- Parameter von Events, deren Bedeutung feststeht.
		local EVENT_PARAMS = {
			RenderStepped = { "dt" }, Heartbeat = { "dt" }, Stepped = { "time", "dt" }, PreRender = { "dt" }, PreSimulation = { "dt" },
			PlayerAdded = { "player" }, PlayerRemoving = { "player" }, CharacterAdded = { "character" },
			CharacterRemoving = { "character" }, CharacterAppearanceLoaded = { "character" },
			Touched = { "hit" }, TouchEnded = { "hit" }, OnServerEvent = { "player" }, Triggered = { "player" },
			MouseClick = { "player" }, Chatted = { "message" }, FocusLost = { "enterPressed" },
			InputBegan = { "input", "gameProcessed" }, InputEnded = { "input", "gameProcessed" }, InputChanged = { "input", "gameProcessed" },
			ChildAdded = { "child" }, ChildRemoved = { "child" }, DescendantAdded = { "descendant" },
			DescendantRemoving = { "descendant" }, Changed = { "property" }, KeyframeReached = { "keyframeName" },
			HealthChanged = { "health" }, StateChanged = { "oldState", "newState" }, Running = { "speed" },
		}

		-- Was nach "name." oder "name:" kommt, verrät, was die Variable ist. Erste passende Rolle in dieser Reihenfolge.
		local MEMBER_ROLES = {
			{ "player", { "Character", "UserId", "Kick", "Backpack", "PlayerGui", "DisplayName", "CharacterAdded" } },
			{ "character", { "Humanoid", "HumanoidRootPart" } },
			{ "humanoid", { "Health", "MaxHealth", "TakeDamage", "WalkSpeed", "JumpPower", "Died", "RootPart" } },
			{ "track", { "TimePosition", "AdjustSpeed", "IsPlaying", "GetMarkerReachedSignal" } },
			{ "animator", { "LoadAnimation", "GetPlayingAnimationTracks" } },
			{ "connection", { "Disconnect" } },
			{ "remote", { "FireServer", "FireClient", "FireAllClients", "InvokeServer", "OnClientEvent", "OnServerEvent" } },
			{ "input", { "UserInputType", "KeyCode", "UserInputState" } },
			{ "part", { "Anchored", "CanCollide", "AssemblyLinearVelocity", "Velocity", "BrickColor", "Material" } },
			{ "vector", { "Magnitude", "Unit" } },
			{ "signal", { "Connect", "Once" } },
			{ "label", { "Text", "TextColor3", "TextTransparency" } },
			{ "gui", { "Visible", "AbsoluteSize", "BackgroundTransparency" } },
			{ "cframe", { "LookVector", "RightVector", "UpVector", "Inverse", "ToWorldSpace", "ToObjectSpace" } },
			{ "part", { "CFrame", "Position", "Size", "Orientation" } },
			{ "instance", { "IsA", "FindFirstChild", "WaitForChild", "GetChildren", "GetDescendants", "Destroy", "Parent",
				"GetAttribute", "SetAttribute", "Clone", "FindFirstChildOfClass", "FindFirstAncestor", "Name", "ClassName" } },
		}
		local MEMBER_TO_ROLE = {}
		for rank, entry in MEMBER_ROLES do
			for _, member in entry[2] do
				if not MEMBER_TO_ROLE[member] then MEMBER_TO_ROLE[member] = { entry[1], rank } end
			end
		end

		local function isDecompName(n)
			return n:match("^[vup]%d+$") ~= nil or n:match("^[%a][%w]*_[%w_]*ret%d*$") ~= nil
		end

		local function lowerFirst(s) return s:sub(1, 1):lower() .. s:sub(2) end
		local function ident(s)
			s = (s or ""):gsub("[^%w_]", "")
			if s == "" then return nil end
			if s:match("^%d") then s = "n" .. s end
			return s
		end

		-- Name aus der rechten Seite von local x = <rhs>. nil, wenn nichts Sinnvolles folgt.
		local nameFromRhs
		function nameFromRhs(rhs)
			rhs = rhs:gsub(";%s*$", ""):gsub("%s+$", ""):gsub("%s+or%s+nil$", "")
			if rhs == "nil" or isDecompName(rhs) then return nil end
			if rhs == "..." then return "args" end
			if rhs:match("^#") then return "count" end
			if rhs:match("^not ") or rhs:find(" and true or false$") or rhs:match("^[%w_%.]+%s*[=~<>]=") then return "flag" end
			local svc = rhs:match('^game:GetService%("([%w_]+)"%)$')
			if svc then return svc end
			if rhs:match("^require%(") then
				return ident(rhs:match('"([^"]+)"%)%)?$') or rhs:match("([%w_]+)%)$"))
			end
			local class = rhs:match('^Instance%.new%("([%w_]+)"')
			if class then return lowerFirst(class) end
			if rhs:find(":LoadAnimation%(") then return "track" end
			if rhs:match("^setmetatable%(") then return "object" end
			local cloned = rhs:match("([%w_]+)%)?:Clone%(%)$") or rhs:match('"([^"]+)"%):Clone%(%)$')
			if cloned then return lowerFirst(ident(cloned) or "object") .. "Clone" end
			if rhs == "os.clock()" or rhs == "tick()" or rhs == "time()" then return "startTime" end
			if rhs == "true" or rhs == "false" then return "flag" end
			if rhs:match("^%-?%d") then return "value" end
			if rhs:match('^"') or rhs:match("^'") then return "text" end
			if rhs:match("^{") then return "list" end
			local child = rhs:match(':WaitForChild%("([^"]+)"[^)]*%)$') or rhs:match(':FindFirstChild%("([^"]+)"[^)]*%)$')
				or rhs:match(':GetAttribute%("([^"]+)"%)$')
			if child then return ident(lowerFirst(child)) end
			local ctor = rhs:match("^([%u][%w]*)%.new%(") or rhs:match("^[%w_%.]*%.([%u][%w]*)%.new%(") -- Parent.Gradient.new(…)
			if ctor then
				-- Vector2 -> vector, CFrame -> cframe, UDim2 -> udim (Ziffern stören, wenn ein Zähler drankommt)
				ctor = ctor:gsub("%d+$", "")
				return ctor:match("^%u%u") and ctor:lower() or lowerFirst(ctor)
			end
			local chain = rhs:match("^[%a_][%w_]*[%.%w_]*%.([%a_][%w_]*)$")
			if chain then return lowerFirst(chain) end
			if rhs:match("^[%a_][%w_]+$") and not KEYWORDS[rhs] then return lowerFirst(rhs) end -- local v5 = LocalPlayer (nicht aus "v")
			local call = rhs:match("^([%a_][%w_]*)%(")
			if call and not ({ tostring = 1, tonumber = 1, pcall = 1, unpack = 1, select = 1, type = 1, typeof = 1, ["function"] = 1 })[call] then
				call = call:gsub("^[Gg]et", ""):gsub("^[Cc]reate", ""):gsub("^[Mm]ake", ""):gsub("^[Bb]uild", "")
				if call ~= "" then return ident(lowerFirst(call)) end
			end
			if call == "tostring" or call == "tonumber" then
				-- tonumber(x:GetAttribute("Volume")) heißt wie das Innere
				return nameFromRhs(rhs:match("^%a+%((.*)%)$") or "") or (call == "tostring" and "text" or "number")
			end
			local method = rhs:match(":([%a_][%w_]*)%([^()]*%)$")
			if method then
				method = method:gsub("^GetPlayerFrom", ""):gsub("^FindFirst", ""):gsub("^Get", ""):gsub("^Find", "")
				if method ~= "" then return ident(lowerFirst(method)) end
			end
			return nil
		end

		-- Lua/Luau zerlegen: { art, text }, art = "n" Name, "s" String, "c" Kommentar, "o" alles andere.
		local function lex(src)
			local toks, i, n = {}, 1, #src
			local function push(kind, text) toks[#toks + 1] = { kind, text } end
			local function skipQuoted(k, q) -- gibt Index des schließenden Zeichens
				k += 1
				while k <= n do
					local d = src:sub(k, k)
					if d == "\\" then k += 2 elseif d == q or d == "\n" then return k else k += 1 end
				end
				return n
			end
			while i <= n do
				local c = src:sub(i, i)
				if c == "-" and src:sub(i + 1, i + 1) == "-" then
					local eq = src:match("^%[(=*)%[", i + 2)
					local j
					if eq then
						local _, e = src:find("]" .. eq .. "]", i + 4 + #eq, true)
						j = e or n
					else
						j = (src:find("\n", i, true) or n + 1) - 1
					end
					push("c", src:sub(i, j))
					i = j + 1
				elseif c == "[" and src:match("^%[=*%[", i) then
					local eq = src:match("^%[(=*)%[", i)
					local _, e = src:find("]" .. eq .. "]", i + 2 + #eq, true)
					local j = e or n
					push("s", src:sub(i, j))
					i = j + 1
				elseif c == '"' or c == "'" then
					local j = skipQuoted(i, c)
					push("s", src:sub(i, j))
					i = j + 1
				elseif c == "`" then
					-- Interpolierter String: Text bleibt String, Code in { } wird mit zerlegt.
					local start, k = i, i + 1
					while k <= n do
						local d = src:sub(k, k)
						if d == "\\" then
							k += 2
						elseif d == "`" then
							break
						elseif d == "{" then
							push("s", src:sub(start, k))
							local depth, m = 1, k + 1
							while m <= n do
								local e = src:sub(m, m)
								if e == '"' or e == "'" then
									m = skipQuoted(m, e)
								elseif e == "{" then
									depth += 1
								elseif e == "}" then
									depth -= 1
									if depth == 0 then break end
								end
								m += 1
							end
							for _, t in lex(src:sub(k + 1, m - 1)) do toks[#toks + 1] = t end
							start, k = m, m + 1
						else
							k += 1
						end
					end
					push("s", src:sub(start, math.min(k, n)))
					i = k + 1
				elseif c:match("[%a_]") then
					local word = src:match("^[%a_][%w_]*", i)
					push("n", word)
					i += #word
				elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
					local num = src:match("^%.?%d[%w_%.]*", i)
					push("o", num)
					i += #num
				else
					push("o", c)
					i += 1
				end
			end
			return toks
		end

		-- Gibt neuen Code und Zahl der umbenannten Variablen. scriptName: Name für die Klassen-Tabelle des Moduls.
		local function renameSource(src, scriptName)
			local toks = lex(src)
			local targets, order = {}, {}
			local function prevSignificant(k)
				k -= 1
				while k > 0 and toks[k][1] == "o" and toks[k][2]:match("^%s+$") do k -= 1 end
				return k
			end
			local ctx = {} -- "{" Tabelle, "(" Klammer, "b" Block: Schlüssel { Name = … } nur direkt in einer Tabelle
			for k, t in toks do
				local w = t[2]
				if t[1] == "o" then
					if w == "{" or w == "(" then
						table.insert(ctx, w)
					elseif w == "}" or w == ")" then
						table.remove(ctx)
					end
				elseif t[1] == "n" then
					-- Feld (obj.v1, obj:v1) ist kein Variablenname; ".." (Verkettung) schon.
					local p = prevSignificant(k)
					local isField = p > 0 and (toks[p][2] == ":" or (toks[p][2] == "." and not (p > 1 and toks[p - 1][2] == ".")))
					local prevP = p > 0 and not isField and toks[p][2]
					if not isDecompName(w) and ctx[#ctx] == "{" and (prevP == "{" or prevP == "," or prevP == ";") then
						-- Schlüssel im Tabellen-Konstruktor { Speed = … } ist auch kein Variablenname.
						local n1 = k + 1
						while n1 <= #toks and toks[n1][1] == "o" and toks[n1][2]:match("^%s+$") do n1 += 1 end
						isField = toks[n1] ~= nil and toks[n1][2] == "=" and not (toks[n1 + 1] and toks[n1 + 1][2] == "=")
					end
					t.field = isField
					if not isField then
						if w == "function" or w == "if" or w == "do" or w == "repeat" then
							table.insert(ctx, "b")
						elseif w == "end" or w == "until" then
							table.remove(ctx)
						end
					end
					if not isField and isDecompName(t[2]) and not targets[t[2]] then
						targets[t[2]] = true
						table.insert(order, t[2]) -- Reihenfolge im Code, damit Zähler (vector, vector2 …) von oben nach unten laufen
					end
				end
			end
			if next(targets) == nil then return src, 0 end
			-- Namen ableiten: aus local x = …, sonst aus Event-Parametern.
			local wanted = {}
			for name in targets do
				local rhs = src:match("local%s+" .. name .. "%s*=%s*([^\n]+)")
				if rhs and rhs:match("^{%s*};?%s*$") and scriptName and src:find(name .. ".__index = " .. name, 1, true) then
					wanted[name] = ident(scriptName) -- local u2 = {}; u2.__index = u2 ist die Klasse des Moduls
				else
					wanted[name] = rhs and nameFromRhs(rhs)
					-- Der Decompiler schreibt den echten Funktionsnamen in den Kommentar: function(…) -- Line: 1, Name: SpringStep
					local real = rhs and rhs:match("^function%(.-%-%-.-Name:%s*([%a_][%w_]*)")
						or src:match("local%s+function%s+" .. name .. "%([^\n]-%-%-[^\n]-Name:%s*([%a_][%w_]*)")
					if real and real ~= "anonymous" and not isDecompName(real) then wanted[name] = lowerFirst(real) end
				end
				if not wanted[name] then
					local later = src:match("\n[ \t]*" .. name .. "[ \t]*=[ \t]*([^=\n][^\n]*)")
					wanted[name] = later and nameFromRhs(later)
				end
			end
			-- Rumpf jeder function Tabelle.Methode(pN …) über Block-Tiefe finden (function/if/do/repeat öffnen, end/until schließen).
			local selfParams = {}
			for k, t in toks do
				if t[1] == "n" and t[2] == "function" and not t.field then
					local m, sawDot, first = k + 1, false, nil
					while m <= #toks and toks[m][2] ~= "(" do
						if toks[m][2] == "." then sawDot = true end
						m += 1
					end
					local q = m + 1
					while q <= #toks and toks[q][1] == "o" and toks[q][2]:match("^%s+$") do q += 1 end
					first = toks[q] and toks[q][1] == "n" and toks[q][2]
					if sawDot and first and first:match("^p%d+$") then
						local depth, e, hasSelf = 0, k, false
						while e <= #toks do
							local w = toks[e]
							if w[1] == "n" and not w.field then
								if w[2] == "function" or w[2] == "if" or w[2] == "do" or w[2] == "repeat" then
									depth += 1
								elseif w[2] == "end" or w[2] == "until" then
									depth -= 1
									if depth == 0 then break end
								elseif w[2] == "self" then
									hasSelf = true
								end
							end
							e += 1
						end
						if not hasSelf then selfParams[first] = true end
					end
				end
			end
			for event, params in src:gmatch("%.([%a_][%w_]*):Connect%(function%(([^%)]*)%)") do
				local names = EVENT_PARAMS[event]
				if names then
					local index = 0
					for param in params:gmatch("[^,%s]+") do
						index += 1
						if targets[param] and not wanted[param] and names[index] then wanted[param] = names[index] end
					end
				end
			end
			-- Gültigkeitsbereich jeder Variable als Token-Spanne: vom ersten Auftreten bis zum Ende des Blocks, in dem sie lebt.
			-- Variablen, deren Spannen sich nicht überschneiden (z. B. in verschiedenen Funktionen), dürfen denselben Namen
			-- tragen. Deshalb heißen sie überall "player" statt player, player2, player3 …
			-- Echte Namen: Deklarationen bekommen ebenfalls Spannen; ein Name, der irgendwo global benutzt wird, ist ganz gesperrt.
			local spans, origDecl, globalNames, ctxFunc = {}, {}, {}, {}
			do
				local blockEnd, stack, nextId = { [0] = #toks }, { 0 }, 0
				local header, inParams, localList, forVars, forCollect = false, false, false, nil, false
				local funcName, headerName = {}, nil -- Block-ID einer Funktion -> ihr Name (für Namen wie switchToAnimValue)
				local origOcc = {}
				local function note(name, k, block, decl)
					local list = origOcc[name]
					if not list then
						list = {}
						origOcc[name] = list
					end
					table.insert(list, { k, block, decl })
				end
				local function mark(name, k, block)
					local s = spans[name]
					if not s then
						s = { first = k, blocks = {} }
						spans[name] = s
						for i = #stack, 1, -1 do -- innerste Funktion mit Namen
							if funcName[stack[i]] then
								ctxFunc[name] = funcName[stack[i]]
								break
							end
						end
					end
					if k < s.first then s.first = k end
					s.blocks[block] = true
				end
				for k, t in toks do
					local w = t[2]
					if header and t[1] == "n" and w ~= "function" then headerName = w end
					if t[1] == "n" and not t.field then
						if w == "function" or w == "if" or w == "repeat" or w == "do" then
							nextId += 1
							table.insert(stack, nextId)
							if w == "function" then
								header, localList, headerName = true, false, nil
								local p = prevSignificant(k) -- M.Foo = function(…) / local v5 = function(…)
								local b = p > 0 and toks[prevSignificant(p)]
								if toks[p] and toks[p][2] == "=" and b and b[1] == "n" then headerName = b[2] end
							end
							if w == "do" and forVars then -- Schleifenvariablen leben im Rumpf der Schleife
								for _, entry in forVars do
									if targets[entry[1]] then mark(entry[1], entry[2], nextId) else note(entry[1], entry[2], nextId, true) end
								end
								forVars = nil
							end
						elseif w == "end" or w == "until" then
							if #stack > 1 then blockEnd[table.remove(stack)] = k end
						elseif (w == "else" or w == "elseif") and #stack > 1 then
							-- Jeder Zweig eines if ist ein eigener Block: Variablen aus then und else dürfen gleich heißen.
							blockEnd[table.remove(stack)] = k
							nextId += 1
							table.insert(stack, nextId)
						elseif w == "for" then
							forVars, forCollect = {}, true
						elseif w == "in" then
							forCollect = false
						elseif w == "local" then
							localList = true
						elseif KEYWORDS[w] then
							-- andere Schlüsselwörter sind keine Namen
						elseif header then -- local function vN(…): der Name gehört zum äußeren Block
							if targets[w] then
								mark(w, k, stack[#stack - 1] or 0)
							else
								local p = prevSignificant(k)
								local pp = p > 0 and prevSignificant(p) or 0
								note(w, k, stack[#stack - 1] or 0, toks[p][2] == "function" and pp > 0 and toks[pp][2] == "local")
							end
						elseif forVars and forCollect then
							table.insert(forVars, { w, k })
						elseif targets[w] then
							mark(w, k, stack[#stack])
						else
							local prev = toks[prevSignificant(k)]
							note(w, k, stack[#stack], inParams or (localList and prev ~= nil and (prev[2] == "local" or prev[2] == ",")))
						end
					elseif w == "(" and header then
						header, inParams = false, true
						funcName[stack[#stack]] = headerName
					elseif w == ")" and inParams then
						inParams = false
					elseif w == "=" or w == ";" or w == "\n" then
						localList = false
						if w == "=" then forCollect = false end
					end
				end
				for _, s in spans do
					local last = s.first
					for block in s.blocks do last = math.max(last, blockEnd[block] or #toks) end
					s.last = last
				end
				for name, list in origOcc do
					local decls = {}
					for _, o in list do
						if o[3] then table.insert(decls, { first = o[1], last = blockEnd[o[2]] or #toks }) end
					end
					origDecl[name] = decls
					for _, o in list do
						local covered = o[3]
						for _, d in decls do
							if covered then break end
							covered = o[1] >= d.first and o[1] <= d.last
						end
						if not covered then
							globalNames[name] = true
							break
						end
					end
				end
			end

			-- Hinweise aus der Verwendung sammeln.
			local CALL_ARG = { FindFirstChild = "childName", WaitForChild = "childName", FindFirstChildOfClass = "className",
				FindFirstChildWhichIsA = "className", IsA = "className", GetService = "serviceName", LoadAnimation = "animation",
				wait = "duration", delay = "delay", GetAttribute = "attributeName", SetAttribute = "attributeName",
				GetPlayerFromCharacter = "character", FireClient = "player", InvokeClient = "player", TakeDamage = "damage",
				GetMarkerReachedSignal = "markerName", AddItem = "object", spawn = "callback", defer = "callback",
				require = "module", Kick = "reason", GetPropertyChangedSignal = "propertyName", Play = "fadeTime", Stop = "fadeTime",
				AdjustSpeed = "speed", AdjustWeight = "weight" }
			local GENERIC_WORDS = { value = true, list = true, text = true, flag = true, object = true, arg = true, amount = true,
				callback = true, instance = true }
			local SETTER = { Set = true, Add = true, Remove = true, Give = true, Take = true, Apply = true, Play = true,
				Load = true, Spawn = true, Equip = true, Unequip = true, Update = true }
			local roles, best, isParam, setter, usage, prop, callArg, counter = {}, {}, {}, {}, {}, {}, {}, {}
			local funcParams, fromCall, headerParen, funcGuess = {}, {}, {}, {}
			local PLUMBING = { Connect = true, Once = true, Wait = true, Disconnect = true, FindFirstChild = true, WaitForChild = true,
				FindFirstChildOfClass = true, FindFirstChildWhichIsA = true, FindFirstAncestor = true, GetService = true, IsA = true,
				GetChildren = true, GetDescendants = true, GetAttribute = true, GetPropertyChangedSignal = true, Clone = true,
				IsDescendantOf = true, FindFirstAncestorOfClass = true, FindFirstAncestorWhichIsA = true }
			local function nextSig(k)
				k += 1
				while k <= #toks and toks[k][1] == "o" and toks[k][2]:match("^%s+$") do k += 1 end
				return k
			end
			for k, t in toks do
				if t[1] == "n" and not t.field then
					local w = t[2]
					if w == "function" then
						local m, fname = k + 1, nil
						while m <= #toks and toks[m][2] ~= "(" do
							if toks[m][1] == "n" then fname = toks[m][2] end
							m += 1
						end
						-- function M.SetSpeed(self, p2): der erste echte Parameter ist die "speed"
						if not fname then -- local v9 = function(…)
							local p = prevSignificant(k)
							local b = p > 0 and toks[prevSignificant(p)]
							if toks[p] and toks[p][2] == "=" and b and b[1] == "n" then fname = b[2] end
						end
						local verb, rest = (fname or ""):match("^(%u%l+)(%u[%w_]*)$")
						local plist = {}
						if fname then funcParams[fname] = plist end
						headerParen[m] = true
						-- Lokale Funktion heißt nach dem, was sie tut: erster :Methode(…)-Aufruf im Rumpf, z. B. takeDamage.
						if fname and targets[fname] and not funcGuess[fname] then
							local depth, e = 0, k
							while e <= #toks do
								local b = toks[e]
								if b[1] == "n" and not b.field then
									if b[2] == "function" or b[2] == "if" or b[2] == "do" or b[2] == "repeat" then
										depth += 1
									elseif b[2] == "end" or b[2] == "until" then
										depth -= 1
										if depth == 0 then break end
									end
								elseif b[1] == "n" and not PLUMBING[b[2]] and toks[prevSignificant(e)][2] == ":" then
									funcGuess[fname] = ident(lowerFirst(b[2]))
									break
								end
								e += 1
							end
						end
						local hint = verb and SETTER[verb] and ident(lowerFirst(rest)) or nil
						m += 1
						while m <= #toks and toks[m][2] ~= ")" do
							local v = toks[m]
							if v[1] == "n" then table.insert(plist, v[2]) end
							if v[1] == "n" and v[2] ~= "self" and not selfParams[v[2]] then
								if targets[v[2]] then
									isParam[v[2]] = true
									if hint then setter[v[2]] = hint end
								end
								hint = nil
							end
							m += 1
						end
					elseif w == "for" then
						local m, vars = k + 1, {}
						while m <= #toks and toks[m][2] ~= "in" and toks[m][2] ~= "=" and toks[m][2] ~= "do" do
							if toks[m][1] == "n" then table.insert(vars, toks[m][2]) end
							m += 1
						end
						local numeric, iter = toks[m] and toks[m][2] == "=", ""
						local q = m + 1
						while q <= #toks and toks[q][2] ~= "do" do
							if toks[q][1] == "n" then iter ..= " " .. toks[q][2] end
							q += 1
						end
						local second = iter:find("GetChildren") and "child" or iter:find("GetDescendants") and "descendant"
							or iter:find("GetPlayers") and "player" or iter:find("ipairs") and "item" or "value"
						for idx, v in vars do
							if targets[v] and not roles[v] then
								roles[v] = numeric and "i" or idx == 1 and (iter:find("ipairs") and "index" or "key") or second
							end
						end
					elseif targets[w] then
						local n1 = nextSig(k)
						local sep = toks[n1] and toks[n1][2]
						local after = toks[nextSig(n1)]
						if sep == "." and after and after[2] == "." then
							usage[w] = usage[w] or "text" -- v .. "…"
						elseif sep == "." or sep == ":" then
							local role = after and after[1] == "n" and MEMBER_TO_ROLE[after[2]]
							if role and (not best[w] or role[2] < best[w][2]) then best[w] = role end
						elseif sep == "(" and not best[w] then
							best[w] = { "callback", 99 }
						elseif sep == "[" then
							usage[w] = usage[w] or "list"
						elseif sep == "+" and after and after[2] == "=" then
							counter[w] = "count" -- v += 1
						elseif sep and sep:match("^[%+%-%*/%%%^<>]$") then
							usage[w] = usage[w] or "amount"
						end
						local p1 = prevSignificant(k)
						local before = toks[p1] and toks[p1][2]
						local b2 = toks[prevSignificant(p1)]
						if before == "=" and b2 and b2[1] == "n" and b2.field then
							prop[w] = prop[w] or ident(lowerFirst(b2[2])) -- x.Parent = v
						elseif before == "(" and b2 and b2[1] == "n" then
							local verb, rest = b2[2]:match("^(%u%l+)(%u[%w_]*)$")
							if CALL_ARG[b2[2]] then
								callArg[w] = callArg[w] or CALL_ARG[b2[2]]
							elseif verb and SETTER[verb] then
								callArg[w] = callArg[w] or ident(lowerFirst(rest)) -- :SetPrimaryPartCFrame(v) -> primaryPartCFrame
							elseif b2[2] == "ipairs" or b2[2] == "pairs" then
								usage[w] = usage[w] or "list"
							end
						elseif before == "#" or before == "in" then
							usage[w] = usage[w] or "list"
						elseif before and before:match("^[%+%-%*/%%%^<>]$") then
							usage[w] = usage[w] or "amount"
						end
					end
				end
			end

			-- Parameter heißen wie das, was an der Aufrufstelle übergeben wird: switchToAnim(animTable, …) -> animTable.
			for k, t in toks do
				local params = t[1] == "n" and funcParams[t[2]]
				if params then
					local n1 = nextSig(k)
					if toks[n1] and toks[n1][2] == "(" and not headerParen[n1] then
						local m, depth, index, argTok, argLen = n1 + 1, 0, 1, nil, 0
						while m <= #toks do
							local a = toks[m]
							local w = a[2]
							if a[1] == "o" and (w == "(" or w == "{" or w == "[") then
								depth += 1
							elseif a[1] == "o" and (w == ")" or w == "}" or w == "]") and depth > 0 then
								depth -= 1
							elseif depth == 0 and a[1] == "o" and (w == "," or w == ")") then
								local param = params[index]
								if argLen == 1 and argTok and argTok[1] == "n" and param and targets[param] and not fromCall[param] then
									local given = argTok[2]
									local idea
									if targets[given] then idea = wanted[given] elseif not KEYWORDS[given] then idea = lowerFirst(given) end
									if idea and not GENERIC_WORDS[idea] then fromCall[param] = idea end
								end
								if w == ")" then break end
								index, argTok, argLen = index + 1, nil, 0
								m += 1
								continue
							end
							if not (a[1] == "o" and w:match("^%s+$")) and a[1] ~= "c" then
								argTok, argLen = a, argLen + 1
							end
							m += 1
						end
					end
				end
			end

			-- Gleicher Name nur, wenn sich die Gültigkeitsbereiche nicht überschneiden und kein Originalname im Skript so heißt.
			local GENERIC = GENERIC_WORDS
			local ORDINALS = { "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth" }
			local SKIP_CONTEXT = { game = true, workspace = true, script = true, math = true, task = true, string = true, table = true,
				Instance = true, Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim2 = true, UDim = true, Enum = true,
				TweenInfo = true, new = true, tostring = true, tonumber = true, require = true, pcall = true, typeof = true, type = true,
				ipairs = true, pairs = true, select = true, unpack = true, setmetatable = true, os = true, self = true }
			local taken = {}
			local function free(candidate, span)
				if globalNames[candidate] or KEYWORDS[candidate] or isDecompName(candidate) or candidate:match("^[vup]%d*$") then
					return false
				end
				for _, other in origDecl[candidate] or {} do
					if span.first <= other.last and other.first <= span.last then return false end
				end
				for _, other in taken[candidate] or {} do
					if span.first <= other.last and other.first <= span.last then return false end
				end
				return true
			end
			local map, count = {}, 0
			for _, name in order do
				if selfParams[name] and not wanted[name] then
					-- pN kommt nur in seiner eigenen Methode vor, und dort gibt es kein anderes self.
					map[name] = "self"
					count += 1
					continue
				end
				local called = best[name] and best[name][1] == "callback"
				local ideas = { wanted[name], roles[name], funcGuess[name], best[name] and best[name][1], setter[name], fromCall[name],
					counter[name], prop[name], callArg[name], not called and usage[name] or nil,
					not called and (isParam[name] and "arg" or "value") or nil }
				local specific, generic = {}, {}
				for i = 1, 11 do
					local idea = ideas[i]
					-- Ideen wie "v" oder "u" sind nie frei: v2, v3 … wären wieder Decompiler-Namen (Endlosschleife).
					if idea and idea ~= "" and not idea:match("^[vup]%d*$") and not isDecompName(idea) then
						idea = idea:gsub("(%a)%d+$", "%1") -- textColor3 -> textColor, sonst sieht es wie ein Zähler aus
						if KEYWORDS[idea] then idea ..= "Value" end -- z. B. "type" aus einem Aufruf
						table.insert(GENERIC[idea] and generic or specific, idea)
					end
				end
				table.move(generic, 1, #generic, #specific + 1, specific)
				local span, chosen = spans[name] or { first = 0, last = math.huge }, nil
				for _, idea in specific do
					if free(idea, span) then
						chosen = idea
						break
					end
				end
				if not chosen then
					-- Alle Ideen belegt. Nie eine Zahl: otherPlayer, dann mit Kontext (switchToAnimArg, startTimeAmount),
					-- dann Ordnungswörter (thirdValue …), zuletzt Buchstaben (valueA, valueB …).
					local base = specific[1] or "value"
					local Base = base:sub(1, 1):upper() .. base:sub(2)
					local tries = { "other" .. Base }
					local function compound(word)
						if type(word) ~= "string" then return end
						if targets[word] then word = map[word] end
						if not word or word == base or KEYWORDS[word] or isDecompName(word) or #word > 24 then return end
						word = lowerFirst(word):gsub("%d+$", "")
						if word ~= "" and not word:match("^[vup]$") then table.insert(tries, word .. Base) end
					end
					compound(ctxFunc[name])
					local rhs = src:match("local%s+" .. name .. "%s*=%s*([^\n]+)") or src:match("\n[ \t]*" .. name .. "[ \t]*=[ \t]*([^=\n][^\n]*)")
					if rhs then
						for word in rhs:gmatch("[%a_][%w_]*") do
							if word ~= name and not KEYWORDS[word] and not SKIP_CONTEXT[word] then
								compound(word)
								break
							end
						end
					end
					for _, ordinal in ORDINALS do table.insert(tries, ordinal .. Base) end
					for _, candidate in tries do
						if free(candidate, span) then
							chosen = candidate
							break
						end
					end
					local n = 0
					while not chosen do
						n += 1
						if n > 100000 then error("Kein freier Name für " .. name) end -- Notbremse, Skript bleibt dann unverändert
						local letters, x = "", n
						repeat
							letters = string.char(65 + (x - 1) % 26) .. letters
							x = (x - 1) // 26
						until x == 0
						if free(base .. letters, span) then chosen = base .. letters end
					end
				end
				taken[chosen] = taken[chosen] or {}
				table.insert(taken[chosen], span)
				map[name] = chosen
				count += 1
			end
			if count == 0 then return src, 0 end
			local out = table.create(#toks)
			for k, t in toks do
				if t[1] == "c" then -- "-- upvalues: u13 (ref)" zeigt die neuen Namen
					out[k] = (t[2]:gsub("%f[%w_][vup]%d+%f[^%w_]", function(n) return map[n] end))
				else
					out[k] = (t[1] == "n" and not t.field and map[t[2]]) or t[2]
				end
			end
			return table.concat(out), count
		end

		local function renameScripts()
			local list, sel = {}, Selection:Get()
			local roots = #sel > 0 and sel or { game }
			for _, root in roots do
				local ok, all = pcall(function()
					local d = root == game and {} or root:GetDescendants()
					if root == game then
						for _, svc in game:GetChildren() do
							local okSvc, sub = pcall(function() return svc.ClassName ~= "CoreGui" and svc:GetDescendants() or {} end)
							if okSvc then table.move(sub, 1, #sub, #d + 1, d) end
						end
					else
						table.insert(d, 1, root)
					end
					return d
				end)
				for _, obj in ok and all or {} do
					if obj:IsA("LuaSourceContainer") then table.insert(list, obj) end
				end
			end
			local r = { scripts = 0, names = 0, skipped = 0, seen = #list }
			for i, s in list do
				if i % 10 == 0 then
					renameBtn.Text = ("Benenne um %d%% (%d/%d) …"):format(math.floor(i / #list * 100), i, #list)
					task.wait()
				end
				pcall(function()
					local src = s.Source
					local renamed, count = renameSource(src, s.Name)
					if count == 0 then return end
					-- Sicherheitsnetz wie bei Credits: kompilierte der Code vorher und danach nicht mehr, bleibt er.
					local okBefore, before = pcall(loadstring, src)
					local okAfter, after = pcall(loadstring, renamed)
					if okBefore and before and not (okAfter and after) then
						r.skipped += 1
						return
					end
					game:GetService("ScriptEditorService"):UpdateSourceAsync(s, function() return renamed end)
					r.scripts += 1
					r.names += count
				end)
			end
			return r
		end

		local confirmUntil = 0
		renameBtn.Activated:Connect(function()
			if RunService:IsRunning() then
				renameLabel.TextColor3, renameLabel.Text = BAD, "Erst den Play-Test beenden."
				return
			end
			if not renameBtn.Active then return end
			if os.clock() > confirmUntil then
				confirmUntil = os.clock() + 5
				local sel = #Selection:Get() > 0
				renameBtn.Text = sel and "Sicher? Nur Auswahl, nochmal" or "Sicher? Ganze Place, nochmal"
				task.delay(5, function() if renameBtn.Active then renameBtn.Text = "Variablennamen aufräumen" end end)
				return
			end
			confirmUntil = 0
			renameBtn.Active = false
			local rec = ChangeHistoryService:TryBeginRecording("Asset Downloader: Variablennamen aufräumen")
			local ok, r = pcall(renameScripts)
			if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
			renameBtn.Active, renameBtn.Text = true, "Variablennamen aufräumen"
			if ok then
				renameLabel.TextColor3 = OK
				renameLabel.Text = ("%d Variablen in %d von %d Scripts umbenannt.%s Strg+Z macht es rückgängig.")
					:format(r.names, r.scripts, r.seen, r.skipped > 0 and (" %d Scripts nicht angefasst, sie wären sonst kaputt gegangen."):format(r.skipped) or "")
			else
				renameLabel.TextColor3, renameLabel.Text = BAD, "Fehler: " .. tostring(r)
			end
		end)
	end
end

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

-- R6-Rigs haben oft den Kopf als PrimaryPart. Wer dann PrimaryPart verankert, friert den Kopf ein und der
-- Körper dreht sich um ihn herum. Deshalb: HumanoidRootPart als PrimaryPart, nur er verankert, Rest lose.
-- root: Wurzel des Rigs (Standard: HumanoidRootPart). Wird PrimaryPart. Teile, die ein Motor6D bewegt, werden
-- gelöst, sonst bleiben sie stehen. Lose Teile (z. B. VFX) bleiben, wie sie sind.
local function fixRigRoot(rig, root)
	root = root or rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
	if root then rig.PrimaryPart = root end
	for _, j in rig:GetDescendants() do
		if j:IsA("Motor6D") then
			for _, part in { j.Part0, j.Part1 } do
				if part and part ~= root and part:IsDescendantOf(rig) then part.Anchored = false end
			end
		end
	end
	return rig
end

-- Rig für die Animation: ausgewähltes Model mit Humanoid, sonst ein Standard-Dummy.
local function makeRig(clip)
	for _, sel in Selection:Get() do
		local m = sel:IsA("Model") and sel or sel:FindFirstAncestorWhichIsA("Model")
		if m and m:FindFirstChildWhichIsA("Humanoid", true) then
			local ok, copy = pcall(function() return m:Clone() end)
			if ok and copy then return fixRigRoot(copy) end
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
	return ok and fixRigRoot(rig) or nil
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
		if track then -- Vorschau läuft sofort; der Knopf Abspielen stellt einen Dummy in die Welt
			track:Play(0)
			stepConn = RunService.Heartbeat:Connect(function(dt) animator:StepAnimations(dt) end)
		end
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
	if parts:FindFirstChildWhichIsA("BasePart", true) then
		parts:PivotTo(cf)
		-- Liegen die Effekte weit auseinander (CursedEnergy: Arm und Trail fast 1000 Studs), landete nur die Mitte
		-- vor der Kamera und jeder Effekt außerhalb des Bildes. Dann jeden einzeln nebeneinander vor die Kamera.
		local units = {}
		local function collect(o)
			if o:IsA("BasePart") or o:IsA("Model") then
				table.insert(units, o)
			elseif o:IsA("Folder") then
				for _, c in o:GetChildren() do collect(c) end
			end
		end
		for _, c in parts:GetChildren() do collect(c) end
		if #units > 1 and select(2, parts:GetBoundingBox()).Magnitude > 30 then
			for i, u in units do
				local target = cf * CFrame.new((i - (#units + 1) / 2) * 4, 0, 0)
				if u:IsA("Model") then
					u:PivotTo(target * u:GetPivot().Rotation)
				else
					local move = target * u.CFrame.Rotation * u.CFrame:Inverse()
					local list = u:GetDescendants()
					table.insert(list, 1, u)
					for _, q in list do
						if q:IsA("BasePart") then q.CFrame = move * q.CFrame end
					end
				end
			end
		end
	end
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
	b.FontFace, b.TextSize = FONT.medium, 13
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

-- Eigenschaften, in denen Assets per ID stecken.
local ID_PROPS = { Animation = { "AnimationId" }, Sound = { "SoundId" }, ParticleEmitter = { "Texture" },
	Beam = { "Texture" }, Trail = { "Texture" }, Decal = { "Texture" }, Texture = { "Texture" },
	MeshPart = { "MeshId", "TextureID" }, SpecialMesh = { "MeshId", "TextureId" }, ImageLabel = { "Image" },
	ImageButton = { "Image" }, Shirt = { "ShirtTemplate" }, Pants = { "PantsTemplate" }, ShirtGraphic = { "Graphic" },
	SurfaceAppearance = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" } }

-- Alle Asset-IDs in der Explorer-Auswahl und darunter, ohne Duplikate, in Explorer-Reihenfolge.
local function idsIn(roots)
	local ids, seen = {}, {}
	local function visit(obj)
		for _, prop in ID_PROPS[obj.ClassName] or {} do
			local okRead, raw = pcall(function() return obj[prop] end) -- manche Eigenschaften dürfen Plugins nicht lesen
			local value = okRead and tostring(raw) or ""
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

-- Objekte sichern: optional Texturen unter eigenem Namen hochladen und IDs tauschen,
-- dann .rbxm + alle Texturen nach downloads/<name>/. Nach dem Hochladen tragen Datei und Bilder die neuen IDs.
-- Schreibt Bytes als Datei nach downloads/<folder>/<file> (leer = <folder>.rbxm). Hex, weil Luau-Strings
-- im HTTP-Body sonst nicht binär-sicher ankommen.
local HEX = {}
for i = 0, 255 do HEX[string.char(i)] = string.format("%02x", i) end

-- In Stücken von 1 MB: Der Knopf (btn, optional) zeigt Prozent, und Studio friert bei großen Dateien nicht ein.
local STORE_CHUNK = 1024 * 1024
local function store(folder, file, bytes, btn)
	local url = ("%s/api/plugin-store?folder=%s&file=%s"):format(SERVER, HttpService:UrlEncode(folder), HttpService:UrlEncode(file))
	local parts = math.max(1, math.ceil(#bytes / STORE_CHUNK))
	for i = 1, parts do
		if btn then btn.Text = progress("Sende Datei", i - 1, parts) end
		-- Tabelle statt Funktion in gsub: bei vielen MB deutlich schneller
		local hex = bytes:sub((i - 1) * STORE_CHUNK + 1, i * STORE_CHUNK):gsub(".", HEX)
		local ok, res = pcall(HttpService.RequestAsync, HttpService,
			{ Url = url .. (i > 1 and "&append=1" or ""), Headers = PLUGIN_HEADERS, Method = "POST", Body = hex })
		if not (ok and res.Success) then return false end
	end
	return true
end

local function backup(roots, name, repair, btn, idleText, outLabel)
	local found, ids = collectTextures(roots), {}
	for id in found do table.insert(ids, id) end
	btn.Active = false
	local lines, allOk, map = {}, true, {}
	if repair and #ids > 0 then lines, allOk, map = repairTextures(found, ids, btn) end

	btn.Text = "Speichere …"
	local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, roots)
	local stored = okSer and store(name, "", buffer.tostring(buf), btn)
	table.insert(lines, stored and ("Gespeichert: downloads/%s/%s.rbxm"):format(name, name) or "Datei konnte nicht gespeichert werden. Läuft start.bat?")
	-- Alles, was in der Auswahl per ID steckt, in denselben Ordner: Meshes, Bilder, Sounds, Animationen.
	-- So muss man ein Model aus mehreren Meshes nicht Teil für Teil herunterladen.
	local all = idsIn(roots)
	if #all > 0 then
		local fileIds = {}
		for _, id in all do table.insert(fileIds, map[id] or id) end
		local r = save(fileIds, name, btn, "Speichere …")
		table.insert(lines, r and ("%d/%d Assets gespeichert (Meshes, Bilder, Sounds, Animationen)."):format(r.saved, r.total)
			or "Assets konnten nicht gespeichert werden.")
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
	local function scanRemote(remote)
	for _, s in scripts do
		local src = s[2]
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
	end
	scanRemote(remoteName())
	-- Jedes Spiel nennt sein Effekt-Remote anders (YBA: ClientFX). Ohne Treffer jedes RemoteEvent probieren
	-- und das mit den meisten Effekten nehmen; der Name landet im Feld, damit Aufnahme und Vorlage ihn kennen.
	if next(fx) == nil then
		local best, bestCount, tried = nil, 0, {}
		for _, obj in game:GetDescendants() do
			local ok, isRemote = pcall(function() return obj:IsA("RemoteEvent") end)
			if ok and isRemote and not tried[obj.Name] then
				tried[obj.Name] = true
				fx = {}
				scanRemote(obj.Name)
				local n = 0
				for _ in fx do n += 1 end
				if n > bestCount then best, bestCount = obj.Name, n end
			end
		end
		fx = {}
		if best then
			fxRemoteBox.Text = best
			plugin:SetSetting("fxRemote", best)
			scanRemote(best)
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
	local first = Selection:Get()[1]
	local clip = first and (first:IsA("AnimationClip") and first or #ids == 0 and first:FindFirstChildWhichIsA("AnimationClip", true))
	if clip then
		-- Animationsdatei (z. B. per Insert from File eingefügt): hat keine ID, also direkt als Clip zeigen.
		if loaded and loaded.sound then loaded.sound:Destroy() end
		local copy = clip:Clone()
		loaded = { id = "", kind = "Animation", name = clip.Name, objects = { copy }, clip = copy }
		status.TextColor3, status.Text = OK, ("Animation: %s. Abspielen stellt einen Dummy vor deine Kamera."):format(clip.Name)
		savedLabel.Text, row2.Visible, uploadBtn.Visible = "", false, false
		insertBtn.Visible, playBtn.Visible, row.Visible = true, true, true
		showTab("Laden")
		showPreview()
		return
	end
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
	local sent = store(TRANSFER, "auswahl.rbxm", buffer.tostring(buf), sendBtn) and store(TRANSFER, "ziel.json", HttpService:JSONEncode(parents))
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
	if not loaded or loaded.clip then return end -- Animationen: Dummy in der Welt, siehe unter startScene
	if loaded.vfx then emitVfx() else playToggle() end
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
	if loaded and loaded.clip then playBtn.Text = "Abspielen" end
	sceneLabel.TextColor3, sceneLabel.Text = MUTED, "Gestoppt, aufgeräumt."
end
plugin.Unloading:Connect(stopScene) -- beim Neuladen des Plugins keinen Dummy im Workspace zurücklassen

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
local function startScene(entry, animOnly)
	stopScene()
	local clip = loaded and loaded.clip
	if not entry and not animOnly then
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
	rig.Name, rig.Archivable = "Vorschau-Dummy", false -- nie mit der Place speichern
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

-- Abspielen im Tab Laden: Animation auf einem Dummy 12 Studs vor der Kamera. Ist ein Rig ausgewählt,
-- spielt eine Kopie davon. Nochmal drücken entfernt ihn.
playBtn.Activated:Connect(function()
	if not (loaded and loaded.clip) then return end
	if scene and scene.clip == loaded.clip then
		stopScene()
		return
	end
	startScene(nil, true)
	if scene then
		scene.clip = loaded.clip
		playBtn.Text = "Stopp"
		status.TextColor3, status.Text = OK, ("%s spielt auf einem Dummy vor deiner Kamera. Stopp entfernt ihn."):format(loaded.name)
	end
end)

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
	local csCurrent = nil -- { scripts, objects, ids }
	do -- Suche nach Abhängigkeiten: eigener Block, danach braucht nur noch csCurrent die Ergebnisse
		local CUTSCENE_MAX_DESCENDANTS = 10000 -- obere Grenze, auch wenn der Code ein Objekt ganz braucht
		local CUTSCENE_MAX_DEPTH = 4 -- require-Ketten so tief verfolgen
		local CUTSCENE_STORE_SIZE = 300 -- größere Objekte nur, wenn der Code sie ganz braucht (sonst Lager wie Anims, Sounds)
		local CUTSCENE_LIBRARY_USERS = 3 -- ab so vielen anderen Scripts, die ein Modul laden, ist es eine Bibliothek
		-- Code braucht ein Objekt ganz, wenn er es klont, durchläuft, umhängt oder mit einem Variablennamen darin sucht.
		-- Feste Namen in FindFirstChild("x") und ["x"] hat normalize() schon zu .x gemacht, was übrig bleibt, ist dynamisch.
		local WHOLE_USES = { ":GetChildren", ":GetDescendants", ":Clone", ":FindFirstChild", ":WaitForChild", "%[", "%.Parent%s*=[^=]" }

		local function usedWhole(obj, text, alias)
			local token = obj.Name:gsub(" ", "\1")
			local names = { token }
			for name, target in alias do
				if target == token then table.insert(names, name) end
			end
			for _, n in names do
				local p = "%f[%w_\1]" .. (n:gsub("[^%w_\1]", "%%%0")) .. "%f[^%w_\1]"
				for _, use in WHOLE_USES do
					if text:find(p .. use) then return true end
				end
			end
			return false
		end

		local function indexAll()
			local byName, sources = {}, {}
			for _, obj in game:GetDescendants() do
				local ok, name = pcall(function() return obj.Name end)
				if ok then
					byName[name] = byName[name] or {}
					table.insert(byName[name], obj)
				end
				local okSrc, src = pcall(function() return obj:IsA("LuaSourceContainer") and obj.Source end)
				if okSrc and src then sources[obj] = src end
			end
			return byName, sources
		end

		-- FindFirstChild(Name) mit Name = script.Name wird zum echten Namen, sonst käme der ganze Ordner aller Varianten mit.
		local function withScriptName(src, name)
			local vars = { "script%.Name" }
			for v in src:gmatch("local ([%w_]+) = script%.Name%s") do table.insert(vars, v) end
			local function literal() return ('["%s"]'):format(name) end
			for _, v in vars do
				src = src:gsub(":FindFirstChild%(" .. v .. "%)", literal):gsub(":WaitForChild%(" .. v .. "%)", literal)
					:gsub("%[" .. v .. "%]", literal)
			end
			return src
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
		-- Bibliotheken (FunctionLibrary & Co.) kommen nur als Code mit: ihre Objekte gehören zum ganzen Spiel.
		local function cutsceneDeps(selected)
			local byName, sources = indexAll()
			local selectedSet = {}
			for _, s in selected do selectedSet[s] = true end
			-- shortcut: zählt Scripts, in denen Modulname und "require" vorkommen, nicht echte require-Aufrufe
			local function isLibrary(module)
				local users = 0
				for s, src in sources do
					if s ~= module and not selectedSet[s] and src:find(module.Name, 1, true) and src:find("require", 1, true) then
						users += 1
						if users >= CUTSCENE_LIBRARY_USERS then return true end
					end
				end
				return false
			end
			local scripts, objects, ids = {}, {}, {}
			local seenScript, seenObj, seenId, libSet = {}, {}, {}, {}
			local function addId(id)
				if #id >= 5 and not seenId[id] then
					seenId[id] = true
					table.insert(ids, id)
				end
			end
			local queue = {}
			for _, s in selected do table.insert(queue, { s, 0, false }) end
			while #queue > 0 do
				local s, depth, lib = table.unpack(table.remove(queue, 1))
				if not seenScript[s] then
					seenScript[s] = true
					table.insert(scripts, s)
					libSet[s] = lib or nil
					local src = withScriptName(sources[s] or "", s.Name)
					if not lib then
						for id in src:gmatch("rbxassetid://(%d+)") do addId(id) end
						for id in src:gmatch("[?&][iI][dD]=(%d+)") do addId(id) end
						for id in src:gmatch("[Ii]d%s*=%s*(%d+)") do addId(id) end -- AnimationId = 123, SoundId = 123
					end
					local text, alias = normalize(src), {}
					for name, rhs in text:gmatch("local ([%w_]+) = ([^\n]+)") do
						alias[name] = rhs:match("([%w_\1]+)%s*%)*%s*$")
					end
					local function accept(obj)
						if obj:IsA("LuaSourceContainer") then return obj:IsA("ModuleScript") end
						if lib then return false end -- Bibliotheken: nur ihre Module zählen
						return #obj:GetDescendants() <= CUTSCENE_STORE_SIZE or usedWhole(obj, text, alias)
					end
					local entry = { name = s.Name, script = s, line = 1, text = src, source = src }
					for _, obj in effectObjects(entry, byName, accept, CUTSCENE_MAX_DESCENDANTS) do
						if obj:IsA("ModuleScript") then
							if depth < CUTSCENE_MAX_DEPTH and not seenScript[obj] then
								table.insert(queue, { obj, depth + 1, lib or isLibrary(obj) })
							end
						elseif not lib and not seenObj[obj] then
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
			return scripts, top, ids, libSet
		end


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
			local scripts, objects, ids, libSet = cutsceneDeps(selected)
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
			for _, s in scripts do
				row(("%s  ·  %s%s"):format(s.Name, s.ClassName, libSet[s] and ", Bibliothek: nur Code" or ""), s)
			end
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
	end

	-- Animation als KeyframeSequence über den lokalen Server holen (der probiert die Spielkontexte durch).
	-- Gleiche IDs nur einmal. Gibt den Clip oder nil.
	-- Im Play-Test darf nur der Server HTTP. Der Client fragt deshalb das Plugin auf dem Server über diese RemoteFunction.
	local CLIP_REMOTE = "AssetDownloaderClip"
	local clipCache = {}
	local function fetchClip(id)
		if clipCache[id] ~= nil then return clipCache[id] or nil end
		local clip = false
		if RunService:IsRunning() and RunService:IsClient() then
			local remote = game:GetService("ReplicatedStorage"):FindFirstChild(CLIP_REMOTE)
			local ok, res = pcall(function() return remote and remote:InvokeServer(id) end)
			clip = ok and typeof(res) == "Instance" and res:IsA("AnimationClip") and res or false
			clipCache[id] = clip
			return clip or nil
		end
		local url = ("%s/api/plugin?q=%s&place=%s"):format(SERVER, id, HttpService:UrlEncode(placeBox.Text))
		local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Headers = PLUGIN_HEADERS, Method = "GET" })
		if ok and res.Success then
			local okDes, objs = pcall(SerializationService.DeserializeInstancesAsync, SerializationService, buffer.fromstring(res.Body))
			for _, obj in okDes and objs or {} do
				clip = obj:IsA("AnimationClip") and obj or obj:FindFirstChildWhichIsA("AnimationClip", true) or false
				if clip then break end
			end
		end
		clipCache[id] = clip
		return clip or nil
	end

	local function animId(a)
		return a.AnimationId:match("(%d%d%d%d%d+)")
	end

	if RunService:IsRunning() and RunService:IsServer() then
		-- Clips für den Client: einmal laden, in ReplicatedStorage legen, damit sie beim Client ankommen.
		local rs = game:GetService("ReplicatedStorage")
		local holder = Instance.new("Folder")
		holder.Name, holder.Parent = CLIP_REMOTE .. "s", rs
		local remote = Instance.new("RemoteFunction")
		remote.Name, remote.Parent = CLIP_REMOTE, rs
		remote.OnServerInvoke = function(_, id)
			if type(id) ~= "string" or not id:match("^%d+$") then return nil end
			local clip = holder:FindFirstChild(id)
			if not clip then
				local fetched = fetchClip(id)
				if not fetched then return nil end
				clip = fetched:Clone()
				clip.Name, clip.Parent = id, holder
			end
			return clip
		end
	end

	local function downloadCutscene(repair, btn, idleText)
		if not csCurrent then
			status.TextColor3, status.Text = BAD, "Erst ein Cutscene-Script im Explorer anklicken."
			return
		end
		if not btn.Active then return end
		local name = csCurrent.scripts[1].Name -- der Server entfernt Zeichen, die in Ordnernamen nicht gehen
		btn.Active = false
		local pack = Instance.new("Folder")
		pack.Name = name
		local folders = { Code = Instance.new("Folder"), Objekte = Instance.new("Folder") }
		for folderName, f in folders do f.Name, f.Parent = folderName, pack end
		local jobs = {}
		for _, s in csCurrent.scripts do table.insert(jobs, { s, folders.Code }) end
		for _, obj in csCurrent.objects do table.insert(jobs, { obj, folders.Objekte }) end
		for i, job in jobs do
			if i % 10 == 1 then
				btn.Text = progress("Kopiere", i - 1, #jobs)
				task.wait() -- Studio zeichnet den Knopf erst nach einem Yield neu
			end
			local ok, copy = pcall(function() return job[1]:Clone() end)
			if ok and copy then copy.Parent = job[2] end -- nicht archivierbare Objekte liefern nil
		end
		-- Unter eigenem Namen: Bilder in der Kopie neu hochladen und alte IDs überall ersetzen, auch im Code.
		local lines, map, allOk, code = {}, {}, true, {}
		if repair then
			local found, texIds = collectTextures({ pack }), {}
			-- Nur IDs aus Textur-Eigenschaften: Bei IDs, die nur im Code stehen, weiß niemand, ob es Bilder sind.
			for id in found do table.insert(texIds, id) end
			if #texIds > 0 then lines, allOk, map = repairTextures(found, texIds, btn) end
			for _, s in pack:GetDescendants() do
				if s:IsA("LuaSourceContainer") then
					pcall(function()
						-- UpdateSourceAsync statt .Source =, das geht nur bis 200000 Zeichen
						game:GetService("ScriptEditorService"):UpdateSourceAsync(s, function(old)
							return (old:gsub("rbxassetid://(%d+)", function(id) return map[id] and ("rbxassetid://" .. map[id]) end))
						end)
					end)
				end
			end
		end
		-- Jede Animation als KeyframeSequence in ihr Animation-Objekt: Dann spielt Abspielen die Cutscene
		-- in jeder Place, auch wo Roblox die Original-ID nicht herausgibt.
		local anims, embedded = {}, 0
		for _, a in pack:GetDescendants() do
			if a:IsA("Animation") and animId(a) and not a:FindFirstChildWhichIsA("AnimationClip") then table.insert(anims, a) end
		end
		for i, a in anims do
			btn.Text = progress("Lade Animationen", i - 1, #anims)
			local clip = fetchClip(animId(a))
			if clip then
				clip:Clone().Parent = a
				embedded += 1
			end
		end
		if #anims > 0 then
			table.insert(lines, ("%d/%d Animationen eingebettet, Abspielen geht damit in jeder Place."):format(embedded, #anims))
		end
		for _, s in pack:GetDescendants() do
			if s:IsA("LuaSourceContainer") then
				local ok, src = pcall(function() return s.Source end)
				if ok then table.insert(code, ("-- ===== %s (%s) =====\n%s"):format(s:GetFullName(), s.ClassName, src)) end
			end
		end
		btn.Text = "Speichere Datei …"
		task.wait()
		local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, { pack })
		pack:Destroy()
		local stored = okSer and store(name, "", buffer.tostring(buf), btn)
		table.insert(lines, stored and ("Gespeichert: downloads/%s/%s.rbxm"):format(name, name)
			or "Cutscene konnte nicht gespeichert werden. Läuft start.bat?")
		if #code > 0 and store(name, "code.lua", table.concat(code, "\n\n")) then table.insert(lines, "Code zum Lesen: code.lua") end
		if #csCurrent.ids > 0 then
			-- Hochgeladene Bilder unter der neuen ID speichern, den Rest (Animationen, Sounds) unter der alten.
			local fileIds = {}
			for _, id in csCurrent.ids do table.insert(fileIds, map[id] or id) end
			local r = save(fileIds, name, btn, "Speichere …")
			if r then
				table.insert(lines, ("%d/%d Assets gespeichert (Animationen, Sounds, Bilder)."):format(r.saved, r.total))
				for _, e in r.errors do table.insert(lines, ("%s: %s"):format(e.id, e.error)) end
			end
			allOk = allOk and r ~= nil and r.saved == r.total
		end
		btn.Active, btn.Text = true, idleText
		status.TextColor3, status.Text = (allOk and stored and embedded == #anims) and OK or BAD, table.concat(lines, "\n")
	end

	csDownloadBtn.Activated:Connect(function() downloadCutscene(false, csDownloadBtn, "Herunterladen") end)
	csRepairBtn.Activated:Connect(function() downloadCutscene(true, csRepairBtn, "Mein Account") end)

	-- Animations-Ordner -------------------------------------------------------------------------
	do -- eigener Block: seine Variablen zählen danach nicht mehr gegen Luaus Grenze von 200
		-- Lässt den Server die Animation unter deinem Account neu hochladen. Gibt die neue ID oder nil, Fehler.
		local function reuploadAnim(id, name)
			local url = ("%s/api/plugin-upload-anim?q=%s&user=%d&place=%s&name=%s"):format(SERVER, id,
				game:GetService("StudioService"):GetUserId(), HttpService:UrlEncode(placeBox.Text), HttpService:UrlEncode(name))
			local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Headers = PLUGIN_HEADERS, Method = "GET" })
			if not ok then return nil, "Server nicht erreichbar oder Zeitüberschreitung" end
			local okJson, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
			if not res.Success then return nil, okJson and body.error or ("HTTP " .. res.StatusCode) end
			return okJson and body.id or nil, "Antwort unlesbar"
		end

		-- Auswahl mit allen Unterordnern als eine .rbxm, jede Animation mit ihrer KeyframeSequence.
		-- upload: vorher alles unter deiner ID hochladen und die neuen IDs einsetzen.
		local function saveAnimFolder(upload, btn, idleText)
			local out = animUi.label
			local sel = Selection:Get()
			if #sel == 0 then
				out.TextColor3, out.Text = BAD, "Erst den Ordner mit den Animationen im Explorer anklicken (z. B. Anubis)."
				return
			end
			if not btn.Active then return end
			local roots, anims = {}, {}
			for _, obj in sel do
				local ok, copy = pcall(function() return obj:Clone() end)
				if ok and copy then table.insert(roots, copy) end
			end
			for _, r in roots do
				local list = r:GetDescendants()
				table.insert(list, 1, r)
				for _, a in list do
					if a:IsA("Animation") and animId(a) then table.insert(anims, a) end
				end
			end
			if #anims == 0 then
				for _, r in roots do r:Destroy() end
				out.TextColor3, out.Text = BAD, "In der Auswahl steckt keine Animation mit ID."
				return
			end
			btn.Active = false
			local name = #sel == 1 and sel[1].Name or ("%s +%d"):format(sel[1].Name, #sel - 1)
			if upload then name ..= " (meine IDs)" end
			local ids, nameOf = {}, {}
			for _, a in anims do
				local id = animId(a)
				if not nameOf[id] then
					nameOf[id] = a.Name
					table.insert(ids, id)
				end
			end
			local errors, map, clips, uploaded = {}, {}, 0, 0
			-- 6 gleichzeitig: einzeln dauert ein ganzer Charakter (60 Animationen) über eine Minute.
			local loadedCount, running = 0, 0
			btn.Text = progress("Lade Animationen", 0, #ids)
			for _, id in ids do
				while running >= 6 do task.wait() end
				running += 1
				task.spawn(function()
					pcall(fetchClip, id) -- ein Fehler darf den Zähler nicht hängen lassen
					running -= 1
					loadedCount += 1
					btn.Text = progress("Lade Animationen", loadedCount, #ids)
				end)
			end
			while running > 0 do task.wait() end
			for _, id in ids do
				if fetchClip(id) then clips += 1 else table.insert(errors, ("%s (%s): nicht ladbar"):format(nameOf[id], id)) end
			end
			if upload then
				local known = plugin:GetSetting("repairedAnims") or {}
				local user = tostring(game:GetService("StudioService"):GetUserId())
				for i, id in ids do
					btn.Text = progress("Lade hoch", i - 1, #ids)
					local k = user .. ":" .. id
					if known[k] then
						map[id] = known[k]
					elseif fetchClip(id) then
						local newId, err = reuploadAnim(id, nameOf[id])
						if newId then
							map[id], known[k] = newId, newId
						else
							table.insert(errors, ("%s (%s): %s"):format(nameOf[id], id, err))
						end
					end
					if map[id] then uploaded += 1 end
				end
				plugin:SetSetting("repairedAnims", known)
			end
			local replaced = 0
			for _, a in anims do
				local id = animId(a)
				for _, c in a:GetChildren() do
					if c:IsA("AnimationClip") then c:Destroy() end
				end
				local clip = fetchClip(id)
				if clip and not upload then
					-- Herunterladen: nur die Keyframes, ohne Asset-ID, wie aus dem Animation Editor gespeichert.
					local copy = clip:Clone()
					copy.Name, copy.Parent = a.Name, a.Parent
					local index = table.find(roots, a)
					if index then roots[index] = copy end
					a:Destroy()
					replaced += 1
				else
					-- Unter meiner ID (oder nicht ladbar): Animation-Objekt bleibt, das Spiel braucht die ID.
					if clip then clip:Clone().Parent = a end
					if map[id] then a.AnimationId = "rbxassetid://" .. map[id] end
				end
			end
			local lines = { upload and ("%d Animationen (%d verschiedene), %d mit KeyframeSequence."):format(#anims, #ids, clips)
				or ("%d/%d Animationen als KeyframeSequence gespeichert (ohne Asset-ID)."):format(replaced, #anims) }
			if upload then
				table.insert(lines, ("%d/%d unter deiner ID hochgeladen, die neuen IDs stehen in der Datei."):format(uploaded, #ids))
				local found, texIds = collectTextures(roots), {}
				for tid in found do table.insert(texIds, tid) end
				if #texIds > 0 then
					local texLines = repairTextures(found, texIds, btn)
					for _, l in texLines do table.insert(lines, l) end
				end
			end
			btn.Text = "Speichere Datei …"
			task.wait()
			local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, roots)
			for _, r in roots do r:Destroy() end
			local stored = okSer and store(name, "", buffer.tostring(buf), btn)
			local savedLine = stored and ("Gespeichert: downloads/%s/%s.rbxm (in Studio: Rechtsklick > Insert from File)"):format(name, name)
				or "Datei konnte nicht gespeichert werden. Läuft start.bat?"
			table.insert(lines, savedLine)
			for i, e in errors do
				if i > 8 then
					table.insert(lines, ("… und %d weitere"):format(#errors - 8))
					break
				end
				table.insert(lines, e)
			end
			btn.Active, btn.Text = true, idleText
			out.TextColor3, out.Text = (stored and #errors == 0) and OK or BAD, table.concat(lines, "\n")
			status.TextColor3, status.Text = out.TextColor3, savedLine
		end

		-- KeyframeSequence ohne ID (z. B. aus Herunterladen) als eigene Animation hochladen. Gibt neue ID oder nil, Fehler.
		local function uploadClip(ks, user)
			local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, { ks })
			if not okSer then return nil, "ließ sich nicht als Datei speichern" end
			local url = ("%s/api/plugin-upload-anim-file?user=%d&name=%s"):format(SERVER, user, HttpService:UrlEncode(ks.Name))
			local ok, res = pcall(HttpService.RequestAsync, HttpService,
				{ Url = url, Headers = PLUGIN_HEADERS, Method = "POST", Body = (buffer.tostring(buf):gsub(".", HEX)) })
			if not ok then return nil, "Server nicht erreichbar oder Zeitüberschreitung" end
			local okJson, body = pcall(HttpService.JSONDecode, HttpService, res.Body)
			if not res.Success then return nil, okJson and body.error or ("HTTP " .. res.StatusCode) end
			return okJson and body.id or nil, "Antwort unlesbar"
		end

		-- Ordner mit losen KeyframeSequences: alle hochladen, danach steckt jede in einer Animation mit der neuen ID,
		-- gleicher Name, gleicher Ort. Gibt false, wenn in der Auswahl keine lose KeyframeSequence ist.
		local function uploadKeyframes(btn, idleText)
			local out, list = animUi.label, {}
			for _, root in Selection:Get() do
				local all = root:GetDescendants()
				table.insert(all, 1, root)
				for _, ks in all do
					if ks:IsA("KeyframeSequence") and not (ks.Parent and ks.Parent:IsA("Animation")) then table.insert(list, ks) end
				end
			end
			if #list == 0 then return false end
			if not btn.Active then return true end
			btn.Active = false
			local user = game:GetService("StudioService"):GetUserId()
			local ids, errors, done, running = {}, {}, 0, 0
			btn.Text = progress("Lade hoch", 0, #list)
			for _, ks in list do
				while running >= 3 do task.wait() end -- 3 gleichzeitig, Roblox begrenzt Uploads pro Minute
				running += 1
				task.spawn(function()
					local ok, newId, err = pcall(uploadClip, ks, user)
					if ok and newId then ids[ks] = newId else table.insert(errors, ("%s: %s"):format(ks.Name, tostring(ok and err or newId))) end
					running -= 1
					done += 1
					btn.Text = progress("Lade hoch", done, #list)
				end)
			end
			while running > 0 do task.wait() end
			local rec = ChangeHistoryService:TryBeginRecording("Animationen unter meiner ID")
			local count = 0
			for _, ks in list do
				if ids[ks] and ks.Parent then
					local anim = Instance.new("Animation")
					anim.Name, anim.AnimationId = ks.Name, "rbxassetid://" .. ids[ks]
					anim.Parent = ks.Parent
					ks.Parent = anim -- bleibt bearbeitbar, steckt jetzt in der Animation
					count += 1
				end
			end
			if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
			local lines = { ("%d/%d Animationen unter deiner ID hochgeladen. Jede steckt jetzt in einer Animation mit der neuen ID, am selben Ort (Strg+Z macht es rückgängig)."):format(count, #list) }
			for i, e in errors do
				if i > 8 then
					table.insert(lines, ("… und %d weitere"):format(#errors - 8))
					break
				end
				table.insert(lines, e)
			end
			btn.Active, btn.Text = true, idleText
			out.TextColor3, out.Text = #errors == 0 and OK or BAD, table.concat(lines, "\n")
			status.TextColor3, status.Text = out.TextColor3, lines[1]
			return true
		end

		animUi.save.Activated:Connect(function() saveAnimFolder(false, animUi.save, "Herunterladen") end)
		animUi.upload.Activated:Connect(function()
			-- Lose Keyframes (ohne ID) direkt hochladen, sonst Animationen mit fremder ID neu hochladen und als Datei sichern.
			if not uploadKeyframes(animUi.upload, "Unter meiner ID") then saveAnimFolder(true, animUi.upload, "Unter meiner ID") end
		end)
	end

	-- Abspielen -------------------------------------------------------------------------------
	-- Der Cutscene-Code läuft nicht: Er braucht den CutsceneController und die Daten des Spiels. Stattdessen macht
	-- das Plugin, was dieser Controller macht: Rigs kopieren, Animationen abspielen, Kamera an CamPart hängen, FOV.
	local CS_AUTOPLAY = "cutsceneAutoplay" -- Plugin-Setting: Namenspfad der Cutscene, die jeder Play-Test abspielt
	local CS_COPY = "AssetDownloaderCutscene" -- Kopie in ReplicatedStorage, wenn nur der Server die Cutscene sieht
	local PLAYER_KEYS = { player = true, players = true, characterrig = true, character = true, fakeplayer = true,
		templater6 = true, clone = true, localplayer = true }
	-- Kamera heißt cam, camera, camerarig …, aber nicht "Camper2" (BoomFamily).
	local function isCamKey(k) return k == "cam" or k:match("^camera") ~= nil end
	local playing = nil -- { model, tracks, stop = Funktion, restore = Funktion }

	local function key(s)
		local k = s:lower():gsub("[%s_%-%.]", "")
		k = k:gsub("animation$", ""):gsub("anim$", "")
		return k
	end

	local function holderOf(m)
		return m:FindFirstChildWhichIsA("Humanoid") or m:FindFirstChildWhichIsA("AnimationController")
	end

	local function rootOf(m)
		-- HumanoidRootPart vor PrimaryPart: Bei R6 ist PrimaryPart oft der Kopf.
		return m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("RootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	end

	-- Teil, dem die Kamera folgt, wie im Spiel: CamPart, sonst Camera, sonst das letzte Teil mit "cam" (Beatdown: camera3).
	local function camPartOf(rig)
		local named, other = nil, {}
		for _, p in rig:GetDescendants() do
			if p:IsA("BasePart") then
				local n = p.Name:lower()
				if n == "campart" then return p end
				if n == "camera" then
					named = named or p
				elseif n:find("cam") and not n:find("root") then
					table.insert(other, p)
				end
			end
		end
		table.sort(other, function(a, b) return a.Name < b.Name end)
		return named or other[#other]
	end

	-- Auswahl zur Cutscene: Download-Ordner (Code + Objekte) oder das Cutscene-Script, auch über ein Unter-Modul.
	local function cutsceneSource(sel)
		local code = sel:FindFirstChild("Code")
		if code and sel:FindFirstChild("Objekte") then
			local best, most = nil, -1
			for _, c in code:GetChildren() do
				local n = 0
				for _, d in c:GetDescendants() do
					if d:IsA("Animation") then n += 1 end
				end
				if n > most then best, most = c, n end
			end
			sel = best or sel
		end
		while not sel:FindFirstChildWhichIsA("Animation", true) and sel.Parent and sel.Parent:IsA("LuaSourceContainer") do
			sel = sel.Parent
		end
		return sel
	end

	local function clipOf(a)
		local clip = a:FindFirstChildWhichIsA("AnimationClip")
		if clip then return clip end
		return animId(a) and fetchClip(animId(a)) or nil
	end

	-- Eingebettet oder vom Server: über RegisterAnimationClip, sonst die Original-ID (geht nur in der eigenen Place).
	local function trackFor(holder, a)
		local animator = holder:FindFirstChildOfClass("Animator") or Instance.new("Animator", holder)
		local anim = Instance.new("Animation")
		anim.AnimationId = a.AnimationId
		local clip = clipOf(a)
		if clip then
			local ok, active = pcall(AnimationClipProvider.RegisterAnimationClip, AnimationClipProvider, clip)
			if ok then anim.AnimationId = active end
		end
		local ok, t = pcall(animator.LoadAnimation, animator, anim)
		if not ok then return nil end
		t.Priority, t.Looped = Enum.AnimationPriority.Action4, false
		return t, animator
	end

	-- FOV pro Frame (60 pro Sekunde) aus dem FOVData-Modul, so wie der CutsceneController es liest.
	local function fovFrames(src)
		for _, m in src:GetDescendants() do
			if m:IsA("ModuleScript") and m.Name:lower():find("fov") then
				local ok, frames = pcall(function() return require(m).Data.CurrentCamera.Properties.FieldOfView.Frames end)
				if ok and type(frames) == "table" then return frames end
			end
		end
		return nil
	end

	-- Kopie der Cutscene: alles außer Scripts und GUIs. Aus "Loaded" (vorbereitete Rigs) nur, was oben fehlt.
	local function buildCutscene(src)
		local model = Instance.new("Model")
		model.Name, model.Archivable = "Cutscene-Vorschau", false
		local loadedFolder, top = src:FindFirstChild("Loaded"), {} -- top: Name -> wie oft oben schon
		local function copyIn(obj)
			local ok, copy = pcall(function() return obj:Clone() end)
			if ok and copy then copy.Parent = model end
		end
		for _, c in src:GetChildren() do
			if c ~= loadedFolder and not c:IsA("LuaSourceContainer") and not c:IsA("LayerCollector") then
				top[c.Name] = (top[c.Name] or 0) + 1
				copyIn(c)
			end
		end
		-- Loaded hat oft mehrere Kopien (Stage2Start: 4 Pferde, oben nur 1): nur die, die oben fehlen.
		for _, c in loadedFolder and loadedFolder:GetChildren() or {} do
			if c:IsA("Model") and holderOf(c) then
				if (top[c.Name] or 0) > 0 then top[c.Name] -= 1 else copyIn(c) end
			end
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
			elseif d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		return model
	end

	-- Welche Animation auf welches Rig: "Camera" aufs Kamera-Rig, sonst gleicher Name (Horse, Figure, Boom2 …),
	-- bei Nummern der Ordnername (Animations.Horses.1). Spieler-Animationen ohne Rig kommen in players.
	local function assign(model, anims)
		local rigs, used, pairs_, players = {}, {}, {}, {}
		for _, d in model:GetDescendants() do
			if d:IsA("Model") and holderOf(d) then table.insert(rigs, d) end
		end
		-- Kamera-Rig: Rig namens Cam/CameraRig …, sonst ein Rig, in dem CamPart steckt (MatchStart: Main.Cam.CamPart).
		local camRig = nil
		for _, r in rigs do
			if isCamKey(key(r.Name)) and camPartOf(r) then
				camRig = r
				break
			end
		end
		if not camRig then
			for _, r in rigs do
				local p = camPartOf(r)
				if p and (p.Name:lower() == "campart" or p.Name:lower() == "camera") then
					camRig = r
					break
				end
			end
		end
		if camRig and isCamKey(key(camRig.Name)) then used[camRig] = true end
		local names = {}
		for _, a in anims do names[key(a.Name)] = true end
		local function find(cands, exact)
			for _, c in cands do
				for _, r in rigs do
					local k = key(r.Name)
					if not used[r] and c ~= "" and (k == c or (not exact and #c >= 3 and k:find(c, 1, true))) then return r end
				end
			end
			return nil
		end
		local function playerRig()
			for _, r in rigs do
				if not used[r] and PLAYER_KEYS[key(r.Name)] then return r end
			end
			return nil
		end
		local leftover = {}
		for _, a in anims do
			local k = key(a.Name)
			local base = k:gsub("idle$", "")
			local folder = a.Parent and a.Parent:IsA("Folder") and key(a.Parent.Name) or ""
			if folder == "animations" or folder == "anims" then folder = "" end
			local single = folder:gsub("s$", "")
			if base ~= k and names[base] then
				continue -- Idle-Variante, wenn es die eigentliche Animation auch gibt
			elseif isCamKey(base) then
				if camRig and not pairs_[camRig] then
					used[camRig], pairs_[camRig] = true, a
				end
			else
				-- Ordner zuerst, damit Horse.Boom3 aufs Pferd Horse_Boom3 geht und nicht auf den Reiter Boom3.
				local cands = tonumber(k) and { folder, single } or { folder .. k, single .. k, k, base }
				local isPlayer = PLAYER_KEYS[base] or PLAYER_KEYS[folder] or PLAYER_KEYS[single]
				local rig = find(cands, true) or find(cands, false) or (isPlayer and playerRig())
				if rig then
					used[rig], pairs_[rig] = true, a
				elseif isPlayer then
					table.insert(players, a)
				else
					table.insert(leftover, a)
				end
			end
		end
		-- Übrige Animationen auf übrige Rigs, wenn die Zahl aufgeht (Stage1Finish: Horse auf Victory).
		local freeRigs = {}
		for _, r in rigs do
			if not used[r] and not PLAYER_KEYS[key(r.Name)] then table.insert(freeRigs, r) end
		end
		if #leftover > 0 and #leftover == #freeRigs then
			for i, a in leftover do pairs_[freeRigs[i]] = a end
			leftover = {}
		end
		-- Am Spieler hängt die Cutscene, wenn es kein Spieler-Rig gibt und sonst nur die Kamera (Barrage, GyroUlt)
		-- oder Spieler-Animationen auf einen Spieler warten (CloneAnim).
		local hasPlayerRig, others = false, 0
		for _, r in rigs do
			if PLAYER_KEYS[key(r.Name)] then hasPlayerRig = true end
			if r ~= camRig then others += 1 end
		end
		return camRig, pairs_, players, leftover, not hasPlayerRig and (#players > 0 or others == 0)
	end

	local function stopCutscene(text)
		local p = playing
		if not p then return end
		playing = nil
		p.stop()
		for _, t in p.tracks do pcall(function() t:Stop(0) end) end
		p.model:Destroy()
		p.restore()
		csPlay.play.Text = "Abspielen"
		if text then csPlay.label.TextColor3, csPlay.label.Text = MUTED, text end
	end

	-- Spielt die Cutscene einmal ab. character: im Play-Test die eigene Figur, im Edit-Modus nil (dann ein Dummy).
	-- Gibt (ok, Text für die Anzeige).
	local function playCutscene(src, character)
		stopCutscene()
		local anims = {}
		for _, a in src:GetDescendants() do
			if a:IsA("Animation") then table.insert(anims, a) end
		end
		if #anims == 0 then
			return false, ("In %s steckt keine Animation. Das Cutscene-Script oder den Download-Ordner anklicken."):format(src.Name)
		end
		local editing = not RunService:IsRunning()
		local model = buildCutscene(src)
		local camRig, pairs_, players, leftover, attach = assign(model, anims)
		local camPart = camRig and camPartOf(camRig)
		local camRoot = camRig and rootOf(camRig)

		-- Ohne Spieler-Rig hängt die Cutscene am Spieler (im Spiel per Motor6D CONNECT): Kamera-Rig an die Figur.
		local subject, hrp, hrpAnchored = nil, nil, nil
		if attach and camRoot then
			if character and character:FindFirstChild("HumanoidRootPart") then
				hrp = character.HumanoidRootPart
				model:PivotTo(hrp.CFrame * camRoot.CFrame:Inverse() * model:GetPivot())
				hrpAnchored, hrp.Anchored = hrp.Anchored, true
				subject = character
			else
				local dummy = makeRig(players[1] and clipOf(players[1]) or nil)
				if dummy then
					dummy.Name = "Spieler (Dummy)"
					dummy:PivotTo(camRoot.CFrame)
					dummy.Parent = model
					subject = dummy
				end
			end
		end

		model.Parent = workspace
		local tracks, animators, missing = {}, {}, {}
		local function start(rig, a)
			local holder = holderOf(rig) or rig:FindFirstChildWhichIsA("Humanoid", true)
			local root = rootOf(rig)
			if root and rig ~= character then
				fixRigRoot(rig, root) -- ein verankerter Kopf oder Arm bliebe sonst stehen
				root.Anchored = true
			end
			local t, animator = nil, nil
			if holder then t, animator = trackFor(holder, a) end
			if t then
				table.insert(tracks, t)
				animators[animator] = true
			else
				table.insert(missing, a.Name)
			end
			return t
		end
		local camTrack = nil
		for rig, a in pairs_ do
			local t = start(rig, a)
			if rig == camRig then camTrack = t end
		end
		if subject and players[1] then start(subject, players[1]) end
		if #tracks == 0 then
			model:Destroy()
			if hrp then hrp.Anchored = hrpAnchored end
			return false, "Keine Animation ließ sich laden. Läuft start.bat? Bei gesperrten IDs den Spiel-Link im Tab Laden eintragen."
		end
		for _, t in tracks do t:Play(0) end
		-- Wie im Spiel: warten, bis die Länge bekannt ist (höchstens 3 s).
		local function length()
			if camTrack then return camTrack.Length end
			local l = 0
			for _, t in tracks do l = math.max(l, t.Length) end
			return l
		end
		local waited = os.clock()
		while length() <= 0 and os.clock() - waited < 3 do
			if editing then
				for animator in animators do animator:StepAnimations(0) end
			end
			task.wait()
		end
		local duration = length()

		local cam = workspace.CurrentCamera
		local saved = { cam.CameraType, cam.CFrame, cam.Focus, cam.FieldOfView, cam.CameraSubject }
		local frames = fovFrames(src)
		local began = os.clock()
		local done = false
		local function step(dt)
			if editing then
				for animator in animators do animator:StepAnimations(dt) end
			end
			local elapsed = os.clock() - began
			if camPart then
				cam.CameraType = Enum.CameraType.Scriptable
				cam.CFrame, cam.Focus = camPart.CFrame, camPart.CFrame
			end
			local fov = frames and frames[math.max(1, math.ceil(elapsed * 60))]
			if fov then cam.FieldOfView = fov end
			if elapsed > duration + 0.1 and not done then
				done = true
				task.defer(stopCutscene, ("%s fertig abgespielt."):format(src.Name))
			end
		end
		local stop
		if editing then
			local conn = RunService.Heartbeat:Connect(step)
			stop = function() conn:Disconnect() end
		else
			-- Als Letztes vor dem Zeichnen, sonst setzt das Kamera-Script des Spiels die Kamera zurück.
			RunService:BindToRenderStep(CS_COPY, Enum.RenderPriority.Last.Value, step)
			stop = function() RunService:UnbindFromRenderStep(CS_COPY) end
		end
		playing = {
			model = model, tracks = tracks, stop = stop,
			restore = function()
				cam.FieldOfView = saved[4]
				if editing then
					-- Scriptable sperrt im Edit-Modus Drehen und Zoomen, deshalb nie Scriptable zurücksetzen.
					cam.CameraType = saved[1] == Enum.CameraType.Scriptable and Enum.CameraType.Fixed or saved[1]
					cam.CFrame, cam.Focus = saved[2], saved[3]
				else
					cam.CameraType, cam.CameraSubject = Enum.CameraType.Custom, saved[5]
				end
				if hrp then hrp.Anchored = hrpAnchored end
			end,
		}
		csPlay.play.Text = "Stopp"

		local info = { ("%s: %d Animationen, %.1f s"):format(src.Name, #tracks, duration) }
		table.insert(info, camPart and ("Kamera folgt %s"):format(camPart:GetFullName():sub(#model:GetFullName() + 2))
			or "Kein Kamera-Rig gefunden, die Kamera bleibt stehen.")
		if subject then table.insert(info, character and "Spieler-Teil läuft auf deiner Figur." or "Spieler-Teil läuft auf einem Dummy.") end
		if #missing > 0 then table.insert(info, "Nicht ladbar: " .. table.concat(missing, ", ")) end
		local skipped = {}
		for _, a in leftover do table.insert(skipped, a.Name) end
		for i = 2, #players do table.insert(skipped, players[i].Name) end
		if #skipped > 0 then table.insert(info, "Ohne passendes Rig übersprungen: " .. table.concat(skipped, ", ")) end
		return true, table.concat(info, "\n")
	end

	csPlay.play.Activated:Connect(function()
		if playing then
			stopCutscene("Gestoppt.")
			return
		end
		local sel = Selection:Get()[1]
		if not sel then
			csPlay.label.TextColor3, csPlay.label.Text = BAD, "Erst die Cutscene im Explorer anklicken: das Cutscene-Script oder den eingefügten Download-Ordner."
			return
		end
		csPlay.play.Text = "Lade …"
		local character = RunService:IsRunning() and Players.LocalPlayer and Players.LocalPlayer.Character or nil
		local ok, text = playCutscene(cutsceneSource(sel), character)
		if not playing then csPlay.play.Text = "Abspielen" end
		csPlay.label.TextColor3, csPlay.label.Text = ok and OK or BAD, text
	end)
	plugin.Unloading:Connect(function() stopCutscene() end)

	-- Beim Play-Test ---------------------------------------------------------------------------
	local function showAuto()
		local names = plugin:GetSetting(CS_AUTOPLAY)
		csPlay.auto.Text = names and "Beim Play-Test: an" or "Beim Play-Test: aus"
		csPlay.auto.BackgroundColor3 = names and GREEN or GREY
		return names
	end
	showAuto()

	csPlay.auto.Activated:Connect(function()
		if plugin:GetSetting(CS_AUTOPLAY) then
			plugin:SetSetting(CS_AUTOPLAY, nil)
			showAuto()
			csPlay.label.TextColor3, csPlay.label.Text = MUTED, "Play-Test spielt keine Cutscene mehr ab."
			return
		end
		local sel = Selection:Get()[1]
		if not sel then
			csPlay.label.TextColor3, csPlay.label.Text = BAD, "Erst die Cutscene im Explorer anklicken."
			return
		end
		local src, names = cutsceneSource(sel), {}
		local cur = src
		while cur and cur ~= game do
			table.insert(names, 1, cur.Name)
			cur = cur.Parent
		end
		plugin:SetSetting(CS_AUTOPLAY, names)
		showAuto()
		csPlay.label.TextColor3, csPlay.label.Text = OK, ("Jeder Play-Test (F5) spielt %s einmal ab, sobald deine Figur da ist."):format(src.Name)
	end)

	-- Namenspfad wie { "ReplicatedStorage", "Effects", "Cutscenes", "Death" } zum Objekt. wait: Sekunden pro Stufe.
	local function resolve(names, wait)
		local cur = game
		for _, n in names do
			cur = if wait then cur:WaitForChild(n, wait) else cur:FindFirstChild(n)
			if not cur then return nil end
		end
		return cur
	end

	local autoNames = RunService:IsRunning() and plugin:GetSetting(CS_AUTOPLAY)
	if autoNames and RunService:IsServer() then
		-- Liegt die Cutscene z. B. in ServerStorage, sieht der Client sie nicht: Kopie nach ReplicatedStorage.
		local src = resolve(autoNames)
		local rs = game:GetService("ReplicatedStorage")
		if src and not (src:IsDescendantOf(rs) or src:IsDescendantOf(workspace)) then
			local ok, copy = pcall(function() return src:Clone() end)
			if ok and copy then copy.Name, copy.Parent = CS_COPY, rs end
		end
	elseif autoNames and RunService:IsClient() then
		task.spawn(function()
			local player = Players.LocalPlayer
			local character = player.Character or player.CharacterAdded:Wait()
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(2) -- erst die Kamera-Scripts des Spiels starten lassen
			local src = game:GetService("ReplicatedStorage"):FindFirstChild(CS_COPY) or resolve(autoNames, 10)
			if not src then
				warn(("[Asset Downloader] Cutscene für den Play-Test nicht gefunden: %s"):format(table.concat(autoNames, " > ")))
				return
			end
			local ok, text = playCutscene(cutsceneSource(src), player.Character or character)
			print("[Asset Downloader] " .. (text:gsub("\n", " · ")))
			csPlay.label.TextColor3, csPlay.label.Text = ok and OK or BAD, text
		end)
	end
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
			info.FontFace, info.TextSize, info.TextColor3, info.TextWrapped = FONT.mono, 11, MUTED, true
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

-- Tab: Upload ------------------------------------------------------------------------------
-- Fremde Animationen, Sounds und Meshes spielen in deinem Spiel nicht, weil sie einem anderen Account gehören.
-- Der Server lädt sie per Open Cloud unter deinem Account neu hoch, das Plugin tauscht die IDs überall.
do -- eigener Block am Dateiende: braucht reupload() und TEXTURE_PROPS von weiter oben
	local KINDS = { { "Animation", "Animationen" }, { "Sound", "Sounds" }, { "Mesh", "Meshes" }, { "Bild", "Bilder" } }
	-- Asset-Typ vom Server auf unsere Art. Decals zählen als Bild.
	local KIND_OF_TYPE = { Animation = "Animation", Audio = "Sound", Mesh = "Mesh", MeshPart = "Mesh", Image = "Bild", Decal = "Bild" }
	local ROBLOX_USER = 1 -- Assets von Roblox selbst darf jedes Spiel benutzen
	local BATCH = 100 -- IDs pro Anfrage an den Server, damit keine Anfrage in den Zeitlimit läuft
	local WORKERS = 3 -- gleichzeitige Uploads
	-- Eigenschaften mit einer Asset-ID: Klasse = { {Eigenschaft, Art} }
	local FIELDS = {
		Animation = { { "AnimationId", "Animation" } },
		Sound = { { "SoundId", "Sound" } },
		MeshPart = { { "MeshId", "Mesh" }, { "TextureID", "Bild" } },
		SpecialMesh = { { "MeshId", "Mesh" }, { "TextureId", "Bild" } },
		FileMesh = { { "MeshId", "Mesh" }, { "TextureId", "Bild" } },
		ImageLabel = { { "Image", "Bild" } },
		ImageButton = { { "Image", "Bild" } },
		Sky = { { "SkyboxBk", "Bild" }, { "SkyboxDn", "Bild" }, { "SkyboxFt", "Bild" }, { "SkyboxLf", "Bild" },
			{ "SkyboxRt", "Bild" }, { "SkyboxUp", "Bild" }, { "SunTextureId", "Bild" }, { "MoonTextureId", "Bild" } },
	}
	for class, prop in TEXTURE_PROPS do FIELDS[class] = FIELDS[class] or { { prop, "Bild" } } end
	local ID_IN_TEXT = "%f[%d](%d%d%d%d%d%d%d+)%f[%D]" -- 7 und mehr Stellen, kürzere Zahlen sind keine Roblox-IDs

	page("Upload", 8)
	pages.Upload.Parent.Visible = false -- showTab("Laden") lief schon, bevor es diesen Tab gab
	card("Auf meinen Account", "Fremde Animationen, Sounds und Meshes spielen in deinem Spiel nicht. Lädt sie unter deinem Account neu hoch und setzt die neuen IDs überall ein.")
	local _, placeBtn, selBtn = buttonRow("Ganze Place: alles in Workspace, ReplicatedStorage, StarterGui, den Scripts usw.\n\nNur Auswahl: nur die im Explorer markierten Objekte und alles darin.",
		"Ganze Place", ACCENT, "Nur Auswahl", GREY)
	local kindRow = add(Instance.new("Frame"))
	kindRow.Size, kindRow.BackgroundTransparency = UDim2.new(1, 0, 0, 30), 1
	local kindLayout = Instance.new("UIListLayout", kindRow)
	kindLayout.FillDirection, kindLayout.Padding, kindLayout.SortOrder = Enum.FillDirection.Horizontal, UDim.new(0, 6), Enum.SortOrder.LayoutOrder
	kindLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local wanted = {}
	for i, k in KINDS do
		local b = makeButton(k[2], ACCENT)
		b.Size, b.LayoutOrder, b.TextSize = UDim2.new(0, 10, 1, 0), i, 12
		wanted[k[1]] = true
		b.Activated:Connect(function()
			wanted[k[1]] = not wanted[k[1]]
			b.BackgroundColor3 = wanted[k[1]] and ACCENT or GREY
		end)
		b.Parent = kindRow
	end
	local _, scanBtn, uploadBtn = buttonRow("Suchen: findet jede Asset-ID in Eigenschaften (AnimationId, SoundId, MeshId, Texturen, Bilder, Himmel), im Code aller Scripts, in StringValues, Zahlen-Werten und Attributen. Fragt Roblox nach Typ und Besitzer. Übersprungen wird, was dir schon gehört oder von Roblox selbst ist.\n\nHochladen: lädt jedes fremde Asset der gewählten Arten unter deinem Account neu hoch (Open Cloud, apikey.txt) und tauscht die alte ID überall gegen die neue, auch im Code. Schon hochgeladene IDs merkt sich das Plugin und lädt sie nie doppelt hoch. Strg+Z macht den Tausch rückgängig.\n\nAb 20 Assets fragt der Knopf nach: zweimal klicken. Während des Hochladens wird er rot und heißt Abbrechen: ein Klick stoppt, was schon hochgeladen ist, wird trotzdem getauscht.\n\nGrenzen von Roblox: Sounds 10 pro Monat ohne ID-Verifizierung, 100 mit. Models lädt es nicht neu hoch.",
		"Suchen", GREY, "Hochladen", ACCENT)
	local upInfo = label("Erst Suchen drücken.")
	local upList = add(autoFrame())
	vlist(upList, 4)

	local useSelection = false
	placeBtn.Activated:Connect(function()
		useSelection = false
		placeBtn.BackgroundColor3, selBtn.BackgroundColor3 = ACCENT, GREY
	end)
	selBtn.Activated:Connect(function()
		useSelection = true
		placeBtn.BackgroundColor3, selBtn.BackgroundColor3 = GREY, ACCENT
	end)

	local function scopeInstances()
		local list = {}
		for _, r in useSelection and Selection:Get() or game:GetChildren() do
			-- Direkt unter game zählen nur Scripts und Werte, Dienste selbst haben keine IDs.
			if useSelection or r:IsA("LuaSourceContainer") or r:IsA("ValueBase") then table.insert(list, r) end
			local ok, d = pcall(function() return r.ClassName ~= "CoreGui" and r:GetDescendants() or {} end)
			if ok then table.move(d, 1, #d, #list + 1, list) end
		end
		return list
	end

	local function idOf(value)
		local s = tostring(value)
		return s:match("rbxassetid://(%d+)") or s:match("[?&][iI][dD]=(%d+)") or s:match("^%s*(%d+)%s*$")
	end

	-- Jede Stelle, an der eine ID steht: { obj, prop | text | attr, number }
	local function findUses()
		local uses, known = {}, {}
		local function use(id, entry, kind)
			if #id < 5 or #id > 15 then return end
			uses[id] = uses[id] or {}
			table.insert(uses[id], entry)
			if kind then known[id] = known[id] or kind end
		end
		for i, obj in scopeInstances() do
			if i % 2000 == 0 then task.wait() end
			pcall(function()
				for _, f in FIELDS[obj.ClassName] or {} do
					local id = idOf(obj[f[1]])
					if id then use(id, { obj = obj, prop = f[1] }, f[2]) end
				end
				if obj:IsA("CharacterMesh") and obj.MeshId > 0 then
					use(("%d"):format(obj.MeshId), { obj = obj, prop = "MeshId", number = true }, "Mesh")
				end
				local text = obj:IsA("LuaSourceContainer") and obj.Source or (obj:IsA("StringValue") and obj.Value) or nil
				if text then
					local seen = {}
					for id in text:gmatch(ID_IN_TEXT) do
						if not seen[id] then
							seen[id] = true
							use(id, { obj = obj, text = true })
						end
					end
				end
				if (obj:IsA("IntValue") or obj:IsA("NumberValue")) and obj.Value >= 1e6 and obj.Value % 1 == 0 then
					use(("%d"):format(obj.Value), { obj = obj, prop = "Value", number = true })
				end
				for key, v in obj:GetAttributes() do
					if type(v) == "string" then
						for id in v:gmatch(ID_IN_TEXT) do use(id, { obj = obj, attr = key }) end
					elseif type(v) == "number" and v >= 1e6 and v % 1 == 0 then
						use(("%d"):format(v), { obj = obj, attr = key, number = true })
					end
				end
			end)
		end
		return uses, known
	end

	-- Typ und Besitzer jeder ID vom Server, in Paketen. Gibt { [id] = {name, type, creator} } oder nil, Fehler.
	local function details(ids)
		local out = {}
		for i = 1, #ids, BATCH do
			upInfo.Text = ("Frage Roblox nach %d/%d IDs …"):format(math.min(i + BATCH - 1, #ids), #ids)
			local body = table.concat(ids, ",", i, math.min(i + BATCH - 1, #ids))
			local ok, res = pcall(HttpService.RequestAsync, HttpService,
				{ Url = SERVER .. "/api/plugin-bulk", Headers = PLUGIN_HEADERS, Method = "POST", Body = body })
			if not ok or not res.Success then return nil, "Server nicht erreichbar. start.bat starten." end
			for _, item in HttpService:JSONDecode(res.Body) do out[item.id] = item end
		end
		return out
	end

	local scan = nil -- { uses, items = { [id] = {kind, name, skip} } }

	local function showScan()
		for _, old in upList:GetChildren() do
			if old:IsA("GuiObject") then old:Destroy() end
		end
		local map = plugin:GetSetting("repaired") or {}
		local count, skipped, uploaded = {}, 0, 0
		local rows = {}
		for id, item in scan.items do
			if item.skip then
				skipped += 1
			else
				count[item.kind] = (count[item.kind] or 0) + 1
				if map[id] then uploaded += 1 end
				table.insert(rows, { id = id, item = item })
			end
		end
		local parts = {}
		for _, k in KINDS do table.insert(parts, ("%s %d"):format(k[2], count[k[1]] or 0)) end
		upInfo.TextColor3 = TEXT
		upInfo.Text = ("Fremd: %s.\n%d schon hochgeladen, %d übersprungen (deine oder von Roblox)."):format(table.concat(parts, ", "), uploaded, skipped)
		if (count.Sound or 0) > 10 then
			upInfo.Text ..= "\nAchtung: Roblox erlaubt ohne ID-Verifizierung nur 10 Sounds im Monat."
		end
		table.sort(rows, function(a, b) return a.item.kind < b.item.kind end)
		for i, r in rows do
			if i > 60 then break end -- shortcut: Liste zeigt 60 Zeilen, hochgeladen wird trotzdem alles
			local b = listButton(("%s  ·  %s%s"):format(r.item.kind, r.item.name, map[r.id] and "  ·  schon hochgeladen" or ""), upList)
			b.LayoutOrder = i
			local obj = scan.uses[r.id][1].obj
			b.Activated:Connect(function() Selection:Set({ obj }) end)
		end
	end

	scanBtn.Activated:Connect(function()
		if not scanBtn.Active then return end
		scanBtn.Active, scanBtn.Text = false, "Suche …"
		local uses, known = findUses()
		local ids = {}
		for id in uses do table.insert(ids, id) end
		local info, err = details(ids)
		scanBtn.Active, scanBtn.Text = true, "Suchen"
		if not info then
			upInfo.TextColor3, upInfo.Text = BAD, err
			return
		end
		local me = game:GetService("StudioService"):GetUserId()
		local items = {}
		for id in uses do
			local d = info[id] or {}
			-- Zahlen im Code ohne bekannten Asset-Typ sind keine Assets (Place-IDs, Zeiten, Preise).
			local kind = KIND_OF_TYPE[d.type or ""] or (d.type == "" and known[id]) or nil
			if kind then
				items[id] = { kind = kind, name = d.name or id, skip = d.creator == me or d.creator == ROBLOX_USER }
			end
		end
		scan = { uses = uses, items = items }
		showScan()
	end)

	-- Setzt die neue ID an jeder Stelle ein. Gibt (Stellen, Fehlerzeilen).
	local function swapIds(map)
		local done, fails, scripts = 0, {}, {}
		local function inText(text, old, new) return (text:gsub("%f[%d]" .. old .. "%f[%D]", new)) end
		for id, item in scan.items do
			local new = map[id]
			if new and wanted[item.kind] and not item.skip then
				for _, u in scan.uses[id] do
					local obj = u.obj
					local ok, err = pcall(function()
						if u.text and obj:IsA("LuaSourceContainer") then
							scripts[obj] = scripts[obj] or {} -- Code einmal pro Script schreiben, nicht pro ID
							scripts[obj][id] = new
						elseif u.text then
							obj.Value = inText(obj.Value, id, new)
						elseif u.attr then
							obj:SetAttribute(u.attr, u.number and tonumber(new) or inText(obj:GetAttribute(u.attr), id, new))
						elseif u.number then
							obj[u.prop] = tonumber(new)
						elseif obj:IsA("MeshPart") and u.prop == "MeshId" then
							-- MeshId ist für Plugins schreibgeschützt: neues Mesh laden und per ApplyMesh übernehmen.
							local fresh = AssetService:CreateMeshPartAsync(Content.fromAssetId(tonumber(new)))
							obj:ApplyMesh(fresh)
							fresh:Destroy()
						else
							obj[u.prop] = "rbxassetid://" .. new
						end
					end)
					if ok then done += 1 elseif #fails < 8 then table.insert(fails, ("%s: %s"):format(obj.Name, tostring(err))) end
				end
			end
		end
		for s, swaps in scripts do
			local ok, err = pcall(function()
				game:GetService("ScriptEditorService"):UpdateSourceAsync(s, function(src)
					for old, new in swaps do src = inText(src, old, new) end
					return src
				end)
			end)
			if ok then done += 1 elseif #fails < 8 then table.insert(fails, ("%s: %s"):format(s.Name, tostring(err))) end
		end
		return done, fails
	end

	local uploading, cancelled, confirmUntil = false, false, 0
	uploadBtn.Activated:Connect(function()
		if uploading then
			-- Derselbe Knopf bricht ab: laufende Uploads werden fertig, neue starten nicht mehr.
			cancelled = true
			uploadBtn.Text = "Breche ab …"
			return
		end
		if not scan then
			upInfo.TextColor3, upInfo.Text = BAD, "Erst Suchen drücken."
			return
		end
		local map = plugin:GetSetting("repaired") or {}
		local todo, errors = {}, {}
		for id, item in scan.items do
			if wanted[item.kind] and not item.skip and not map[id] then table.insert(todo, id) end
		end
		-- Ab 20 Assets erst nach zweitem Klick, damit nicht aus Versehen Tausende hochgehen.
		if #todo >= 20 and os.clock() > confirmUntil then
			confirmUntil = os.clock() + 5
			uploadBtn.Text = ("%d hochladen? Nochmal klicken"):format(#todo)
			task.delay(5, function()
				if not uploading then uploadBtn.Text = "Hochladen" end
			end)
			return
		end
		confirmUntil, uploading, cancelled = 0, true, false
		uploadBtn.BackgroundColor3, uploadBtn.Text = BAD, ("Abbrechen  ·  0/%d"):format(#todo)
		local nextIndex, finished, running = 0, 0, WORKERS
		for _ = 1, WORKERS do
			task.spawn(function()
				while not cancelled and nextIndex < #todo do
					nextIndex += 1
					local id = todo[nextIndex]
					local newId, err = reupload(id)
					if newId then map[id] = tostring(newId) else table.insert(errors, ("%s %s: %s"):format(scan.items[id].kind, scan.items[id].name, err)) end
					finished += 1
					-- Zwischendurch merken: auch nach Abbruch oder Studio-Absturz nie doppelt hochladen.
					if finished % 10 == 0 then plugin:SetSetting("repaired", map) end
					if not cancelled then uploadBtn.Text = ("Abbrechen  ·  %d/%d"):format(finished, #todo) end
				end
				running -= 1
			end)
		end
		while running > 0 do task.wait(0.2) end
		plugin:SetSetting("repaired", map)
		uploadBtn.Text = "Tausche IDs …"
		local rec = ChangeHistoryService:TryBeginRecording("Auf meinen Account: IDs tauschen")
		local done, fails = swapIds(map)
		if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
		uploading = false
		uploadBtn.BackgroundColor3, uploadBtn.Text = ACCENT, "Hochladen"
		local lines = { ("%s%d von %d hochgeladen, %d Stellen getauscht."):format(cancelled and "Abgebrochen. " or "",
			finished - #errors, #todo, done) }
		for i, e in errors do
			if i > 6 then table.insert(lines, ("… und %d weitere Fehler."):format(#errors - 6)) break end
			table.insert(lines, e)
		end
		for _, f in fails do table.insert(lines, "Tausch: " .. f) end
		showScan()
		upInfo.TextColor3 = (#errors == 0 and #fails == 0) and OK or BAD
		upInfo.Text = table.concat(lines, "\n") .. "\n" .. upInfo.Text
	end)
end
