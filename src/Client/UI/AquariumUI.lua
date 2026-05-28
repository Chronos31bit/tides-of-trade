--!strict
-- AquariumUI.lua — Layout from StarterGuiAssets.AquariumUI_Template; behavior only.
-- AquariumService (AquariumController): AquariumChanged, IncomeEarned (toast)
-- onDeposit / onWithdraw -> AquariumService:Deposit / :Withdraw

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit = require(script.Parent.UIKit)
local UIUtil = require(script.Parent.UIUtil)
local FishCatalogRaw = require(ReplicatedStorage.Shared.Config.FishCatalog)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local AquariumIncome = require(ReplicatedStorage.Shared.Util.AquariumIncome)

local P, M = UIUtil.Palette, UIUtil.Modal
local AquariumUI = {}
export type AquariumHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (contents: {any}, inventory: {any}, capacity: number) -> (),
}

local _fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalogRaw.fish) do _fishById[f.id] = f end
local _modNames: {[string]: string} = {}
for _, m in ipairs(GameConfig.FishModifiers) do
	_modNames[m.id] = m.displayName
end
local _layoutSkip = { UIGridLayout = true, UIListLayout = true, UIPadding = true, UICorner = true, UIStroke = true }

type InvSortMode = "none" | "desc" | "asc"

local function req(parent: Instance, name: string, class: string): Instance
	local c = parent:FindFirstChild(name)
	if not c or not c:IsA(class) then
		error(`[AquariumUI] Missing {class} "{name}" under {parent:GetFullName()}`, 2)
	end
	return c
end

local function metaNum(meta: Folder?, key: string, def: number): number
	local v = meta and meta:FindFirstChild(key)
	return (v and v:IsA("NumberValue")) and v.Value or def
end

local function titleCase(s: string): string
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

local function formatIncomeLine(item: any): string
	local cps = AquariumIncome.coinsPerSecond(item)
	if cps <= 0 then
		return "No passive income"
	end
	local w = item.weightKg or 0
	local rate: string
	if cps >= 100 then
		rate = ("+%.0f coins/s"):format(cps)
	elseif cps >= 1 then
		rate = ("+%.1f coins/s"):format(cps)
	else
		rate = ("+%.2f coins/s"):format(cps)
	end
	return ("%s · %.1f kg"):format(rate, w)
end

local function applySlotGrid(scroll: ScrollingFrame, cols: number, cellW: number, cellH: number)
	local grid = scroll:FindFirstChild("GridLayout")
	if grid and grid:IsA("UIGridLayout") then
		grid.FillDirectionMaxCells = cols
		grid.CellSize = UDim2.fromOffset(cellW, cellH)
	end
end

-- Fill the scroll width with exactly `cols` cells (no right-side gutter on wide panels).
local function measureCellSize(scroll: ScrollingFrame, cols: number): (number, number)
	local grid = scroll:FindFirstChild("GridLayout")
	local pad = scroll:FindFirstChildOfClass("UIPadding")
	local padL = if pad then pad.PaddingLeft.Offset else 8
	local padR = if pad then pad.PaddingRight.Offset else 8
	local gapX = if grid and grid:IsA("UIGridLayout") then grid.CellPadding.X.Offset else 8
	local scrollW = scroll.AbsoluteSize.X
	local fallbackW = GameConfig.Aquarium.SlotCellWidthPx
	local fallbackH = GameConfig.Aquarium.SlotCellHeightPx
	if scrollW < 80 then
		return fallbackW, fallbackH
	end
	local usable = scrollW - padL - padR
	local cellW = math.floor((usable - gapX * (cols - 1)) / cols)
	cellW = math.max(cellW, 96)
	local aspect = fallbackH / math.max(fallbackW, 1)
	local cellH = math.max(132, math.floor(cellW * aspect))
	return cellW, cellH
end

local function ensureIncomeLabel(slot: Frame): TextLabel
	local lbl = slot:FindFirstChild("IncomeRateLabel")
	if lbl and lbl:IsA("TextLabel") then
		return lbl
	end
	lbl = Instance.new("TextLabel")
	lbl.Name = "IncomeRateLabel"
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 11
	lbl.TextColor3 = P.Gold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Parent = slot
	return lbl
end

local function layoutSlotText(slot: Frame)
	local nameLbl = req(slot, "NameLabel", "TextLabel") :: TextLabel
	local incomeLbl = ensureIncomeLabel(slot)
	local pills = req(slot, "ModifierPillStrip", "Frame") :: Frame
	local btn = req(slot, "ActionButton", "TextButton") :: TextButton
	local pad = 4
	local btnH = math.max(UIUtil.MinTouchPx, btn.Size.Y.Offset > 0 and btn.Size.Y.Offset or 44)

	-- Header text at top (keeps income off the action button).
	nameLbl.Position = UDim2.new(0, pad, 0, pad)
	nameLbl.Size = UDim2.new(1, -pad * 2, 0, 16)
	nameLbl.ZIndex = 6
	incomeLbl.Position = UDim2.new(0, pad, 0, pad + 17)
	incomeLbl.Size = UDim2.new(1, -pad * 2, 0, 28)
	incomeLbl.TextWrapped = true
	incomeLbl.ZIndex = 6

	pills.Position = UDim2.new(0, pad, 1, -(btnH + 18))
	pills.Size = UDim2.new(1, -pad * 2, 0, 16)
	pills.ZIndex = 5

	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -pad)
	btn.Size = UDim2.new(1, -pad * 2, 0, btnH)
	btn.ZIndex = 4

	local ring = slot:FindFirstChild("RarityRing")
	if ring and ring:IsA("Frame") then
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.new(0.5, 0, 0, pad + 50)
	end
end

local function ensureSortButton(invCol: Frame): TextButton
	local btn = invCol:FindFirstChild("SortButton")
	if btn and btn:IsA("TextButton") then
		return btn
	end
	local hdr = invCol:FindFirstChild("ColumnHeader")
	if hdr and hdr:IsA("TextLabel") then
		hdr.Size = UDim2.new(1, -100, 0, 22)
	end
	btn = Instance.new("TextButton")
	btn.Name = "SortButton"
	btn.AutoButtonColor = false
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, 0, 0, 0)
	btn.Size = UDim2.fromOffset(92, UIUtil.MinTouchPx)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = P.Cream
	btn.BackgroundColor3 = P.TealDark
	btn.BorderSizePixel = 0
	btn.Text = "Sort"
	btn.Parent = invCol
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn
	local scroll = invCol:FindFirstChild("InventorySlotGrid")
	if scroll and scroll:IsA("ScrollingFrame") then
		scroll.Position = UDim2.new(0, 0, 0, UIUtil.MinTouchPx + 4)
		scroll.Size = UDim2.new(1, 0, 1, -(UIUtil.MinTouchPx + 4))
	end
	return btn
end

local function sortLabel(mode: InvSortMode): string
	if mode == "desc" then
		return "Best ▼"
	elseif mode == "asc" then
		return "Worst ▲"
	end
	return "Sort"
end

local function sortInventoryFish(fish: {any}, mode: InvSortMode)
	if mode == "none" then
		return
	end
	table.sort(fish, function(a, b)
		local ca = AquariumIncome.coinsPerSecond(a)
		local cb = AquariumIncome.coinsPerSecond(b)
		if mode == "desc" then
			return ca > cb
		end
		return ca < cb
	end)
end

local function bindSlot(
	slot: Frame,
	item: any?,
	action: string?,
	onClick: (() -> ())?,
	conns: {[TextButton]: RBXScriptConnection}
)
	layoutSlotText(slot)
	local empty = req(slot, "EmptyHint", "TextLabel") :: TextLabel
	local ring = req(slot, "RarityRing", "Frame") :: Frame
	local nameLbl = req(slot, "NameLabel", "TextLabel") :: TextLabel
	local incomeLbl = ensureIncomeLabel(slot)
	local pills = req(slot, "ModifierPillStrip", "Frame") :: Frame
	local btn = req(slot, "ActionButton", "TextButton") :: TextButton

	if not item then
		empty.Visible = true
		ring.Visible = false
		nameLbl.Visible = false
		incomeLbl.Visible = false
		pills.Visible = false
		btn.Visible = false
		return
	end

	empty.Visible = false
	ring.Visible = true
	nameLbl.Visible = true
	incomeLbl.Visible = true
	btn.Visible = true

	local sid = item.speciesId or ""
	local fd = _fishById[sid]
	local stroke = ring:FindFirstChildOfClass("UIStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = UIUtil.rarityColor((fd and fd.rarity) or "Common")
	end

	local displayName = titleCase(sid)
	if fd and fd.rarity then
		displayName = displayName .. " (" .. fd.rarity .. ")"
	end
	nameLbl.Text = displayName
	incomeLbl.Text = formatIncomeLine(item)

	-- #region agent log
	do
		local HttpService = game:GetService("HttpService")
		print(`[DEBUG:39f298] {HttpService:JSONEncode({
			message = "slot_income",
			hypothesisId = "H1",
			location = "AquariumUI:bindSlot",
			timestamp = DateTime.now().UnixTimestampMillis,
			data = {
				speciesId = sid,
				rarity = fd and fd.rarity or "unknown",
				coinsPerSec = AquariumIncome.coinsPerSecond(item),
				weightKg = item.weightKg,
				modifiers = item.modifiers,
			},
		})}`)
	end
	-- #endregion

	local vpf = req(ring, "ViewportFrame", "ViewportFrame") :: ViewportFrame
	vpf.Visible = true
	local cw = if slot.Size.X.Offset > 0 then slot.Size.X.Offset else 152
	local ch = if slot.Size.Y.Offset > 0 then slot.Size.Y.Offset else 180
	local thumbScale = math.clamp(math.min(cw, ch) / 108, 1.2, 2.2)
	UIKit.attachFishThumb(vpf, sid, { modifiers = item.modifiers or {}, scaleTarget = thumbScale })

	for _, ch in pills:GetChildren() do
		if ch:IsA("Frame") and ch.Name == "ModifierPill" then
			ch:Destroy()
		end
	end
	local mods = item.modifiers or {}
	if #mods == 0 then
		pills.Visible = false
	else
		pills.Visible = true
		for i = 1, math.min(#mods, 3) do
			UIKit.ModifierPill(mods[i], _modNames[mods[i]] or mods[i], {
				Size = UDim2.fromOffset(0, 14),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = i,
				Parent = pills,
			})
		end
	end

	btn.Text = action or "Add"
	btn.BackgroundColor3 = if action == "Take" then P.Teal else P.TealLight
	if conns[btn] then
		conns[btn]:Disconnect()
	end
	conns[btn] = btn.Activated:Connect(function()
		if onClick then
			onClick()
		end
	end)
end

function AquariumUI.show(
	contents: {any},
	inventory: {any},
	capacity: number,
	onDeposit: (string) -> (),
	onWithdraw: (string) -> ()
): AquariumHandle
	local rm = MotionUtil.reducedMotionEnabled()
	local gui = TemplateLoader.spawn("Aquarium", { instanceName = "AquariumUI" })
	local backdrop = req(gui, "Backdrop", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local header = req(panel, "Header", "Frame")
	local capLbl = req(header, "CapacityLabel", "TextLabel") :: TextLabel
	local closeBtn = req(header, "Close", "TextButton") :: TextButton
	local body = req(panel, "Body", "Frame") :: Frame
	local aqScroll = req(req(body, "AquariumColumn", "Frame"), "AquariumSlotGrid", "ScrollingFrame") :: ScrollingFrame
	local invCol = req(body, "InventoryColumn", "Frame") :: Frame
	local invScroll = req(invCol, "InventorySlotGrid", "ScrollingFrame") :: ScrollingFrame
	local slotTpl = req(body, "Slot_Template", "Frame") :: Frame
	local sortBtn = ensureSortButton(invCol)
	local meta = gui:FindFirstChild("Meta")
	local metaF = if meta and meta:IsA("Folder") then meta else nil
	local fadeDur = metaNum(metaF, "FadeDuration", M.FadeDuration)
	local slidePx = metaNum(metaF, "SlideOffsetPx", M.SlideOffsetPx)
	local maxCap = math.max(1, metaNum(metaF, "MaxAquariumCapacity", 24))
	local gridCols = math.max(1, metaNum(metaF, "SlotGridColumns", GameConfig.Aquarium.SlotGridColumns))
	local gridMetrics = {
		w = GameConfig.Aquarium.SlotCellWidthPx,
		h = GameConfig.Aquarium.SlotCellHeightPx,
	}

	local closed = false
	local conns: {[TextButton]: RBXScriptConnection} = {}
	local layoutConns: {RBXScriptConnection} = {}
	local invSortMode: InvSortMode = "none"
	local lastContents: {any} = contents
	local lastInv: {any} = inventory
	local lastCap = capacity

	local aqSlots: {Frame} = {}

	local function syncGridCellSizes()
		local cellW, cellH = measureCellSize(aqScroll, gridCols)
		gridMetrics.w, gridMetrics.h = cellW, cellH
		applySlotGrid(aqScroll, gridCols, cellW, cellH)
		applySlotGrid(invScroll, gridCols, cellW, cellH)
		slotTpl.Size = UDim2.fromOffset(cellW, cellH)
		for _, slot in aqSlots do
			slot.Size = UDim2.fromOffset(cellW, cellH)
			layoutSlotText(slot)
		end
		for _, ch in invScroll:GetChildren() do
			if ch:IsA("Frame") and ch.Name ~= "Slot_Template" then
				ch.Size = UDim2.fromOffset(cellW, cellH)
				layoutSlotText(ch)
			end
		end

		-- #region agent log
		do
			local HttpService = game:GetService("HttpService")
			print(`[DEBUG:39f298] {HttpService:JSONEncode({
				message = "grid_fill",
				hypothesisId = "H1",
				location = "AquariumUI:syncGridCellSizes",
				timestamp = DateTime.now().UnixTimestampMillis,
				data = {
					scrollW = aqScroll.AbsoluteSize.X,
					cellW = cellW,
					cellH = cellH,
					cols = gridCols,
				},
			})}`)
		end
		-- #endregion
	end

	local restPos = panel.Position
	local fromPos = UDim2.new(restPos.X.Scale, restPos.X.Offset, restPos.Y.Scale, restPos.Y.Offset + slidePx)
	local fadeInfo = TweenInfo.new(fadeDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function destroy()
		if closed then
			return
		end
		closed = true
		for _, c in conns do
			c:Disconnect()
		end
		for _, c in layoutConns do
			c:Disconnect()
		end
		table.clear(conns)
		table.clear(layoutConns)
		if gui.Parent then
			gui:Destroy()
		end
	end

	local function refresh(contents_: {any}, inv: {any}, cap_: number)
		lastContents, lastInv, lastCap = contents_, inv, cap_
		capLbl.Text = ("%d / %d"):format(#contents_, cap_)

		for i = 1, maxCap do
			local slot = aqSlots[i]
			slot.Visible = i <= cap_
			if i <= cap_ then
				bindSlot(slot, nil, nil, nil, conns)
			end
		end
		for i, item in ipairs(contents_) do
			if i <= cap_ then
				bindSlot(aqSlots[i], item, "Take", function()
					onWithdraw(item.uid)
				end, conns)
			end
		end

		for _, c in invScroll:GetChildren() do
			if c:IsA("GuiObject") and not _layoutSkip[c.ClassName] then
				c:Destroy()
			end
		end

		local fish: {any} = {}
		for _, it in inv do
			if it.kind == "Fish" then
				table.insert(fish, it)
			end
		end
		sortInventoryFish(fish, invSortMode)

		if #fish == 0 then
			UIUtil.makeLabel("No fish in inventory.", "subtitle", {
				Size = UDim2.new(1, 0, 0, 36),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = P.CreamSoft,
				LayoutOrder = 1,
				Parent = invScroll,
			})
		else
			for i, it in fish do
				local slot = slotTpl:Clone()
				slot.Name = "InvSlot_" .. (it.uid or i)
				slot.Size = UDim2.fromOffset(gridMetrics.w, gridMetrics.h)
				slot.Visible = true
				slot.LayoutOrder = i
				slot.Parent = invScroll
				bindSlot(slot, it, "Add", function()
					onDeposit(it.uid)
				end, conns)
			end
		end
		syncGridCellSizes()
	end

	sortBtn.Activated:Connect(function()
		if invSortMode == "none" then
			invSortMode = "desc"
		elseif invSortMode == "desc" then
			invSortMode = "asc"
		else
			invSortMode = "none"
		end
		sortBtn.Text = sortLabel(invSortMode)
		refresh(lastContents, lastInv, lastCap)
	end)

	backdrop.Activated:Connect(destroy)
	closeBtn.Activated:Connect(destroy)
	panel.BackgroundTransparency, backdrop.BackgroundTransparency = 1, 1
	if rm then
		panel.Position = restPos
		panel.BackgroundTransparency = 0
		backdrop.BackgroundTransparency = M.BackdropAlpha
	else
		panel.Position = fromPos
		MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = M.BackdropAlpha })
		MotionUtil.tweenOrSnap(panel, fadeInfo, { BackgroundTransparency = 0, Position = restPos })
	end

	for i = 1, maxCap do
		local slot = slotTpl:Clone()
		slot.Name = "AquariumSlot_" .. i
		slot.LayoutOrder = i
		slot.Parent = aqScroll
		bindSlot(slot, nil, nil, nil, conns)
		aqSlots[i] = slot
	end

	table.insert(layoutConns, aqScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncGridCellSizes))
	table.insert(layoutConns, invScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncGridCellSizes))
	task.defer(syncGridCellSizes)
	task.delay(0.05, syncGridCellSizes)

	refresh(contents, inventory, capacity)
	return { gui = gui, close = destroy, refresh = refresh }
end

return AquariumUI
