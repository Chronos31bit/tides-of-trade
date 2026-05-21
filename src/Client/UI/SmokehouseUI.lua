--!strict
-- SmokehouseUI.lua
-- Two-column manager: left = preserve slots (empty / smoking / ready),
-- right = inventory fish to place. Cozy: cancel while smoking, claim when ready.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIUtil = require(script.Parent.UIUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local P   = UIUtil.Palette
local SP  = UIUtil.Spacing
local RAD = UIUtil.Radii

local PRESERVE_TIME = GameConfig.Buildings.Smokehouse.PreserveTimeSec

local SmokehouseUI = {}

export type SmokehouseHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (slots: {[number]: any}, inventory: {any}, capacity: number) -> (),
	destroy: () -> (),
}

local function titleCase(s: string): string
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- Remote tables may arrive with string keys ("1", "10"); coerce to 1..capacity.
local function normalizeSlots(slots: {[any]: any}, capacity: number): {[number]: any}
	local out: {[number]: any} = {}
	for i = 1, capacity do
		out[i] = slots[i] or slots[tostring(i)]
	end
	return out
end

local function isSlotClaimable(slot: any): boolean
	if slot.ready == true then return true end
	if slot.startedAt then
		return os.time() - slot.startedAt >= PRESERVE_TIME
	end
	return false
end

local function formatCountdown(secondsLeft: number): string
	if secondsLeft <= 0 then
		return "Ready"
	end
	local m = math.floor(secondsLeft / 60)
	local s = secondsLeft % 60
	if m > 0 then
		return ("%dm %ds"):format(m, s)
	end
	return ("%ds"):format(s)
end

function SmokehouseUI.show(
	slots: {[number]: any},
	inventory: {any},
	capacity: number,
	onPlace: (string) -> (),
	onCancel: (number) -> (),
	onClaim: (number) -> (),
	onDismiss: (() -> ())?
): SmokehouseHandle
	local shell
	shell = UIUtil.makeModalShell({
		name = "SmokehouseUI",
		title = "Smokehouse",
		-- onDismiss must tear down the handle (shell.destroy + heartbeat).
		onClose = function()
			if onDismiss then onDismiss() end
		end,
		width = 720,
		heightScale = 0.88,
	})
	local gui  = shell.gui
	local body = shell.body
	shell.open()

	slots = normalizeSlots(slots, capacity)

	local usedCount = 0
	for i = 1, capacity do
		if slots[i] then usedCount += 1 end
	end

	local capLbl = UIUtil.makeLabel(("%d / %d"):format(usedCount, capacity), "subtitle", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(UIUtil.Modal.CloseButtonPx + UIUtil.Spacing.xl), 0.5, 0),
		Size = UDim2.fromOffset(120, 26),
		Font = Enum.Font.GothamBold,
		TextColor3 = P.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = shell.header,
	})

	local function makeColumn(headerText: string, xAnchor: number)
		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.Position = UDim2.new(xAnchor, xAnchor == 0 and 0 or SP.sm, 0, 0)
		col.Size = UDim2.new(0.5, xAnchor == 0 and -SP.sm or -SP.sm, 1, 0)
		col.Parent = body

		UIUtil.makeLabel(headerText:upper(), "subtitle", {
			Size = UDim2.new(1, 0, 0, 22),
			Font = Enum.Font.GothamBold,
			TextColor3 = P.CreamSoft,
			Parent = col,
		})

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Scroll"
		scroll.BackgroundColor3 = P.Teal
		scroll.BackgroundTransparency = 0
		scroll.BorderSizePixel = 0
		scroll.Position = UDim2.new(0, 0, 0, 30)
		scroll.Size = UDim2.new(1, 0, 1, -30)
		scroll.ScrollBarThickness = 6
		scroll.ScrollBarImageColor3 = P.TealDeeper
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, RAD.md); sc.Parent = scroll
		scroll.Parent = col

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, SP.sm); pad.PaddingBottom = UDim.new(0, SP.sm)
		pad.PaddingLeft = UDim.new(0, SP.sm); pad.PaddingRight = UDim.new(0, SP.sm)
		pad.Parent = scroll

		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = scroll
		return scroll
	end

	local leftScroll  = makeColumn("Slots", 0)
	local rightScroll = makeColumn("Inventory  (tap to smoke)", 0.5)

	local slotRows: {Frame} = {}
	local countdownLabels: {TextLabel} = {}
	local lastSlots: {[number]: any} = slots
	local lastInv: {any} = inventory
	local lastCap: number = capacity

	local function buildSlotCard(slotIndex: number, slot: any?)
		local row = Instance.new("Frame")
		-- LayoutOrder forces numeric order; Name alone sorts Slot_10 before Slot_2.
		row.Name = ("Slot_%02d"):format(slotIndex)
		row.LayoutOrder = slotIndex
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = P.TealDark
		row.BorderSizePixel = 0
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, RAD.sm); rc.Parent = row
		row.Parent = leftScroll
		table.insert(slotRows, row)

		if not slot then
			UIUtil.makeLabel(("Slot %d — empty"):format(slotIndex), "body", {
				Position = UDim2.new(0, SP.md, 0, 0),
				Size = UDim2.new(1, -SP.md, 1, 0),
				TextColor3 = P.CreamSoft,
				Parent = row,
			})
			return
		end

		UIUtil.makeLabel(titleCase(slot.speciesId), "body", {
			Position = UDim2.new(0, SP.md, 0, SP.xs),
			Size = UDim2.new(1, -100, 0, 22),
			Font = Enum.Font.GothamBold,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		local subLbl = UIUtil.makeLabel(("%.1f kg"):format(slot.weightKg or 0), "caption", {
			Position = UDim2.new(0, SP.md, 0, 26),
			Size = UDim2.new(1, -100, 0, 18),
			Parent = row,
		})

		if isSlotClaimable(slot) then
			subLbl.Text = "Preserved — ready to claim"
			local btn = UIUtil.makePrimaryButton("Claim", function() onClaim(slotIndex) end, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -SP.sm, 0.5, 0),
				Size = UDim2.fromOffset(80, UIUtil.MinTouchPx),
			})
			btn.Parent = row
		else
			local cdLbl = UIUtil.makeLabel("", "caption", {
				Position = UDim2.new(0, SP.md, 0, 44),
				Size = UDim2.new(1, -180, 0, 16),
				TextColor3 = P.SunsetSoft,
				Parent = row,
			})
			table.insert(countdownLabels, cdLbl)
			cdLbl:SetAttribute("slotIndex", slotIndex)
			cdLbl:SetAttribute("startedAt", slot.startedAt)

			local cancelBtn = UIUtil.makeSecondaryButton("Cancel", function() onCancel(slotIndex) end, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -SP.sm, 0.5, 0),
				Size = UDim2.fromOffset(80, UIUtil.MinTouchPx),
			})
			cancelBtn.Parent = row
		end
	end

	local function buildFishCard(parent: ScrollingFrame, item: any, onClick: () -> ())
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 52)
		row.BackgroundColor3 = P.TealDark
		row.BorderSizePixel = 0
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, RAD.sm); rc.Parent = row
		row.Parent = parent

		UIUtil.makeLabel(titleCase(item.speciesId or "fish"), "body", {
			Position = UDim2.new(0, SP.md, 0, SP.xs),
			Size = UDim2.new(1, -110, 0, 22),
			Font = Enum.Font.GothamBold,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		UIUtil.makeLabel(("%.1f kg"):format(item.weightKg or 0), "caption", {
			Position = UDim2.new(0, SP.md, 0, 26),
			Size = UDim2.new(1, -110, 0, 18),
			Parent = row,
		})

		local btn = UIUtil.makePrimaryButton("Smoke", function() onClick() end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -SP.sm, 0.5, 0),
			Size = UDim2.fromOffset(80, UIUtil.MinTouchPx),
		})
		btn.Parent = row
	end

	local function refresh(slots_: {[number]: any}, inv: {any}, cap_: number)
		slots_ = normalizeSlots(slots_, cap_)
		lastSlots = slots_
		lastInv = inv
		lastCap = cap_
		local used = 0
		for i = 1, cap_ do
			if slots_[i] then used += 1 end
		end
		capLbl.Text = ("%d / %d"):format(used, cap_)

		table.clear(slotRows)
		table.clear(countdownLabels)
		for _, c in ipairs(leftScroll:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i = 1, cap_ do
			buildSlotCard(i, slots_[i])
		end

		for _, c in ipairs(rightScroll:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local fish = {}
		for _, item in ipairs(inv) do
			if item.kind == "Fish" then table.insert(fish, item) end
		end
		if #fish == 0 then
			UIUtil.makeLabel("No fish in inventory.", "subtitle", {
				Size = UDim2.new(1, 0, 0, 36),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = rightScroll,
			})
		else
			for _, item in ipairs(fish) do
				buildFishCard(rightScroll, item, function() onPlace(item.uid) end)
			end
		end
	end
	refresh(slots, inventory, capacity)

	local claimUiRebuilt = false
	local heartbeatConn: RBXScriptConnection? = RunService.Heartbeat:Connect(function()
		local now = os.time()
		local needRebuild = false
		for _, lbl in ipairs(countdownLabels) do
			local startedAt = lbl:GetAttribute("startedAt")
			if typeof(startedAt) == "number" then
				local left = PRESERVE_TIME - (now - startedAt)
				lbl.Text = formatCountdown(left)
				if left <= 0 then
					needRebuild = true
				end
			end
		end
		if needRebuild and not claimUiRebuilt then
			claimUiRebuilt = true
			refresh(lastSlots, lastInv, lastCap)
		elseif not needRebuild then
			claimUiRebuilt = false
		end
	end)

	local function destroy()
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		shell.destroy()
	end

	return {
		gui = gui,
		close = function() destroy() end,
		destroy = destroy,
		refresh = refresh,
	}
end

return SmokehouseUI
