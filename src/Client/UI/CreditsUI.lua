--!strict
-- CreditsUI.lua
-- Audio attribution modal. CC BY 4.0 (and most CC licenses) require *visibly*
-- crediting the author and linking the license, so this is the screen that
-- discharges that obligation for every licensed sound the game ships.
--
-- Opened from the Settings hub (SettingsUI's "Audio credits" button). Pure
-- presentation: it reads CreditsConfig and renders each entry with UIKit
-- chrome only — Card, Label, CloseButton, Divider. No inline Color3 / font
-- size / spacing / radius; every value is a UIKit (GameConfig.UI) token, so
-- the whole modal restyles from one place. Show/hide routes through MotionUtil
-- so ReducedMotion snaps instead of sliding, and the panel never flashes
-- opacity (only the backdrop fades, only the panel slides).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameConfig    = require(ReplicatedStorage.Shared.Config.GameConfig)
local CreditsConfig = require(ReplicatedStorage.Shared.Config.CreditsConfig)
local MotionUtil    = require(ReplicatedStorage.Shared.Util.MotionUtil)
local UIKit         = require(script.Parent.UIKit)

local CreditsUI = {}

type CreditEntry = {
	title: string,
	author: string,
	license: string,
	licenseUrl: string?,
	sourceUrl: string?,
}

export type Handle = {
	show: () -> (),
	hide: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	destroy: () -> (),
}

-- One CreditEntry → an inset Card: title (subtitle) + "by author" (body) +
-- license (caption) + link line(s) (caption). AutomaticSize.Y so wrapped text
-- always fits on a 380px phone without clipping.
local function buildEntryCard(entry: CreditEntry, order: number): Frame
	local P = UIKit.Palette
	local S = UIKit.Spacing

	local card = UIKit.Card({
		style = "inset",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
	})

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, S.md)
	pad.PaddingBottom = UDim.new(0, S.md)
	pad.PaddingLeft = UDim.new(0, S.md)
	pad.PaddingRight = UDim.new(0, S.md)
	pad.Parent = card

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.xs)
	list.Parent = card

	UIKit.Label(entry.title, "subtitle", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextColor3 = P.Ink,
		LayoutOrder = 0,
		Parent = card,
	})

	UIKit.Label(("by %s"):format(entry.author), "body", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = card,
	})

	UIKit.Label(entry.license, "caption", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = card,
	})

	-- Link line(s): the source where we have it, plus the license text URL.
	-- Shown as selectable text (Roblox can't open external links in-experience)
	-- so a curious player can read or type it out. Cozy, not pushy.
	local linkOrder = 3
	local function linkLine(label: string, url: string?)
		if not url or url == "" then return end
		UIKit.Label(("%s  %s"):format(label, url), "caption", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextColor3 = P.MintDeep,
			LayoutOrder = linkOrder,
			Parent = card,
		})
		linkOrder += 1
	end
	linkLine("Source:", entry.sourceUrl)
	linkLine("License:", entry.licenseUrl)

	return card
end

function CreditsUI.create(): Handle
	local P = UIKit.Palette
	local S = UIKit.Spacing
	local M = UIKit.Modal
	local C = GameConfig.UI.CreditsModal

	local gui = UIKit.makeScreenGui("CreditsUI")
	-- Sits one step above the Settings panel (DisplayOrder.Modal) it opens from.
	gui.DisplayOrder = UIKit.DisplayOrder.Credits

	-- Backdrop: tap-to-dismiss dim behind the panel.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = P.Shadow
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	-- Panel: a Card, phone-width, capped on tablet/desktop by a size constraint.
	local panel = UIKit.Card({
		style = "default",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -(S.xl * 2), 0, C.MaxHeightPx),
	})
	panel.Parent = gui

	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(M.MaxWidthPx, C.MaxHeightPx)
	sizeCap.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, M.BodyPaddingPx)
	pad.PaddingBottom = UDim.new(0, M.BodyPaddingPx)
	pad.PaddingLeft = UDim.new(0, M.BodyPaddingPx)
	pad.PaddingRight = UDim.new(0, M.BodyPaddingPx)
	pad.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, S.sm)
	layout.Parent = panel

	-- Header: title + close X (44px touch floor from UIKit.CloseButton).
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, UIKit.MinTouchPx)
	header.LayoutOrder = 0
	header.Parent = panel

	UIKit.Label("Credits", "title", {
		Size = UDim2.new(1, -(M.CloseButtonPx + S.sm), 1, 0),
		Position = UDim2.fromScale(0, 0),
		TextColor3 = P.Ink,
		Parent = header,
	})

	-- Intro: warm one-liner, no FOMO.
	UIKit.Label(
		"Sounds in Tides of Trade are used with thanks under the licenses below.",
		"caption",
		{
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 1,
			Parent = panel,
		}
	)

	UIKit.Divider({ LayoutOrder = 2, Parent = panel })

	-- Scrolling list of entries — fills the remaining panel height via UIFlexItem
	-- so the header/intro stay pinned and only the list scrolls if it grows.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Entries"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 0, 0)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = S.xs
	scroll.ScrollBarImageColor3 = P.BorderMid
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.LayoutOrder = 3
	scroll.Parent = panel

	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = scroll

	local scrollList = Instance.new("UIListLayout")
	scrollList.FillDirection = Enum.FillDirection.Vertical
	scrollList.SortOrder = Enum.SortOrder.LayoutOrder
	scrollList.Padding = UDim.new(0, S.sm)
	scrollList.Parent = scroll

	for i, entry in ipairs(CreditsConfig :: { CreditEntry }) do
		local card = buildEntryCard(entry, i)
		card.Parent = scroll
	end

	-- ----------------------------------------------------------------
	-- Open / close
	-- ----------------------------------------------------------------
	local isOpen = false
	local closed = false
	local restPos = panel.Position
	local fromPos = UDim2.new(
		restPos.X.Scale, restPos.X.Offset,
		restPos.Y.Scale, restPos.Y.Offset + M.SlideOffsetPx
	)
	local fadeInfo = TweenInfo.new(M.FadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local escConn: RBXScriptConnection? = nil

	local hide: () -> ()
	local show: () -> ()

	hide = function()
		if not isOpen or closed then return end
		isOpen = false
		if escConn then escConn:Disconnect(); escConn = nil end
		if UIKit.reducedMotion() then
			gui.Enabled = false
			return
		end
		MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = 1 })
		MotionUtil.tweenOrSnap(panel, fadeInfo, { Position = fromPos })
		task.delay(M.FadeDuration, function()
			-- Don't disable if a reopen raced in during the fade.
			if not isOpen then gui.Enabled = false end
		end)
	end

	show = function()
		if isOpen or closed then return end
		isOpen = true
		gui.Enabled = true
		backdrop.BackgroundTransparency = 1
		if UIKit.reducedMotion() then
			panel.Position = restPos
			backdrop.BackgroundTransparency = M.BackdropAlpha
		else
			panel.Position = fromPos
			MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = M.BackdropAlpha })
			MotionUtil.tweenOrSnap(panel, fadeInfo, { Position = restPos })
		end
		escConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.KeyCode == Enum.KeyCode.Escape then hide() end
		end)
	end

	-- Close X lives in the header, flush to its right edge.
	UIKit.CloseButton(function() hide() end, {
		Parent = header,
		Position = UDim2.new(1, 0, 0.5, 0),
	})
	backdrop.Activated:Connect(function() hide() end)

	gui.Enabled = false

	return {
		show = show,
		hide = hide,
		toggle = function()
			if isOpen then hide() else show() end
		end,
		isOpen = function() return isOpen end,
		destroy = function()
			closed = true
			if escConn then escConn:Disconnect(); escConn = nil end
			if gui.Parent then gui:Destroy() end
		end,
	}
end

return CreditsUI
