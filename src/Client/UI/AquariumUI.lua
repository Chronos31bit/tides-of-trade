--!strict
-- AquariumUI.lua
-- Two-pane manager: left side shows fish currently displayed in this
-- aquarium, right side shows fish in inventory available to deposit.
-- Tap a fish on either side to move it.

local UIUtil = require(script.Parent.UIUtil)

local AquariumUI = {}

export type AquariumHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (contents: {any}, inventory: {any}, capacity: number) -> (),
}

function AquariumUI.show(
	contents: {any},
	inventory: {any},
	capacity: number,
	onDeposit: (string) -> (),
	onWithdraw: (string) -> ()
): AquariumHandle
	local gui = UIUtil.makeScreenGui("AquariumUI")

	local backdrop = UIUtil.makeFrame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
	})
	backdrop.Parent = gui

	local panel = UIUtil.makePanel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.88, 0),
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})
	local cap = Instance.new("UISizeConstraint"); cap.MaxSize = Vector2.new(880, 720); cap.Parent = panel
	panel.Parent = gui

	local title = UIUtil.makeLabel("Aquarium", "title", {
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.new(1, -200, 0, 28),
	}); title.Parent = panel

	local capLbl = UIUtil.makeLabel(("0 / %d"):format(capacity), "body", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -110, 0, 14),
		Size = UDim2.fromOffset(80, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UIUtil.Palette.Gold,
	}); capLbl.Parent = panel

	local closeBtn = UIUtil.makeButton("Close", function() gui:Destroy() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(80, 32),
		BackgroundColor3 = UIUtil.Palette.Wood,
	}); closeBtn.Parent = panel

	-- Two columns: aquarium on left, inventory on right. On phones we'd
	-- swap to tabs, but most phones in portrait still fit two narrow columns.
	local function makeColumn(name: string, anchorX: number, sideLabel: string)
		local col = UIUtil.makeFrame({
			Name = name,
			Position = UDim2.new(anchorX, anchorX == 0 and 16 or 0, 0, 56),
			Size = UDim2.new(0.5, anchorX == 0 and -20 or -16, 1, -68),
			BackgroundTransparency = 1,
		})
		col.Parent = panel

		local heading = UIUtil.makeLabel(sideLabel, "title", {
			Size = UDim2.new(1, 0, 0, 22),
			TextSize = 16,
			TextColor3 = UIUtil.Palette.Cream,
		}); heading.Parent = col

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Scroll"
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.Position = UDim2.new(0, 0, 0, 30)
		scroll.Size = UDim2.new(1, 0, 1, -30)
		scroll.ScrollBarThickness = 6
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.Parent = col

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.Parent = scroll
		return col, scroll
	end

	local _, leftScroll  = makeColumn("Aquarium", 0,   "In Aquarium — tap to remove")
	local _, rightScroll = makeColumn("Inventory", 0.5, "Inventory — tap to add")

	local function buildCard(parent: ScrollingFrame, item: any, action: string, onClick: () -> ())
		local row = UIUtil.makePanel({
			Name = item.uid,
			Size = UDim2.new(1, -4, 0, 44),
			BackgroundColor3 = UIUtil.Palette.Teal,
		})
		row.Parent = parent

		local nameText = (item.speciesId or "fish"):gsub("_", " ")
		local nameLbl = UIUtil.makeLabel(nameText, "body", {
			Position = UDim2.new(0, 12, 0, 4),
			Size = UDim2.new(1, -90, 0, 18),
			TextSize = 14,
		}); nameLbl.Parent = row
		local sub = UIUtil.makeLabel(("%.1f kg"):format(item.weightKg or 0), "caption", {
			Position = UDim2.new(0, 12, 0, 22),
			Size = UDim2.new(1, -90, 0, 16),
		}); sub.Parent = row

		local btn = UIUtil.makeButton(action, onClick, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(72, 32),
			TextSize = 13,
		})
		btn.Parent = row
	end

	local function refresh(contents_: {any}, inv: {any}, cap_: number)
		capLbl.Text = ("%d / %d"):format(#contents_, cap_)

		for _, c in ipairs(leftScroll:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for _, c in ipairs(rightScroll:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end

		if #contents_ == 0 then
			local empty = UIUtil.makeLabel("No fish yet — add some from inventory", "caption", {
				Size = UDim2.new(1, 0, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Center,
			}); empty.Parent = leftScroll
		else
			for _, item in ipairs(contents_) do
				buildCard(leftScroll, item, "Take", function() onWithdraw(item.uid) end)
			end
		end

		-- Filter inventory to fish only — only fish can go in aquariums.
		local fish = {}
		for _, item in ipairs(inv) do
			if item.kind == "Fish" then table.insert(fish, item) end
		end
		if #fish == 0 then
			local empty = UIUtil.makeLabel("No fish in inventory", "caption", {
				Size = UDim2.new(1, 0, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Center,
			}); empty.Parent = rightScroll
		else
			for _, item in ipairs(fish) do
				buildCard(rightScroll, item, "Add", function() onDeposit(item.uid) end)
			end
		end
	end
	refresh(contents, inventory, capacity)

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		refresh = refresh,
	}
end

return AquariumUI
