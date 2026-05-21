--!strict
-- ShopUI.lua
-- Generic shop modal. Built once, displays a list of rows; each row has a
-- name, description, price, and a Buy button. The controller decides what
-- to put in it (rod tiers, bait, etc.) by passing rowsBuilder.

local UIUtil = require(script.Parent.UIUtil)

local P    = UIUtil.Palette
local SP   = UIUtil.Spacing
local RAD  = UIUtil.Radii

local ShopUI = {}

export type ShopRow = {
	id: string | number,
	name: string,
	description: string,
	priceText: string,      -- e.g. "500 coins" or "Owned" or "Unlocked"
	disabled: boolean,      -- if true, row's button is greyed out
	buyLabel: string?,      -- defaults to "Buy"
}

export type ShopHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (rows: {ShopRow}) -> (),
}

function ShopUI.show(title: string, initialRows: {ShopRow}, onBuy: (string | number) -> ()): ShopHandle
	local shell
	shell = UIUtil.makeModalShell({
		name = "ShopUI",
		title = title,
		onClose = function() if shell then shell.destroy() end end,
		width = 720,
		heightScale = 0.86,
	})
	local gui  = shell.gui
	local body = shell.body

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = P.TealDeeper
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, SP.sm)
	layout.Parent = list

	local function buildRow(row: ShopRow, i: number)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 80)
		frame.BackgroundColor3 = P.Teal
		frame.BorderSizePixel = 0
		frame.LayoutOrder = i
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, RAD.md); rc.Parent = frame
		frame.Parent = list

		UIUtil.makeLabel(row.name, "subtitle", {
			Position = UDim2.new(0, SP.md, 0, SP.sm),
			Size = UDim2.new(0.6, 0, 0, 22),
			Font = Enum.Font.GothamBold,
			Parent = frame,
		})

		UIUtil.makeLabel(row.description, "caption", {
			Position = UDim2.new(0, SP.md, 0, 32),
			Size = UDim2.new(0.6, 0, 0, 36),
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Parent = frame,
		})

		UIUtil.makeLabel(row.priceText, "body", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -130, 0.5, 0),
			Size = UDim2.fromOffset(130, 26),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextColor3 = row.disabled and P.CreamSoft or P.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})

		local buyBtn
		if row.disabled then
			buyBtn = UIUtil.makeSecondaryButton(row.buyLabel or "Buy", function() end, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -SP.sm, 0.5, 0),
				Size = UDim2.fromOffset(110, UIUtil.MinTouchPx),
			})
			buyBtn.TextColor3 = P.CreamSoft
			buyBtn.BackgroundColor3 = P.TealDark
		else
			buyBtn = UIUtil.makePrimaryButton(row.buyLabel or "Buy", function()
				onBuy(row.id)
			end, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -SP.sm, 0.5, 0),
				Size = UDim2.fromOffset(110, UIUtil.MinTouchPx),
			})
		end
		buyBtn.Parent = frame
	end

	local function refresh(rows: {ShopRow})
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		if #rows == 0 then
			UIUtil.makeLabel("Nothing here right now.", "subtitle", {
				Size = UDim2.new(1, 0, 0, 60),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = list,
			})
			return
		end
		for i, row in ipairs(rows) do buildRow(row, i) end
	end
	refresh(initialRows)

	return {
		gui = gui,
		close = function() shell.destroy() end,
		refresh = refresh,
	}
end

return ShopUI
