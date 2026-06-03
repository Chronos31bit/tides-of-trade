--!strict
-- SocialUI.lua
-- Crew & friends panel. Layout from SocialUI_Template; emote buttons + crew
-- chat wired in script. Tabs (Crew | Chat | Friends) switch the body panels.
--
-- The Chat tab fills the (template-hidden) ChatPanel with a scrolling message
-- list + a send row. A dedicated tab keeps the emote stack intact on the Crew
-- tab — on a 380px portrait phone the five emote buttons already fill that
-- column, so chat gets its own full-height area rather than fighting for space.
--
-- Public API:
--   SocialUI.show(opts) -> SocialHandle
--     opts = {
--       emotes      : { string },
--       onPlayEmote : (emoteId: string) -> (),
--       onSendChat  : ((message: string) -> ())?,   -- nil disables the send row
--       initialChat : ({ {from: string, message: string} })?,  -- replayed on open
--       onClose     : (() -> ())?,
--     }
--   handle.close()
--   handle.refresh(emotes)
--   handle.appendChat(fromName, message)

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

-- Cap the number of rendered chat rows so a long session can't grow the
-- message list without bound. The controller keeps a matching history cap.
local MAX_CHAT_ROWS = 50
-- Mirror of the server-side crew-chat length limit (SocialService:SendCrewChat).
local MAX_CHAT_LEN = 140

local SocialUI = {}

export type ChatEntry = { from: string, message: string }

export type SocialShowOpts = {
	emotes: { string },
	onPlayEmote: (emoteId: string) -> (),
	onSendChat: ((message: string) -> ())?,
	initialChat: { ChatEntry }?,
	onClose: (() -> ())?,
}

export type SocialHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (emotes: { string }) -> (),
	appendChat: (fromName: string, message: string) -> (),
}

local function req(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[SocialUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

-- RichText escape so a message containing < > & can't break (or inject into)
-- the bold-sender markup we render each row with.
local function escapeRich(s: string): string
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	return s
end

local function setTabActive(active: TextButton, inactive: { TextButton })
	active.BackgroundColor3 = P.Sunset
	active.TextColor3 = P.Cream
	for _, btn in ipairs(inactive) do
		btn.BackgroundColor3 = P.Teal
		btn.TextColor3 = P.CreamSoft
	end
end

function SocialUI.show(opts: SocialShowOpts): SocialHandle
	local emotes = opts.emotes
	local onPlayEmote = opts.onPlayEmote
	local onSendChat = opts.onSendChat
	local onClose = opts.onClose

	local gui = TemplateLoader.spawn("Social", { instanceName = "SocialUI" })
	local backdrop = req(gui, "Backdrop", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local closeBtn = req(req(panel, "Header", "Frame"), "Close", "TextButton") :: TextButton
	local body = req(panel, "Body", "Frame") :: Frame

	local tabs = req(body, "Tabs", "Frame") :: Frame
	-- Enforce 44px touch floor on tab bar (template defaults to 36px).
	tabs.Size = UDim2.new(tabs.Size.X.Scale, tabs.Size.X.Offset, 0, math.max(tabs.Size.Y.Offset, UIUtil.MinTouchPx))
	local tabCrew = req(tabs, "TabCrew", "TextButton") :: TextButton
	local tabFriends = req(tabs, "TabFriends", "TextButton") :: TextButton
	local crewPanel = req(body, "CrewPanel", "Frame") :: Frame
	local friendsPanel = req(body, "FriendsPanel", "Frame") :: Frame
	local chatPanel = req(body, "ChatPanel", "Frame") :: Frame
	local emoteStack = req(crewPanel, "EmoteStack", "Frame") :: Frame

	-- ----------------------------------------------------------------
	-- CHAT TAB BUTTON — built in code (the template ships Crew/Friends
	-- only, same as the emote buttons being built here rather than in
	-- the template). Sits between Crew and Friends.
	-- ----------------------------------------------------------------
	tabFriends.LayoutOrder = 3
	local tabChat = tabFriends:Clone()
	tabChat.Name = "TabChat"
	tabChat.Text = "Chat"
	tabChat.LayoutOrder = 2
	tabChat.Parent = tabs

	-- ----------------------------------------------------------------
	-- CHAT PANEL CONTENTS — scrolling message list + send row.
	-- ----------------------------------------------------------------
	local placeholder = chatPanel:FindFirstChild("PlaceholderLabel")
	if placeholder then
		(placeholder :: GuiObject).Visible = false
	end

	local chatPad = chatPanel:FindFirstChildOfClass("UIPadding")
	if not chatPad then
		chatPad = Instance.new("UIPadding")
		chatPad.PaddingLeft = UDim.new(0, UIUtil.Spacing.sm)
		chatPad.PaddingRight = UDim.new(0, UIUtil.Spacing.sm)
		chatPad.PaddingTop = UDim.new(0, UIUtil.Spacing.sm)
		chatPad.PaddingBottom = UDim.new(0, UIUtil.Spacing.sm)
		chatPad.Parent = chatPanel
	end

	local hasSend = onSendChat ~= nil
	local inputRowHeight = UIUtil.MinTouchPx -- 44px touch floor
	local gap = UIUtil.Spacing.sm

	local messageScroll = Instance.new("ScrollingFrame")
	messageScroll.Name = "MessageScroll"
	messageScroll.BackgroundTransparency = 1
	messageScroll.BorderSizePixel = 0
	messageScroll.ScrollBarThickness = 4
	messageScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	messageScroll.CanvasSize = UDim2.new()
	messageScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	messageScroll.Position = UDim2.new(0, 0, 0, 0)
	-- Leave room at the bottom for the send row when present.
	messageScroll.Size = if hasSend
		then UDim2.new(1, 0, 1, -(inputRowHeight + gap))
		else UDim2.fromScale(1, 1)
	messageScroll.Parent = chatPanel

	local msgLayout = Instance.new("UIListLayout")
	msgLayout.Padding = UDim.new(0, UIUtil.Spacing.xs)
	msgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	msgLayout.Parent = messageScroll

	-- Auto-follow: whenever content grows, pin the view to the newest message.
	msgLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		messageScroll.CanvasPosition = Vector2.new(0, messageScroll.AbsoluteCanvasSize.Y)
	end)

	local emptyLabel: TextLabel? = UIUtil.makeLabel("No messages yet — say hi to your crew.", "caption", {
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 0,
		Parent = messageScroll,
	})

	local nextOrder = 1
	local function appendChat(fromName: string, message: string)
		if emptyLabel then
			emptyLabel:Destroy()
			emptyLabel = nil
		end

		local row = UIUtil.makeLabel("", "body", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextOrder,
			Parent = messageScroll,
		})
		row.RichText = true
		row.Text = ("<b>%s</b>  %s"):format(escapeRich(fromName), escapeRich(message))
		nextOrder += 1

		-- Trim oldest rows past the cap (skip the destroyed empty label).
		local rows = {}
		for _, c in ipairs(messageScroll:GetChildren()) do
			if c:IsA("TextLabel") then
				table.insert(rows, c)
			end
		end
		if #rows > MAX_CHAT_ROWS then
			table.sort(rows, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			for i = 1, #rows - MAX_CHAT_ROWS do
				rows[i]:Destroy()
			end
		end
	end

	if hasSend then
		local inputRow = Instance.new("Frame")
		inputRow.Name = "InputRow"
		inputRow.BackgroundTransparency = 1
		inputRow.BorderSizePixel = 0
		inputRow.AnchorPoint = Vector2.new(0, 1)
		inputRow.Position = UDim2.new(0, 0, 1, 0)
		inputRow.Size = UDim2.new(1, 0, 0, inputRowHeight)
		inputRow.Parent = chatPanel

		local sendBtnWidth = 80
		local input = Instance.new("TextBox")
		input.Name = "ChatInput"
		input.PlaceholderText = "Message your crew…"
		input.PlaceholderColor3 = P.CreamSoft
		input.Text = ""
		input.ClearTextOnFocus = false
		input.ClipsDescendants = true
		input.Font = UIUtil.Typography.body.font
		input.TextSize = math.max(UIUtil.Typography.body.size, UIUtil.MinFontPx)
		input.TextColor3 = P.Cream
		input.TextXAlignment = Enum.TextXAlignment.Left
		input.BackgroundColor3 = P.Teal
		input.BorderSizePixel = 0
		input.Position = UDim2.new(0, 0, 0, 0)
		input.Size = UDim2.new(1, -(sendBtnWidth + gap), 1, 0)
		local inCorner = Instance.new("UICorner")
		inCorner.CornerRadius = UDim.new(0, UIUtil.Radii.md)
		inCorner.Parent = input
		local inPad = Instance.new("UIPadding")
		inPad.PaddingLeft = UDim.new(0, UIUtil.Spacing.sm)
		inPad.PaddingRight = UDim.new(0, UIUtil.Spacing.sm)
		inPad.Parent = input
		input.Parent = inputRow

		-- Mirror-clamp to the server's 140-char limit so the player can't type
		-- a message the server would silently drop.
		input:GetPropertyChangedSignal("Text"):Connect(function()
			if #input.Text > MAX_CHAT_LEN then
				input.Text = input.Text:sub(1, MAX_CHAT_LEN)
			end
		end)

		local function submit()
			local text = input.Text:gsub("^%s+", ""):gsub("%s+$", "")
			if #text == 0 then return end
			-- Don't echo locally — the server fans the message back to every
			-- crew member (including the sender), so it arrives via appendChat.
			input.Text = ""
			(onSendChat :: (string) -> ())(text)
		end

		input.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				submit()
			end
		end)

		local sendBtn = UIUtil.makePrimaryButton("Send", submit, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, sendBtnWidth, 1, 0),
		})
		sendBtn.Name = "SendButton"
		sendBtn.Parent = inputRow
	end

	-- ----------------------------------------------------------------
	-- TAB SWITCHING
	-- ----------------------------------------------------------------
	local function showCrewTab()
		setTabActive(tabCrew, { tabChat, tabFriends })
		crewPanel.Visible = true
		chatPanel.Visible = false
		friendsPanel.Visible = false
	end

	local function showChatTab()
		setTabActive(tabChat, { tabCrew, tabFriends })
		crewPanel.Visible = false
		chatPanel.Visible = true
		friendsPanel.Visible = false
		-- Snap to the newest message when the tab is opened.
		messageScroll.CanvasPosition = Vector2.new(0, messageScroll.AbsoluteCanvasSize.Y)
	end

	local function showFriendsTab()
		setTabActive(tabFriends, { tabCrew, tabChat })
		crewPanel.Visible = false
		chatPanel.Visible = false
		friendsPanel.Visible = true
	end

	showCrewTab()

	tabCrew.Activated:Connect(showCrewTab)
	tabChat.Activated:Connect(showChatTab)
	tabFriends.Activated:Connect(showFriendsTab)

	-- ----------------------------------------------------------------
	-- EMOTE STACK
	-- ----------------------------------------------------------------
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

	-- Replay any chat history captured while the panel was closed.
	if opts.initialChat then
		for _, entry in ipairs(opts.initialChat) do
			appendChat(entry.from, entry.message)
		end
	end

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
		appendChat = appendChat,
	}
end

return SocialUI
