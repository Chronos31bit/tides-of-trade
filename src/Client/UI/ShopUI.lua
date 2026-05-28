--!strict
-- ShopUI.lua
-- Generic shop modal. Layout from ShopUI_Template; rows clone ShopRow_Template.
-- Controller supplies row data and onBuy callback.

local CollectionService = game:GetService("CollectionService")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit = require(script.Parent.UIKit)
local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local ShopUI = {}

local ROW_TAG = "TotShopRow"

export type ShopRow = {
	id: string | number,
	name: string,
	description: string,
	priceText: string,
	disabled: boolean,
	buyLabel: string?,
}

export type ShopHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (rows: { ShopRow }) -> (),
}

local function req(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[ShopUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

local function styleHeaderLabels(gui: ScreenGui)
	local panel = gui:FindFirstChild("Panel")
	local header = panel and panel:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.TextColor3 = P.Cream
	end
	local closeBtn = header and header:FindFirstChild("Close")
	if closeBtn and closeBtn:IsA("TextButton") then
		closeBtn.BackgroundColor3 = P.Wood
		closeBtn.TextColor3 = P.Cream
	end
end

function ShopUI.show(title: string, initialRows: { ShopRow }, onBuy: (string | number) -> ()): ShopHandle
	local gui = TemplateLoader.spawn("Shop", { instanceName = "ShopUI" })
	styleHeaderLabels(gui)

	local backdrop = req(gui, "Backdrop", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local header = req(panel, "Header", "Frame") :: Frame
	local titleLbl = req(header, "Title", "TextLabel") :: TextLabel
	local closeBtn = req(header, "Close", "TextButton") :: TextButton
	local body = req(panel, "Body", "Frame") :: Frame
	local list = req(body, "ShopList", "ScrollingFrame") :: ScrollingFrame
	local rowTpl = req(gui, "ShopRow_Template", "Frame") :: Frame

	titleLbl.Text = title

	local function buildRow(row: ShopRow, i: number)
		local frame = rowTpl:Clone()
		frame.Name = "Row_" .. tostring(row.id)
		frame.Visible = true
		frame.LayoutOrder = i
		frame.Parent = list
		CollectionService:AddTag(frame, ROW_TAG)
		UIKit.applyCardStyle(frame, "teal")

		local nameLbl = req(frame, "NameLabel", "TextLabel") :: TextLabel
		local descLbl = req(frame, "DescriptionLabel", "TextLabel") :: TextLabel
		local priceLbl = req(frame, "PriceLabel", "TextLabel") :: TextLabel
		local buyBtn = req(frame, "BuyButton", "TextButton") :: TextButton

		nameLbl.Text = row.name
		nameLbl.TextColor3 = P.Cream
		descLbl.Text = row.description
		descLbl.TextColor3 = P.CreamSoft
		priceLbl.Text = row.priceText
		priceLbl.TextColor3 = row.disabled and P.CreamSoft or P.Gold

		local label = row.buyLabel or "Buy"
		buyBtn.Text = label
		if row.disabled then
			buyBtn.BackgroundColor3 = P.TealDark
			buyBtn.TextColor3 = P.CreamSoft
			buyBtn.Active = false
			UIKit.prepareInteractive(buyBtn)
		else
			buyBtn.BackgroundColor3 = P.Sunset
			buyBtn.TextColor3 = P.Cream
			buyBtn.Active = true
			UIKit.prepareInteractive(buyBtn)
			buyBtn.Activated:Connect(function()
				onBuy(row.id)
			end)
		end
	end

	local function refresh(rows: { ShopRow })
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") and CollectionService:HasTag(c, ROW_TAG) then
				c:Destroy()
			end
		end
		if #rows == 0 then
			local empty = UIUtil.makeLabel("Nothing here right now.", "subtitle", {
				Size = UDim2.new(1, 0, 0, 60),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = list,
			})
			empty.TextColor3 = P.CreamSoft
			return
		end
		for i, row in ipairs(rows) do
			buildRow(row, i)
		end
	end

	refresh(initialRows)

	local closed = false
	local function destroy()
		if closed then
			return
		end
		closed = true
		if gui.Parent then
			gui:Destroy()
		end
	end

	backdrop.Activated:Connect(destroy)
	closeBtn.Activated:Connect(destroy)

	return {
		gui = gui,
		close = destroy,
		refresh = refresh,
	}
end

return ShopUI
