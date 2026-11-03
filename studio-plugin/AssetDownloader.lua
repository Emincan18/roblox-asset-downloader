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
local function showTab(name)
	for n, page in pages do
		page.Visible = n == name
		tabs[n].BackgroundColor3 = n == name and ACCENT or CARD
		tabs[n].TextColor3 = n == name and Color3.new(1, 1, 1) or MUTED
	end
	root.CanvasPosition = Vector2.zero
end

local function page(name, index)
	local t = makeButton(name, CARD)
	t.Size, t.LayoutOrder, t.TextSize = UDim2.new(0.25, -3, 1, 0), index, 13
	t.Parent = tabBar
	t.Activated:Connect(function() showTab(name) end)
	tabs[name] = t
	local p = autoFrame()
	vlist(p, 10)
	container = root
	add(p)
	pages[name] = p
	container = p
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

card("Vorschau")
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
card("Viele Assets auf einmal", "Eine ID oder ein Link pro Zeile.")
local bulkBox = input("507766388\n180435571\n...")
bulkBox.MultiLine, bulkBox.TextWrapped = true, true
bulkBox.TextYAlignment = Enum.TextYAlignment.Top
bulkBox.Size = UDim2.new(1, 0, 0, 110)
bulkBox:FindFirstChildOfClass("UIPadding").PaddingTop = UDim.new(0, 8)
local bulkBtn = button("Liste laden", ACCENT,
	"Zeigt zu jeder ID Name und Typ. Das geht schnell, weil noch nichts heruntergeladen wird.\n\nKlick auf einen Eintrag öffnet die Vorschau im Tab Laden. + legt ihn in den Korb.")
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
local cartUploadBtn = button("Bilder im Korb hochladen", PURPLE,
	"Lädt alle Bilder im Korb unter deinem Namen hoch. Die neuen IDs erscheinen oben zum Kopieren. Braucht apikey.txt.")
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
	"Löst alle ParticleEmitter der Auswahl einmal aus (mit EmitCount und EmitDelay, falls gesetzt). Hit-VFX sieht man sonst nicht, weil sie nur per Script feuern.\n\nLose Attachments ohne Part kommen dafür an ein unsichtbares Teil vor dir. Strg+Z macht das rückgängig.")
local vfxLabel = label("")

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
	local r6 = clip:FindFirstChild("Torso", true) ~= nil
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
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Method = "GET" })
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

-- Auswahl im Workspace abspielen. Attachments und Emitter ohne Part zeigen nichts,
-- deshalb kommen sie an ein unsichtbares Halter-Part vor der Kamera (Strg+Z macht das rückgängig).
local function playSelection(outLabel)
	local sel = Selection:Get()
	if #sel == 0 then
		outLabel.TextColor3, outLabel.Text = BAD, "Erst die VFX im Explorer anklicken."
		return
	end
	local rec = ChangeHistoryService:TryBeginRecording("VFX abspielen")
	local holder, moved = nil, 0
	for _, root in sel do
		local list = root:GetDescendants()
		table.insert(list, 1, root)
		for _, obj in list do
			local loose = (obj:IsA("Attachment") and not obj.Parent:IsA("BasePart"))
				or ((obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam"))
					and not (obj.Parent:IsA("BasePart") or obj.Parent:IsA("Attachment")))
			if loose then
				if not holder then
					local camCf = workspace.CurrentCamera.CFrame
					holder = Instance.new("Part")
					holder.Name, holder.Anchored, holder.CanCollide = root.Name .. " Halter", true, false
					holder.Transparency, holder.Size = 1, Vector3.one
					holder.CFrame = CFrame.new(camCf.Position + camCf.LookVector * 12)
					holder.Parent = workspace
				end
				obj.Parent = holder
				moved += 1
			end
		end
	end
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	-- Verschobene Teile nur über den Halter auslösen, sonst feuern sie doppelt.
	local roots = holder and { holder } or {}
	for _, root in sel do
		if not (holder and root:IsDescendantOf(holder)) then table.insert(roots, root) end
	end
	local n = emitIn(roots)
	outLabel.TextColor3 = n > 0 and OK or BAD
	outLabel.Text = n == 0 and "In der Auswahl sind keine ParticleEmitter."
		or ("%d Emitter ausgelöst.%s"):format(n, moved > 0 and (" %d lose Teile an \"%s\" gehängt, damit Partikel sichtbar sind."):format(moved, holder.Name) or "")
end

local cart, bulkItems = {}, {}

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

-- Lädt die IDs neu von Roblox und speichert sie über den Server in downloads/ (oder downloads/<folder>).
local function save(ids, folder, btn, idleText)
	btn.Active, btn.Text = false, "Speichere …"
	local url = ("%s/api/plugin-save?place=%s&folder=%s"):format(SERVER, HttpService:UrlEncode(placeBox.Text), HttpService:UrlEncode(folder))
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Method = "POST", Body = table.concat(ids, "\n") })
	btn.Active, btn.Text = true, idleText
	if not ok or not res.Success then
		status.TextColor3, status.Text = BAD, "Speichern fehlgeschlagen. Läuft start.bat?"
		return nil
	end
	local r = HttpService:JSONDecode(res.Body)
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
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Method = "GET" })
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
		btn.Text = ("Lade hoch %d/%d …"):format(i, #ids)
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
local function backup(roots, name, repair, btn, idleText, outLabel)
	local found, ids = collectTextures(roots), {}
	for id in found do table.insert(ids, id) end
	btn.Active = false
	local lines, allOk, map = {}, true, {}
	if repair and #ids > 0 then lines, allOk, map = repairTextures(found, ids, btn) end

	btn.Text = "Speichere …"
	local okSer, buf = pcall(SerializationService.SerializeInstancesAsync, SerializationService, roots)
	local stored = false
	if okSer then
		local hex = buffer.tostring(buf):gsub(".", function(c) return string.format("%02x", c:byte()) end)
		local url = ("%s/api/plugin-store?folder=%s"):format(SERVER, HttpService:UrlEncode(name))
		local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Method = "POST", Body = hex })
		stored = ok and res.Success
	end
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
	local ok, res = pcall(HttpService.RequestAsync, HttpService, { Url = url, Method = "POST", Body = text })
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
			showTab("Laden")
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
local function idsInSelection()
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
	for _, sel in Selection:Get() do
		visit(sel)
		for _, d in sel:GetDescendants() do visit(d) end
	end
	return ids
end

pickBtn.Activated:Connect(function()
	local ids = idsInSelection()
	if #ids == 0 then
		status.TextColor3, status.Text = BAD, "In der Auswahl steckt keine Asset-ID. Klick z. B. eine Animation oder einen ParticleEmitter an."
	elseif #ids == 1 then
		idBox.Text = ids[1]
		load(ids[1])
	else
		bulkBox.Text = table.concat(ids, "\n")
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
bulkAllBtn.Activated:Connect(function()
	for _, item in bulkItems do addToCart(item.id, item.name, item.type) end
end)
-- Bilder unter dem eigenen Account hochladen. Liste alt -> neu landet im Kopierfeld.
local function uploadImages(items, btn, idleText)
	local map = plugin:GetSetting("repaired") or {}
	local lines, okCount = {}, 0
	btn.Active = false
	for i, item in items do
		btn.Text = ("Lade hoch %d/%d …"):format(i, #items)
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
cartUploadBtn.Activated:Connect(function()
	if not cartUploadBtn.Active then return end
	local images = {}
	for _, item in cart do
		if item.kind == "Image" then table.insert(images, item) end
	end
	uploadImages(images, cartUploadBtn, "Bilder im Korb hochladen")
end)
cartBtn.Activated:Connect(function()
	if #cart == 0 or not cartBtn.Active then return end
	local ids = {}
	for _, item in cart do table.insert(ids, item.id) end
	local folder = folderBox.Text:match("^%s*(.-)%s*$")
	local r = save(ids, folder ~= "" and folder or "Korb " .. os.date("%Y-%m-%d %H-%M"), cartBtn, "Korb herunterladen")
	if r and #r.errors == 0 then
		table.clear(cart)
		refreshCart()
	end
end)
insertBtn.Activated:Connect(insert)
playBtn.Activated:Connect(function()
	if loaded and loaded.vfx and not loaded.clip then emitVfx() else playToggle() end
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function() if not widget.Enabled then stopPreview() end end)
plugin.Unloading:Connect(stopPreview)
