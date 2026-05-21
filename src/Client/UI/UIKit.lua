--!strict
-- UIKit.lua
-- Phase 1 design system — cozy warm palette, factory functions, token re-exports.
--
-- ====================================================================
-- USAGE CONTRACT
-- ====================================================================
-- • NEVER inline a Color3 in a feature UI. Use UIKit.Palette.<Name>.
-- • NEVER inline a font size. Use UIKit.Typography.<style>.size.
-- • NEVER inline a spacing number. Use UIKit.Spacing.<key>.
-- • NEVER inline a corner radius. Use UIKit.Radii.<key>.
-- • Call UIKit.Button(text, opts) for every interactive button.
-- • Call UIKit.Card(opts) for every card/tile container.
-- • All token values are sourced from GameConfig.UI — tune there, not here.
--
-- ====================================================================
-- DESIGN TOKENS (from GameConfig.UI)
-- ====================================================================
-- Spacing:  xs=4  sm=8  md=12  lg=16  xl=24  xxl=32
-- Radii:    sm=6  md=10  lg=12  xl=16  pill=999
-- Typography (task names → GameConfig names):
--   Caption / Label  → caption  (Gotham 12)
--   Body             → body     (GothamMedium 15)
--   Subtitle         → subtitle (GothamSemibold 16)
--   Header           → title    (GothamBold 20)
--   Title            → display  (GothamBlack 28)
-- Touch floor: 44px. Font floor: 12px.
-- ====================================================================

local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local GuiService    = game:GetService("GuiService")
local GameConfig    = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local MotionUtil    = require(game:GetService("ReplicatedStorage").Shared.Util.MotionUtil)

local UIKit = {}

-- ====================================================================
-- TOKEN RE-EXPORTS — ergonomic aliases for GameConfig.UI sub-tables
-- ====================================================================
local UI = GameConfig.UI

UIKit.Spacing      = UI.Spacing       -- xs/sm/md/lg/xl/xxl
UIKit.Radii        = UI.Radii         -- sm/md/lg/xl/pill
UIKit.Typography   = UI.Typography    -- display/title/subtitle/body/caption
UIKit.DisplayOrder = UI.DisplayOrder  -- World/HUD/Modal/…
UIKit.Modal        = UI.Modal
UIKit.Notification = UI.Notification
UIKit.MinTouchPx   = UI.MinTouchPx    -- 44
UIKit.MinFontPx    = UI.MinFontPx     -- 12

-- ====================================================================
-- PALETTE — cozy harbor, warm and weathered.
-- Replaces the dark nautical tones with warm beige, soft mint, muted
-- amber, and dark ink as directed. Rarity colors are sourced directly
-- from GameConfig.Fishing.RarityColors so they stay in sync with the
-- cast-meter zone tints and catch-reveal badges.
-- ====================================================================
UIKit.Palette = {
	-- ── Backgrounds / surfaces ─────────────────────────────────────
	-- Primary surface: warm aged parchment — the "paper" everything sits on.
	Parchment     = Color3.fromRGB(245, 236, 218),
	-- Slightly darker for card insets, recessed panels.
	ParchmentDeep = Color3.fromRGB(232, 220, 198),
	-- Lightest wash — used as ScreenGui backdrop / modal backdrop base.
	ParchmentWash = Color3.fromRGB(252, 247, 238),

	-- ── Mint / teal accent ────────────────────────────────────────
	-- Soft harbour-water mint for primary buttons and active states.
	Mint          = Color3.fromRGB(140, 196, 182),
	MintDark      = Color3.fromRGB( 88, 152, 138),
	MintDeep      = Color3.fromRGB( 48, 108,  96),
	MintLight     = Color3.fromRGB(192, 228, 218),

	-- ── Amber / warmth ────────────────────────────────────────────
	-- Muted amber for secondary highlights, XP bar fill, coin accents.
	Amber         = Color3.fromRGB(210, 158,  80),
	AmberDeep     = Color3.fromRGB(168, 118,  48),
	AmberLight    = Color3.fromRGB(238, 196, 128),
	AmberSoft     = Color3.fromRGB(245, 215, 160),

	-- ── Ink / text ────────────────────────────────────────────────
	-- Dark warm ink for primary text on light surfaces.
	Ink           = Color3.fromRGB( 48,  38,  28),
	InkSoft       = Color3.fromRGB( 96,  80,  64),    -- secondary / caption text
	InkFaint      = Color3.fromRGB(148, 130, 110),    -- placeholder / disabled text

	-- ── Cream / light text ────────────────────────────────────────
	-- Used for text on dark surfaces (dark buttons, dark cards).
	Cream         = Color3.fromRGB(252, 244, 228),
	CreamSoft     = Color3.fromRGB(220, 208, 188),

	-- ── Borders / strokes ─────────────────────────────────────────
	BorderLight   = Color3.fromRGB(210, 194, 168),    -- subtle divide on light bg
	BorderMid     = Color3.fromRGB(172, 152, 122),    -- card outlines, panel dividers
	BorderDark    = Color3.fromRGB(100,  80,  56),    -- strong outlines, headers

	-- ── State ─────────────────────────────────────────────────────
	Success       = Color3.fromRGB(108, 186, 118),
	Danger        = Color3.fromRGB(210,  90,  80),
	Warning       = Color3.fromRGB(222, 160,  60),

	-- ── Currency ──────────────────────────────────────────────────
	Gold          = Color3.fromRGB(220, 175,  70),
	GoldDeep      = Color3.fromRGB(175, 130,  40),
	Lure          = Color3.fromRGB(185, 118, 210),

	-- ── Rarity (sourced from GameConfig so zone tints stay in sync) ─
	Common        = Color3.fromRGB(176, 182, 190),
	Uncommon      = Color3.fromRGB(120, 205, 135),
	Rare          = Color3.fromRGB( 95, 165, 240),
	Epic          = Color3.fromRGB(185, 120, 235),
	Legendary     = Color3.fromRGB(245, 180,  75),
	Mythic        = Color3.fromRGB(240,  95, 140),
	Divine        = Color3.fromRGB(255, 225, 150),

	-- ── Misc ──────────────────────────────────────────────────────
	Shadow        = Color3.new(0, 0, 0),
	ThumbLight    = Color3.fromRGB(225, 232, 245),   -- viewport studio light tint
}

-- Rarity sub-table for convenience: UIKit.Palette.Rarity["Epic"]
UIKit.Palette.Rarity = {
	Common    = UIKit.Palette.Common,
	Uncommon  = UIKit.Palette.Uncommon,
	Rare      = UIKit.Palette.Rare,
	Epic      = UIKit.Palette.Epic,
	Legendary = UIKit.Palette.Legendary,
	Mythic    = UIKit.Palette.Mythic,
	Divine    = UIKit.Palette.Divine,
}

-- Animated cycle second-color for high rarity borders (decorative; skipped under ReducedMotion).
UIKit.Palette.RarityCycle = {
	Legendary = Color3.fromRGB(255, 220,  80),
	Mythic    = Color3.fromRGB(240, 100, 100),
	Divine    = Color3.fromRGB(255, 200, 255),
}

-- Modifier accent colors built from GameConfig.ModifierGlow (single source of truth).
UIKit.Palette.Modifiers = {}
do
	local mg = (GameConfig :: any).ModifierGlow
	if mg then
		for id, glow in pairs(mg) do
			UIKit.Palette.Modifiers[id] = glow.Color
		end
	end
end

-- ====================================================================
-- LOOKUP HELPERS
-- ====================================================================

-- Returns the accent color for a rarity string. Falls back to Common.
function UIKit.rarityColor(rarity: string?): Color3
	if not rarity then return UIKit.Palette.Common end
	return UIKit.Palette.Rarity[rarity] or UIKit.Palette.Common
end

-- Returns the accent color for a modifier id. Falls back to InkFaint.
function UIKit.modifierColor(id: string?): Color3
	if not id then return UIKit.Palette.InkFaint end
	return UIKit.Palette.Modifiers[id] or UIKit.Palette.InkFaint
end

-- Returns accent/accent2/isMax for a rod tier — consistent with HUD rod chip.
function UIKit.tierPalette(tier: number, maxTier: number): { accent: Color3, accent2: Color3, isMax: boolean }
	local P = UIKit.Palette
	if tier <= 1 then
		return { accent = P.Common,   accent2 = P.Common,  isMax = (maxTier <= 1) }
	elseif tier == 2 then
		return { accent = P.Uncommon, accent2 = P.Uncommon, isMax = (maxTier <= 2) }
	elseif tier == 3 then
		return { accent = P.Rare,     accent2 = P.Rare,     isMax = (maxTier <= 3) }
	end
	return { accent = P.Gold, accent2 = P.GoldDeep, isMax = true }
end

-- ====================================================================
-- REDUCED MOTION HELPER
-- ====================================================================
-- Reads GuiService.ReducedMotionEnabled once per frame on demand, with
-- a cached value so callers don't need to require MotionUtil directly.
-- Use UIKit.reducedMotion() anywhere a factory or feature UI needs it.

local _rmCache: boolean? = nil
local function _initRM()
	_rmCache = GuiService.ReducedMotionEnabled
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		_rmCache = GuiService.ReducedMotionEnabled
	end)
end
_initRM()

function UIKit.reducedMotion(): boolean
	return _rmCache == true
end

-- ====================================================================
-- SCREEN GUI FACTORY
-- ====================================================================
-- Identical logic to UIUtil.makeScreenGui — included here so screens
-- rebuilt against UIKit have no UIUtil dependency for scaffolding.
-- opts.respectTopbar=true shifts Y=0 below the Roblox topbar chrome.
local DESIGN_HEIGHT   = 720
local MIN_PHONE_WIDTH = 380

function UIKit.makeScreenGui(name: string, parent: Instance?, opts: {respectTopbar: boolean?}?): (ScreenGui, UIScale)
	opts = opts or {}
	local pg = parent or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local existing = pg:FindFirstChild(name)
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = not (opts :: any).respectTopbar
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg

	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = gui

	local function refresh()
		local cam = workspace.CurrentCamera
		if not cam then scale.Scale = 1; return end
		local size = cam.ViewportSize
		if size.X <= 1 or size.Y <= 1 then scale.Scale = 1; return end
		local s = size.Y / DESIGN_HEIGHT
		if size.X < MIN_PHONE_WIDTH * s then
			s = s * (MIN_PHONE_WIDTH / math.max(size.X, 1))
		end
		scale.Scale = math.clamp(s, 0.35, 2)
	end

	local function bindCamera(cam: Camera)
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		refresh()
	end

	local cam = workspace.CurrentCamera
	if cam then
		bindCamera(cam)
	else
		scale.Scale = 1
		local conn: RBXScriptConnection? = nil
		conn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			local c = workspace.CurrentCamera
			if not c then return end
			if conn then conn:Disconnect(); conn = nil end
			bindCamera(c)
		end)
	end

	return gui, scale
end

-- ====================================================================
-- LABEL FACTORY
-- ====================================================================
-- style = "display" | "title" | "subtitle" | "body" | "caption"
-- Equivalent task names: Title=display, Header=title, Body=body, Label/Caption=caption.
-- All sizes come from UIKit.Typography (GameConfig.UI.Typography).

function UIKit.Label(text: string, style: string?, props: {[string]: any}?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = UIKit.Palette.Ink
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center

	local token = UIKit.Typography[style or "body"] or UIKit.Typography.body
	lbl.Font = token.font
	lbl.TextSize = math.max(token.size, UIKit.MinFontPx)

	-- Secondary styles are rendered softer
	if style == "caption" or style == "subtitle" then
		lbl.TextColor3 = UIKit.Palette.InkSoft
	end

	if props then
		for k, v in pairs(props) do (lbl :: any)[k] = v end
	end

	if RunService:IsStudio() and lbl.TextSize < UIKit.MinFontPx then
		warn(("[UIKit] TextSize %d below MinFontPx %d on label %q"):format(
			lbl.TextSize, UIKit.MinFontPx, text))
	end
	return lbl
end

-- ====================================================================
-- BUTTON FACTORY
-- ====================================================================
-- UIKit.Button(text, opts)
--
-- opts (all optional):
--   variant  "primary" | "secondary" | "ghost" | "danger"  (default: "primary")
--   icon     string prepended to text with a gap
--   size     UDim2   (defaults to 180×44; height enforces MinTouchPx)
--   onClick  function (can also be wired after return via .Activated)
--   [any other TextButton property]
--
-- Variants:
--   primary   — Mint fill, Cream text   (main CTAs)
--   secondary — Parchment fill, Ink text, Mint border  (secondary actions)
--   ghost     — Transparent fill, Ink text, border     (low-emphasis)
--   danger    — Danger fill, Cream text  (destructive)
--
-- Always 44px minimum height. Always rounded at UIKit.Radii.md.
-- Hover/press feedback routes through MotionUtil so ReducedMotion is respected.

function UIKit.Button(text: string, opts: {[string]: any}?): TextButton
	opts = opts or {}
	local o = opts :: {[string]: any}
	local variant  = o.variant  or "primary"
	local icon     = o.icon
	local onClick  = o.onClick
	local sizeArg  = o.size

	-- Consume UIKit-specific keys before applying rest as properties
	o.variant = nil
	o.icon    = nil
	o.onClick = nil
	o.size    = nil

	local P = UIKit.Palette
	local R = UIKit.Radii

	local btn = Instance.new("TextButton")
	btn.Name = "Button"
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = UIKit.Typography.body.font
	btn.TextSize = math.max(UIKit.Typography.body.size, UIKit.MinFontPx)
	btn.Text = icon and (icon .. "  " .. text) or text

	-- Enforce touch floor on height
	local sz = sizeArg or UDim2.fromOffset(180, UIKit.MinTouchPx)
	if sz.Y.Scale == 0 and sz.Y.Offset < UIKit.MinTouchPx then
		sz = UDim2.new(sz.X.Scale, sz.X.Offset, 0, UIKit.MinTouchPx)
	end
	btn.Size = sz

	-- Variant styling
	local restBg: Color3
	local restText: Color3
	local strokeColor: Color3
	local strokeThickness = 0

	if variant == "primary" then
		restBg       = P.Mint
		restText     = P.Cream
		strokeColor  = P.MintDark
		strokeThickness = 1.2
	elseif variant == "secondary" then
		restBg       = P.Parchment
		restText     = P.Ink
		strokeColor  = P.Mint
		strokeThickness = 1.5
	elseif variant == "ghost" then
		restBg       = P.Parchment
		restText     = P.InkSoft
		strokeColor  = P.BorderMid
		strokeThickness = 1.2
		btn.BackgroundTransparency = 0.15
	elseif variant == "danger" then
		restBg       = P.Danger
		restText     = P.Cream
		strokeColor  = P.BorderDark
		strokeThickness = 1.2
	else
		restBg      = P.Mint
		restText    = P.Cream
		strokeColor = P.MintDark
		strokeThickness = 1.2
	end

	btn.BackgroundColor3 = restBg
	btn.TextColor3       = restText

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, R.md)
	corner.Parent = btn

	if strokeThickness > 0 then
		local stroke = Instance.new("UIStroke")
		stroke.Color = strokeColor
		stroke.Thickness = strokeThickness
		stroke.Transparency = 0.25
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = btn
	end

	-- Apply any remaining caller props
	for k, v in pairs(o) do (btn :: any)[k] = v end

	-- Hover / press feedback via MotionUtil (ReducedMotion-aware)
	local pressColor = restBg:Lerp(Color3.new(0, 0, 0), 0.14)
	local hoverColor = restBg:Lerp(Color3.new(1, 1, 1), 0.08)
	local fbInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	btn.MouseEnter:Connect(function()
		MotionUtil.tweenOrSnap(btn, fbInfo, { BackgroundColor3 = hoverColor })
	end)
	btn.MouseLeave:Connect(function()
		MotionUtil.tweenOrSnap(btn, fbInfo, { BackgroundColor3 = restBg })
	end)
	btn.MouseButton1Down:Connect(function()
		MotionUtil.tweenOrSnap(btn, fbInfo, { BackgroundColor3 = pressColor })
	end)
	btn.MouseButton1Up:Connect(function()
		MotionUtil.tweenOrSnap(btn, fbInfo, { BackgroundColor3 = hoverColor })
	end)

	if onClick then
		btn.Activated:Connect(onClick)
	end

	if RunService:IsStudio() and btn.Size.Y.Scale == 0 and btn.Size.Y.Offset < UIKit.MinTouchPx then
		warn(("[UIKit] Button height %d below MinTouchPx %d"):format(btn.Size.Y.Offset, UIKit.MinTouchPx))
	end

	return btn
end

-- ====================================================================
-- CARD FACTORY
-- ====================================================================
-- UIKit.Card(opts)
--
-- A rounded, bordered content tile. Cozy: warm parchment surface with a
-- subtle border. Used for fish cards, listing rows, building slots, etc.
--
-- opts (all optional):
--   size         UDim2   (no default — caller must set or it stays 0,0)
--   style        "default" | "inset" | "dark"
--                  default — ParchmentDeep surface, BorderLight border
--                  inset   — ParchmentWash surface (recessed inner area)
--                  dark    — Ink-tinted surface, Cream text (selected state)
--   radius       number   (defaults to UIKit.Radii.md)
--   strokeColor  Color3   (overrides the style default border)
--   [any Frame property]
--
-- Returns a Frame. Caller mounts children into it directly.

function UIKit.Card(opts: {[string]: any}?): Frame
	opts = opts or {}
	local o = opts :: {[string]: any}
	local style       = o.style       or "default"
	local radiusArg   = o.radius      or UIKit.Radii.md
	local strokeOverride = o.strokeColor

	o.style       = nil
	o.radius      = nil
	o.strokeColor = nil

	local P = UIKit.Palette

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BorderSizePixel = 0

	local bgColor: Color3
	local strokeColor: Color3

	if style == "inset" then
		bgColor     = P.ParchmentWash
		strokeColor = P.BorderLight
	elseif style == "dark" then
		bgColor     = P.MintDeep
		strokeColor = P.MintDark
	else -- "default"
		bgColor     = P.ParchmentDeep
		strokeColor = P.BorderMid
	end

	if strokeOverride then strokeColor = strokeOverride end

	card.BackgroundColor3 = bgColor

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radiusArg)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = 1.2
	stroke.Transparency = 0.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	-- Apply remaining props
	for k, v in pairs(o) do (card :: any)[k] = v end

	return card
end

-- ====================================================================
-- RARITY CHIP
-- ====================================================================
-- Small rounded badge tinted by rarity. 72×22px by default.
-- Used by InventoryUI, CatchRevealUI, MarketUI.

function UIKit.RarityChip(rarity: string, text: string?, props: {[string]: any}?): Frame
	props = props or {}
	local chip = Instance.new("Frame")
	chip.Name = "RarityChip"
	chip.BorderSizePixel = 0
	chip.BackgroundColor3 = UIKit.rarityColor(rarity)
	chip.BackgroundTransparency = 0.08
	chip.Size = UDim2.fromOffset(72, 22)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIKit.Radii.sm)
	corner.Parent = chip

	local stroke = Instance.new("UIStroke")
	stroke.Color = UIKit.Palette.Ink
	stroke.Thickness = 1
	stroke.Transparency = 0.55
	stroke.Parent = chip

	local lbl = UIKit.Label(text or rarity, "caption", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIKit.Palette.Ink,
		Font = UIKit.Typography.caption.font,
		Parent = chip,
	})
	lbl.Font = Enum.Font.GothamBold

	for k, v in pairs(props :: {[string]: any}) do (chip :: any)[k] = v end
	return chip
end

-- ====================================================================
-- MODIFIER PILL
-- ====================================================================
-- Tiny tinted pill labelled with modifier display name. 72×18px default.

function UIKit.ModifierPill(id: string, displayName: string?, props: {[string]: any}?): Frame
	props = props or {}
	local pill = Instance.new("Frame")
	pill.Name = "ModifierPill"
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = UIKit.modifierColor(id)
	pill.BackgroundTransparency = 0.18
	pill.Size = UDim2.fromOffset(72, 18)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIKit.Radii.sm)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.Color = UIKit.Palette.Ink
	stroke.Thickness = 1
	stroke.Transparency = 0.6
	stroke.Parent = pill

	UIKit.Label(displayName or id, "caption", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIKit.Palette.Ink,
		Font = Enum.Font.GothamBold,
		Parent = pill,
	})

	for k, v in pairs(props :: {[string]: any}) do (pill :: any)[k] = v end
	return pill
end

-- ====================================================================
-- CLOSE BUTTON
-- ====================================================================
-- Standard 44×44 X button for modal headers.
-- Gotham does not render "✕" — uses ASCII "X".

UIKit.CloseGlyph = "X"

function UIKit.CloseButton(onClick: () -> (), props: {[string]: any}?): TextButton
	props = props or {}
	local P = UIKit.Palette
	local M = UIKit.Modal

	local btn = Instance.new("TextButton")
	btn.Name = "Close"
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.BackgroundColor3 = P.ParchmentDeep
	btn.Text = UIKit.CloseGlyph
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = P.InkSoft
	btn.TextScaled = true
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -UIKit.Spacing.md, 0.5, 0)
	btn.Size = UDim2.fromOffset(M.CloseButtonPx, M.CloseButtonPx)

	local textCap = Instance.new("UITextSizeConstraint")
	textCap.MaxTextSize = 20
	textCap.MinTextSize = 14
	textCap.Parent = btn

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIKit.Radii.sm)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = P.BorderMid
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = btn

	for k, v in pairs(props :: {[string]: any}) do (btn :: any)[k] = v end
	btn.Activated:Connect(onClick)
	return btn
end

-- ====================================================================
-- DIVIDER
-- ====================================================================
-- Horizontal rule for separating sections inside a card or panel.
-- height = 1px by default; use UIKit.Divider({ Size = UDim2.new(1,0,0,2) })
-- for a thicker line.

function UIKit.Divider(props: {[string]: any}?): Frame
	props = props or {}
	local div = Instance.new("Frame")
	div.Name = "Divider"
	div.BorderSizePixel = 0
	div.BackgroundColor3 = UIKit.Palette.BorderLight
	div.Size = UDim2.new(1, 0, 0, 1)
	for k, v in pairs(props :: {[string]: any}) do (div :: any)[k] = v end
	return div
end

-- ====================================================================
-- MODAL SHELL
-- ====================================================================
-- Standard full-screen modal chrome: backdrop + panel + header + close.
-- All feature modals mount content into shell.body.
--
-- opts:
--   name          string   — ScreenGui name (dedupes on construction)
--   title         string   — header title text
--   onClose       function?
--   parent        Instance?
--   displayOrder  number?  (defaults to UIKit.DisplayOrder.Modal)
--   bodyPadding   number?  (defaults to Modal.BodyPaddingPx)
--   width         number?  (defaults to Modal.MaxWidthPx)
--   heightScale   number?  (defaults to 0.78)
--
-- Returns the same shape as UIUtil.makeModalShell for drop-in compatibility.

export type ModalShell = {
	gui: ScreenGui,
	scale: UIScale,
	backdrop: TextButton,
	panel: Frame,
	header: Frame,
	title: TextLabel,
	closeButton: TextButton,
	body: Frame,
	open: () -> (),
	close: () -> (),
	destroy: () -> (),
}

function UIKit.ModalShell(opts: {
	name: string,
	title: string,
	onClose: (() -> ())?,
	parent: Instance?,
	displayOrder: number?,
	bodyPadding: number?,
	width: number?,
	heightScale: number?,
}): ModalShell
	local P = UIKit.Palette
	local M = UIKit.Modal
	local R = UIKit.Radii
	local S = UIKit.Spacing

	local gui, scale = UIKit.makeScreenGui(opts.name, opts.parent)
	gui.DisplayOrder = opts.displayOrder or UIKit.DisplayOrder.Modal

	-- Full-screen backdrop
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = P.Shadow
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = gui

	-- Panel — warm parchment surface, cozy card feel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = P.Parchment
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, opts.heightScale or 0.78, 0)
	panel.ZIndex = 2
	panel.Parent = gui

	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(opts.width or M.MaxWidthPx, math.huge)
	sizeCap.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, R.lg)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = P.BorderMid
	panelStroke.Thickness = 1.5
	panelStroke.Transparency = 0.25
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	panelStroke.Parent = panel

	-- Header — slightly darker parchment strip
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = P.ParchmentDeep
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, M.HeaderHeightPx)
	header.ZIndex = 3
	header.Parent = panel

	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, R.lg)
	hCorner.Parent = header

	-- Mask: fill bottom-rounded corners of header so it meets panel flush
	local hMask = Instance.new("Frame")
	hMask.Name = "HeaderMask"
	hMask.BackgroundColor3 = P.ParchmentDeep
	hMask.BorderSizePixel = 0
	hMask.AnchorPoint = Vector2.new(0, 1)
	hMask.Position = UDim2.new(0, 0, 1, 0)
	hMask.Size = UDim2.new(1, 0, 0, R.lg)
	hMask.ZIndex = 3
	hMask.Parent = header

	-- Header divider line
	local hDiv = UIKit.Divider({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = P.BorderLight,
		ZIndex = 4,
		Parent = header,
	})
	hDiv.Size = UDim2.new(1, 0, 0, 1)

	-- Title label
	local titleLbl = UIKit.Label(opts.title or "", "title", {
		Parent = header,
		Position = UDim2.fromOffset(S.lg, 0),
		Size = UDim2.new(1, -(S.lg * 2 + M.CloseButtonPx), 1, 0),
		TextColor3 = P.Ink,
		ZIndex = 4,
	})

	-- Body frame — padded, transparent bg (inherits panel parchment)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.new(0, 0, 0, M.HeaderHeightPx)
	body.Size = UDim2.new(1, 0, 1, -M.HeaderHeightPx)
	body.ZIndex = 2
	body.Parent = panel

	local pad = Instance.new("UIPadding")
	local p = opts.bodyPadding or M.BodyPaddingPx
	pad.PaddingLeft   = UDim.new(0, p)
	pad.PaddingRight  = UDim.new(0, p)
	pad.PaddingTop    = UDim.new(0, p)
	pad.PaddingBottom = UDim.new(0, p)
	pad.Parent = body

	-- Open / close animation
	local isOpen = false
	local closed = false
	local restPos = panel.Position
	local fromPos = UDim2.new(restPos.X.Scale, restPos.X.Offset,
		restPos.Y.Scale, restPos.Y.Offset + M.SlideOffsetPx)
	local fadeInfo = TweenInfo.new(M.FadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local close: (() -> ())
	local open: (() -> ())

	open = function()
		if isOpen then return end
		isOpen = true
		panel.BackgroundTransparency = 1
		backdrop.BackgroundTransparency = 1
		gui.Enabled = true
		if UIKit.reducedMotion() then
			panel.Position = restPos
			panel.BackgroundTransparency = 0
			backdrop.BackgroundTransparency = M.BackdropAlpha
		else
			panel.Position = fromPos
			MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = M.BackdropAlpha })
			MotionUtil.tweenOrSnap(panel,    fadeInfo, { BackgroundTransparency = 0, Position = restPos })
		end
	end

	close = function()
		if not isOpen or closed then return end
		isOpen = false
		if opts.onClose then opts.onClose() end
	end

	local closeBtn = UIKit.CloseButton(close, {
		Parent = header,
		ZIndex = 4,
	})

	local function destroy()
		closed = true
		if gui and gui.Parent then gui:Destroy() end
	end

	backdrop.Activated:Connect(close)
	open()

	return {
		gui         = gui,
		scale       = scale,
		backdrop    = backdrop,
		panel       = panel,
		header      = header,
		title       = titleLbl,
		closeButton = closeBtn,
		body        = body,
		open        = open,
		close       = close,
		destroy     = destroy,
	}
end

-- ====================================================================
-- PLACEHOLDER STATE
-- ====================================================================
-- Renders a clean "feature coming soon" placeholder into any parent
-- frame. Used by post-launch stub screens (Season Pass, Cosmetic Shop)
-- and any screen that has no data yet.
--
-- UIKit.Placeholder(parent, opts)
--   opts.icon  string? — large emoji/unicode glyph (default "🚧")
--   opts.title string? — headline
--   opts.body  string? — secondary line

function UIKit.Placeholder(parent: Frame, opts: {icon: string?, title: string?, body: string?}?)
	opts = opts or {}
	local o = opts :: {icon: string?, title: string?, body: string?}
	local P = UIKit.Palette
	local S = UIKit.Spacing

	local container = Instance.new("Frame")
	container.Name = "Placeholder"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.Parent = parent

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.sm)
	list.Parent = container

	-- Icon glyph
	if o.icon then
		local iconLbl = Instance.new("TextLabel")
		iconLbl.BackgroundTransparency = 1
		iconLbl.Text = o.icon
		iconLbl.Font = Enum.Font.GothamBold
		iconLbl.TextSize = 48
		iconLbl.TextColor3 = P.AmberLight
		iconLbl.Size = UDim2.new(1, 0, 0, 56)
		iconLbl.TextXAlignment = Enum.TextXAlignment.Center
		iconLbl.LayoutOrder = 1
		iconLbl.Parent = container
	end

	if o.title then
		local t = UIKit.Label(o.title, "title", {
			Size = UDim2.new(1, 0, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = P.Ink,
			LayoutOrder = 2,
			Parent = container,
		})
		_ = t
	end

	if o.body then
		local b = UIKit.Label(o.body, "caption", {
			Size = UDim2.new(0.85, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			TextColor3 = P.InkSoft,
			LayoutOrder = 3,
			Parent = container,
		})
		_ = b
	end
end

-- ====================================================================
-- TOOLTIP
-- ====================================================================
-- Floating read-only panel. Identical contract to UIUtil.makeTooltip
-- but styled with the new cozy palette.

export type TooltipHandle = {
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	destroy: () -> (),
}

function UIKit.Tooltip(topts: {
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	build: (Frame) -> (),
	inactivitySeconds: number,
	fadeDuration: number,
	slideOffsetPx: number,
}): TooltipHandle
	local P = UIKit.Palette
	local UserInputService = game:GetService("UserInputService")

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "TooltipBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 50
	backdrop.Visible = false
	backdrop.Parent = topts.parent

	local panel = Instance.new("CanvasGroup")
	panel.Name = "Tooltip"
	panel.BackgroundColor3 = P.Parchment
	panel.BorderSizePixel = 0
	panel.AnchorPoint = topts.anchorPoint or Vector2.new(1, 0)
	panel.Size = topts.size
	panel.ZIndex = 51
	panel.Visible = false
	panel.GroupTransparency = 1
	panel.Parent = topts.parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIKit.Radii.md)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = P.BorderMid
	stroke.Thickness = 1.5
	stroke.Transparency = 0.25
	stroke.Parent = panel

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = panel
	topts.build(content)

	local restPos = topts.position
	local fromPos = UDim2.new(
		restPos.X.Scale, restPos.X.Offset,
		restPos.Y.Scale, restPos.Y.Offset + topts.slideOffsetPx
	)

	local isOpen = false
	local dismissThread: thread? = nil
	local escConn: RBXScriptConnection? = nil
	local fadeTween: Tween? = nil

	local function cancelDismiss()
		if dismissThread then task.cancel(dismissThread); dismissThread = nil end
	end

	local close, open

	close = function()
		if not isOpen then return end
		isOpen = false
		cancelDismiss()
		if escConn then escConn:Disconnect(); escConn = nil end
		backdrop.Visible = false
		if fadeTween then fadeTween:Destroy(); fadeTween = nil end
		local reduced = UIKit.reducedMotion()
		local dur = reduced and (topts.fadeDuration * 0.5) or topts.fadeDuration
		local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local props: {[string]: any} = { GroupTransparency = 1 }
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
			cancelDismiss()
			dismissThread = task.delay(topts.inactivitySeconds, close)
			return
		end
		isOpen = true
		if fadeTween then fadeTween:Destroy(); fadeTween = nil end
		panel.Visible = true
		backdrop.Visible = true
		local reduced = UIKit.reducedMotion()
		local dur = reduced and (topts.fadeDuration * 0.5) or topts.fadeDuration
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
		dismissThread = task.delay(topts.inactivitySeconds, close)
	end

	backdrop.Activated:Connect(close)

	return {
		open   = open,
		close  = close,
		toggle = function() if isOpen then close() else open() end end,
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
function UIKit.isTouchDevice(): boolean
	local UIS = game:GetService("UserInputService")
	return UIS.TouchEnabled and not UIS.KeyboardEnabled
end

return UIKit
