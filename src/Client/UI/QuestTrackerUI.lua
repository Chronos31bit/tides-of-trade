--!strict
-- QuestTrackerUI.lua
-- Pinned-right-edge quest tracker. Layout from StarterGuiAssets.QuestTrackerUI_Template;
-- behavior wiring only. State from server snapshots via QuestTrackerController.
--
-- QuestService.Client signals (wired in QuestTrackerController):
--   QuestsRefreshed(snapshot) — profile load, daily roll, claim, debounced progress
--   QuestCompleted(questId) — completion popup queue
--   StreakAdvanced(day, reward) — streak popup queue
-- onClaim(questId) -> QuestService:Claim(questId)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIUtil = require(script.Parent.UIUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local QuestTrackerUI = {}

local P = UIUtil.Palette

local TAB_WIDTH = 56
local POPUP_WIDTH = 300
local POPUP_HEIGHT = 160

local CATEGORY_ICON = {
	fishing = "🎣",
	market = "🪙",
	social = "👋",
	building = "🔨",
	exploration = "🧭",
}

local function requireChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[QuestTrackerUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

local function accentForDifficulty(difficulty: string): Color3
	if difficulty == "easy" then
		return P.Common
	end
	if difficulty == "medium" then
		return P.Uncommon
	end
	if difficulty == "hard" then
		return P.Rare
	end
	if difficulty == "tutorial" then
		return P.Sunset
	end
	return P.Common
end

local function formatHMS(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function rewardSummary(reward: any): string
	if not reward then
		return ""
	end
	local parts: {string} = {}
	if reward.coins and reward.coins > 0 then
		table.insert(parts, ("%d coins"):format(reward.coins))
	end
	if reward.xp and reward.xp > 0 then
		table.insert(parts, ("%d XP"):format(reward.xp))
	end
	if reward.lureTokens and reward.lureTokens > 0 then
		table.insert(parts, ("%d lure"):format(reward.lureTokens))
	end
	if reward.items then
		for _, it in ipairs(reward.items) do
			table.insert(parts, ("%dx %s"):format(it.count or 1, it.id))
		end
	end
	return table.concat(parts, ", ")
end

local function enumItemFromValue(enumType: Enum, value: number): EnumItem
	for _, item in ipairs(enumType:GetEnumItems()) do
		if item.Value == value then
			return item
		end
	end
	return enumType.Quad
end

local function readClaimTweenInfo(meta: Folder?): TweenInfo
	local duration = 0.35
	local style: Enum.EasingStyle = Enum.EasingStyle.Quint
	local direction: Enum.EasingDirection = Enum.EasingDirection.Out
	if meta then
		local d = meta:FindFirstChild("ClaimTweenDuration")
		if d and d:IsA("NumberValue") then
			duration = d.Value
		end
		local s = meta:FindFirstChild("ClaimTweenEasingStyle")
		if s and s:IsA("NumberValue") then
			style = enumItemFromValue(Enum.EasingStyle, s.Value) :: Enum.EasingStyle
		end
		local dir = meta:FindFirstChild("ClaimTweenEasingDirection")
		if dir and dir:IsA("NumberValue") then
			direction = enumItemFromValue(Enum.EasingDirection, dir.Value) :: Enum.EasingDirection
		end
	end
	return TweenInfo.new(duration, style, direction)
end

local function readPopupOffsets(meta: Folder?): (number, number)
	local slideOffset = POPUP_WIDTH + 20
	local restOffset = -12
	if meta then
		local so = meta:FindFirstChild("PopupSlideOffsetPx")
		if so and so:IsA("NumberValue") then
			slideOffset = so.Value
		end
		local ro = meta:FindFirstChild("PopupRestOffsetX")
		if ro and ro:IsA("NumberValue") then
			restOffset = ro.Value
		end
	end
	return slideOffset, restOffset
end

function QuestTrackerUI.create()
	local gui = TemplateLoader.spawn("QuestTracker", { instanceName = "QuestTrackerUI" })
	local meta = gui:FindFirstChild("Meta")
	local claimTweenInfo = readClaimTweenInfo(if meta and meta:IsA("Folder") then meta else nil)
	local popupSlideOffset, popupRestOffset = readPopupOffsets(if meta and meta:IsA("Folder") then meta else nil)

	local root = requireChild(gui, "Root", "Frame") :: Frame
	local tab = requireChild(root, "Tab", "TextButton") :: TextButton
	local tabStroke = requireChild(tab, "TabStroke", "UIStroke") :: UIStroke
	local tabLabel = requireChild(tab, "TabLabel", "TextLabel") :: TextLabel
	local tabBadgeBg = requireChild(tab, "TabBadge", "Frame") :: Frame
	local panel = requireChild(root, "Panel", "Frame") :: Frame
	local todayList = requireChild(panel, "TodayList", "Frame")
	local allCompleteBanner = requireChild(panel, "AllCompleteBanner", "Frame")
	local streakBanner = requireChild(panel, "StreakBanner", "Frame")
	local yesterdayHdr = requireChild(panel, "YesterdayHeader", "TextLabel") :: TextLabel
	local yesterdayList = requireChild(panel, "YesterdayList", "Frame")
	local refreshLabel = requireChild(panel, "RefreshLabel", "TextLabel") :: TextLabel
	local rowTpl = requireChild(root, "QuestRow_Template", "Frame")

	local expanded = false
	local function setExpanded(v: boolean)
		expanded = v
		panel.Visible = v
	end
	tab.Activated:Connect(function()
		setExpanded(not expanded)
	end)

	local function makeStreakRow(streakDay: number): Frame
		local container = Instance.new("Frame")
		container.BackgroundTransparency = 1
		container.Size = UDim2.new(1, 0, 1, 0)

		local cycleDay = ((streakDay - 1) % 7) + 1
		local weekNumber = math.floor((streakDay - 1) / 7) + 1

		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 36)
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
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = circle
			local stroke = Instance.new("UIStroke")
			stroke.Color = P.TealLight
			stroke.Thickness = 1.5
			stroke.Parent = circle

			local fill = P.TealDeeper
			local textColor = P.CreamSoft
			if i < cycleDay then
				fill = P.Sunset
				textColor = P.Cream
			elseif i == cycleDay then
				fill = P.SunsetDeep
				textColor = P.Cream
				stroke.Color = P.Sunset
				stroke.Thickness = 2.5
			end
			if i == 7 then
				stroke.Color = P.Lure
				stroke.Thickness = if i == cycleDay then 3 else 2
			end
			circle.BackgroundColor3 = fill

			local lbl = UIUtil.makeLabel(tostring(i), "subtitle", {
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = textColor,
				TextSize = 13,
				Parent = circle,
			})
			lbl = lbl
			circle.Parent = row
		end

		UIUtil.makeLabel(("Day %d streak — back tomorrow for the next reward."):format(streakDay), "caption", {
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 0, 38),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = container,
		})

		if weekNumber > 1 then
			UIUtil.makeLabel(("Week %d"):format(weekNumber), "caption", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 0),
				Size = UDim2.fromOffset(60, 14),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = P.Gold,
				Parent = container,
			})
		end

		return container
	end

	local function buildPopup(parent: Instance, title: string, body: string, isStreak: boolean): (Frame, () -> (), () -> ())
		local popup = UIUtil.makePanel({
			Size = UDim2.fromOffset(POPUP_WIDTH, if isStreak then 110 else POPUP_HEIGHT),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, popupSlideOffset, 0, 90),
			BackgroundColor3 = if isStreak then P.SunsetDeep else P.TealDark,
		})
		popup.Parent = parent

		UIUtil.makeLabel(title, "title", {
			Position = UDim2.new(0, 16, 0, 12),
			Size = UDim2.new(1, -32, 0, 24),
			TextColor3 = if isStreak then P.Cream else P.Sunset,
			Parent = popup,
		})

		UIUtil.makeLabel(body, "body", {
			Position = UDim2.new(0, 16, 0, 40),
			Size = UDim2.new(1, -32, 0, if isStreak then 50 else 70),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = popup,
		})

		local restPos = UDim2.new(1, popupRestOffset, 0, 90)
		local function slideIn()
			MotionUtil.tweenOrSnap(popup, claimTweenInfo, { Position = restPos })
		end

		local function slideOut(onDone: (() -> ())?)
			if MotionUtil.reducedMotionEnabled() then
				popup:Destroy()
				if onDone then
					onDone()
				end
				return
			end
			local outTween = MotionUtil.tween(popup, claimTweenInfo, {
				Position = UDim2.new(1, popupSlideOffset, 0, 90),
			})
			outTween.Completed:Connect(function()
				outTween:Destroy()
				popup:Destroy()
				if onDone then
					onDone()
				end
			end)
		end

		return popup, slideIn, function()
			slideOut()
		end
	end

	local popupQueue: {{kind: string, payload: any}} = {}
	local currentPopup: (() -> ())? = nil
	local processNext: () -> ()

	local function makeQuestRow(quest: any, onClaim: (string) -> ()): Frame
		local card = rowTpl:Clone()
		card.Name = "Quest_" .. (quest.id or "row")
		card.Visible = true

		local accent = requireChild(card, "AccentBar", "Frame") :: Frame
		accent.BackgroundColor3 = accentForDifficulty(quest.difficulty)

		local icon = requireChild(card, "CategoryIcon", "TextLabel") :: TextLabel
		icon.Text = CATEGORY_ICON[quest.category] or "•"

		local text = requireChild(card, "QuestText", "TextLabel") :: TextLabel
		text.Text = quest.renderedText or quest.templateId or "Quest"

		local barBg = requireChild(card, "ProgressBg", "Frame")
		local fill = requireChild(barBg, "ProgressFill", "Frame") :: Frame
		local frac = if quest.target > 0 then math.clamp(quest.progress / quest.target, 0, 1) else 0
		fill.Size = UDim2.new(frac, 0, 1, 0)
		fill.BackgroundColor3 = accentForDifficulty(quest.difficulty)

		local prog = requireChild(card, "ProgressLabel", "TextLabel") :: TextLabel
		prog.Text = ("%d / %d"):format(quest.progress, quest.target)

		local reward = requireChild(card, "RewardLabel", "TextLabel") :: TextLabel
		reward.Text = rewardSummary(quest.reward)

		local claimBtn = card:FindFirstChild("ClaimButton")
		local doneLbl = card:FindFirstChild("DoneLabel")

		if quest.completed and not quest.claimed and claimBtn and claimBtn:IsA("TextButton") then
			claimBtn.Visible = true
			-- 44px min touch target (design pillar: mobile-first accessibility)
			local sizeConstraint = Instance.new("UISizeConstraint")
			sizeConstraint.MinSize = Vector2.new(0, UIUtil.MinTouchPx)
			sizeConstraint.Parent = claimBtn
			claimBtn.Activated:Connect(function()
				onClaim(quest.id)
			end)
		elseif quest.claimed then
			card.Size = UDim2.new(1, -8, 0, 28)
			text.Size = UDim2.new(1, -56, 1, 0)
			barBg.Visible = false
			prog.Visible = false
			reward.Visible = false
			if claimBtn and claimBtn:IsA("GuiObject") then
				claimBtn.Visible = false
			end
			if doneLbl and doneLbl:IsA("TextLabel") then
				doneLbl.Visible = true
			end
		end

		return card
	end

	local function clearList(list: Frame)
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
	end

	local function showCompletionPopup(quest: any, onClaim: (string) -> ())
		local popup, slideIn, slideOut = buildPopup(gui, "Quest complete!", quest.renderedText or "", false)
		local btn = UIUtil.makeButton("Claim", function()
			onClaim(quest.id)
			if currentPopup then
				currentPopup()
			end
		end, {
			Position = UDim2.new(0, 16, 1, -52),
			Size = UDim2.new(1, -32, 0, 38),
			TextSize = 14,
			variant = "primary",
		})
		btn.Parent = popup
		UIUtil.makeLabel(rewardSummary(quest.reward), "caption", {
			Position = UDim2.new(0, 16, 1, -78),
			Size = UDim2.new(1, -32, 0, 18),
			TextColor3 = P.Gold,
			Parent = popup,
		})
		slideIn()

		local dismissed = false
		local function dismiss()
			if dismissed then
				return
			end
			dismissed = true
			currentPopup = nil
			tabBadgeBg.Visible = true
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
			if dismissed then
				return
			end
			dismissed = true
			currentPopup = nil
			slideOut()
			task.spawn(processNext)
		end
		currentPopup = dismiss
		task.delay(4.0, dismiss)
	end

	-- Welcome-back popup: shown when a player returns after an extended
	-- absence. Uses a warm "Welcome back!" tone — not a streak, no FOMO.
	local function showWelcomeBackPopup(daysAway: number, coinsGranted: number)
		local title = ("Welcome back after %d days!"):format(daysAway)
		local body = ("We missed you! Here's %d coins to help you get settled."):format(coinsGranted)
		local popup, slideIn, slideOut = buildPopup(gui, title, body, false)
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
		task.delay(4.5, dismiss)
	end

	processNext = function()
		if currentPopup then
			return
		end
		local next_ = table.remove(popupQueue, 1)
		if not next_ then
			return
		end
		if next_.kind == "completion" then
			showCompletionPopup(next_.payload.quest, next_.payload.onClaim)
		elseif next_.kind == "streak" then
			showStreakPopup(next_.payload.day, next_.payload.reward)
		elseif next_.kind == "welcome_back" then
			showWelcomeBackPopup(next_.payload.daysAway, next_.payload.coinsGranted)
		end
	end

	local lastSnapshot: any = nil

	local function refreshTabState(today: {any})
		local completed = 0
		local total = #today
		local hasClaim = false
		local allClaimed = total > 0
		for _, q in ipairs(today) do
			if q.claimed then
				completed += 1
			else
				allClaimed = false
			end
			if q.completed and not q.claimed then
				hasClaim = true
			end
		end
		tabLabel.Text = ("%d/%d"):format(completed, total)
		if hasClaim then
			tabLabel.TextColor3 = P.Gold
			tabBadgeBg.Visible = true
		elseif completed == total and total > 0 then
			tabLabel.TextColor3 = P.Success
			tabBadgeBg.Visible = false
		else
			tabLabel.TextColor3 = P.Cream
			tabBadgeBg.Visible = false
		end
		allCompleteBanner.Visible = allClaimed
	end

	local handle = {}

	function handle.refresh(snapshot: any, onClaim: (string) -> ())
		lastSnapshot = snapshot
		clearList(todayList)
		for i, q in ipairs(snapshot.today or {}) do
			local row = makeQuestRow(q, onClaim)
			row.LayoutOrder = i
			row.Parent = todayList
		end

		clearList(yesterdayList)
		local yesterday = snapshot.yesterday or {}
		local yVisible = #yesterday > 0
		yesterdayHdr.Visible = yVisible
		yesterdayList.Visible = yVisible
		for i, q in ipairs(yesterday) do
			local row = makeQuestRow(q, onClaim)
			row.LayoutOrder = i
			row.Parent = yesterdayList
		end

		for _, c in ipairs(streakBanner:GetChildren()) do
			c:Destroy()
		end
		local row = makeStreakRow(snapshot.streak and snapshot.streak.current or 0)
		row.Parent = streakBanner

		refreshTabState(snapshot.today or {})
	end

	function handle.tickCountdown()
		if not lastSnapshot then
			refreshLabel.Text = "New quests in --:--:--"
			return
		end
		local secs = (lastSnapshot.refreshesAt or 0) - os.time()
		refreshLabel.Text = "New quests in " .. formatHMS(secs)
		if secs > 0 and secs < 300 then
			if not MotionUtil.reducedMotionEnabled() then
				local t = (os.clock() % 1.5) / 1.5
				tabStroke.Transparency = 0.2 + 0.5 * math.abs(math.sin(t * math.pi))
			else
				tabStroke.Transparency = 0.2
			end
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

	function handle.queueWelcomeBack(daysAway: number, coinsGranted: number)
		table.insert(popupQueue, { kind = "welcome_back", payload = { daysAway = daysAway, coinsGranted = coinsGranted } })
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
