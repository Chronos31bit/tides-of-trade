--!strict
-- SeasonPassUI.lua
-- Minimal season-pass panel. Renders tier progress bar + milestone claim
-- buttons. Inline construction (no template dependency) — full horizontal
-- tier-track layout deferred until cosmetics catalog ships.

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette
local MinTouchPx = UIUtil.MinTouchPx
local Radii = UIUtil.Radii

local SeasonPassUI = {}

export type SeasonPassHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (state: any) -> (),
}

function SeasonPassUI.show(initialState: {xp: number, tier: number, tierCount: number, xpPerTier: number, claimedTiers: {[number]: boolean}, freeRewards: any}, onClaimTier: (number) -> (), onClose: (() -> ())?): SeasonPassHandle
	local shell = UIUtil.makeModalShell({
		name = "SeasonPassUI",
		title = "Season Pass",
		onClose = onClose,
		bodyPadding = UIUtil.Spacing.sm,
	})

	local body = shell.body

	-- Force dark theme on the entire modal (template may ship with light fills).
	local panel = shell.panel
	if panel and panel:IsA("Frame") then
		panel.BackgroundColor3 = P.TealDeeper
	end
	local header = shell.header
	if header and header:IsA("Frame") then
		header.BackgroundColor3 = P.Teal
	end
	local titleLabel = shell.title
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.TextColor3 = P.Cream
	end

	-- ---- PROGRESS SECTION ----
	local progressSection = Instance.new("Frame")
	progressSection.Name = "Progress"
	progressSection.BackgroundTransparency = 1
	progressSection.BorderSizePixel = 0
	progressSection.Size = UDim2.new(1, 0, 0, 80)
	progressSection.Parent = body

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "TierLabel"
	tierLabel.BackgroundTransparency = 1
	tierLabel.Size = UDim2.new(1, 0, 0, 28)
	tierLabel.Position = UDim2.new(0, 0, 0, 0)
	tierLabel.Font = Enum.Font.GothamBold
	tierLabel.TextSize = 18
	tierLabel.TextColor3 = P.Cream
	tierLabel.Text = "Season Pass"
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.Parent = progressSection

	local xpLabel = Instance.new("TextLabel")
	xpLabel.Name = "XPLabel"
	xpLabel.BackgroundTransparency = 1
	xpLabel.Size = UDim2.new(1, 0, 0, 18)
	xpLabel.Position = UDim2.new(0, 0, 0, 30)
	xpLabel.Font = Enum.Font.Gotham
	xpLabel.TextSize = 13
	xpLabel.TextColor3 = P.CreamSoft
	xpLabel.Text = "0 / 100 XP"
	xpLabel.TextXAlignment = Enum.TextXAlignment.Left
	xpLabel.Parent = progressSection

	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBar"
	barBg.BackgroundColor3 = P.TealDeeper
	barBg.BorderSizePixel = 0
	barBg.Size = UDim2.new(1, 0, 0, 12)
	barBg.Position = UDim2.new(0, 0, 0, 54)
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 6)
	bgCorner.Parent = barBg
	barBg.Parent = progressSection

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = P.Sunset
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	local fCorner = Instance.new("UICorner")
	fCorner.CornerRadius = UDim.new(0, 6)
	fCorner.Parent = fill
	fill.Parent = barBg

	-- ---- REWARDS SECTION ----
	local rewardsTitle = Instance.new("TextLabel")
	rewardsTitle.Name = "RewardsTitle"
	rewardsTitle.BackgroundTransparency = 1
	rewardsTitle.Size = UDim2.new(1, 0, 0, 22)
	rewardsTitle.Position = UDim2.new(0, 0, 0, 90)
	rewardsTitle.Font = Enum.Font.GothamBold
	rewardsTitle.TextSize = 14
	rewardsTitle.TextColor3 = P.Cream
	rewardsTitle.Text = "Free Rewards"
	rewardsTitle.TextXAlignment = Enum.TextXAlignment.Left
	rewardsTitle.Parent = body

	local rewardsList = Instance.new("ScrollingFrame")
	rewardsList.Name = "RewardsList"
	rewardsList.BackgroundTransparency = 1
	rewardsList.BorderSizePixel = 0
	rewardsList.ScrollBarThickness = 4
	rewardsList.ScrollingDirection = Enum.ScrollingDirection.Y
	rewardsList.CanvasSize = UDim2.new()
	rewardsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rewardsList.Position = UDim2.new(0, 0, 0, 114)
	rewardsList.Size = UDim2.new(1, 0, 1, -114)
	rewardsList.Parent = body

	local rLayout = Instance.new("UIListLayout")
	rLayout.Padding = UDim.new(0, UIUtil.Spacing.sm)
	rLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rLayout.Parent = rewardsList

	-- ---- RENDER ----
	local function render(state: {xp: number, tier: number, tierCount: number, xpPerTier: number, claimedTiers: {[number]: boolean}, freeRewards: any})
		local xpInTier = state.xp - (state.tier - 1) * state.xpPerTier
		local frac = math.clamp(xpInTier / state.xpPerTier, 0, 1)

		tierLabel.Text = ("Season Pass · Tier %d/%d"):format(state.tier, state.tierCount)
		xpLabel.Text = ("%d / %d XP to next tier"):format(xpInTier, state.xpPerTier)
		fill.Size = UDim2.new(frac, 0, 1, 0)

		-- Clear existing reward rows.
		for _, c in ipairs(rewardsList:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end

		local freeRewards = state.freeRewards or {}
		local claimedTiers = state.claimedTiers or {}
		local sortable: {{number}} = {}
		for t_ in pairs(freeRewards) do table.insert(sortable, t_) end
		table.sort(sortable)

		for i, t_ in ipairs(sortable) do
			local reward = freeRewards[t_]
			if reward then
				local row = Instance.new("Frame")
				row.Name = "Reward_" .. t_
				row.BackgroundColor3 = P.Teal
				row.BorderSizePixel = 0
				row.Size = UDim2.new(1, 0, 0, MinTouchPx)
				row.LayoutOrder = i
				local rc = Instance.new("UICorner")
				rc.CornerRadius = UDim.new(0, Radii.md)
				rc.Parent = row
				row.Parent = rewardsList

				local badge = Instance.new("TextLabel")
				badge.Name = "TierBadge"
				badge.BackgroundTransparency = 1
				badge.Size = UDim2.new(0, 72, 0, MinTouchPx)
				badge.Position = UDim2.new(0, UIUtil.Spacing.sm, 0, 0)
				badge.Font = Enum.Font.GothamBold
				badge.TextSize = 14
				badge.TextColor3 = P.Cream
				badge.Text = ("Tier %d"):format(t_)
				badge.TextXAlignment = Enum.TextXAlignment.Left
				badge.Parent = row

				local parts: {string} = {}
				if reward.xp and reward.xp > 0 then table.insert(parts, ("%d XP"):format(reward.xp)) end
				if reward.lureTokens and reward.lureTokens > 0 then table.insert(parts, ("%d Lure Tokens"):format(reward.lureTokens)) end

				local desc = Instance.new("TextLabel")
				desc.Name = "RewardDesc"
				desc.BackgroundTransparency = 1
				desc.Size = UDim2.new(1, -160, 0, MinTouchPx)
				desc.Position = UDim2.new(0, 80, 0, 0)
				desc.Font = Enum.Font.Gotham
				desc.TextSize = 13
				desc.TextColor3 = P.CreamSoft
				desc.Text = table.concat(parts, " + ")
				desc.TextXAlignment = Enum.TextXAlignment.Left
				desc.Parent = row

				local btn = Instance.new("TextButton")
				btn.Name = "ClaimButton"
				btn.BackgroundColor3 = P.Wood
				btn.BorderSizePixel = 0
				btn.Size = UDim2.new(0, 72, 0, MinTouchPx - 8)
				btn.Position = UDim2.new(1, -80, 0, 4)
				btn.Font = Enum.Font.GothamBold
				btn.TextSize = 13
				btn.TextColor3 = P.Cream
				local bc = Instance.new("UICorner")
				bc.CornerRadius = UDim.new(0, Radii.sm)
				bc.Parent = btn
				btn.Parent = row

				local claimed = claimedTiers[t_] or false
				if claimed then
					btn.Text = "Claimed"
					btn.BackgroundColor3 = P.Wood
					btn.Active = false
				elseif t_ > state.tier then
					btn.Text = "Locked"
					btn.BackgroundColor3 = P.TealDeeper
					btn.Active = false
				else
					btn.Text = "Claim"
					btn.BackgroundColor3 = P.Sunset
					btn.TextColor3 = P.Cream
					btn.Active = true
					local targetTier = t_
					btn.Activated:Connect(function()
						btn.Text = "..."
						btn.Active = false
						onClaimTier(targetTier)
					end)
				end
			end
		end
	end

	render(initialState)

	return {
		gui = shell.gui,
		close = shell.destroy,
		refresh = render,
	}
end

return SeasonPassUI
