--!strict
-- QuestTrackerUI.lua
-- Minimal always-visible quest tracker tucked under the topbar. Displays each
-- daily quest as one row with progress and a Claim button when complete.

local UIUtil = require(script.Parent.UIUtil)

local QuestTrackerUI = {}

export type QuestTrackerHandle = {
	gui: ScreenGui,
	refresh: (quests: {any}) -> (),
}

function QuestTrackerUI.show(initialQuests: {any}, onClaim: (string) -> ()): QuestTrackerHandle
	local gui = UIUtil.makeScreenGui("QuestTrackerUI")

	local panel = UIUtil.makePanel({
		Name = "Tracker",
		AnchorPoint = Vector2.new(1, 0),
		-- Tucked top-right under the topbar margin.
		Position = UDim2.new(1, -12, 0, 80),
		Size = UDim2.new(0, 280, 0, 160),
		BackgroundColor3 = UIUtil.Palette.TealDark,
		BackgroundTransparency = 0.15,
	})
	panel.Parent = gui

	local title = UIUtil.makeLabel("Daily Quests", "title", {
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, 22),
		TextSize = 16,
	})
	title.Parent = panel

	local list = UIUtil.makeFrame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 36),
		Size = UDim2.new(1, -16, 1, -44),
	})
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4); layout.Parent = list

	local function questText(q: any): string
		-- Build a player-friendly description from kind + target.
		if q.kind == "CatchAnyFish" then return ("Catch %d fish"):format(q.target) end
		if q.kind == "CatchSpecies" then return ("Catch %d %s"):format(q.target, ((q.speciesId or "?"):gsub("_", " "))) end
		if q.kind == "SellAtMarket" then return ("Sell %d at market"):format(q.target) end
		if q.kind == "EarnCoins" then return ("Earn %d coins"):format(q.target) end
		if q.kind == "VisitHarbor" then return ("Visit %d harbors"):format(q.target) end
		return q.kind
	end

	local function refresh(quests: {any})
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, q in ipairs(quests) do
			local row = UIUtil.makeFrame({
				BackgroundColor3 = UIUtil.Palette.Teal,
				BackgroundTransparency = 0.1,
				Size = UDim2.new(1, 0, 0, 32),
				LayoutOrder = i,
			})
			row.Parent = list
			local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row

			local txt = UIUtil.makeLabel(("%s (%d/%d)"):format(questText(q), q.progress, q.target), "body", {
				Position = UDim2.new(0, 8, 0, 0),
				Size = UDim2.new(1, -88, 1, 0),
				TextSize = 13,
			})
			txt.Parent = row

			if q.completed and not q.claimed then
				local claim = UIUtil.makeButton("Claim", function() onClaim(q.id) end, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -6, 0.5, 0),
					Size = UDim2.fromOffset(72, 26),
					TextSize = 12,
				})
				claim.Parent = row
			elseif q.claimed then
				local done = UIUtil.makeLabel("Done", "caption", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.fromOffset(60, 24),
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = UIUtil.Palette.Uncommon,
				})
				done.Parent = row
			end
		end
	end
	refresh(initialQuests)

	return {
		gui = gui,
		refresh = refresh,
	}
end

return QuestTrackerUI
