-- Command bar: build SocialUI_Template under StarterGui.StarterGuiAssets.

local StarterGui = game:GetService("StarterGui")

local P = {
	TealDark = Color3.fromRGB(18, 52, 60),
	TealDeeper = Color3.fromRGB(10, 32, 40),
	Teal = Color3.fromRGB(38, 102, 110),
	Sunset = Color3.fromRGB(232, 138, 86),
	Cream = Color3.fromRGB(244, 230, 200),
	CreamSoft = Color3.fromRGB(208, 198, 178),
	Success = Color3.fromRGB(120, 200, 130),
}

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
	error("[SocialUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("SocialUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "SocialUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "Modal")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "IgnoreGuiInset", true)
numberValue(meta, "FadeDuration", 0.18)
numberValue(meta, "SlideOffsetPx", 16)

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.BackgroundTransparency = 1
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.92, 0, 0.7, 0)
panel.BackgroundColor3 = P.TealDark
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 12)
local cap = Instance.new("UISizeConstraint")
cap.MaxSize = Vector2.new(440, 99999)
cap.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundColor3 = P.TealDeeper
header.Size = UDim2.new(1, 0, 0, 56)
header.Parent = panel
corner(header, 12)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Crew & Friends"
title.TextColor3 = P.Cream
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.Position = UDim2.new(0, 16, 0, 0)
title.Size = UDim2.new(1, -92, 1, 0)
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AutoButtonColor = false
closeBtn.BackgroundColor3 = P.Teal
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = P.Cream
closeBtn.TextScaled = true
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(44, 44)
closeBtn.Parent = header
corner(closeBtn, 10)

local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Position = UDim2.new(0, 0, 0, 56)
body.Size = UDim2.new(1, 0, 1, -56)
body.Parent = panel

local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingLeft = UDim.new(0, 16)
bodyPad.PaddingRight = UDim.new(0, 16)
bodyPad.PaddingTop = UDim.new(0, 12)
bodyPad.PaddingBottom = UDim.new(0, 16)
bodyPad.Parent = body

local tabs = Instance.new("Frame")
tabs.Name = "Tabs"
tabs.BackgroundTransparency = 1
tabs.Size = UDim2.new(1, 0, 0, 36)
tabs.Parent = body
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabs

local tabCrew = Instance.new("TextButton")
tabCrew.Name = "TabCrew"
tabCrew.AutoButtonColor = false
tabCrew.BackgroundColor3 = P.Sunset
tabCrew.Font = Enum.Font.GothamBold
tabCrew.Text = "Crew"
tabCrew.TextColor3 = P.Cream
tabCrew.TextSize = 14
tabCrew.Size = UDim2.fromOffset(100, 36)
tabCrew.LayoutOrder = 1
tabCrew.Parent = tabs
corner(tabCrew, 8)

local tabFriends = Instance.new("TextButton")
tabFriends.Name = "TabFriends"
tabFriends.AutoButtonColor = false
tabFriends.BackgroundColor3 = P.Teal
tabFriends.Font = Enum.Font.GothamBold
tabFriends.Text = "Friends"
tabFriends.TextColor3 = P.CreamSoft
tabFriends.TextSize = 14
tabFriends.Size = UDim2.fromOffset(100, 36)
tabFriends.LayoutOrder = 2
tabFriends.Parent = tabs
corner(tabFriends, 8)

local crewPanel = Instance.new("Frame")
crewPanel.Name = "CrewPanel"
crewPanel.BackgroundTransparency = 1
crewPanel.Position = UDim2.new(0, 0, 0, 44)
crewPanel.Size = UDim2.new(1, 0, 1, -44)
crewPanel.Parent = body

local crewCard = Instance.new("Frame")
crewCard.Name = "CrewCard"
crewCard.BackgroundColor3 = P.Teal
crewCard.Size = UDim2.new(1, 0, 0, 72)
crewCard.Parent = crewPanel
corner(crewCard, 10)

local crewTitle = Instance.new("TextLabel")
crewTitle.Name = "CrewTitle"
crewTitle.BackgroundTransparency = 1
crewTitle.Font = Enum.Font.GothamBold
crewTitle.Text = "Crew"
crewTitle.TextColor3 = P.Cream
crewTitle.TextSize = 16
crewTitle.Position = UDim2.new(0, 16, 0, 8)
crewTitle.Size = UDim2.new(1, -32, 0, 22)
crewTitle.Parent = crewCard

local crewBlurb = Instance.new("TextLabel")
crewBlurb.Name = "CrewBlurb"
crewBlurb.BackgroundTransparency = 1
crewBlurb.Font = Enum.Font.Gotham
crewBlurb.Text = "Crew browser coming soon — invite, chat, share daily haul."
crewBlurb.TextColor3 = P.CreamSoft
crewBlurb.TextSize = 12
crewBlurb.TextWrapped = true
crewBlurb.Position = UDim2.new(0, 16, 0, 32)
crewBlurb.Size = UDim2.new(1, -32, 0, 32)
crewBlurb.Parent = crewCard

local emotesHeader = Instance.new("TextLabel")
emotesHeader.Name = "EmotesHeader"
emotesHeader.BackgroundTransparency = 1
emotesHeader.Font = Enum.Font.GothamBold
emotesHeader.Text = "EMOTES"
emotesHeader.TextColor3 = P.CreamSoft
emotesHeader.TextSize = 12
emotesHeader.Position = UDim2.new(0, 0, 0, 80)
emotesHeader.Size = UDim2.new(1, 0, 0, 18)
emotesHeader.Parent = crewPanel

local emoteStack = Instance.new("Frame")
emoteStack.Name = "EmoteStack"
emoteStack.BackgroundTransparency = 1
emoteStack.Position = UDim2.new(0, 0, 0, 104)
emoteStack.Size = UDim2.new(1, 0, 1, -104)
emoteStack.Parent = crewPanel
Instance.new("UIListLayout", emoteStack).Padding = UDim.new(0, 8)

local friendsPanel = Instance.new("Frame")
friendsPanel.Name = "FriendsPanel"
friendsPanel.BackgroundTransparency = 1
friendsPanel.Position = UDim2.new(0, 0, 0, 44)
friendsPanel.Size = UDim2.new(1, 0, 1, -44)
friendsPanel.Visible = false
friendsPanel.Parent = body

local playerList = Instance.new("ScrollingFrame")
playerList.Name = "PlayerList"
playerList.BackgroundTransparency = 1
playerList.Size = UDim2.fromScale(1, 1)
playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerList.ScrollBarThickness = 4
playerList.Parent = friendsPanel
Instance.new("UIListLayout", playerList).Padding = UDim.new(0, 8)

local chatPanel = Instance.new("Frame")
chatPanel.Name = "ChatPanel"
chatPanel.BackgroundColor3 = P.TealDeeper
chatPanel.Position = UDim2.new(0, 0, 0, 44)
chatPanel.Size = UDim2.new(1, 0, 1, -44)
chatPanel.Visible = false
chatPanel.Parent = body
corner(chatPanel, 10)

local chatPlaceholder = Instance.new("TextLabel")
chatPlaceholder.Name = "PlaceholderLabel"
chatPlaceholder.BackgroundTransparency = 1
chatPlaceholder.Font = Enum.Font.Gotham
chatPlaceholder.Text = "Crew chat — coming soon"
chatPlaceholder.TextColor3 = P.CreamSoft
chatPlaceholder.TextSize = 14
chatPlaceholder.TextWrapped = true
chatPlaceholder.Size = UDim2.new(1, -32, 1, -32)
chatPlaceholder.Position = UDim2.new(0, 16, 0, 16)
chatPlaceholder.Parent = chatPanel

local rowTpl = Instance.new("Frame")
rowTpl.Name = "PlayerRow_Template"
rowTpl.BackgroundColor3 = P.Teal
rowTpl.Size = UDim2.new(1, 0, 0, 52)
rowTpl.Visible = false
rowTpl.Parent = gui
corner(rowTpl, 10)

local playerName = Instance.new("TextLabel")
playerName.Name = "PlayerNameLabel"
playerName.BackgroundTransparency = 1
playerName.Font = Enum.Font.GothamBold
playerName.Text = "Player"
playerName.TextColor3 = P.Cream
playerName.TextSize = 14
playerName.Position = UDim2.new(0, 14, 0, 8)
playerName.Size = UDim2.new(1, -28, 0, 20)
playerName.Parent = rowTpl

local statusLbl = Instance.new("TextLabel")
statusLbl.Name = "StatusLabel"
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham
statusLbl.Text = "Online"
statusLbl.TextColor3 = P.Success
statusLbl.TextSize = 12
statusLbl.Position = UDim2.new(0, 14, 0, 30)
statusLbl.Size = UDim2.new(1, -28, 0, 16)
statusLbl.Parent = rowTpl

gui.Parent = assets
print("[SocialUI] SocialUI_Template built.")
