--!strict
-- ShopUI.lua
-- Generic shop modal. Built once, displays a list of rows; each row has a
-- name, description, price, and a Buy button. The controller decides what
-- to put in it (rod tiers, bait, etc.) by passing rowsBuilder.

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

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
	local gui = UIUtil.makeScreenGui("ShopUI")

	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0.86, 0)
	panel.BackgroundColor3 = P.TealDark
	panel.BorderSizePixel = 0
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 14); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = P.TealDeeper; ps.Thickness = 1.5; ps.Transparency = 0.25; ps.Parent = panel
	local pcap = Instance.new("UISizeConstraint"); pcap.MaxSize = Vector2.new(820, 720); pcap.Parent = panel
	panel.Parent = gui

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 20, 0, 14)
	titleLabel.Size = UDim2.new(1, -120, 0, 30)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 22
	titleLabel.TextColor3 = P.Cream
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = title
	titleLabel.Parent = panel

	local closeBtn = UIUtil.makeButton("Close", function() gui:Destroy() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(84, 36),
		BackgroundColor3 = P.Wood,
	})
	closeBtn.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 14, 0, 60)
	list.Size = UDim2.new(1, -28, 1, -74)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = P.TealDeeper
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local function buildRow(row: ShopRow, i: number)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 72)
		frame.BackgroundColor3 = P.Teal
		frame.BorderSizePixel = 0
		frame.LayoutOrder = i
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 10); rc.Parent = frame
		frame.Parent = list

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 16, 0, 8)
		name.Size = UDim2.new(0.6, 0, 0, 22)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 16
		name.TextColor3 = P.Cream
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = row.name
		name.Parent = frame

		local desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Position = UDim2.new(0, 16, 0, 32)
		desc.Size = UDim2.new(0.6, 0, 0, 32)
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 12
		desc.TextColor3 = P.CreamSoft
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextWrapped = true
		desc.Text = row.description
		desc.Parent = frame

		local price = Instance.new("TextLabel")
		price.BackgroundTransparency = 1
		price.AnchorPoint = Vector2.new(1, 0.5)
		price.Position = UDim2.new(1, -130, 0.5, 0)
		price.Size = UDim2.fromOffset(130, 26)
		price.Font = Enum.Font.GothamBold
		price.TextSize = 16
		price.TextColor3 = row.disabled and P.CreamSoft or P.Gold
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.Text = row.priceText
		price.Parent = frame

		local buyBtn = UIUtil.makeButton(row.buyLabel or "Buy", function()
			if not row.disabled then onBuy(row.id) end
		end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(110, 40),
			BackgroundColor3 = row.disabled and P.TealDark or P.Sunset,
		})
		if row.disabled then buyBtn.TextColor3 = P.CreamSoft end
		buyBtn.Parent = frame
	end

	local function refresh(rows: {ShopRow})
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		if #rows == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 60)
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 16
			empty.TextColor3 = P.CreamSoft
			empty.TextXAlignment = Enum.TextXAlignment.Center
			empty.Text = "Nothing here right now."
			empty.Parent = list
			return
		end
		for i, row in ipairs(rows) do buildRow(row, i) end
	end
	refresh(initialRows)

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		refresh = refresh,
	}
end

return ShopUI
