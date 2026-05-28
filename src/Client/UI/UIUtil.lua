--!strict
-- UIUtil.lua
-- Helpers for building UI programmatically with consistent scaling. Every
-- ScreenGui this game creates uses an identical set of UIScale +
-- AspectRatio configuration so 380px phones, tablets, PCs, and Xbox UIs
-- all look right.
--
-- ====================================================================
-- DESIGN SYSTEM CONVENTIONS — read before touching feature UI
-- ====================================================================
-- 1. **Palette is the only color source.** Feature UI files MUST NOT call
--    `Color3.fromRGB(...)`. Use `UIUtil.Palette.<Name>` or one of the
--    lookups (`UIUtil.rarityColor`, `UIUtil.modifierColor`,
--    `UIUtil.tierPalette`). New named colors are added here, not inline.
--
-- 2. **Spacing / Radii / Typography are tokens.** Mirror tables live in
--    `GameConfig.UI` so designers can tune values in one place;
--    UIUtil re-exports them as `UIUtil.Spacing` / `UIUtil.Radii` /
--    `UIUtil.Typography` for ergonomic access.
--
-- 3. **DisplayOrder is centralised.** Every ScreenGui this UI layer
--    creates sets `gui.DisplayOrder = UIUtil.DisplayOrder.<role>`. The
--    canonical layering (low to high) is:
--      World  < HUD  < QuestTracker < Dialogue < CastMeter
--             < Modal < CatchReveal  < Tutorial
--    See `GameConfig.UI.DisplayOrder` for the exact integer values.
--
-- 4. **44px touch + 12px font floors.** `MinTouchPx` and `MinFontPx` are
--    enforced by `makePrimaryButton`/`makeSecondaryButton`/etc. and
--    asserted in Studio (`RunService:IsStudio()`).
--
-- 5. **Motion goes through MotionUtil.** Hover/press button feedback,
--    modal slide-ins, and any cosmetic animation MUST call
--    `MotionUtil.tween` or `MotionUtil.tweenOrSnap`. Never invoke
--    `TweenService:Create` directly from a feature UI module.
--
-- 6. **How to add a new modal.** Prefer template-driven modals:
--      local gui = TemplateLoader.spawn("MyFeature", { instanceName = "MyFeatureUI" })
--      -- layout in StarterGuiAssets; UIKit.integrateSpawnedGui runs on spawn.
--    Legacy programmatic shell:
--      local shell = UIUtil.makeModalShell({ name = "MyModal", title = "My Modal", onClose = onClose })
--      -- forwards to UIKit.ModalShell → ModalShell_Template via TemplateLoader.
--
-- ====================================================================
-- TEMPLATE INTEGRATION
-- ====================================================================
-- • Feature ScreenGuis live in src/StarterGuiAssets/*_Template.model.json.
-- • TemplateLoader.spawn() applies Meta (DisplayOrder, ResetOnSpawn) + UIKit.integrateSpawnedGui.
-- • Tokens: UIUtil.Palette / UIKit.Palette — never Color3.fromRGB in feature UI files.
-- • Motion: MotionUtil.tween / tweenOrSnap only; decoration respects ReducedMotion.
-- • Kept for gradual migration: makeScreenGui, makeLabel, make*Button, tierPalette, etc.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MotionUtil = require(game:GetService("ReplicatedStorage").Shared.Util.MotionUtil)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

local UIUtil = {}

local UI_CONFIG       = GameConfig.UI
local DESIGN_HEIGHT   = 720
local MIN_TOUCH_PX    = UI_CONFIG.MinTouchPx -- 44
local MIN_FONT_PX     = UI_CONFIG.MinFontPx  -- 12
local MIN_PHONE_WIDTH = 380

-- Design tokens — re-exported so callers can write
-- `UIUtil.Spacing.md` instead of `GameConfig.UI.Spacing.md`.
UIUtil.Spacing      = UI_CONFIG.Spacing
UIUtil.Radii        = UI_CONFIG.Radii
UIUtil.Typography   = UI_CONFIG.Typography
UIUtil.DisplayOrder = UI_CONFIG.DisplayOrder
UIUtil.Modal         = UI_CONFIG.Modal
UIUtil.Notification  = UI_CONFIG.Notification
UIUtil.MinTouchPx   = MIN_TOUCH_PX
UIUtil.MinFontPx    = MIN_FONT_PX

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

	-- Currency / rarity. Values mirror GameConfig.Fishing.RarityColors so
	-- cast meter zone tints, catch-reveal badges, and inventory cards all
	-- speak the same visual language. Update both if tuning.
	Gold         = Color3.fromRGB(220, 180, 88),
	GoldDeep     = Color3.fromRGB(180, 140, 60),
	Lure         = Color3.fromRGB(200, 124, 220),
	Common       = Color3.fromRGB(176, 182, 190),
	Uncommon     = Color3.fromRGB(120, 205, 135),
	Rare         = Color3.fromRGB( 95, 165, 240),
	Epic         = Color3.fromRGB(185, 120, 235),
	Legendary    = Color3.fromRGB(245, 180,  75),
	Mythic       = Color3.fromRGB(240,  95, 140),
	Divine       = Color3.fromRGB(255, 225, 150),

	-- Feedback
	Danger       = Color3.fromRGB(220, 100, 100),
	Success      = Color3.fromRGB(120, 200, 130),

	-- Chrome
	Shadow       = Color3.fromRGB(0, 0, 0),

	-- ViewportFrame lighting (thumbnail studio lights, not chrome). Used
	-- by inventory + catch-reveal fish previews. Centralised here so
	-- feature files never call Color3.fromRGB for light tints.
	ThumbLight   = Color3.fromRGB(210, 225, 255),
}

-- ====================================================================
-- RARITY + MODIFIER LOOKUPS — single source of truth
-- ====================================================================
-- Replaces local RARITY_COLORS / TIER_COLORS / MOD_COLORS tables that
-- used to be duplicated in CatchRevealUI and InventoryUI.
UIUtil.Palette.Rarity = {
	Common    = UIUtil.Palette.Common,
	Uncommon  = UIUtil.Palette.Uncommon,
	Rare      = UIUtil.Palette.Rare,
	Epic      = UIUtil.Palette.Epic,
	Legendary = UIUtil.Palette.Legendary,
	Mythic    = UIUtil.Palette.Mythic,
	Divine    = UIUtil.Palette.Divine,
}

-- Border ping-pong targets for the catch-reveal card's animated stroke
-- cycle. Only Legendary / Mythic / Divine have a cycle; absence means
-- the card's stroke stays solid at Palette.Rarity[rarity]. Decorative
-- only — skipped entirely under ReducedMotionEnabled.
UIUtil.Palette.RarityCycle = {
	Legendary = Color3.fromRGB(255, 220,  80),  -- gold ↔ bright amber
	Mythic    = Color3.fromRGB(240, 100, 100),  -- crimson ↔ coral
	Divine    = Color3.fromRGB(255, 200, 255),  -- icy blue ↔ lavender
}

-- Returns the chip / accent color for a rarity string. Falls back to
-- Common for unknown values so a missing rarity never blanks the UI.
function UIUtil.rarityColor(rarity: string?): Color3
	if not rarity then return UIUtil.Palette.Common end
	return UIUtil.Palette.Rarity[rarity] or UIUtil.Palette.Common
end

-- Modifier accent colors are sourced from GameConfig.ModifierGlow so
-- the glow ring (gameplay-tuned) and the inventory pill (UI-tuned)
-- never drift apart. Built once on require.
UIUtil.Palette.Modifiers = {}
do
	for id, glow in pairs(GameConfig.ModifierGlow) do
		UIUtil.Palette.Modifiers[id] = glow.Color
	end
end

-- Returns the accent color for a modifier id (e.g. "rainbow"). Falls
-- back to CreamSoft for an unknown id so legacy items still render.
function UIUtil.modifierColor(id: string?): Color3
	if not id then return UIUtil.Palette.CreamSoft end
	return UIUtil.Palette.Modifiers[id] or UIUtil.Palette.CreamSoft
end

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

	-- CurrentCamera is often nil during the first KnitStart tick; indexing it
	-- here used to throw and prevent HUD / modals from parenting to PlayerGui.
	local function refresh()
		local cam = workspace.CurrentCamera
		if not cam then
			scale.Scale = 1
			return
		end
		local size = cam.ViewportSize
		if size.X <= 1 or size.Y <= 1 then
			scale.Scale = 1
			return
		end
		local s = size.Y / DESIGN_HEIGHT
		if size.X < MIN_PHONE_WIDTH * (s / 1) then
			s *= MIN_PHONE_WIDTH / math.max(size.X, 1)
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

	gui.Enabled = true
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
-- Font + size are sourced from UIUtil.Typography so designers tune the
-- type ramp in GameConfig.UI without touching this file.
function UIUtil.makeLabel(text: string, style: string?, props: {[string]: any}?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = UIUtil.Palette.Cream
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center

	local token = UIUtil.Typography[style or "body"] or UIUtil.Typography.body
	lbl.Font = token.font
	lbl.TextSize = math.max(token.size, MIN_FONT_PX)
	if style == "subtitle" or style == "caption" then
		lbl.TextColor3 = UIUtil.Palette.CreamSoft
	end

	if props then
		for k, v in pairs(props) do (lbl :: any)[k] = v end
	end
	-- Studio-only floor guard: any explicit TextSize override that drops
	-- below the 12px accessibility floor is a bug. Catch it in dev.
	if RunService:IsStudio() and lbl.TextSize < MIN_FONT_PX then
		warn(("[UIUtil] TextSize %d below MinFontPx %d on label %q"):format(lbl.TextSize, MIN_FONT_PX, text))
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
	-- Hover/press feedback routes through MotionUtil so the snap-to-final
	-- color behavior under GuiService.ReducedMotionEnabled is honoured.
	local feedbackInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	btn.MouseEnter:Connect(function()
		MotionUtil.tweenOrSnap(btn, feedbackInfo, { BackgroundColor3 = hoverColor })
	end)
	btn.MouseLeave:Connect(function()
		MotionUtil.tweenOrSnap(btn, feedbackInfo, { BackgroundColor3 = restColor })
	end)
	btn.MouseButton1Down:Connect(function()
		MotionUtil.tweenOrSnap(btn, feedbackInfo, { BackgroundColor3 = pressColor })
	end)
	btn.MouseButton1Up:Connect(function()
		MotionUtil.tweenOrSnap(btn, feedbackInfo, { BackgroundColor3 = hoverColor })
	end)
	btn.Activated:Connect(onClick)
	-- No automatic drop shadow (was causing layout phantom slots).
	return btn
end

-- ====================================================================
-- BUTTON VARIANT WRAPPERS — enforce the 44px touch floor + variant
-- ====================================================================
-- Use these in feature UI instead of calling makeButton directly. They
-- lock in `variant`, set a minimum size of (Auto, MinTouchPx), and warn
-- in Studio if the caller shrinks the button below the floor.
local function _ensureTouchSize(props: {[string]: any})
	local size = props.Size
	if not size then
		props.Size = UDim2.fromOffset(180, MIN_TOUCH_PX)
		return
	end
	if size.Y.Scale == 0 and size.Y.Offset < MIN_TOUCH_PX then
		props.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale, MIN_TOUCH_PX)
	end
	if RunService:IsStudio() and size.Y.Scale == 0 and size.Y.Offset > 0 and size.Y.Offset < MIN_TOUCH_PX then
		warn(("[UIUtil] Button height %d below MinTouchPx %d"):format(size.Y.Offset, MIN_TOUCH_PX))
	end
end

local function _variantButton(variant: string, text: string, onClick: () -> (), props: {[string]: any}?): TextButton
	props = props or {}
	props.variant = variant
	_ensureTouchSize(props)
	return UIUtil.makeButton(text, onClick, props)
end

function UIUtil.makePrimaryButton(text, onClick, props)   return _variantButton("primary",   text, onClick, props) end
function UIUtil.makeSecondaryButton(text, onClick, props) return _variantButton("secondary", text, onClick, props) end
function UIUtil.makeGhostButton(text, onClick, props)     return _variantButton("ghost",     text, onClick, props) end
function UIUtil.makeDangerButton(text, onClick, props)    return _variantButton("danger",    text, onClick, props) end

-- ====================================================================
-- RARITY CHIP + MODIFIER PILL — small reusable badges
-- ====================================================================
-- A small rounded chip tinted by rarity. Used by InventoryUI,
-- CatchRevealUI, and MarketUI to display fish rarity at a glance.
function UIUtil.makeRarityChip(rarity: string, text: string?, props: {[string]: any}?): Frame
	props = props or {}
	local chip = Instance.new("Frame")
	chip.BorderSizePixel = 0
	chip.BackgroundColor3 = UIUtil.rarityColor(rarity)
	chip.BackgroundTransparency = 0.1
	chip.Size = UDim2.fromOffset(72, 22)
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, UIUtil.Radii.sm); corner.Parent = chip
	local stroke = Instance.new("UIStroke"); stroke.Color = UIUtil.Palette.Ink; stroke.Thickness = 1; stroke.Transparency = 0.5; stroke.Parent = chip

	local label = UIUtil.makeLabel(text or rarity, "caption", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIUtil.Palette.Ink,
		Parent = chip,
	})
	label.Font = Enum.Font.GothamBold

	for k, v in pairs(props) do (chip :: any)[k] = v end
	return chip
end

-- A tiny tinted pill labelled with the modifier's display name. Used on
-- inventory cards and the catch-reveal modifier row.
function UIUtil.makeModifierPill(id: string, displayName: string?, props: {[string]: any}?): Frame
	props = props or {}
	local pill = Instance.new("Frame")
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = UIUtil.modifierColor(id)
	pill.BackgroundTransparency = 0.2
	pill.Size = UDim2.fromOffset(72, 18)
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, UIUtil.Radii.sm); corner.Parent = pill
	local stroke = Instance.new("UIStroke"); stroke.Color = UIUtil.Palette.Ink; stroke.Thickness = 1; stroke.Transparency = 0.6; stroke.Parent = pill

	UIUtil.makeLabel(displayName or id, "caption", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UIUtil.Palette.Ink,
		Font = Enum.Font.GothamBold,
		Parent = pill,
	})

	for k, v in pairs(props) do (pill :: any)[k] = v end
	return pill
end

-- ====================================================================
-- CLOSE BUTTON — Gotham does not render Unicode "✕"; use ASCII "X".
-- ====================================================================
UIUtil.CloseGlyph = "X"

function UIUtil.makeCloseButton(onClick: () -> (), props: {[string]: any}?): TextButton
	props = props or {}
	local M = UIUtil.Modal
	local btn = Instance.new("TextButton")
	btn.Name = "Close"
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.BackgroundColor3 = UIUtil.Palette.Teal
	btn.Text = UIUtil.CloseGlyph
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = UIUtil.Palette.Cream
	btn.TextScaled = true
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -UIUtil.Spacing.md, 0.5, 0)
	btn.Size = UDim2.fromOffset(M.CloseButtonPx, M.CloseButtonPx)

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 22
	textConstraint.MinTextSize = 14
	textConstraint.Parent = btn

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIUtil.Radii.md)
	corner.Parent = btn

	for k, v in pairs(props) do (btn :: any)[k] = v end
	btn.Activated:Connect(onClick)
	return btn
end

-- ====================================================================
-- MODAL SHELL — one chrome, every full-screen modal
-- ====================================================================
-- Builds the backdrop + panel + header + close button used by every
-- modal in the game. Feature UI mounts its content into `shell.body`
-- and calls `shell.open()` / `shell.close()`.
--
-- opts:
--   name          string  — ScreenGui name (auto-dedupes; see makeScreenGui)
--   title         string  — header title text
--   onClose       function — called when user dismisses (tap backdrop / close / Esc)
--   parent        Instance? — defaults to LocalPlayer.PlayerGui
--   displayOrder  number?   — defaults to UIUtil.DisplayOrder.Modal
--   bodyPadding   number?   — defaults to GameConfig.UI.Modal.BodyPaddingPx
--   width         number?   — clamp panel max width (defaults to Modal.MaxWidthPx)
--   heightScale   number?   — panel height as scale of viewport (defaults to 0.78)
--
-- Returns:
--   { gui, scale, backdrop, panel, header, title, closeButton, body,
--     open(), close(), destroy() }
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
function UIUtil.makeModalShell(opts: {
	name: string,
	title: string,
	onClose: (() -> ())?,
	parent: Instance?,
	displayOrder: number?,
	bodyPadding: number?,
	width: number?,
	heightScale: number?,
}): ModalShell
	local UIKit = require(script.Parent.UIKit)
	local shell = UIKit.ModalShell({
		name = opts.name,
		title = opts.title,
		onClose = opts.onClose,
		parent = opts.parent,
		displayOrder = opts.displayOrder,
		bodyPadding = opts.bodyPadding,
		width = opts.width,
		heightScale = opts.heightScale,
	})
	return shell
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
