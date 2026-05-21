--!strict
-- QuestTrackerUI.lua
-- Pinned-right-edge quest tracker. Collapsed: a single tab showing "N/3
-- done"; expanded: a panel with Today's quests, login streak, and the
-- refresh countdown. The tracker is purely presentational — every state
-- comes from a server snapshot pushed via QuestService.Client.QuestsRefreshed.
--
-- The controller (QuestTrackerController) owns the data path and the
-- completion / streak popup queue; this module owns the visuals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIUtil = require(script.Parent.UIUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local QuestTrackerUI = {}

-- Difficulty → left-edge accent. Cozy hierarchy: easy=common (grey),
-- medium=uncommon (green), hard=rare (blue). Tutorial uses sunset so
-- the seeded quest reads as "special, not difficult".
local function accentForDifficulty(difficulty: string): Color3
	if difficulty == "easy" then return UIUtil.Palette.Common end
	if difficulty == "medium" then return UIUtil.Palette.Uncommon end
	if difficulty == "hard" then return UIUtil.Palette.Rare end
	if difficulty == "tutorial" then return UIUtil.Palette.Sunset end
	return UIUtil.Palette.Common
end

local CATEGORY_ICON = {
	fishing     = "🎣",
	market      = "🪙",
	social      = "👋",
	building    = "🛠",
	exploration = "🧭",
}

-- ====================================================================
-- LAYOUT CONSTANTS
-- ====================================================================
local TAB_WIDTH = 56
local TAB_HEIGHT = 110
local PANEL_WIDTH = 340
local PANEL_HEIGHT = 480
local PANEL_OFFSET_Y = 0
local POPUP_WIDTH = 300
local POPUP_HEIGHT = 160

-- ====================================================================
-- HELPERS
-- ====================================================================
local function formatHMS(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function rewardSummary(reward: any): string
	if not reward then return "" end
	local parts = {}
	if reward.coins and reward.coins > 0 then table.insert(parts, ("%d coins"):format(reward.coins)) end
	if reward.xp and reward.xp > 0 then table.insert(parts, ("%d XP"):format(reward.xp)) end
	if reward.lureTokens and reward.lureTokens > 0 then table.insert(parts, ("%d lure"):format(reward.lureTokens)) end
	if reward.items then
		for _, it in ipairs(reward.items) do
			table.insert(parts, ("%dx %s"):format(it.count or 1, it.id))
		end
	end
	return table.concat(parts, ", ")
end

-- ====================================================================
-- QUEST CARD
-- ====================================================================
local function makeQuestCard(quest: any, onClaim: (string) -> ()): Frame
	local card = UIUtil.makeSoftPanel({
		Size = UDim2.new(1, -8, 0, 70),
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})

	-- Left accent bar
	local accent = Instance.new("Frame")
	accent.BackgroundColor3 = accentForDifficulty(quest.difficulty)
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 4, 1, -8)
	accent.Position = UDim2.new(0, 4, 0, 4)
	local accentCorner = Instance.new("UICorner"); accentCorner.CornerRadius = UDim.new(0, 2); accentCorner.Parent = accent
	accent.Parent = card

	-- Category icon
	local icon = UIUtil.makeLabel(CATEGORY_ICON[quest.category] or "•", "title", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0, 14, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	icon.Parent = card

	-- Quest text
	local text = UIUtil.makeLabel(quest.renderedText or quest.templateId or "Quest", "body", {
		Position = UDim2.new(0, 46, 0, 6),
		Size = UDim2.new(1, -56, 0, 22),
		TextWrapped = true,
		TextSize = 13,
	})
	text.Parent = card

	-- Progress bar
	local barBg = Instance.new("Frame")
	barBg.BackgroundColor3 = UIUtil.Palette.TealDeeper
	barBg.BorderSizePixel = 0
	barBg.Position = UDim2.new(0, 46, 0, 30)
	barBg.Size = UDim2.new(1, -56, 0, 8)
	local bgC = Instance.new("UICorner"); bgC.CornerRadius = UDim.new(0, 4); bgC.Parent = barBg
	barBg.Parent = card

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = accentForDifficulty(quest.difficulty)
	fill.BorderSizePixel = 0
	local frac = quest.target > 0 and math.clamp(quest.progress / quest.target, 0, 1) or 0
	fill.Size = UDim2.new(frac, 0, 1, 0)
	local fillC = Instance.new("UICorner"); fillC.CornerRadius = UDim.new(0, 4); fillC.Parent = fill
	fill.Parent = barBg

	-- Progress numbers
	local prog = UIUtil.makeLabel(("%d / %d"):format(quest.progress, quest.target), "caption", {
		Position = UDim2.new(0, 46, 0, 40),
		Size = UDim2.new(0.5, -28, 0, 18),
	})
	prog.Parent = card

	-- Reward preview
	local reward = UIUtil.makeLabel(rewardSummary(quest.reward), "caption", {
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.new(0.5, -10, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UIUtil.Palette.Gold,
	})
	reward.Parent = card

	-- Claim overlay (only when completed-not-claimed)
	if quest.completed and not quest.claimed then
		local claimBtn = UIUtil.makeButton("Claim", function()
			onClaim(quest.id)
		end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(70, 30),
			TextSize = 13,
			variant = "primary",
		})
		claimBtn.Parent = card
	elseif quest.claimed then
		-- Collapsed "Done" strip — keep the card a thin one-line.
		card.Size = UDim2.new(1, -8, 0, 28)
		text.Size = UDim2.new(1, -56, 1, 0)
		barBg.Visible = false
		prog.Visible = false
		reward.Visible = false
		local done = UIUtil.makeLabel("✓ Done", "caption", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(60, 22),
			TextColor3 = UIUtil.Palette.Success,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		done.Parent = card
	end

	return card
end

-- ====================================================================
-- STREAK SECTION
-- ====================================================================
-- Render 7 day circles. The current day is highlighted; completed days
-- filled; future days outlined. Day 7 gets a special glow (the Rare lure).
local function makeStreakRow(streakDay: number): Frame
	local container = UIUtil.makeFrame({
		Size = UDim2.new(1, -8, 0, 56),
		BackgroundTransparency = 1,
	})

	-- Day-in-cycle is ((streak-1) mod 7) + 1, so streak 8 → cycle day 1, etc.
	local cycleDay = ((streakDay - 1) % 7) + 1
	local weekNumber = math.floor((streakDay - 1) / 7) + 1

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 36)
	row.Position = UDim2.new(0, 0, 0, 0)
	row.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row

	for i = 1, 7 do
		local circle = Instance.new("Frame")
		circle.Size = UDim2.fromOffset(34, 34)
		circle.BorderSizePixel = 0
		circle.LayoutOrder = i
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = circle
		local stroke = Instance.new("UIStroke")
		stroke.Color = UIUtil.Palette.TealLight
		stroke.Thickness = 1.5
		stroke.Parent = circle

		local labelText: string = tostring(i)
		local fill: Color3 = UIUtil.Palette.TealDeeper
		local textColor: Color3 = UIUtil.Palette.CreamSoft

		if i < cycleDay then
			-- Already completed this cycle
			fill = UIUtil.Palette.Sunset
			textColor = UIUtil.Palette.Cream
		elseif i == cycleDay then
			-- Today
			fill = UIUtil.Palette.SunsetDeep
			textColor = UIUtil.Palette.Cream
			stroke.Color = UIUtil.Palette.Sunset
			stroke.Thickness = 2.5
		end
		if i == 7 then
			-- Day 7 reward halo. The visible reward is a Rare lure today.
			stroke.Color = UIUtil.Palette.Lure
			stroke.Thickness = i == cycleDay and 3 or 2
		end

		circle.BackgroundColor3 = fill

		local lbl = UIUtil.makeLabel(labelText, "subtitle", {
			Size = UDim2.new(1, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = textColor,
			TextSize = 13,
		})
		lbl.Parent = circle
		circle.Parent = row
	end

	-- Bottom caption
	local caption = UIUtil.makeLabel(("Day %d streak — back tomorrow for the next reward."):format(streakDay), "caption", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	caption.Parent = container

	if weekNumber > 1 then
		local week = UIUtil.makeLabel(("Week %d"):format(weekNumber), "caption", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 0),
			Size = UDim2.fromOffset(60, 14),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = UIUtil.Palette.Gold,
		})
		week.Parent = container
	end

	return container
end

-- ====================================================================
-- POPUPS — completion and streak
-- ====================================================================
-- Slides in from the right. The completion popup has a Claim button and
-- auto-collapses to a tab badge after CompletionPopupDuration. The
-- streak popup is smaller and auto-grants (no Claim).
local function buildPopup(parent: Instance, title: string, body: string, isStreak: boolean): (Frame, () -> (), () -> ())
	local popup = UIUtil.makePanel({
		Size = UDim2.fromOffset(POPUP_WIDTH, isStreak and 110 or POPUP_HEIGHT),
		AnchorPoint = Vector2.new(1, 0),
		-- Start fully off-screen on the right; tween in.
		Position = UDim2.new(1, POPUP_WIDTH + 20, 0, 90),
		BackgroundColor3 = isStreak and UIUtil.Palette.SunsetDeep or UIUtil.Palette.TealDark,
	})
	popup.Parent = parent

	local hdr = UIUtil.makeLabel(title, "title", {
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.new(1, -32, 0, 24),
		TextColor3 = isStreak and UIUtil.Palette.Cream or UIUtil.Palette.Sunset,
	})
	hdr.Parent = popup

	local bod = UIUtil.makeLabel(body, "body", {
		Position = UDim2.new(0, 16, 0, 40),
		Size = UDim2.new(1, -32, 0, isStreak and 50 or 70),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	bod.Parent = popup

	-- Tween IN — routed through MotionUtil so the snap-to-final behaviour
	-- under ReducedMotion is honoured (no slide on accessibility setting).
	local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local function slideIn()
		MotionUtil.tweenOrSnap(popup, tweenInfo, {
			Position = UDim2.new(1, -12, 0, 90),
		})
	end

	local function slideOut(onDone: (() -> ())?)
		if MotionUtil.reducedMotionEnabled() then
			popup:Destroy()
			if onDone then onDone() end
			return
		end
		local outTween = MotionUtil.tween(popup, tweenInfo, {
			Position = UDim2.new(1, POPUP_WIDTH + 20, 0, 90),
		})
		outTween.Completed:Connect(function()
			outTween:Destroy()
			popup:Destroy()
			if onDone then onDone() end
		end)
	end

	return popup, slideIn, function() slideOut() end
end

-- ====================================================================
-- PUBLIC: create()
-- ====================================================================
function QuestTrackerUI.create()
	local gui, _scale = UIUtil.makeScreenGui("QuestTrackerUI", nil, { respectTopbar = true })
	-- Render above the HUD so the panel and the
	-- completion/streak popups are never clipped behind it. Below tutorial
	-- dialogue (5) so Mira still reads on top during onboarding, and below
	-- modal confirms (20).
	gui.DisplayOrder = UIUtil.DisplayOrder.QuestTracker

	-- Root container (right edge)
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, 0, 0, 140)
	root.Size = UDim2.fromOffset(PANEL_WIDTH + TAB_WIDTH + 12, PANEL_HEIGHT + 20)
	root.Parent = gui

	-- Tab (always visible)
	local tab = Instance.new("TextButton")
	tab.AutoButtonColor = false
	tab.Text = ""
	tab.BackgroundColor3 = UIUtil.Palette.TealDark
	tab.BorderSizePixel = 0
	tab.AnchorPoint = Vector2.new(1, 0)
	tab.Position = UDim2.new(1, -2, 0, 0)
	tab.Size = UDim2.fromOffset(TAB_WIDTH, TAB_HEIGHT)
	local tabCorner = Instance.new("UICorner"); tabCorner.CornerRadius = UDim.new(0, 10); tabCorner.Parent = tab
	local tabStroke = Instance.new("UIStroke")
	tabStroke.Color = UIUtil.Palette.TealDeeper
	tabStroke.Thickness = 1.5
	tabStroke.Parent = tab
	tab.Parent = root

	local tabIcon = UIUtil.makeLabel("📜", "title", {
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 24,
	})
	tabIcon.Parent = tab
	local tabLabel = UIUtil.makeLabel("0/3", "subtitle", {
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	tabLabel.Parent = tab
	local tabHint = UIUtil.makeLabel("quests", "caption", {
		Position = UDim2.new(0, 0, 0, 64),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	tabHint.Parent = tab
	local tabBadgeBg = Instance.new("Frame")
	tabBadgeBg.BackgroundColor3 = UIUtil.Palette.Danger
	tabBadgeBg.BorderSizePixel = 0
	tabBadgeBg.AnchorPoint = Vector2.new(1, 0)
	tabBadgeBg.Position = UDim2.new(1, -4, 0, 4)
	tabBadgeBg.Size = UDim2.fromOffset(14, 14)
	tabBadgeBg.Visible = false
	local badgeC = Instance.new("UICorner"); badgeC.CornerRadius = UDim.new(1, 0); badgeC.Parent = tabBadgeBg
	tabBadgeBg.Parent = tab

	-- Expandable panel
	local panel = UIUtil.makePanel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(TAB_WIDTH + 6), 0, PANEL_OFFSET_Y),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		Visible = false,
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})
	panel.Parent = root

	-- Section: Today
	local todayHdr = UIUtil.makeLabel("Today's quests", "title", {
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, 24),
	})
	todayHdr.Parent = panel

	local todayList = Instance.new("Frame")
	todayList.BackgroundTransparency = 1
	todayList.Position = UDim2.new(0, 8, 0, 36)
	todayList.Size = UDim2.new(1, -16, 0, 224)
	todayList.Parent = panel
	local todayLayout = Instance.new("UIListLayout")
	todayLayout.SortOrder = Enum.SortOrder.LayoutOrder
	todayLayout.Padding = UDim.new(0, 6)
	todayLayout.Parent = todayList

	-- Section: Streak
	local streakHdr = UIUtil.makeLabel("Login streak", "title", {
		Position = UDim2.new(0, 12, 0, 268),
		Size = UDim2.new(1, -24, 0, 24),
	})
	streakHdr.Parent = panel
	local streakSlot = Instance.new("Frame")
	streakSlot.BackgroundTransparency = 1
	streakSlot.Position = UDim2.new(0, 8, 0, 296)
	streakSlot.Size = UDim2.new(1, -16, 0, 60)
	streakSlot.Parent = panel

	-- Section: Yesterday (only visible when there are unclaimed quests)
	local yesterdayHdr = UIUtil.makeLabel("Yesterday (claim before midnight)", "subtitle", {
		Position = UDim2.new(0, 12, 0, 360),
		Size = UDim2.new(1, -24, 0, 20),
		Visible = false,
	})
	yesterdayHdr.Parent = panel
	local yesterdayList = Instance.new("Frame")
	yesterdayList.BackgroundTransparency = 1
	yesterdayList.Position = UDim2.new(0, 8, 0, 382)
	yesterdayList.Size = UDim2.new(1, -16, 0, 60)
	yesterdayList.Visible = false
	yesterdayList.Parent = panel
	local yesterdayLayout = Instance.new("UIListLayout")
	yesterdayLayout.SortOrder = Enum.SortOrder.LayoutOrder
	yesterdayLayout.Padding = UDim.new(0, 4)
	yesterdayLayout.Parent = yesterdayList

	-- Section: Refresh countdown (bottom)
	local refreshLabel = UIUtil.makeLabel("New quests in --:--:--", "caption", {
		Position = UDim2.new(0, 12, 1, -28),
		Size = UDim2.new(1, -24, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	refreshLabel.Parent = panel

	-- ----------------- expansion state -----------------
	local expanded = false
	local function setExpanded(v: boolean)
		expanded = v
		panel.Visible = v
	end
	tab.Activated:Connect(function() setExpanded(not expanded) end)

	-- ----------------- popup queue -----------------
	-- Only one popup visible at a time. The queue holds pending ones.
	local popupQueue: {{kind: string, payload: any}} = {}
	local currentPopup: (() -> ())? = nil
	local processNext: () -> ()

	local function showCompletionPopup(quest: any, onClaim: (string) -> ())
		local popup, slideIn, slideOut = buildPopup(gui, "Quest complete!", quest.renderedText or "", false)
		local btn = UIUtil.makeButton("Claim", function()
			onClaim(quest.id)
			if currentPopup then currentPopup() end
		end, {
			Position = UDim2.new(0, 16, 1, -52),
			Size = UDim2.new(1, -32, 0, 38),
			TextSize = 14,
			variant = "primary",
		})
		btn.Parent = popup
		local rewardLabel = UIUtil.makeLabel(rewardSummary(quest.reward), "caption", {
			Position = UDim2.new(0, 16, 1, -78),
			Size = UDim2.new(1, -32, 0, 18),
			TextColor3 = UIUtil.Palette.Gold,
		})
		rewardLabel.Parent = popup
		slideIn()

		local dismissed = false
		local function dismiss()
			if dismissed then return end
			dismissed = true
			currentPopup = nil
			tabBadgeBg.Visible = true  -- mark "you've got reward(s) waiting"
			slideOut()
			task.spawn(processNext)
		end
		currentPopup = dismiss
		task.delay(GameConfig.Quests.CompletionPopupDuration, dismiss)
	end

	local function showStreakPopup(day: number, reward: any)
		local body = "Day " .. day .. " streak!  " .. rewardSummary(reward)
		if day == 7 or day == 14 or day == 21 or day == 28 then
			body = "Milestone reached!  " .. body
		end
		local popup, slideIn, slideOut = buildPopup(gui, ("Day %d streak!"):format(day), body, true)
		slideIn()
		local dismissed = false
		local function dismiss()
			if dismissed then return end
			dismissed = true
			currentPopup = nil
			slideOut()
			task.spawn(processNext)
		end
		currentPopup = dismiss
		task.delay(4.0, dismiss)
	end

	processNext = function()
		if currentPopup then return end
		local next_ = table.remove(popupQueue, 1)
		if not next_ then return end
		if next_.kind == "completion" then
			showCompletionPopup(next_.payload.quest, next_.payload.onClaim)
		elseif next_.kind == "streak" then
			showStreakPopup(next_.payload.day, next_.payload.reward)
		end
	end

	-- ----------------- snapshot apply -----------------
	local lastSnapshot: any = nil
	local function rebuildToday(today: {any}, onClaim: (string) -> ())
		for _, c in ipairs(todayList:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, q in ipairs(today) do
			local card = makeQuestCard(q, onClaim)
			card.LayoutOrder = i
			card.Parent = todayList
		end
	end
	local function rebuildYesterday(yesterday: {any}, onClaim: (string) -> ())
		for _, c in ipairs(yesterdayList:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local visible = #yesterday > 0
		yesterdayHdr.Visible = visible
		yesterdayList.Visible = visible
		for i, q in ipairs(yesterday) do
			local card = makeQuestCard(q, onClaim)
			card.LayoutOrder = i
			card.Parent = yesterdayList
		end
	end
	local function rebuildStreak(streak: any)
		for _, c in ipairs(streakSlot:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local row = makeStreakRow(streak and streak.current or 0)
		row.Size = UDim2.new(1, 0, 1, 0)
		row.Parent = streakSlot
	end
	local function refreshTabState(today: {any})
		local completed = 0
		local total = #today
		local hasClaim = false
		for _, q in ipairs(today) do
			if q.claimed then completed += 1 end
			if q.completed and not q.claimed then hasClaim = true end
		end
		tabLabel.Text = ("%d/%d"):format(completed, total)
		if hasClaim then
			tabLabel.TextColor3 = UIUtil.Palette.Gold
			tabBadgeBg.Visible = true
		elseif completed == total and total > 0 then
			tabLabel.TextColor3 = UIUtil.Palette.Success
			tabBadgeBg.Visible = false
		else
			tabLabel.TextColor3 = UIUtil.Palette.Cream
			tabBadgeBg.Visible = false
		end
	end

	local handle = {}

	function handle.refresh(snapshot: any, onClaim: (string) -> ())
		lastSnapshot = snapshot
		rebuildToday(snapshot.today or {}, onClaim)
		rebuildYesterday(snapshot.yesterday or {}, onClaim)
		rebuildStreak(snapshot.streak)
		refreshTabState(snapshot.today or {})
	end

	function handle.tickCountdown()
		if not lastSnapshot then
			refreshLabel.Text = "New quests in --:--:--"
			return
		end
		local secs = (lastSnapshot.refreshesAt or 0) - os.time()
		refreshLabel.Text = "New quests in " .. formatHMS(secs)
		-- Tab pulse when refresh is imminent.
		if secs > 0 and secs < 300 then
			local t = (os.clock() % 1.5) / 1.5
			tabStroke.Transparency = 0.2 + 0.5 * math.abs(math.sin(t * math.pi))
		else
			tabStroke.Transparency = 0.3
		end
	end

	function handle.queueCompletion(quest: any, onClaim: (string) -> ())
		table.insert(popupQueue, { kind = "completion", payload = { quest = quest, onClaim = onClaim } })
		processNext()
	end

	function handle.queueStreak(day: number, reward: any)
		table.insert(popupQueue, { kind = "streak", payload = { day = day, reward = reward } })
		processNext()
	end

	function handle.setExpanded(v: boolean)
		setExpanded(v)
	end

	function handle.destroy()
		gui:Destroy()
	end

	handle.gui = gui
	handle.tab = tab
	handle.panel = panel
	return handle
end

return QuestTrackerUI
