--!strict
-- UIUtil.lua
-- Helpers for building UI programmatically with consistent scaling. Every
-- ScreenGui this game creates uses an identical set of UIScale + AspectRatio
-- configuration so 380px phones, tablets, PCs, and Xbox UIs all look right.
--
-- This rev focuses on visual quality:
--   * Drop shadows (offset + blurred via UIStroke trick — no asset required)
--   * Layered gradients (top-light + bottom-shadow on every panel/button)
--   * Emoji glyph icons in chips so the topbar reads at a glance
--   * Tighter typography hierarchy with weight contrast

local TweenService = game:GetService("TweenService")

local UIUtil = {}

local DESIGN_HEIGHT = 720
local MIN_TOUCH_PX  = 44
local MIN_PHONE_WIDTH = 380

-- ====================================================================
-- PALETTE — warm sunset / weathered teal / driftwood
-- Refer to these by name everywhere; never hardcode RGB tuples in features.
-- ====================================================================
UIUtil.Palette = {
	-- Sunsets / accents
	Sunset       = Color3.fromRGB(232, 138, 86),
	SunsetDeep   = Color3.fromRGB(196, 86, 64),
	SunsetSoft   = Color3.fromRGB(245, 175, 130),

	-- Sea
	Teal         = Color3.fromRGB(38, 102, 110),
	TealDark     = Color3.fromRGB(18, 52, 60),
	TealDeeper   = Color3.fromRGB(10, 32, 40),    -- background-most
	TealLight    = Color3.fromRGB(78, 156, 162),

	-- Wood / earth
	Wood         = Color3.fromRGB(120, 90, 60),
	WoodDark     = Color3.fromRGB(78, 58, 40),
	WoodLight    = Color3.fromRGB(160, 124, 88),

	-- Text
	Cream        = Color3.fromRGB(244, 230, 200),
	CreamSoft    = Color3.fromRGB(208, 198, 178),
	Ink          = Color3.fromRGB(40, 32, 28),

	-- Currency / rarity
	Gold         = Color3.fromRGB(220, 180, 88),
	GoldDeep     = Color3.fromRGB(180, 140, 60),
	Lure         = Color3.fromRGB(200, 124, 220),
	Common       = Color3.fromRGB(180, 180, 180),
	Uncommon     = Color3.fromRGB(120, 200, 130),
	Rare         = Color3.fromRGB(120, 170, 230),
	Mythic       = Color3.fromRGB(220, 130, 200),

	-- Feedback
	Danger       = Color3.fromRGB(220, 100, 100),
	Success      = Color3.fromRGB(120, 200, 130),

	-- Chrome
	Shadow       = Color3.fromRGB(0, 0, 0),
}

-- ====================================================================
-- SCREEN RIG
-- ====================================================================
-- Caller can pass options.respectTopbar=true to keep our coordinate space
-- BELOW the Roblox topbar (chat / menu / mic). The HUD sets this — it has
-- elements anchored top-left and top-right that would otherwise overlap
-- the Roblox chrome icons. Modal UIs leave it at the default (false) so
-- their full-screen dark backdrop covers behind the chrome.
function UIUtil.makeScreenGui(name: string, parent: Instance?, options: {respectTopbar: boolean?}?): (ScreenGui, UIScale)
	options = options or {}
	-- Defensive: if a ScreenGui with this exact name already exists in
	-- PlayerGui, destroy it. Prevents UI stacking when controllers run
	-- twice (duplicate scripts, hot-reload, fast respawn race, etc.).
	local pg = parent or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local existing = pg:FindFirstChild(name)
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	-- IgnoreGuiInset=true means our Y=0 is the literal top of the screen
	-- (under Roblox chrome). respectTopbar=true flips this so Y=0 is below
	-- the chrome, leaving the topbar icons visible & untouched.
	gui.IgnoreGuiInset = not options.respectTopbar
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg

	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = gui

	local cam = workspace.CurrentCamera
	local function refresh()
		local size = cam.ViewportSize
		local s = size.Y / DESIGN_HEIGHT
		if size.X < MIN_PHONE_WIDTH * (s / 1) then
			s *= MIN_PHONE_WIDTH / math.max(size.X, 1)
		end
		scale.Scale = s
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	refresh()
	return gui, scale
end

-- ====================================================================
-- DROP SHADOW (no image asset required)
-- We add a same-shape sibling Frame behind the target, slightly offset and
-- darkened. Cheap and renders cleanly at any scale.
-- ====================================================================
function UIUtil.addDropShadow(target: GuiObject, opts: {offset: number?, transparency: number?, cornerRadius: number?}?)
	opts = opts or {}
	local offset = opts.offset or 4
	local transparency = opts.transparency or 0.55
	local radius = opts.cornerRadius or 12

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = UIUtil.Palette.Shadow
	shadow.BackgroundTransparency = transparency
	shadow.BorderSizePixel = 0
	shadow.AnchorPoint = target.AnchorPoint
	shadow.Position = target.Position + UDim2.fromOffset(0, offset)
	shadow.Size = target.Size
	shadow.ZIndex = target.ZIndex - 1
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, radius); c.Parent = shadow
	shadow.Parent = target.Parent
	-- Keep shadow in sync if the target moves (used by some animations).
	target:GetPropertyChangedSignal("Position"):Connect(function()
		shadow.Position = target.Position + UDim2.fromOffset(0, offset)
	end)
	target:GetPropertyChangedSignal("Size"):Connect(function()
		shadow.Size = target.Size
	end)
	return shadow
end

-- ====================================================================
-- BASIC FRAMES
-- ====================================================================
function UIUtil.makeFrame(props: {[string]: any}): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = UIUtil.Palette.Teal
	for k, v in pairs(props) do (f :: any)[k] = v end
	return f
end

-- Standard panel: rounded corners, soft top-light gradient, 1.5px stroke.
-- NO automatic drop shadow — shadows must be opt-in (call addDropShadow
-- manually) because parenting shadows as siblings of layout items breaks
-- UIListLayout (it reserves slot space for the shadow Frame).
function UIUtil.makePanel(props: {[string]: any}): Frame
	local f = UIUtil.makeFrame(props)
	if not props.BackgroundColor3 then f.BackgroundColor3 = UIUtil.Palette.TealDark end

	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 14); corner.Parent = f

	local stroke = Instance.new("UIStroke")
	stroke.Color = UIUtil.Palette.TealDeeper
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f

	-- Very subtle top-light only — a thin sheen at the top edge. The
	-- previous gradient feathered the entire panel and made everything
	-- look hazy.
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.92),
		NumberSequenceKeypoint.new(0.15, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = f
	return f
end

-- "Soft" inner panel: lighter background, used inside makePanel groups for
-- nested rows / cards.
function UIUtil.makeSoftPanel(props: {[string]: any}): Frame
	local f = UIUtil.makeFrame(props)
	if not props.BackgroundColor3 then f.BackgroundColor3 = UIUtil.Palette.Teal end
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = UIUtil.Palette.TealDark
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = f
	return f
end

-- ====================================================================
-- TEXT
-- ====================================================================
-- Style = "display" | "title" | "subtitle" | "body" | "caption"
function UIUtil.makeLabel(text: string, style: string?, props: {[string]: any}?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = text
	lbl.TextColor3 = UIUtil.Palette.Cream
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center

	if style == "display" then
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextSize = 28
	elseif style == "title" then
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 20
	elseif style == "subtitle" then
		lbl.Font = Enum.Font.GothamSemibold
		lbl.TextSize = 16
		lbl.TextColor3 = UIUtil.Palette.CreamSoft
	elseif style == "caption" then
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 12
		lbl.TextColor3 = UIUtil.Palette.CreamSoft
	else
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextSize = 15
	end

	if props then
		for k, v in pairs(props) do (lbl :: any)[k] = v end
	end
	return lbl
end

-- ====================================================================
-- BUTTON
-- Inputs:
--   text, onClick, props
-- Optional props:
--   variant = "primary" | "secondary" | "ghost" | "danger"
--   icon    = string (emoji / unicode) prepended to text
-- ====================================================================
function UIUtil.makeButton(text: string, onClick: () -> (), props: {[string]: any}?): TextButton
	props = props or {}
	local variant = props.variant or "primary"
	local icon = props.icon
	props.variant = nil
	props.icon = nil

	local btn = Instance.new("TextButton")
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 15
	btn.Text = icon and (icon .. "  " .. text) or text
	btn.Size = UDim2.fromOffset(180, 44)

	-- Variant defaults
	if variant == "primary" then
		btn.BackgroundColor3 = UIUtil.Palette.Sunset
		btn.TextColor3 = UIUtil.Palette.Cream
	elseif variant == "secondary" then
		btn.BackgroundColor3 = UIUtil.Palette.Teal
		btn.TextColor3 = UIUtil.Palette.Cream
	elseif variant == "ghost" then
		btn.BackgroundColor3 = UIUtil.Palette.TealDark
		btn.BackgroundTransparency = 0.2
		btn.TextColor3 = UIUtil.Palette.Cream
	elseif variant == "danger" then
		btn.BackgroundColor3 = UIUtil.Palette.Danger
		btn.TextColor3 = UIUtil.Palette.Cream
	end

	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Color = UIUtil.Palette.Shadow
	stroke.Thickness = 1
	stroke.Transparency = 0.75
	stroke.Parent = btn

	-- A small top sheen + tiny bottom shadow, both barely visible. Anything
	-- stronger washes the button color out.
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	})
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.88),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	grad.Parent = btn

	-- Apply caller props *before* derived states so background can be overridden.
	for k, v in pairs(props) do (btn :: any)[k] = v end

	-- Press state derived from final BackgroundColor3 — works for any tint.
	local restColor = btn.BackgroundColor3
	local pressColor = restColor:Lerp(Color3.new(0, 0, 0), 0.18)
	local hoverColor = restColor:Lerp(Color3.new(1, 1, 1), 0.06)
	local tween = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, tween, { BackgroundColor3 = hoverColor }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, tween, { BackgroundColor3 = restColor }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, tween, { BackgroundColor3 = pressColor }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, tween, { BackgroundColor3 = hoverColor }):Play()
	end)
	btn.Activated:Connect(onClick)
	-- No automatic drop shadow (was causing layout phantom slots).
	return btn
end

-- ====================================================================
-- CHIP — pill-shaped, used for currency/info clusters in the topbar.
-- Body uses an emoji icon glyph (free, no asset required).
-- ====================================================================
function UIUtil.makeChip(opts: {iconGlyph: string, iconColor: Color3?, name: string, value: string?}): (Frame, TextLabel)
	local chip = UIUtil.makeFrame({
		Name = opts.name,
		Size = UDim2.fromOffset(132, 38),
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = chip
	local s = Instance.new("UIStroke")
	s.Color = UIUtil.Palette.TealDeeper; s.Thickness = 1.2; s.Transparency = 0.3; s.Parent = chip

	-- Subtle top sheen on the chip — just a hint of gloss.
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.92),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = chip

	-- Icon — emoji glyph in a TextLabel. Roblox's Gotham doesn't render
	-- color emoji, so we use a colored glyph approximation: a Frame disc
	-- behind the glyph, glyph drawn in dark for contrast.
	local iconBg = Instance.new("Frame")
	iconBg.AnchorPoint = Vector2.new(0, 0.5)
	iconBg.Position = UDim2.new(0, 6, 0.5, 0)
	iconBg.Size = UDim2.fromOffset(26, 26)
	iconBg.BackgroundColor3 = opts.iconColor or UIUtil.Palette.Gold
	iconBg.BorderSizePixel = 0
	local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(1, 0); ic.Parent = iconBg
	-- Glossy highlight on the icon disc — barely there, just enough to read
	-- as 3D rather than flat.
	local ig = Instance.new("UIGradient")
	ig.Rotation = 90
	ig.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	ig.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	ig.Parent = iconBg
	iconBg.Parent = chip

	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Font = Enum.Font.GothamBlack
	glyph.TextSize = 16
	glyph.TextColor3 = UIUtil.Palette.Ink
	glyph.Text = opts.iconGlyph
	glyph.Parent = iconBg

	local valueLbl = Instance.new("TextLabel")
	valueLbl.BackgroundTransparency = 1
	valueLbl.Position = UDim2.new(0, 38, 0, 0)
	valueLbl.Size = UDim2.new(1, -42, 1, 0)
	valueLbl.Font = Enum.Font.GothamSemibold
	valueLbl.TextSize = 15
	valueLbl.TextColor3 = UIUtil.Palette.Cream
	valueLbl.TextXAlignment = Enum.TextXAlignment.Left
	valueLbl.Text = opts.value or "0"
	valueLbl.Parent = chip
	return chip, valueLbl
end

-- ====================================================================
-- DEVICE HELPERS
-- ====================================================================
function UIUtil.isTouchDevice(): boolean
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return UIUtil
