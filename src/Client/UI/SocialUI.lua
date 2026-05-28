--!strict
-- SocialUI.lua
-- Crew & friends panel. Layout from SocialUI_Template; emote buttons wired
-- in script. Tabs + PlayerRow_Template + hidden ChatPanel reserved for Crew v1.
--
-- Public API:
--   SocialUI.show(emotes, onPlayEmote, onClose) -> SocialHandle
--   handle.close()
--   handle.refresh(emotes)

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local SocialUI = {}

export type SocialHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (emotes: { string }) -> (),
}

local function req(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[SocialUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

local function setTabActive(active: TextButton, inactive: TextButton)
	active.BackgroundColor3 = P.Sunset
	active.TextColor3 = P.Cream
	inactive.BackgroundColor3 = P.Teal
	inactive.TextColor3 = P.CreamSoft
end

function SocialUI.show(
	emotes: { string },
	onPlayEmote: (emoteId: string) -> (),
	onClose: (() -> ())?
): SocialHandle
	local gui = TemplateLoader.spawn("Social", { instanceName = "SocialUI" })
	local backdrop = req(gui, "Backdrop", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local closeBtn = req(req(panel, "Header", "Frame"), "Close", "TextButton") :: TextButton
	local body = req(panel, "Body", "Frame") :: Frame

	local tabs = req(body, "Tabs", "Frame") :: Frame
	local tabCrew = req(tabs, "TabCrew", "TextButton") :: TextButton
	local tabFriends = req(tabs, "TabFriends", "TextButton") :: TextButton
	local crewPanel = req(body, "CrewPanel", "Frame") :: Frame
	local friendsPanel = req(body, "FriendsPanel", "Frame") :: Frame
	local _chatPanel = req(body, "ChatPanel", "Frame") :: Frame
	local emoteStack = req(crewPanel, "EmoteStack", "Frame") :: Frame
	local _playerRowTpl = req(gui, "PlayerRow_Template", "Frame") :: Frame

	local function showCrewTab()
		setTabActive(tabCrew, tabFriends)
		crewPanel.Visible = true
		friendsPanel.Visible = false
	end

	local function showFriendsTab()
		setTabActive(tabFriends, tabCrew)
		crewPanel.Visible = false
		friendsPanel.Visible = true
	end

	showCrewTab()

	tabCrew.Activated:Connect(showCrewTab)
	tabFriends.Activated:Connect(showFriendsTab)

	local function rebuild(currentEmotes: { string })
		for _, c in ipairs(emoteStack:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, e in ipairs(currentEmotes) do
			local label = "Emote: " .. e:gsub("_", " ")
			local btn = UIUtil.makePrimaryButton(label, function()
				onPlayEmote(e)
			end, {
				Size = UDim2.new(1, 0, 0, UIUtil.MinTouchPx),
				LayoutOrder = i,
			})
			btn.Parent = emoteStack
		end
	end

	rebuild(emotes)

	local closed = false
	local function destroy()
		if closed then
			return
		end
		closed = true
		if gui.Parent then
			gui:Destroy()
		end
		if onClose then
			onClose()
		end
	end

	backdrop.Activated:Connect(destroy)
	closeBtn.Activated:Connect(destroy)

	return {
		gui = gui,
		close = destroy,
		refresh = rebuild,
	}
end

return SocialUI
