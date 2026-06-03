--!strict
-- LeaderboardUI.lua
-- Two-tab panel (Catches / Species) showing the top-10 global leaderboard.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIUtil            = require(script.Parent.UIUtil)
local UIKit             = require(script.Parent.UIKit)
local GameConfig        = require(ReplicatedStorage.Shared.Config.GameConfig)

local P = UIUtil.Palette
local T = UIKit.Typography

export type LeaderboardHandle = {
	open: () -> (),
	close: () -> (),
	destroy: () -> (),
}

local LeaderboardUI = {}

local TAB_LABELS = { catches = "Catches", species = "Species" }

function LeaderboardUI.show(
	fetchEntries: (string) -> Promise
): LeaderboardHandle
	local shell = UIUtil.makeModalShell({
		name = "Leaderboard",
		title = "Leaderboard",
		size = UDim2.fromOffset(340, 420),
	})
	local body = shell.body

	-- Tab bar: two buttons side by side.
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, 0, 0, 40)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = body

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.Parent = tabBar

	local tabCatches = UIUtil.makeButton(TAB_LABELS.catches, function() end, {
		Size = UDim2.new(0.5, -2, 1, 0),
		BackgroundColor3 = P.TealDark,
		TextSize = T.body.size,
	})
	tabCatches.LayoutOrder = 1
	tabCatches.Parent = tabBar

	local tabSpecies = UIUtil.makeButton(TAB_LABELS.species, function() end, {
		Size = UDim2.new(0.5, -2, 1, 0),
		BackgroundColor3 = P.TealDeeper,
		TextSize = T.body.size,
	})
	tabSpecies.LayoutOrder = 2
	tabSpecies.Parent = tabBar

	-- Scrolling entry list.
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "EntryList"
	listFrame.Size = UDim2.new(1, -8, 1, -48)
	listFrame.Position = UDim2.new(0, 4, 0, 44)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.ScrollBarThickness = 6
	listFrame.Parent = body

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		listFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 4)
	end)
	listLayout.Parent = listFrame

	-- Loading placeholder.
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Name = "LoadingLabel"
	loadingLabel.Size = UDim2.new(1, 0, 0, 40)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.Font = T.body.font
	loadingLabel.TextSize = T.body.size
	loadingLabel.TextColor3 = P.CreamSoft
	loadingLabel.Text = "Loading..."
	loadingLabel.Parent = listFrame

	-- Build one row for a leaderboard entry.
	local function buildRow(entry: {rank: number, displayName: string, score: number}): Frame
		local row = Instance.new("Frame")
		row.Name = "Row"
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundColor3 = P.TealDark
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = row

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Name = "Rank"
		rankLabel.Size = UDim2.new(0, 40, 1, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Font = T.title.font
		rankLabel.TextSize = T.body.size
		rankLabel.TextColor3 = P.Gold
		rankLabel.Text = "#" .. tostring(entry.rank)
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Size = UDim2.new(1, -120, 1, 0)
		nameLabel.Position = UDim2.new(0, 44, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = T.body.font
		nameLabel.TextSize = T.body.size
		nameLabel.TextColor3 = P.Cream
		nameLabel.Text = entry.displayName
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local scoreLabel = Instance.new("TextLabel")
		scoreLabel.Name = "Score"
		scoreLabel.Size = UDim2.new(0, 76, 1, 0)
		scoreLabel.Position = UDim2.new(1, -80, 0, 0)
		scoreLabel.BackgroundTransparency = 1
		scoreLabel.Font = T.body.font
		scoreLabel.TextSize = T.body.size
		scoreLabel.TextColor3 = P.Gold
		scoreLabel.Text = tostring(entry.score)
		scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
		scoreLabel.Parent = row

		row.LayoutOrder = entry.rank
		return row
	end

	-- Populate the list from fetched entries.
	local function populate(entries: {{rank: number, displayName: string, score: number}})
		-- Clear existing rows.
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		if loadingLabel then loadingLabel.Visible = false end

		if #entries == 0 then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Size = UDim2.new(1, 0, 0, 40)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Font = T.body.font
			emptyLabel.TextSize = T.body.size
			emptyLabel.TextColor3 = P.CreamSoft
			emptyLabel.Text = "No entries yet. Catch some fish!"
			emptyLabel.Parent = listFrame
			return
		end

		for _, entry in ipairs(entries) do
			buildRow(entry).Parent = listFrame
		end
	end

	-- Active tab state.
	local activeTab = "catches"

	local function switchTab(tab: string)
		activeTab = tab
		tabCatches.BackgroundColor3 = tab == "catches" and P.TealDark or P.TealDeeper
		tabSpecies.BackgroundColor3 = tab == "species" and P.TealDark or P.TealDeeper
		loadingLabel.Visible = true
		fetchEntries(tab):andThen(function(entries)
			populate(entries)
		end):catch(function()
			loadingLabel.Text = "Failed to load. Try again."
		end)
	end

	-- Wire tab buttons.
	local catchesBtn = tabCatches:FindFirstChildOfClass("TextButton") or tabCatches
	local speciesBtn = tabSpecies:FindFirstChildOfClass("TextButton") or tabSpecies
	if catchesBtn:IsA("GuiButton") then
		catchesBtn.Activated:Connect(function() switchTab("catches") end)
	end
	if speciesBtn:IsA("GuiButton") then
		speciesBtn.Activated:Connect(function() switchTab("species") end)
	end

	-- Initial load.
	switchTab("catches")

	return shell
end

return LeaderboardUI
