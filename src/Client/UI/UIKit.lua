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
--
-- Modal chrome: UIKit.ModalShell clones StarterGui.StarterGuiAssets.ModalShell_Template
-- via TemplateLoader (see src/StarterGuiAssets/). Layout/tween defaults live in the
-- template Meta folder; tokens and motion behavior stay in this module.
--
-- ====================================================================
-- TEMPLATE INTEGRATION
-- ====================================================================
-- • TemplateLoader.spawn() clones StarterGuiAssets; call UIKit.integrateSpawnedGui(gui)
--   after spawn (TemplateLoader does this automatically) for accessibility + button feedback.
-- • Layout lives in .model.json / Studio templates — avoid Color3.fromRGB in templates;
--   apply chrome via UIKit.applySpawnedChrome(gui) and row/tile via applyCardStyle /
--   applyRarityChip at bind time.
-- • ModalShell(opts) is a thin TemplateLoader.spawn("ModalShell") wrapper; mount feature
--   content in shell.body. UIUtil.makeModalShell forwards here for legacy callers.
-- • Decoration (hover tweens, rarity border cycle) must respect UIKit.reducedMotion().
-- ====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local GuiService    = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local GameConfig         = require(ReplicatedStorage.Shared.Config.GameConfig)
local FishMutations      = require(ReplicatedStorage.Shared.Util.FishMutations)
local MotionUtil         = require(ReplicatedStorage.Shared.Util.MotionUtil)
local ScreenGuiAutoScale = require(script.Parent.ScreenGuiAutoScale)
local TemplateLoader     = require(script.Parent.TemplateLoader)

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
-- TEMPLATE INTEGRATION — spawn-time styling + accessibility
-- ====================================================================

local _FEEDBACK_ATTR = "TotButtonFeedback"

function UIKit.attachButtonFeedback(btn: GuiButton, restColor: Color3?)
	local rest = restColor or btn.BackgroundColor3
	local pressed = rest:Lerp(Color3.new(0, 0, 0), 0.14)
	local hover = rest:Lerp(Color3.new(1, 1, 1), 0.08)
	local info = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	btn:SetAttribute(_FEEDBACK_ATTR, true)

	btn.MouseEnter:Connect(function()
		MotionUtil.tweenOrSnap(btn, info, { BackgroundColor3 = hover })
	end)
	btn.MouseLeave:Connect(function()
		MotionUtil.tweenOrSnap(btn, info, { BackgroundColor3 = rest })
	end)
	btn.MouseButton1Down:Connect(function()
		MotionUtil.tweenOrSnap(btn, info, { BackgroundColor3 = pressed })
	end)
	btn.MouseButton1Up:Connect(function()
		MotionUtil.tweenOrSnap(btn, info, { BackgroundColor3 = hover })
	end)
end

export type CardStyleName = "default" | "inset" | "dark" | "teal" | "teal-inset" | "teal-dark"

-- Applies card surface colors to an existing template Frame (UICorner/UIStroke optional).
function UIKit.applyCardStyle(card: Frame, style: CardStyleName?)
	local UIUtil = require(script.Parent.UIUtil)
	local P = UIUtil.Palette
	local styleName = style or "teal"

	local bg: Color3
	local strokeColor: Color3
	if styleName == "inset" then
		bg = UIKit.Palette.ParchmentWash
		strokeColor = UIKit.Palette.BorderLight
	elseif styleName == "dark" then
		bg = UIKit.Palette.MintDeep
		strokeColor = UIKit.Palette.MintDark
	elseif styleName == "teal-inset" then
		bg = P.Teal
		strokeColor = P.TealDeeper
	elseif styleName == "teal-dark" then
		bg = P.TealDeeper
		strokeColor = P.TealDeeper
	elseif styleName == "default" then
		bg = UIKit.Palette.ParchmentDeep
		strokeColor = UIKit.Palette.BorderMid
	else
		bg = P.Teal
		strokeColor = P.TealDeeper
	end

	card.BackgroundColor3 = bg
	local corner = card:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, UIKit.Radii.md)
		corner.Parent = card
	end
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.2
		stroke.Transparency = 0.25
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
	end
	stroke.Color = strokeColor
end

-- Tints an existing template rarity chip (Frame + TextLabel child).
function UIKit.applyRarityChip(chip: Frame, rarity: string, text: string?)
	chip.BackgroundColor3 = UIKit.rarityColor(rarity)
	chip.BackgroundTransparency = 0.08

	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Transparency = 0.55
		stroke.Parent = chip
	end
	stroke.Color = UIKit.Palette.Ink

	local lbl = chip:FindFirstChildWhichIsA("TextLabel", true)
	if lbl then
		lbl.Text = text or rarity
		lbl.TextScaled = false
		lbl.TextSize = math.max(UIKit.Typography.caption.size, UIKit.MinFontPx)
		lbl.TextColor3 = UIKit.Palette.Ink
	end
end

local function _enforceMinTouch(guiObj: GuiObject)
	if guiObj.Size.Y.Scale ~= 0 or guiObj.Size.X.Scale ~= 0 then
		return
	end
	local w = guiObj.Size.X.Offset
	local h = guiObj.Size.Y.Offset
	local newW = if w > 0 and w < UIKit.MinTouchPx then UIKit.MinTouchPx else w
	local newH = if h > 0 and h < UIKit.MinTouchPx then UIKit.MinTouchPx else h
	if newW ~= w or newH ~= h then
		guiObj.Size = UDim2.new(0, newW, 0, newH)
	end
end

-- Applies modal/admin chrome from Meta.ThemeKey (modal-teal | modal-parchment | admin).
function UIKit.applySpawnedChrome(gui: ScreenGui)
	local UIUtil = require(script.Parent.UIUtil)
	local P = UIUtil.Palette

	local theme = "modal-teal"
	local meta = gui:FindFirstChild("Meta")
	if meta and meta:IsA("Folder") then
		local themeVal = meta:FindFirstChild("ThemeKey")
		if themeVal and themeVal:IsA("StringValue") and themeVal.Value ~= "" then
			theme = themeVal.Value
		end
	end

	local backdrop = gui:FindFirstChild("Backdrop")
	if backdrop and backdrop:IsA("TextButton") then
		backdrop.BackgroundColor3 = P.Shadow
	end

	local panel = gui:FindFirstChild("Panel")
	if not panel or not panel:IsA("Frame") then
		return
	end

	if theme == "modal-parchment" then
		panel.BackgroundColor3 = UIKit.Palette.Parchment
		local header = panel:FindFirstChild("Header")
		if header and header:IsA("Frame") then
			header.BackgroundColor3 = UIKit.Palette.ParchmentDeep
		end
		local stroke = panel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = UIKit.Palette.BorderMid
		end
	elseif theme == "admin" then
		panel.BackgroundColor3 = P.TealDeeper
		local toggle = gui:FindFirstChild("ToggleButton")
		if toggle and toggle:IsA("TextButton") then
			toggle.BackgroundColor3 = P.Teal
			toggle.TextColor3 = P.Cream
		end
	else
		panel.BackgroundColor3 = P.TealDark
		local header = panel:FindFirstChild("Header")
		if header and header:IsA("Frame") then
			header.BackgroundColor3 = P.TealDeeper
			local title = header:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.TextColor3 = P.Cream
			end
			local closeBtn = header:FindFirstChild("Close")
			if closeBtn and closeBtn:IsA("TextButton") then
				closeBtn.BackgroundColor3 = P.Wood
				closeBtn.TextColor3 = P.Cream
			end
		end
		local stroke = panel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = P.TealDeeper
		end
	end
end

-- Apply accessibility + feedback to a single cloned interactive (template rows).
function UIKit.prepareInteractive(obj: GuiObject, selectionOrder: number?)
	if obj:IsA("TextLabel") then
		if obj.TextScaled then
			obj.TextScaled = false
		end
		if obj.TextSize > 0 and obj.TextSize < UIKit.MinFontPx then
			obj.TextSize = UIKit.MinFontPx
		end
		return
	end
	if not obj:IsA("TextButton") and not obj:IsA("ImageButton") then
		return
	end
	obj.Selectable = true
	if selectionOrder then
		obj.SelectionOrder = selectionOrder
	end
	_enforceMinTouch(obj)
	if obj:IsA("TextButton") and not obj:GetAttribute(_FEEDBACK_ATTR) then
		UIKit.attachButtonFeedback(obj)
	end
end

-- Post-spawn pass: chrome, 44px touch floor, 12px fonts, Selectable + SelectionOrder, button feedback.
function UIKit.integrateSpawnedGui(gui: ScreenGui)
	UIKit.applySpawnedChrome(gui)

	local selectionOrder = 1
	for _, desc in ipairs(gui:GetDescendants()) do
		if desc:IsA("TextLabel") then
			if desc.TextScaled then
				desc.TextScaled = false
			end
			if desc.TextSize > 0 and desc.TextSize < UIKit.MinFontPx then
				desc.TextSize = UIKit.MinFontPx
			end
		elseif desc:IsA("TextButton") or desc:IsA("ImageButton") then
			desc.Selectable = true
			desc.SelectionOrder = selectionOrder
			selectionOrder += 1
			_enforceMinTouch(desc)
			if desc:IsA("TextButton") and not desc:GetAttribute(_FEEDBACK_ATTR) then
				UIKit.attachButtonFeedback(desc)
			end
		end
	end
end

-- ====================================================================
-- SCREEN GUI FACTORY
-- ====================================================================
-- Identical logic to UIUtil.makeScreenGui — included here so screens
-- rebuilt against UIKit have no UIUtil dependency for scaffolding.
-- opts.respectTopbar=true shifts Y=0 below the Roblox topbar chrome.
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

	local scale = ScreenGuiAutoScale.apply(gui)
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
-- ACTION BUTTON SKIN (HUD action-bar tiles)
-- ====================================================================
-- Hover / press feedback via MotionUtil (ReducedMotion-aware). Layout lives
-- in StarterGui templates; call after TemplateLoader.spawn resolves buttons.

function UIKit.skinActionButton(btn: GuiButton, restColor: Color3?)
	local rest = restColor or btn.BackgroundColor3
	local pressed = rest:Lerp(Color3.new(0, 0, 0), 0.22)
	local hover = rest:Lerp(Color3.new(1, 1, 1), 0.08)
	local info = TweenInfo.new(0.08)

	btn.MouseEnter:Connect(function()
		MotionUtil.tweenOrSnap(btn, info, { BackgroundColor3 = hover })
	end)
	btn.MouseLeave:Connect(function()
		MotionUtil.tweenOrSnap(btn, info, { BackgroundColor3 = rest })
	end)
	btn.MouseButton1Down:Connect(function()
		MotionUtil.tweenOrSnap(btn, info, { BackgroundColor3 = pressed })
	end)
	btn.MouseButton1Up:Connect(function()
		MotionUtil.tweenOrSnap(btn, info, { BackgroundColor3 = hover })
	end)
end

-- Gold upgrade CTA — visible-transformation pillar (HarborEdit global Upgrade mode).
function UIKit.skinUpgradeButton(btn: GuiButton, restColor: Color3?)
	local P = UIKit.Palette
	local rest = restColor or P.Gold
	UIKit.skinActionButton(btn, rest)
	local stroke = btn:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = btn
	end
	stroke.Color = P.Gold
	stroke.Thickness = 2
	stroke.Transparency = 0.15
end

export type BuildingThumbResult = { clone: Model? }

function UIKit.attachBuildingThumb(viewport: ViewportFrame, kind: string, tier: number, footprint: {number}?): BuildingThumbResult
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	local BuildingAssetUtil = require(game:GetService("ReplicatedStorage").Shared.Util.BuildingAssetUtil)
	local BuildingModelFactory = require(game:GetService("ReplicatedStorage").Shared.Util.BuildingModelFactory)
	local tmpl = BuildingAssetUtil.getVisualTemplate(kind, tier)
	local clone: Model?
	if tmpl then
		clone = tmpl:Clone()
	else
		clone = BuildingModelFactory.build(kind, tier, footprint or { 2, 2 })
	end
	local wm = Instance.new("WorldModel")
	wm.Parent = viewport
	clone.Parent = wm
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local scaleTarget = 1.4
	local ok, pivot, ext = pcall(function(): (CFrame, Vector3)
		return clone:GetBoundingBox()
	end)
	if ok and ext then
		local maxDim = math.max(ext.X, ext.Y, ext.Z)
		if maxDim > 0.01 then
			pcall(function() clone:ScaleTo(scaleTarget / maxDim) end)
		end
	end
	local tcam = Instance.new("Camera")
	tcam.FieldOfView = 40
	viewport.CurrentCamera = tcam
	tcam.Parent = viewport
	if ok and pivot then
		local md = math.max(ext.X, ext.Y, ext.Z)
		local dist = math.max(md * 1.5, 4)
		tcam.CFrame = CFrame.lookAt(
			pivot.Position + Vector3.new(dist * 0.65, dist * 0.35, dist * 0.65),
			pivot.Position
		)
	end
	return { clone = clone }
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
-- TOGGLE  (settings switches — mute, future on/off prefs)
-- ====================================================================
-- UIKit.Toggle(opts) -> { frame, set(value), get(), instance }
--   opts.value    boolean        starting state (default false)
--   opts.onChanged (boolean)->()  fired on user tap (not on programmatic set)
--   opts.label    string?         optional left-aligned label inside the row
--   [any other Frame property applied to the row]
--
-- 44px-tall row; the pill track is the 44px hit target. On = Mint, off =
-- BorderMid (neutral — never red/green, per cozy rules). Knob slides via
-- MotionUtil so ReducedMotion snaps it.

export type Toggle = {
	frame: Frame,
	set: (value: boolean) -> (),
	get: () -> boolean,
	instance: TextButton,
}

function UIKit.Toggle(opts: {[string]: any}?): Toggle
	opts = opts or {}
	local o = opts :: {[string]: any}
	local value    = o.value == true
	local onChanged = o.onChanged
	local labelText = o.label
	o.value = nil
	o.onChanged = nil
	o.label = nil

	local P = UIKit.Palette
	local TRACK_W = 64
	local KNOB = UIKit.MinTouchPx - 12
	local KNOB_HALF = KNOB / 2
	local INSET = (UIKit.MinTouchPx - KNOB) / 2

	local row = Instance.new("Frame")
	row.Name = "Toggle"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, UIKit.MinTouchPx)

	if labelText then
		UIKit.Label(labelText, "body", {
			Parent = row,
			Size = UDim2.new(1, -(TRACK_W + UIKit.Spacing.md), 1, 0),
			Position = UDim2.fromScale(0, 0),
		})
	end

	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.Text = ""
	track.AutoButtonColor = false
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, 0, 0.5, 0)
	track.Size = UDim2.fromOffset(TRACK_W, UIKit.MinTouchPx)
	track.BackgroundColor3 = if value then P.Mint else P.BorderMid
	track.Parent = row
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, UIKit.Radii.pill)
	tc.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BorderSizePixel = 0
	knob.BackgroundColor3 = P.Cream
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.Parent = track
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0, UIKit.Radii.pill)
	kc.Parent = knob

	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function knobPos(on: boolean): UDim2
		return if on
			then UDim2.new(1, -(INSET + KNOB_HALF), 0.5, 0)
			else UDim2.new(0, INSET + KNOB_HALF, 0.5, 0)
	end
	knob.Position = knobPos(value)

	local function render()
		MotionUtil.tweenOrSnap(track, info, { BackgroundColor3 = if value then P.Mint else P.BorderMid })
		MotionUtil.tweenOrSnap(knob, info, { Position = knobPos(value) })
	end

	track.Activated:Connect(function()
		value = not value
		render()
		if onChanged then onChanged(value) end
	end)

	for k, v in pairs(o) do (row :: any)[k] = v end

	return {
		frame = row,
		instance = track,
		get = function() return value end,
		set = function(v: boolean)
			value = v == true
			render()
		end,
	}
end

-- ====================================================================
-- SLIDER  (continuous value — master volume, future ranges)
-- ====================================================================
-- UIKit.Slider(opts) -> { frame, set(value), get(), instance }
--   opts.value    number   starting value (clamped to [min,max])
--   opts.min      number?  default 0
--   opts.max      number?  default 1
--   opts.step     number?  snap granularity (e.g. 0.05); nil = continuous
--   opts.onChanged (number)->()  fired during drag (not on programmatic set)
--   [any other Frame property applied to the row]
--
-- 44px-tall row with a 44px thumb (thumb-only friendly). Track Mint fill on
-- BorderMid rail, Amber thumb. Drag captured via UserInputService.

export type Slider = {
	frame: Frame,
	set: (value: number) -> (),
	get: () -> number,
	instance: TextButton,
}

function UIKit.Slider(opts: {[string]: any}?): Slider
	opts = opts or {}
	local o = opts :: {[string]: any}
	local minV = o.min or 0
	local maxV = o.max or 1
	local step = o.step
	local value = math.clamp(o.value or minV, minV, maxV)
	local onChanged = o.onChanged
	o.min = nil
	o.max = nil
	o.step = nil
	o.value = nil
	o.onChanged = nil

	local P = UIKit.Palette
	local TH = UIKit.MinTouchPx

	local row = Instance.new("Frame")
	row.Name = "Slider"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, TH)

	-- Tap/drag anywhere on the row jumps + grabs.
	local hit = Instance.new("TextButton")
	hit.Name = "HitArea"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BorderSizePixel = 0
	track.BackgroundColor3 = P.BorderMid
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, TH / 2, 0.5, 0)
	track.Size = UDim2.new(1, -TH, 0, 8)
	track.ZIndex = 1
	track.Parent = row
	local trc = Instance.new("UICorner")
	trc.CornerRadius = UDim.new(0, UIKit.Radii.pill)
	trc.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = P.Mint
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 1
	fill.Parent = track
	local flc = Instance.new("UICorner")
	flc.CornerRadius = UDim.new(0, UIKit.Radii.pill)
	flc.Parent = fill

	local thumb = Instance.new("TextButton")
	thumb.Name = "Thumb"
	thumb.Text = ""
	thumb.AutoButtonColor = false
	thumb.BorderSizePixel = 0
	thumb.BackgroundColor3 = P.Amber
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Size = UDim2.fromOffset(TH, TH)
	thumb.ZIndex = 2
	thumb.Parent = row
	local thc = Instance.new("UICorner")
	thc.CornerRadius = UDim.new(0, UIKit.Radii.pill)
	thc.Parent = thumb
	local ths = Instance.new("UIStroke")
	ths.Color = P.AmberDeep
	ths.Thickness = 1.5
	ths.Transparency = 0.2
	ths.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ths.Parent = thumb

	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function frac(): number
		if maxV <= minV then return 0 end
		return (value - minV) / (maxV - minV)
	end
	-- Thumb centre tracks the inset track: px = TH/2 + f*(rowW - TH).
	local function thumbPos(f: number): UDim2
		return UDim2.new(f, TH * (0.5 - f), 0.5, 0)
	end

	local function paint(animate: boolean)
		local f = frac()
		if animate then
			MotionUtil.tweenOrSnap(thumb, info, { Position = thumbPos(f) })
			MotionUtil.tweenOrSnap(fill, info, { Size = UDim2.fromScale(f, 1) })
		else
			thumb.Position = thumbPos(f)
			fill.Size = UDim2.fromScale(f, 1)
		end
	end
	paint(false)

	local function applyFromX(px: number)
		local tx = track.AbsolutePosition.X
		local tw = track.AbsoluteSize.X
		if tw <= 0 then return end
		local f = math.clamp((px - tx) / tw, 0, 1)
		local raw = minV + f * (maxV - minV)
		if step and step > 0 then
			raw = math.floor((raw / step) + 0.5) * step
		end
		raw = math.clamp(raw, minV, maxV)
		if raw ~= value then
			value = raw
			paint(false)
			if onChanged then onChanged(value) end
		end
	end

	local dragging = false
	local function isPointer(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			applyFromX(input.Position.X)
		end
	end)
	thumb.InputBegan:Connect(function(input)
		if isPointer(input) then dragging = true end
	end)

	local moveConn = UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			applyFromX(input.Position.X)
		end
	end)
	local endConn = UserInputService.InputEnded:Connect(function(input)
		if isPointer(input) then dragging = false end
	end)

	-- Disconnect the global UIS listeners when the slider leaves the tree.
	row.AncestryChanged:Connect(function()
		if not row:IsDescendantOf(game) then
			moveConn:Disconnect()
			endConn:Disconnect()
		end
	end)

	for k, v in pairs(o) do (row :: any)[k] = v end

	return {
		frame = row,
		instance = thumb,
		get = function() return value end,
		set = function(v: number)
			value = math.clamp(v, minV, maxV)
			paint(true)
		end,
	}
end

-- ====================================================================
-- COLLAPSIBLE CARD  (settings sections)
-- ====================================================================
-- UIKit.CollapsibleCard(opts) -> { card, body, header, setOpen, toggle, isOpen }
--   opts.title     string    header text
--   opts.startOpen boolean?  default true
--   [any other Frame property applied to the card]
--
-- A UIKit.Card with a 44px header button + chevron and a body the caller
-- mounts children into. Card auto-sizes (UIListLayout + AutomaticSize.Y).
-- Chevron rotates via MotionUtil (snaps under ReducedMotion); body toggles
-- visibility (no opacity flashing).

export type CollapsibleCard = {
	card: Frame,
	body: Frame,
	header: TextButton,
	setOpen: (open: boolean) -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
}

function UIKit.CollapsibleCard(opts: {[string]: any}?): CollapsibleCard
	opts = opts or {}
	local o = opts :: {[string]: any}
	local title = o.title or ""
	local startOpen = o.startOpen ~= false
	o.title = nil
	o.startOpen = nil

	local P = UIKit.Palette

	local card = UIKit.Card({ style = "default" })
	card.Name = "CollapsibleCard"
	card.AutomaticSize = Enum.AutomaticSize.Y

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, UIKit.Spacing.sm)
	pad.PaddingBottom = UDim.new(0, UIKit.Spacing.sm)
	pad.PaddingLeft = UDim.new(0, UIKit.Spacing.md)
	pad.PaddingRight = UDim.new(0, UIKit.Spacing.md)
	pad.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UIKit.Spacing.sm)
	layout.Parent = card

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.Text = ""
	header.AutoButtonColor = false
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, UIKit.MinTouchPx)
	header.LayoutOrder = 0
	header.Parent = card

	UIKit.Label(title, "subtitle", {
		Parent = header,
		Size = UDim2.new(1, -28, 1, 0),
		Position = UDim2.fromScale(0, 0),
		TextColor3 = P.Ink,
	})

	local chevron = UIKit.Label("▾", "subtitle", {
		Parent = header,
		Size = UDim2.fromOffset(24, UIKit.MinTouchPx),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = P.InkSoft,
	})

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	body.Parent = card

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Vertical
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, UIKit.Spacing.sm)
	bodyLayout.Parent = body

	local info = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local isOpen = startOpen

	local function render()
		body.Visible = isOpen
		-- Chevron points down when open, rotates to point right when closed.
		MotionUtil.tweenOrSnap(chevron, info, { Rotation = if isOpen then 0 else -90 })
	end
	render()

	header.Activated:Connect(function()
		isOpen = not isOpen
		render()
	end)

	for k, v in pairs(o) do (card :: any)[k] = v end

	return {
		card = card,
		body = body,
		header = header,
		isOpen = function() return isOpen end,
		setOpen = function(open: boolean)
			isOpen = open
			render()
		end,
		toggle = function()
			isOpen = not isOpen
			render()
		end,
	}
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
-- FISH THUMBNAIL (ViewportFrame)
-- ====================================================================
-- Clones ReplicatedStorage.Assets.Fish[speciesId] into a ViewportFrame,
-- scales to fit, applies modifier VFX, and frames a Camera. Used by
-- InventoryUI, CatchRevealUI, MarketUI.

export type FishThumbResult = {
	clone: Model?,
	initPivot: CFrame?,
}

function UIKit.attachFishThumb(
	viewport: ViewportFrame,
	speciesId: string,
	opts: {
		modifiers: {string}?,
		scaleTarget: number?,
		fieldOfView: number?,
	}?
): FishThumbResult
	opts = opts or {}
	local mods = opts.modifiers or {}
	local scaleTarget = opts.scaleTarget or 2.2
	local fieldOfView = opts.fieldOfView or 40

	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	local fishAssets = ReplicatedStorage:FindFirstChild("Assets")
		and (ReplicatedStorage.Assets :: Instance):FindFirstChild("Fish")
	local tmpl = fishAssets and fishAssets:FindFirstChild(speciesId)
	if not tmpl or not tmpl:IsA("Model") then
		return { clone = nil, initPivot = nil }
	end

	local wm = Instance.new("WorldModel")
	wm.Parent = viewport
	local clone = tmpl:Clone()
	clone.Parent = wm

	local thumbAnchor: BasePart? = clone.PrimaryPart
		and clone.PrimaryPart:IsA("BasePart") and (clone.PrimaryPart :: BasePart)
		or nil
	if not thumbAnchor then
		local named = clone:FindFirstChild("body_geom", true)
		if named and named:IsA("BasePart") then
			thumbAnchor = named :: BasePart
		end
	end
	if not thumbAnchor then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				thumbAnchor = d :: BasePart
				break
			end
		end
	end

	if thumbAnchor then
		local okBB, _pivotBB, ext = pcall(function(): (CFrame, Vector3)
			return clone:GetBoundingBox()
		end)
		if okBB and ext then
			local maxDim = math.max(ext.X, ext.Y, ext.Z)
			if maxDim > 0.01 then
				pcall(function()
					clone:ScaleTo(scaleTarget / maxDim)
				end)
			end
		end
		if #mods > 0 then
			FishMutations.attach(thumbAnchor, mods, { viewport = true, intensity = 1 })
		end
	end

	local tcam = Instance.new("Camera")
	tcam.FieldOfView = fieldOfView
	viewport.CurrentCamera = tcam
	tcam.Parent = viewport

	local initPivot: CFrame? = nil
	local ok, pivot, ext = pcall(function(): (CFrame, Vector3)
		return clone:GetBoundingBox()
	end)
	if ok and pivot then
		local md = math.max(ext.X, ext.Y, ext.Z)
		local dist = math.max(md * 1.5, 4)
		tcam.CFrame = CFrame.lookAt(
			pivot.Position + Vector3.new(dist * 0.7, dist * 0.4, dist * 0.7),
			pivot.Position
		)
		initPivot = clone:GetPivot()
	end

	return { clone = clone, initPivot = initPivot }
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
-- MODAL SHELL (StarterGui template: ModalShell_Template.rbxmx)
-- ====================================================================
-- Standard full-screen modal chrome: backdrop + panel + header + close.
-- Clones ModalShell_Template via TemplateLoader; wires behavior only.
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
	local M = UIKit.Modal

	local gui = TemplateLoader.spawn("ModalShell", {
		parent = opts.parent,
		instanceName = opts.name,
	})
	if opts.displayOrder then
		gui.DisplayOrder = opts.displayOrder
	end

	local scale = gui:WaitForChild("AutoScale") :: UIScale
	local backdrop = gui:WaitForChild("Backdrop") :: TextButton
	local panel = gui:WaitForChild("Panel") :: Frame
	local header = panel:WaitForChild("Header") :: Frame
	local titleLbl = header:WaitForChild("Title") :: TextLabel
	local closeBtn = header:WaitForChild("Close") :: TextButton
	local body = panel:WaitForChild("Body") :: Frame

	titleLbl.Text = opts.title or ""
	panel.Size = UDim2.new(0.92, 0, opts.heightScale or 0.78, 0)

	local sizeCap = panel:FindFirstChildOfClass("UISizeConstraint")
	if sizeCap then
		sizeCap.MaxSize = Vector2.new(opts.width or M.MaxWidthPx, math.huge)
	end

	local pad = body:FindFirstChildOfClass("UIPadding")
	if pad then
		local p = opts.bodyPadding or M.BodyPaddingPx
		pad.PaddingLeft   = UDim.new(0, p)
		pad.PaddingRight  = UDim.new(0, p)
		pad.PaddingTop    = UDim.new(0, p)
		pad.PaddingBottom = UDim.new(0, p)
	end

	local fadeDuration = M.FadeDuration
	local slideOffsetPx = M.SlideOffsetPx
	local meta = gui:FindFirstChild("Meta")
	if meta and meta:IsA("Folder") then
		local fadeVal = meta:FindFirstChild("FadeDuration")
		if fadeVal and fadeVal:IsA("NumberValue") then
			fadeDuration = fadeVal.Value
		end
		local slideVal = meta:FindFirstChild("SlideOffsetPx")
		if slideVal and slideVal:IsA("NumberValue") then
			slideOffsetPx = slideVal.Value
		end
	end

	local isOpen = false
	local closed = false
	local restPos = panel.Position
	local fromPos = UDim2.new(restPos.X.Scale, restPos.X.Offset,
		restPos.Y.Scale, restPos.Y.Offset + slideOffsetPx)
	local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
			MotionUtil.tweenOrSnap(panel, fadeInfo, { BackgroundTransparency = 0, Position = restPos })
		end
	end

	close = function()
		if not isOpen or closed then return end
		isOpen = false
		if opts.onClose then opts.onClose() end
	end

	local function destroy()
		closed = true
		if gui and gui.Parent then gui:Destroy() end
	end

	backdrop.Activated:Connect(close)
	closeBtn.Activated:Connect(close)
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
