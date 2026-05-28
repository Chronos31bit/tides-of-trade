-- Command bar: build QuestTrackerUI_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar. Re-running replaces the template.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local S = GameConfig.UI.Spacing
local R = GameConfig.UI.Radii

local P = {
	TealDark = Color3.fromRGB(18, 52, 60),
	TealDeeper = Color3.fromRGB(10, 32, 40),
	TealLight = Color3.fromRGB(78, 156, 162),
	Cream = Color3.fromRGB(244, 230, 200),
	CreamSoft = Color3.fromRGB(208, 198, 178),
	Sunset = Color3.fromRGB(232, 138, 86),
	SunsetDeep = Color3.fromRGB(196, 86, 64),
	Gold = Color3.fromRGB(220, 180, 88),
	Success = Color3.fromRGB(120, 200, 130),
	Danger = Color3.fromRGB(220, 100, 100),
	Common = Color3.fromRGB(176, 182, 190),
}

local TAB_W, TAB_H = 56, 110
local PANEL_W, PANEL_H = 340, 480
local ROW_H = 70

local function boolValue(parent: Instance, name: string, value: boolean)
	local v = Instance.new("BoolValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function stringValue(parent: Instance, name: string, value: string)
	local v = Instance.new("StringValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function numberValue(parent: Instance, name: string, value: number)
	local v = Instance.new("NumberValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("[QuestTracker] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("QuestTrackerUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "QuestTrackerUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "QuestTracker")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "RespectTopbar", true)
numberValue(meta, "ClaimTweenDuration", 0.35)
numberValue(meta, "ClaimTweenEasingStyle", Enum.EasingStyle.Quint.Value)
numberValue(meta, "ClaimTweenEasingDirection", Enum.EasingDirection.Out.Value)
numberValue(meta, "PopupSlideOffsetPx", 320)
numberValue(meta, "PopupRestOffsetX", -12)

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.AnchorPoint = Vector2.new(1, 0)
root.Position = UDim2.new(1, 0, 0, 140)
root.Size = UDim2.fromOffset(PANEL_W + TAB_W + 12, PANEL_H + 20)
root.Parent = gui

local tab = Instance.new("TextButton")
tab.Name = "Tab"
tab.AutoButtonColor = false
tab.Text = ""
tab.BackgroundColor3 = P.TealDark
tab.BorderSizePixel = 0
tab.AnchorPoint = Vector2.new(1, 0)
tab.Position = UDim2.new(1, -2, 0, 0)
tab.Size = UDim2.fromOffset(TAB_W, TAB_H)
tab.Parent = root
corner(tab, R.md)
local tabStroke = Instance.new("UIStroke")
tabStroke.Name = "TabStroke"
tabStroke.Color = P.TealDeeper
tabStroke.Thickness = 1.5
tabStroke.Transparency = 0.3
tabStroke.Parent = tab

local tabIcon = Instance.new("TextLabel")
tabIcon.Name = "TabIcon"
tabIcon.BackgroundTransparency = 1
tabIcon.Text = "📜"
tabIcon.Font = Enum.Font.GothamBold
tabIcon.TextSize = 24
tabIcon.TextColor3 = P.Cream
tabIcon.Size = UDim2.new(1, 0, 0, 28)
tabIcon.Position = UDim2.new(0, 0, 0, 8)
tabIcon.Parent = tab

local tabLabel = Instance.new("TextLabel")
tabLabel.Name = "TabLabel"
tabLabel.BackgroundTransparency = 1
tabLabel.Text = "0/3"
tabLabel.Font = Enum.Font.GothamMedium
tabLabel.TextSize = 16
tabLabel.TextColor3 = P.Cream
tabLabel.Size = UDim2.new(1, 0, 0, 22)
tabLabel.Position = UDim2.new(0, 0, 0, 40)
tabLabel.Parent = tab

local tabHint = Instance.new("TextLabel")
tabHint.Name = "TabHint"
tabHint.BackgroundTransparency = 1
tabHint.Text = "quests"
tabHint.Font = Enum.Font.Gotham
tabHint.TextSize = 12
tabHint.TextColor3 = P.CreamSoft
tabHint.Size = UDim2.new(1, 0, 0, 18)
tabHint.Position = UDim2.new(0, 0, 0, 64)
tabHint.Parent = tab

local tabBadge = Instance.new("Frame")
tabBadge.Name = "TabBadge"
tabBadge.BackgroundColor3 = P.Danger
tabBadge.BorderSizePixel = 0
tabBadge.AnchorPoint = Vector2.new(1, 0)
tabBadge.Position = UDim2.new(1, -4, 0, 4)
tabBadge.Size = UDim2.fromOffset(14, 14)
tabBadge.Visible = false
tabBadge.Parent = tab
corner(tabBadge, 999)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.BackgroundColor3 = P.TealDark
panel.BorderSizePixel = 0
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -(TAB_W + 6), 0, 0)
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.Visible = false
panel.Parent = root
corner(panel, R.lg)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = P.TealDeeper
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.25
panelStroke.Parent = panel

local todayHdr = Instance.new("TextLabel")
todayHdr.Name = "TodayHeader"
todayHdr.BackgroundTransparency = 1
todayHdr.Text = "Today's quests"
todayHdr.Font = Enum.Font.GothamBold
todayHdr.TextSize = 20
todayHdr.TextColor3 = P.Cream
todayHdr.Position = UDim2.fromOffset(12, 8)
todayHdr.Size = UDim2.new(1, -24, 0, 24)
todayHdr.Parent = panel

local todayList = Instance.new("Frame")
todayList.Name = "TodayList"
todayList.BackgroundTransparency = 1
todayList.Position = UDim2.new(0, 8, 0, 36)
todayList.Size = UDim2.new(1, -16, 0, 224)
todayList.Parent = panel
local todayLayout = Instance.new("UIListLayout")
todayLayout.SortOrder = Enum.SortOrder.LayoutOrder
todayLayout.Padding = UDim.new(0, 6)
todayLayout.Parent = todayList

local allComplete = Instance.new("Frame")
allComplete.Name = "AllCompleteBanner"
allComplete.BackgroundColor3 = P.Success
allComplete.BackgroundTransparency = 0.85
allComplete.BorderSizePixel = 0
allComplete.Position = UDim2.new(0, 8, 0, 36)
allComplete.Size = UDim2.new(1, -16, 0, 40)
allComplete.Visible = false
allComplete.Parent = panel
corner(allComplete, R.md)
local allCompleteLbl = Instance.new("TextLabel")
allCompleteLbl.Name = "AllCompleteLabel"
allCompleteLbl.BackgroundTransparency = 1
allCompleteLbl.Text = "All quests complete for today!"
allCompleteLbl.Font = Enum.Font.GothamBold
allCompleteLbl.TextSize = 14
allCompleteLbl.TextColor3 = P.Success
allCompleteLbl.Size = UDim2.fromScale(1, 1)
allCompleteLbl.Parent = allComplete

local streakHdr = Instance.new("TextLabel")
streakHdr.Name = "StreakHeader"
streakHdr.BackgroundTransparency = 1
streakHdr.Text = "Login streak"
streakHdr.Font = Enum.Font.GothamBold
streakHdr.TextSize = 20
streakHdr.TextColor3 = P.Cream
streakHdr.Position = UDim2.fromOffset(12, 268)
streakHdr.Size = UDim2.new(1, -24, 0, 24)
streakHdr.Parent = panel

local streakBanner = Instance.new("Frame")
streakBanner.Name = "StreakBanner"
streakBanner.BackgroundTransparency = 1
streakBanner.Position = UDim2.new(0, 8, 0, 296)
streakBanner.Size = UDim2.new(1, -16, 0, 60)
streakBanner.Parent = panel

local yesterdayHdr = Instance.new("TextLabel")
yesterdayHdr.Name = "YesterdayHeader"
yesterdayHdr.BackgroundTransparency = 1
yesterdayHdr.Text = "Yesterday (claim before midnight)"
yesterdayHdr.Font = Enum.Font.GothamMedium
yesterdayHdr.TextSize = 16
yesterdayHdr.TextColor3 = P.CreamSoft
yesterdayHdr.Position = UDim2.fromOffset(12, 360)
yesterdayHdr.Size = UDim2.new(1, -24, 0, 20)
yesterdayHdr.Visible = false
yesterdayHdr.Parent = panel

local yesterdayList = Instance.new("Frame")
yesterdayList.Name = "YesterdayList"
yesterdayList.BackgroundTransparency = 1
yesterdayList.Position = UDim2.new(0, 8, 0, 382)
yesterdayList.Size = UDim2.new(1, -16, 0, 60)
yesterdayList.Visible = false
yesterdayList.Parent = panel
local yLayout = Instance.new("UIListLayout")
yLayout.SortOrder = Enum.SortOrder.LayoutOrder
yLayout.Padding = UDim.new(0, 4)
yLayout.Parent = yesterdayList

local refreshLbl = Instance.new("TextLabel")
refreshLbl.Name = "RefreshLabel"
refreshLbl.BackgroundTransparency = 1
refreshLbl.Text = "New quests in --:--:--"
refreshLbl.Font = Enum.Font.Gotham
refreshLbl.TextSize = 12
refreshLbl.TextColor3 = P.CreamSoft
refreshLbl.Position = UDim2.new(0, 12, 1, -28)
refreshLbl.Size = UDim2.new(1, -24, 0, 20)
refreshLbl.TextXAlignment = Enum.TextXAlignment.Center
refreshLbl.Parent = panel

local rowTpl = Instance.new("Frame")
rowTpl.Name = "QuestRow_Template"
rowTpl.BackgroundColor3 = P.TealDark
rowTpl.BorderSizePixel = 0
rowTpl.Size = UDim2.new(1, -8, 0, ROW_H)
rowTpl.Visible = false
rowTpl.Parent = root
corner(rowTpl, R.md)

local accent = Instance.new("Frame")
accent.Name = "AccentBar"
accent.BackgroundColor3 = P.Common
accent.BorderSizePixel = 0
accent.Size = UDim2.new(0, 4, 1, -8)
accent.Position = UDim2.fromOffset(4, 4)
accent.Parent = rowTpl
corner(accent, 2)

local catIcon = Instance.new("TextLabel")
catIcon.Name = "CategoryIcon"
catIcon.BackgroundTransparency = 1
catIcon.Text = "🎣"
catIcon.Font = Enum.Font.GothamBold
catIcon.TextSize = 20
catIcon.TextColor3 = P.Cream
catIcon.Size = UDim2.fromOffset(28, 28)
catIcon.Position = UDim2.fromOffset(14, 8)
catIcon.Parent = rowTpl

local questText = Instance.new("TextLabel")
questText.Name = "QuestText"
questText.BackgroundTransparency = 1
questText.Text = "Quest"
questText.Font = Enum.Font.GothamMedium
questText.TextSize = 13
questText.TextColor3 = P.Cream
questText.TextWrapped = true
questText.TextXAlignment = Enum.TextXAlignment.Left
questText.Position = UDim2.new(0, 46, 0, 6)
questText.Size = UDim2.new(1, -56, 0, 22)
questText.Parent = rowTpl

local barBg = Instance.new("Frame")
barBg.Name = "ProgressBg"
barBg.BackgroundColor3 = P.TealDeeper
barBg.BorderSizePixel = 0
barBg.Position = UDim2.new(0, 46, 0, 30)
barBg.Size = UDim2.new(1, -56, 0, 8)
barBg.Parent = rowTpl
corner(barBg, 4)

local barFill = Instance.new("Frame")
barFill.Name = "ProgressFill"
barFill.BackgroundColor3 = P.Common
barFill.BorderSizePixel = 0
barFill.Size = UDim2.new(0.5, 0, 1, 0)
barFill.Parent = barBg
corner(barFill, 4)

local progLbl = Instance.new("TextLabel")
progLbl.Name = "ProgressLabel"
progLbl.BackgroundTransparency = 1
progLbl.Text = "0 / 1"
progLbl.Font = Enum.Font.Gotham
progLbl.TextSize = 12
progLbl.TextColor3 = P.CreamSoft
progLbl.Position = UDim2.new(0, 46, 0, 40)
progLbl.Size = UDim2.new(0.5, -28, 0, 18)
progLbl.Parent = rowTpl

local rewardLbl = Instance.new("TextLabel")
rewardLbl.Name = "RewardLabel"
rewardLbl.BackgroundTransparency = 1
rewardLbl.Text = ""
rewardLbl.Font = Enum.Font.Gotham
rewardLbl.TextSize = 12
rewardLbl.TextColor3 = P.Gold
rewardLbl.TextXAlignment = Enum.TextXAlignment.Right
rewardLbl.Position = UDim2.new(0.5, 0, 0, 40)
rewardLbl.Size = UDim2.new(0.5, -10, 0, 18)
rewardLbl.Parent = rowTpl

local claimBtn = Instance.new("TextButton")
claimBtn.Name = "ClaimButton"
claimBtn.AutoButtonColor = false
claimBtn.Text = "Claim"
claimBtn.Font = Enum.Font.GothamBold
claimBtn.TextSize = 13
claimBtn.TextColor3 = P.Cream
claimBtn.BackgroundColor3 = P.TealLight
claimBtn.BorderSizePixel = 0
claimBtn.AnchorPoint = Vector2.new(1, 0.5)
claimBtn.Position = UDim2.new(1, -8, 0.5, 0)
claimBtn.Size = UDim2.fromOffset(70, 30)
claimBtn.Visible = false
claimBtn.Parent = rowTpl
corner(claimBtn, R.sm)

local doneLbl = Instance.new("TextLabel")
doneLbl.Name = "DoneLabel"
doneLbl.BackgroundTransparency = 1
doneLbl.Text = "✓ Done"
doneLbl.Font = Enum.Font.Gotham
doneLbl.TextSize = 12
doneLbl.TextColor3 = P.Success
doneLbl.TextXAlignment = Enum.TextXAlignment.Right
doneLbl.AnchorPoint = Vector2.new(1, 0.5)
doneLbl.Position = UDim2.new(1, -10, 0.5, 0)
doneLbl.Size = UDim2.fromOffset(60, 22)
doneLbl.Visible = false
doneLbl.Parent = rowTpl

gui.Parent = assets

print("[QuestTracker] Built QuestTrackerUI_Template under StarterGui.StarterGuiAssets.")
print("[QuestTracker] Save to file: src/StarterGuiAssets/QuestTrackerUI_Template.rbxmx")
