--!strict
-- SeasonPassUI.lua
-- Fortnite-style horizontal two-row tier track.
--   * Top row    = PREMIUM — visual only, locked "Coming Soon" (no paid track
--                  at launch; cosmetic-only when it ships — pillar 2).
--   * Bottom row = FREE — claimable rewards earned by everyday play.
-- Columns scroll horizontally; the current tier auto-centres on open. All
-- decorative motion routes through MotionUtil (ReducedMotion-aware). Inline
-- build (no template) — the modal chrome comes from UIUtil.makeModalShell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local UIUtil           = require(script.Parent.UIUtil)
local MotionUtil       = require(ReplicatedStorage.Shared.Util.MotionUtil)
local CosmeticsCatalog = require(ReplicatedStorage.Shared.Config.CosmeticsCatalog)

local P          = UIUtil.Palette
local MinTouchPx = UIUtil.MinTouchPx
local Radii      = UIUtil.Radii
local Spacing    = UIUtil.Spacing

-- Layout constants (offsets, px).
local COL_W    = 104
local COL_GAP  = 8
local CELL_H   = 96
local BADGE_H  = 30
local COL_H    = CELL_H * 2 + BADGE_H -- 222
local GUTTER_W = 58
local TRACK_TOP = 86 -- below the progress section

local SeasonPassUI = {}

export type SeasonPassHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (state: any) -> (),
}

-- Premium kind → glyph (display only).
local PREMIUM_GLYPH: {[string]: string} = {
	cosmetic = "✶",
	emote    = "☺",
	coins    = "⊙",
	lure     = "★",
}

-- Free reward → (glyph, text). Resolves cosmetic display names from the catalog.
local function freeRewardDisplay(reward: any): (string, string)
	if reward == nil then
		return "", "—"
	end
	if reward.cosmeticId then
		local def = CosmeticsCatalog.byId[reward.cosmeticId]
		return "✶", (def and def.displayName) or "Cosmetic"
	elseif reward.coins then
		return "⊙", ("%d Coins"):format(reward.coins)
	elseif reward.lureTokens then
		return "★", ("%d Lure"):format(reward.lureTokens)
	elseif reward.xp then
		return "✦", ("%d XP"):format(reward.xp)
	end
	return "", "—"
end

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function label(parent: Instance, text: string, sizePx: number, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = math.max(sizePx, 12) -- never below 12px (accessibility)
	l.TextColor3 = color
	l.Text = text
	l.TextWrapped = true
	l.Parent = parent
	return l
end

function SeasonPassUI.show(initialState: any, onClaimTier: (number) -> (), onClose: (() -> ())?): SeasonPassHandle
	local shell = UIUtil.makeModalShell({
		name = "SeasonPassUI",
		title = "Season Pass",
		onClose = onClose,
		bodyPadding = Spacing.sm,
		width = 660,
		heightScale = 0.62,
	})

	local body = shell.body

	-- Force dark theme on the modal chrome (template may ship light fills).
	if shell.panel and shell.panel:IsA("Frame") then shell.panel.BackgroundColor3 = P.TealDeeper end
	if shell.header and shell.header:IsA("Frame") then shell.header.BackgroundColor3 = P.Teal end
	if shell.title and shell.title:IsA("TextLabel") then shell.title.TextColor3 = P.Cream end

	-- ---- PROGRESS SECTION (top, full width) ----
	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.BackgroundTransparency = 1
	progress.BorderSizePixel = 0
	progress.Size = UDim2.new(1, 0, 0, 78)
	progress.Parent = body

	local tierLabel = label(progress, "Season Pass · Tier 1/20", 18, P.Cream, Enum.Font.GothamBold)
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.TextWrapped = false
	tierLabel.Size = UDim2.new(1, 0, 0, 26)
	tierLabel.Position = UDim2.new(0, 0, 0, 0)

	local xpLabel = label(progress, "0 / 100 XP to next tier", 13, P.CreamSoft, Enum.Font.Gotham)
	xpLabel.TextXAlignment = Enum.TextXAlignment.Left
	xpLabel.TextWrapped = false
	xpLabel.Size = UDim2.new(1, 0, 0, 18)
	xpLabel.Position = UDim2.new(0, 0, 0, 30)

	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBar"
	barBg.BackgroundColor3 = P.TealDeeper
	barBg.BorderSizePixel = 0
	barBg.Size = UDim2.new(1, 0, 0, 12)
	barBg.Position = UDim2.new(0, 0, 0, 56)
	corner(barBg, 6)
	barBg.Parent = progress

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = P.Sunset
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	corner(fill, 6)
	fill.Parent = barBg

	-- ---- ROW GUTTER (PREMIUM / FREE labels, non-scrolling) ----
	local gutter = Instance.new("Frame")
	gutter.Name = "RowGutter"
	gutter.BackgroundTransparency = 1
	gutter.BorderSizePixel = 0
	gutter.Position = UDim2.new(0, 0, 0, TRACK_TOP)
	gutter.Size = UDim2.new(0, GUTTER_W, 0, COL_H)
	gutter.Parent = body

	local premiumRowLabel = label(gutter, "PREMIUM", 12, P.Gold, Enum.Font.GothamBold)
	premiumRowLabel.TextXAlignment = Enum.TextXAlignment.Center
	premiumRowLabel.Size = UDim2.new(1, 0, 0, CELL_H)
	premiumRowLabel.Position = UDim2.new(0, 0, 0, 0)

	local soonLabel = label(gutter, "soon", 12, P.CreamSoft, Enum.Font.Gotham)
	soonLabel.TextXAlignment = Enum.TextXAlignment.Center
	soonLabel.Size = UDim2.new(1, 0, 0, 16)
	soonLabel.Position = UDim2.new(0, 0, 0, CELL_H - 18)

	local freeRowLabel = label(gutter, "FREE", 12, P.Sunset, Enum.Font.GothamBold)
	freeRowLabel.TextXAlignment = Enum.TextXAlignment.Center
	freeRowLabel.Size = UDim2.new(1, 0, 0, CELL_H)
	freeRowLabel.Position = UDim2.new(0, 0, 0, CELL_H + BADGE_H)

	-- ---- SCROLLING TIER TRACK ----
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "TierTrack"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.Position = UDim2.new(0, GUTTER_W + 4, 0, TRACK_TOP)
	scroll.Size = UDim2.new(1, -(GUTTER_W + 4), 0, COL_H + 14)
	scroll.Parent = body

	local trackLayout = Instance.new("UIListLayout")
	trackLayout.FillDirection = Enum.FillDirection.Horizontal
	trackLayout.Padding = UDim.new(0, COL_GAP)
	trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trackLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	trackLayout.Parent = scroll

	-- Build one reward cell (premium = locked/visual, free = claimable).
	local function buildPremiumCell(parent: Instance, reward: any)
		local cell = Instance.new("Frame")
		cell.Name = "PremiumCell"
		cell.BackgroundColor3 = P.TealDark
		cell.BackgroundTransparency = 0.35 -- dimmed: locked
		cell.BorderSizePixel = 0
		cell.Size = UDim2.new(1, 0, 0, CELL_H)
		cell.Position = UDim2.new(0, 0, 0, 0)
		corner(cell, Radii.md)
		cell.Parent = parent

		local stroke = Instance.new("UIStroke")
		stroke.Color = P.Gold
		stroke.Thickness = 1
		stroke.Transparency = 0.6
		stroke.Parent = cell

		local glyph = label(cell, (reward and PREMIUM_GLYPH[reward.kind]) or "✶", 22, P.Gold, Enum.Font.GothamBlack)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Size = UDim2.new(1, 0, 0, 30)
		glyph.Position = UDim2.new(0, 0, 0, 12)
		glyph.TextTransparency = 0.25

		local name = label(cell, (reward and reward.label) or "—", 12, P.CreamSoft, Enum.Font.GothamMedium)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.Size = UDim2.new(1, -8, 0, 36)
		name.Position = UDim2.new(0, 4, 0, 44)

		-- Lock badge (emoji with text fallback meaning via gutter "soon").
		local lock = label(cell, "🔒", 14, P.Cream, Enum.Font.GothamBold)
		lock.TextXAlignment = Enum.TextXAlignment.Right
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Size = UDim2.new(0, 18, 0, 18)
		lock.Position = UDim2.new(1, -6, 0, 6)
	end

	local function buildFreeCell(parent: Instance, t: number, reward: any, isClaimed: boolean, isReached: boolean)
		local cell = Instance.new("Frame")
		cell.Name = "FreeCell"
		cell.BackgroundColor3 = P.TealDark
		cell.BackgroundTransparency = isReached and 0 or 0.4 -- future tiers dimmed
		cell.BorderSizePixel = 0
		cell.Size = UDim2.new(1, 0, 0, CELL_H)
		cell.Position = UDim2.new(0, 0, 0, CELL_H + BADGE_H)
		corner(cell, Radii.md)
		cell.Parent = parent

		local glyphTxt, rewardTxt = freeRewardDisplay(reward)

		local glyph = label(cell, glyphTxt, 22, P.Sunset, Enum.Font.GothamBlack)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Size = UDim2.new(1, 0, 0, 26)
		glyph.Position = UDim2.new(0, 0, 0, 8)

		local desc = label(cell, rewardTxt, 12, P.Cream, Enum.Font.GothamMedium)
		desc.TextXAlignment = Enum.TextXAlignment.Center
		desc.Size = UDim2.new(1, -8, 0, 30)
		desc.Position = UDim2.new(0, 4, 0, 34)

		-- Action / status (≥44px touch target).
		local btn = Instance.new("TextButton")
		btn.Name = "ClaimButton"
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.TextColor3 = P.Cream
		btn.AnchorPoint = Vector2.new(0.5, 1)
		btn.Position = UDim2.new(0.5, 0, 1, -6)
		btn.Size = UDim2.new(1, -12, 0, MinTouchPx)
		corner(btn, Radii.sm)
		btn.Parent = cell

		if reward == nil then
			btn.Text = "—"
			btn.BackgroundColor3 = P.TealDeeper
			btn.Active = false
			btn.AutoButtonColor = false
		elseif isClaimed then
			btn.Text = "Claimed"
			btn.BackgroundColor3 = P.TealDeeper
			btn.TextColor3 = P.CreamSoft
			btn.Active = false
		elseif isReached then
			btn.Text = "Claim"
			btn.BackgroundColor3 = P.Sunset
			btn.Active = true
			btn.Activated:Connect(function()
				btn.Text = "…"
				btn.Active = false
				onClaimTier(t)
			end)
		else
			btn.Text = "Locked"
			btn.BackgroundColor3 = P.TealDeeper
			btn.TextColor3 = P.CreamSoft
			btn.Active = false
		end
	end

	-- ---- RENDER ----
	local function render(state: any)
		local tier      = state.tier or 1
		local tierCount = state.tierCount or 20
		local xpPerTier  = state.xpPerTier or 100
		local xpInTier  = (state.xp or 0) - (tier - 1) * xpPerTier
		local frac      = math.clamp(xpInTier / math.max(xpPerTier, 1), 0, 1)

		tierLabel.Text = ("Season Pass · Tier %d/%d"):format(tier, tierCount)
		if tier >= tierCount then
			xpLabel.Text = "Season complete — all tiers reached"
		else
			xpLabel.Text = ("%d / %d XP to next tier"):format(math.max(xpInTier, 0), xpPerTier)
		end
		MotionUtil.tweenOrSnap(
			fill,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(frac, 0, 1, 0) }
		)

		-- Clear existing columns.
		for _, c in ipairs(scroll:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end

		local freeRewards    = state.freeRewards or {}
		local premiumRewards = state.premiumRewards or {}
		local claimedTiers   = state.claimedTiers or {}

		for t = 1, tierCount do
			local col = Instance.new("Frame")
			col.Name = "Col_" .. t
			col.BackgroundTransparency = 1
			col.BorderSizePixel = 0
			col.Size = UDim2.new(0, COL_W, 0, COL_H)
			col.LayoutOrder = t
			col.Parent = scroll

			-- Premium cell (top).
			buildPremiumCell(col, premiumRewards[t])

			-- Tier badge (middle). Current tier highlighted.
			local badge = Instance.new("Frame")
			badge.Name = "TierBadge"
			badge.BackgroundColor3 = (t == tier) and P.Sunset or P.TealDeeper
			badge.BorderSizePixel = 0
			badge.Size = UDim2.new(0, BADGE_H, 0, BADGE_H)
			badge.AnchorPoint = Vector2.new(0.5, 0)
			badge.Position = UDim2.new(0.5, 0, 0, CELL_H)
			corner(badge, BADGE_H / 2)
			badge.Parent = col
			if t == tier then
				local bs = Instance.new("UIStroke")
				bs.Color = P.Cream
				bs.Thickness = 2
				bs.Parent = badge
			end
			local badgeLbl = label(badge, tostring(t), 13, (t == tier) and P.Ink or P.CreamSoft, Enum.Font.GothamBold)
			badgeLbl.TextXAlignment = Enum.TextXAlignment.Center
			badgeLbl.TextYAlignment = Enum.TextYAlignment.Center
			badgeLbl.Size = UDim2.new(1, 0, 1, 0)
			badgeLbl.TextWrapped = false

			-- Free cell (bottom).
			local isClaimed = claimedTiers[t] == true
			local isReached = t <= tier
			buildFreeCell(col, t, freeRewards[t], isClaimed, isReached)
		end

		-- Auto-scroll to centre the current tier (next frame, once laid out).
		task.defer(function()
			if not scroll.Parent then return end
			local perCol = COL_W + COL_GAP
			local viewW = scroll.AbsoluteWindowSize.X
			if viewW <= 0 then viewW = 320 end
			local canvasW = scroll.AbsoluteCanvasSize.X
			local targetX = (tier - 1) * perCol - (viewW * 0.5 - COL_W * 0.5)
			targetX = math.clamp(targetX, 0, math.max(0, canvasW - viewW))
			MotionUtil.tweenOrSnap(
				scroll,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CanvasPosition = Vector2.new(targetX, 0) }
			)
		end)
	end

	render(initialState)

	return {
		gui = shell.gui,
		close = shell.destroy,
		refresh = render,
	}
end

return SeasonPassUI
