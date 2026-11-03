--[[
	Roblox Asset Downloader als Studio-Plugin.
	Redet mit dem lokalen Server (start.bat), der die Assets lädt und in downloads/ speichert.
	Zeigt Models und Animationen in einer Vorschau und fügt sie auf Knopfdruck ins Spiel ein.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local SerializationService = game:GetService("SerializationService")
local AnimationClipProvider = game:GetService("AnimationClipProvider")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Players = game:GetService("Players")

local SERVER = "http://127.0.0.1:8765"

local BG = Color3.fromRGB(30, 30, 34)
local FIELD = Color3.fromRGB(44, 44, 50)
local TEXT = Color3.fromRGB(230, 230, 235)
local MUTED = Color3.fromRGB(150, 150, 160)
local ACCENT = Color3.fromRGB(226, 60, 60)
local BAD = Color3.fromRGB(240, 120, 110)
local OK = Color3.fromRGB(110, 210, 150)

local toolbar = plugin:CreateToolbar("Asset Downloader")
local toggle = toolbar:CreateButton("Asset Downloader", "Roblox-Assets laden und ansehen", "")
toggle.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync("AssetDownloader",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 320, 560, 260, 420))
widget.Title = "Asset Downloader"
toggle.Click:Connect(function() widget.Enabled = not widget.Enabled end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function() toggle:SetActive(widget.Enabled) end)

-- UI ---------------------------------------------------------------------------------------

local root = Instance.new("ScrollingFrame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = BG
root.BorderSizePixel = 0
root.ScrollBarThickness = 6
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
root.CanvasSize = UDim2.new()
root.Parent = widget
local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 12)
pad.Parent = root
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = root

local order = 0
local function add(inst)
	order += 1
	inst.LayoutOrder = order
	inst.Parent = root
	return inst
end

local function corner(inst)
	Instance.new("UICorner", inst).CornerRadius = UDim.new(0, 6)
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
	t.Size = UDim2.new(1, 0, 0, 32)
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
	p.PaddingLeft, p.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	return add(corner(t))
end

local function button(text, color, parent)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 34)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	corner(b)
	if parent then b.Parent = parent else add(b) end
	return b
end

label("Asset Downloader", TEXT, 18).Font = Enum.Font.GothamBold
label("Asset-ID oder Link")
local idBox = input("z. B. 507766388")
label("Spiel, aus dem es stammt (optional)")
local placeBox = input("roblox.com/games/...")
placeBox.Text = plugin:GetSetting("place") or ""
placeBox.FocusLost:Connect(function() plugin:SetSetting("place", placeBox.Text) end)
local loadBtn = button("Laden", ACCENT)
local status = label("Server muss laufen: start.bat doppelklicken.")

local view = add(corner(Instance.new("ViewportFrame")))
view.Size = UDim2.new(1, 0, 0, 240)
view.BackgroundColor3 = FIELD
view.Ambient = Color3.fromRGB(200, 200, 200)
view.LightColor = Color3.new(1, 1, 1)
local camera = Instance.new("Camera")
camera.FieldOfView = 40
camera.Parent = view
view.CurrentCamera = camera
local thumb = Instance.new("ImageLabel")
thumb.Size = UDim2.fromScale(1, 1)
thumb.BackgroundTransparency = 1
thumb.ScaleType = Enum.ScaleType.Fit
thumb.Parent = view
label("Maus ziehen dreht die Vorschau, Mausrad zoomt.")

local row = add(Instance.new("Frame"))
row.Size = UDim2.new(1, 0, 0, 34)
row.BackgroundTransparency = 1
local rowList = Instance.new("UIListLayout", row)
rowList.FillDirection = Enum.FillDirection.Horizontal
rowList.Padding = UDim.new(0, 8)
local insertBtn = button("Einfügen", Color3.fromRGB(60, 120, 200), row)
insertBtn.Size = UDim2.new(0.5, -4, 1, 0)
local playBtn = button("Abspielen", Color3.fromRGB(70, 70, 80), row)
playBtn.Size = UDim2.new(0.5, -4, 1, 0)
row.Visible = false

local savedLabel = label("")

-- Vorschau ---------------------------------------------------------------------------------

local loaded = nil -- { id, objects = {Instance}, clip = KeyframeSequence/AnimationClip? }
local world, stepConn, track, animator

local function stopPreview()
	if stepConn then stepConn:Disconnect() stepConn = nil end
	if track then track:Stop(0) track = nil end
	animator = nil
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
	thumb.Image = ""
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
		-- Audio, Bild, Mesh: Roblox-Vorschaubild statt 3D.
		thumb.Image = ("rbxthumb://type=Asset&id=%s&w=420&h=420"):format(loaded.id)
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

local function load()
	local q = idBox.Text
	if q:match("^%s*$") then return end
	loadBtn.Active, loadBtn.Text = false, "Lade …"
	status.TextColor3, status.Text = MUTED, "Lade … Hängt es? Plugins > Plugins verwalten > Asset Downloader: HTTP-Zugriff auf 127.0.0.1 erlauben."
	savedLabel.Text, row.Visible = "", false
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
	loaded = { id = id, objects = {} }
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

	local name = urlDecode(header(res, "x-filename"))
	status.TextColor3, status.Text = OK, ("%s geladen%s"):format(kind ~= "" and kind or "Asset", #loaded.objects == 0 and ext:match("^rbxm") and " (Vorschau nicht möglich)" or "")
	savedLabel.Text = "Gespeichert: " .. urlDecode(header(res, "x-saved"))
	insertBtn.Visible = #loaded.objects > 0
	playBtn.Visible = loaded.clip ~= nil
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
		copy.Name = ("Animation %s"):format(loaded.id)
		copy.Parent = target
		table.insert(placed, copy)
	else
		local focus = workspace.CurrentCamera.Focus.Position
		for _, obj in loaded.objects do
			local copy = obj:Clone()
			copy.Parent = workspace
			if copy:IsA("PVInstance") then pcall(copy.PivotTo, copy, CFrame.new(focus)) end
			table.insert(placed, copy)
		end
	end
	Selection:Set(placed)
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	status.TextColor3, status.Text = OK, "Eingefügt in " .. placed[1].Parent:GetFullName()
end

loadBtn.Activated:Connect(function() if loadBtn.Active then load() end end)
idBox.FocusLost:Connect(function(enter) if enter then load() end end)
insertBtn.Activated:Connect(insert)
playBtn.Activated:Connect(playToggle)
widget:GetPropertyChangedSignal("Enabled"):Connect(function() if not widget.Enabled then stopPreview() end end)
plugin.Unloading:Connect(stopPreview)
