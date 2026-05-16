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
local UserInputService = game:GetService("UserInputService")
local MotionUtil = require(game:GetService("ReplicatedStorage").Shared.Util.MotionUtil)

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

-- Drop-shadow helper was removed: it parented a sibling Frame as a layout
-- item and broke UIListLayout containers. If you need shadows later, do
-- it with a dedicated child Frame behind everything (negative LayoutOrder
-- only works in specific cases; the cleanest fix is to wrap the target
-- in a same-position container).

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

-- Standard panel: solid rounded background with a thin border. No
-- gradient, no shadow, no transparency. Everything that called makePanel
-- on top of a player's view was reading hazy / faded.
function UIUtil.makePanel(props: {[string]: any}): Frame
	local f = UIUtil.makeFrame(props)
	if not props.BackgroundColor3 then f.BackgroundColor3 = UIUtil.Palette.TealDark end
	-- Force opaque — older callers leaked BackgroundTransparency from
	-- props or relied on makeFrame defaults.
	f.BackgroundTransparency = 0

	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = f

	local stroke = Instance.new("UIStroke")
	stroke.Color = UIUtil.Palette.TealDeeper
	stroke.Thickness = 1.5
	stroke.Transparency = 0.25
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
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
	stroke.Color = UIUtil.Palette.TealDeeper
	stroke.Thickness = 1.2
	stroke.Transparency = 0.4
	stroke.Parent = btn
	-- Buttons are solid color, no gradient. Tint variation comes from
	-- explicit BackgroundColor3 per variant, not from overlay.

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

-- makeChip helper removed; the new HUD builds its own purpose-fit currency
-- pills inline.

-- ====================================================================
-- ROD TIER COLOUR CODING
-- ====================================================================
-- Maps a rod tier to an accent colour, reusing the existing rarity palette
-- so the chip reads consistently with catch-reveal badges:
--   tier 1            -> Common  (neutral gray)
--   tier 2            -> Uncommon (green)
--   tier 3            -> Rare    (blue)
--   tier 4 .. maxTier -> a single amber "max" treatment (no per-tier colour
--                        creep above 3; tiers 4, 5, 6... all share this).
-- `accent2` is only meaningfully different for the max treatment, where the
-- caller may cycle the stroke between accent and accent2 for a subtle shimmer.
-- The chip *background* stays TealDark (HUD opaque-legibility rule) — tier
-- colour lives in the icon disc / stroke / value text only.
function UIUtil.tierPalette(tier: number, maxTier: number): { accent: Color3, accent2: Color3, isMax: boolean }
	local P = UIUtil.Palette
	if tier <= 1 then
		return { accent = P.Common, accent2 = P.Common, isMax = (maxTier <= 1) }
	elseif tier == 2 then
		return { accent = P.Uncommon, accent2 = P.Uncommon, isMax = (maxTier <= 2) }
	elseif tier == 3 then
		return { accent = P.Rare, accent2 = P.Rare, isMax = (maxTier <= 3) }
	end
	-- tier 4+ : unified amber max treatment (palette has no amber "Mythic";
	-- Mythic is magenta, Gold is the amber — see report flag).
	return { accent = P.Gold, accent2 = P.GoldDeep, isMax = true }
end

-- ====================================================================
-- TOOLTIP
-- ====================================================================
-- A read-only floating panel anchored near a chip. Dismisses on: tap
-- outside (full-screen backdrop button), Escape (PC), or `inactivitySeconds`
-- after it opened. Fades in (slide too, unless ReducedMotion). The caller
-- owns nothing — handle:destroy() tears down every instance + connection.
--
-- opts:
--   parent            ScreenGui to mount into
--   size              UDim2 of the panel
--   position          UDim2 (resting position)
--   anchorPoint       Vector2 (default 1,0)
--   build             function(content: Frame) -> () : fills the panel body
--   inactivitySeconds number
--   fadeDuration      number
--   slideOffsetPx     number (downward offset the panel slides up from)
export type TooltipHandle = {
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	destroy: () -> (),
}
function UIUtil.makeTooltip(opts: {
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	build: (Frame) -> (),
	inactivitySeconds: number,
	fadeDuration: number,
	slideOffsetPx: number,
}): TooltipHandle
	local P = UIUtil.Palette

	-- Full-screen invisible backdrop catches "tap outside to dismiss".
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "TooltipBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 50
	backdrop.Visible = false
	backdrop.Parent = opts.parent

	-- CanvasGroup root so the whole panel fades as one (GroupTransparency).
	local panel = Instance.new("CanvasGroup")
	panel.Name = "Tooltip"
	panel.BackgroundColor3 = P.TealDark
	panel.BorderSizePixel = 0
	panel.AnchorPoint = opts.anchorPoint or Vector2.new(1, 0)
	panel.Size = opts.size
	panel.ZIndex = 51
	panel.Visible = false
	panel.GroupTransparency = 1
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = P.TealDeeper
	stroke.Thickness = 1.5
	stroke.Transparency = 0.25
	stroke.Parent = panel
	panel.Parent = opts.parent

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = panel
	opts.build(content)

	local restPos = opts.position
	local fromPos = UDim2.new(
		restPos.X.Scale, restPos.X.Offset,
		restPos.Y.Scale, restPos.Y.Offset + opts.slideOffsetPx
	)

	local isOpen = false
	local dismissThread: thread? = nil
	local escConn: RBXScriptConnection? = nil
	local fadeTween: Tween? = nil

	local function cancelDismiss()
		if dismissThread then
			task.cancel(dismissThread)
			dismissThread = nil
		end
	end

	local close, open

	close = function()
		if not isOpen then return end
		isOpen = false
		cancelDismiss()
		if escConn then escConn:Disconnect(); escConn = nil end
		backdrop.Visible = false
		if fadeTween then fadeTween:Destroy(); fadeTween = nil end
		local reduced = MotionUtil.reducedMotionEnabled()
		local dur = reduced and (opts.fadeDuration * 0.5) or opts.fadeDuration
		local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local props: { [string]: any } = { GroupTransparency = 1 }
		if not reduced then props.Position = fromPos end
		fadeTween = TweenService:Create(panel, info, props)
		local t = fadeTween
		t.Completed:Connect(function()
			if t == fadeTween then panel.Visible = false end
		end)
		t:Play()
	end

	open = function()
		if isOpen then
			-- Re-open resets the inactivity timer.
			cancelDismiss()
			dismissThread = task.delay(opts.inactivitySeconds, close)
			return
		end
		isOpen = true
		if fadeTween then fadeTween:Destroy(); fadeTween = nil end
		panel.Visible = true
		backdrop.Visible = true
		local reduced = MotionUtil.reducedMotionEnabled()
		local dur = reduced and (opts.fadeDuration * 0.5) or opts.fadeDuration
		local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if reduced then
			panel.Position = restPos
			fadeTween = TweenService:Create(panel, info, { GroupTransparency = 0 })
		else
			panel.Position = fromPos
			fadeTween = TweenService:Create(panel, info, { GroupTransparency = 0, Position = restPos })
		end
		fadeTween:Play()

		escConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.KeyCode == Enum.KeyCode.Escape then close() end
		end)
		cancelDismiss()
		dismissThread = task.delay(opts.inactivitySeconds, close)
	end

	backdrop.Activated:Connect(close)

	return {
		open = open,
		close = close,
		toggle = function()
			if isOpen then close() else open() end
		end,
		isOpen = function() return isOpen end,
		destroy = function()
			cancelDismiss()
			if escConn then escConn:Disconnect(); escConn = nil end
			if fadeTween then fadeTween:Destroy(); fadeTween = nil end
			backdrop:Destroy()
			panel:Destroy()
		end,
	}
end

-- ====================================================================
-- DEVICE HELPERS
-- ====================================================================
function UIUtil.isTouchDevice(): boolean
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return UIUtil
