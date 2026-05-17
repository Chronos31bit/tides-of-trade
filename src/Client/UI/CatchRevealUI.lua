--!strict
-- CatchRevealUI.lua
-- The "you caught X" reveal card. Slides up from the bottom of the screen,
-- holds for 3 seconds, slides back down (or fades if reduced motion). Tap
-- the card to dismiss early. Tier-colored 3px border; Mythics get a slow
-- amber↔coral color cycle for the duration of the card's life.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIUtil      = require(script.Parent.UIUtil)
local MotionUtil  = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig  = require(ReplicatedStorage.Shared.Config.GameConfig)

local CatchRevealUI = {}

local P = UIUtil.Palette
local FT = GameConfig.Fishing.FeelTuning

-- ====================================================================
-- TIER COLORS — single source of truth for the rarity → color mapping.
-- Used by the border, badge fill, and (for mythic) the color cycle.
-- ====================================================================
local TIER_COLORS = {
	Common   = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB( 70, 200, 110),
	Rare     = Color3.fromRGB( 60, 140, 240),
	Mythic   = Color3.fromRGB(240, 160,  40),
}
-- Mythic cycle target — the *other* color the border lerps to when on a
-- mythic catch. Coral pairs with amber for a fire/treasure vibe.
local MYTHIC_CYCLE_TARGET = Color3.fromRGB(240, 100, 100)

export type CatchPayload = {
	fish: { displayName: string, rarity: string, basePrice: number, id: string? },
	weightKg: number,
	coinsEarned: number?,   -- instant coin bonus from perfect reel (0 if not perfect)
	xpGained: number?,
	perfect: boolean?,      -- reel was perfect-zone (triggers coin bonus)
	castPerfect: boolean?,  -- cast marker hit the inner gold strip (triggers weight bonus)
}

export type RevealHandle = {
	gui: ScreenGui,
	dismiss: () -> (),
}

-- Convert a snake_case species id to Title Case ("harbor_mackerel" -> "Harbor Mackerel").
local function titleCase(s: string?): string
	if not s then return "" end
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

function CatchRevealUI.show(payload: CatchPayload): RevealHandle
	local gui = UIUtil.makeScreenGui("CatchReveal", nil, { respectTopbar = true })

	local rarity = payload.fish.rarity or "Common"
	local tierColor = TIER_COLORS[rarity] or TIER_COLORS.Common
	local perfectColor = TIER_COLORS.Mythic  -- prompt says perfect always uses mythic amber

	-- ----------------------------------------------------------------
	-- CARD — solid teal panel, tier-colored stroke, rounded.
	-- ----------------------------------------------------------------
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	-- Starts offscreen below; positioned to slide in.
	card.Position = UDim2.new(0.5, 0, 1, 240)
	card.Size = UDim2.fromOffset(360, 132)
	card.BackgroundColor3 = P.TealDark
	card.BorderSizePixel = 0
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 14); corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = tierColor
	stroke.Thickness = 3
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	card.Parent = gui

	-- A TextButton overlay so the whole card responds to taps without
	-- intercepting per-element clicks (we have no inner clickable bits).
	local tapCatcher = Instance.new("TextButton")
	tapCatcher.BackgroundTransparency = 1
	tapCatcher.Text = ""
	tapCatcher.Size = UDim2.fromScale(1, 1)
	tapCatcher.ZIndex = 5
	tapCatcher.Parent = card

	-- ----------------------------------------------------------------
	-- ICON PLACEHOLDER — 80x80 dark square in the top-left.
	-- TODO: when AssetIds.Images.FishIconSheet is populated, set the
	-- ImageRectOffset/Size to the species' slot in the sheet.
	-- ----------------------------------------------------------------
	local icon = Instance.new("Frame")
	icon.Name = "IconPlaceholder"
	icon.Position = UDim2.new(0, 16, 0, 16)
	icon.Size = UDim2.fromOffset(80, 80)
	icon.BackgroundColor3 = P.TealDeeper
	icon.BorderSizePixel = 0
	local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 10); ic.Parent = icon
	icon.Parent = card

	-- ----------------------------------------------------------------
	-- TEXT BLOCK
	-- ----------------------------------------------------------------
	-- Perfect label — shows above the fish name whenever either phase was perfect.
	local nameTopY = 12
	local reelPerfect = payload.perfect == true
	local castPerfect = payload.castPerfect == true
	if reelPerfect or castPerfect then
		local perfectLbl = Instance.new("TextLabel")
		perfectLbl.BackgroundTransparency = 1
		perfectLbl.Position = UDim2.new(0, 108, 0, 8)
		perfectLbl.Size = UDim2.new(1, -120, 0, 14)
		perfectLbl.Font = Enum.Font.GothamBlack
		perfectLbl.TextSize = 12
		perfectLbl.TextColor3 = perfectColor
		perfectLbl.TextXAlignment = Enum.TextXAlignment.Left
		if reelPerfect and castPerfect then
			perfectLbl.Text = "PERFECT CATCH"      -- both phases nailed
		elseif reelPerfect then
			perfectLbl.Text = "PERFECT REEL"       -- reel mini-game only
		else
			perfectLbl.Text = "PRECISION CAST"     -- cast timing only
		end
		perfectLbl.Parent = card
		nameTopY = 24
	end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Position = UDim2.new(0, 108, 0, nameTopY)
	nameLbl.Size = UDim2.new(1, -120, 0, 28)
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 24
	nameLbl.TextColor3 = P.Cream
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = payload.fish.displayName or titleCase(payload.fish.id)
	nameLbl.Parent = card

	local weightLbl = Instance.new("TextLabel")
	weightLbl.BackgroundTransparency = 1
	weightLbl.Position = UDim2.new(0, 108, 0, nameTopY + 30)
	weightLbl.Size = UDim2.new(1, -120, 0, 18)
	weightLbl.Font = Enum.Font.GothamMedium
	weightLbl.TextSize = 16
	weightLbl.TextColor3 = P.CreamSoft
	weightLbl.TextXAlignment = Enum.TextXAlignment.Left
	weightLbl.Text = ("%.1f kg"):format(payload.weightKg or 0)
	weightLbl.Parent = card

	-- Coin label — shows the instant perfect-reel bonus if earned, otherwise
	-- shows the fish's market sell value as a reference.
	local coinLbl = Instance.new("TextLabel")
	coinLbl.BackgroundTransparency = 1
	coinLbl.AnchorPoint = Vector2.new(0, 1)
	coinLbl.Position = UDim2.new(0, 108, 1, -14)
	coinLbl.Size = UDim2.new(0, 180, 0, 22)
	coinLbl.Font = Enum.Font.GothamBold
	coinLbl.TextSize = 16
	coinLbl.TextXAlignment = Enum.TextXAlignment.Left
	local earned = payload.coinsEarned or 0
	if earned > 0 then
		coinLbl.TextColor3 = perfectColor   -- amber to match the perfect label
		coinLbl.Text = ("+%d coins bonus!"):format(earned)
	else
		coinLbl.TextColor3 = P.Gold
		coinLbl.Text = ("~%d coins"):format(payload.fish.basePrice or 0)
	end
	coinLbl.Parent = card

	-- ----------------------------------------------------------------
	-- RARITY BADGE — small tier-tinted pill in the bottom-right corner.
	-- ----------------------------------------------------------------
	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Position = UDim2.new(1, -14, 1, -14)
	badge.Size = UDim2.fromOffset(96, 24)
	badge.BackgroundColor3 = tierColor
	badge.BorderSizePixel = 0
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = badge
	badge.Parent = card

	local badgeLbl = Instance.new("TextLabel")
	badgeLbl.BackgroundTransparency = 1
	badgeLbl.Size = UDim2.fromScale(1, 1)
	badgeLbl.Font = Enum.Font.GothamBold
	badgeLbl.TextSize = 12
	-- Pick text color for contrast — dark on uncommon/mythic, light on rare/common.
	badgeLbl.TextColor3 = (rarity == "Rare" or rarity == "Common") and P.Cream or P.Ink
	badgeLbl.Text = rarity:upper()
	badgeLbl.Parent = badge

	-- ----------------------------------------------------------------
	-- MYTHIC BORDER CYCLE — slow color tween between amber and coral.
	-- Runs for as long as the card exists; killed in dismiss().
	-- ----------------------------------------------------------------
	local cycleTask: thread? = nil
	if rarity == "Mythic" and not MotionUtil.reducedMotionEnabled() then
		cycleTask = task.spawn(function()
			local toCoral = true
			while card.Parent do
				local target = toCoral and MYTHIC_CYCLE_TARGET or tierColor
				local tween = MotionUtil.tween(stroke, TweenInfo.new(FT.MythicBorderCycleDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Color = target })
				tween.Completed:Wait()
				tween:Destroy()
				toCoral = not toCoral
			end
		end)
	end

	-- ----------------------------------------------------------------
	-- PERFECT SPARKLES — 1-second burst of tiny gold dots drifting up
	-- along the card border. We don't have a 2D ParticleEmitter, so we
	-- spawn ~10 short-lived Frames manually. Skipped under reduced motion.
	-- ----------------------------------------------------------------
	if (payload.perfect or payload.castPerfect) and not MotionUtil.reducedMotionEnabled() then
		task.spawn(function()
			for i = 1, 10 do
				if not card.Parent then return end
				local dot = Instance.new("Frame")
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				-- Spawn along the top edge, randomly distributed.
				dot.Position = UDim2.new(math.random(), math.random(-4, 4), 0, math.random(-2, 2))
				dot.Size = UDim2.fromOffset(4, 4)
				dot.BackgroundColor3 = perfectColor
				dot.BorderSizePixel = 0
				local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
				dot.ZIndex = 6
				dot.Parent = card
				local rise = MotionUtil.tween(dot, TweenInfo.new(0.7 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = dot.Position + UDim2.fromOffset(math.random(-12, 12), -30),
					BackgroundTransparency = 1,
				})
				rise.Completed:Connect(function() rise:Destroy(); dot:Destroy() end)
				task.wait(0.07)
			end
		end)
	end

	-- ----------------------------------------------------------------
	-- SLIDE IN — Back/Out for a satisfying overshoot. Reduced motion =
	-- fade in only.
	-- ----------------------------------------------------------------
	local restPosition = UDim2.new(0.5, 0, 1, -110)
	if MotionUtil.reducedMotionEnabled() then
		card.Position = restPosition
		card.BackgroundTransparency = 1
		MotionUtil.tween(card, TweenInfo.new(0.25), { BackgroundTransparency = 0 })
	else
		MotionUtil.tween(card, TweenInfo.new(FT.RevealSlideInDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = restPosition,
		})
	end

	-- ----------------------------------------------------------------
	-- DISMISS — slide back down (or fade) and clean up tweens / cycle
	-- task / parent ScreenGui.
	-- ----------------------------------------------------------------
	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		if cycleTask then task.cancel(cycleTask); cycleTask = nil end
		if MotionUtil.reducedMotionEnabled() then
			local fade = MotionUtil.tween(card, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
			fade.Completed:Connect(function() fade:Destroy(); gui:Destroy() end)
		else
			local slide = MotionUtil.tween(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, 0, 1, 240),
			})
			slide.Completed:Connect(function() slide:Destroy(); gui:Destroy() end)
		end
	end

	tapCatcher.Activated:Connect(dismiss)
	task.delay(FT.RevealAutoDismissAfter, dismiss)

	return {
		gui = gui,
		dismiss = dismiss,
	}
end

return CatchRevealUI
