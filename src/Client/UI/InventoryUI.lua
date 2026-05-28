--!strict
-- InventoryUI.lua
-- Modal grid of inventory cards. Layout from StarterGuiAssets.InventoryUI_Template;
-- behavior wiring only (sort, filters, selection batch-sell, hold-fish).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit = require(script.Parent.UIKit)
local UIUtil = require(script.Parent.UIUtil)
local FishCatalogRaw = require(ReplicatedStorage.Shared.Config.FishCatalog)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local EconomyUtil = require(ReplicatedStorage.Shared.Util.EconomyUtil)

local P = UIUtil.Palette
local M = UIUtil.Modal

local InventoryUI = {}

export type InventoryHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (items: {any}) -> (),
}

local _fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalogRaw.fish) do
	_fishById[f.id] = f
end

local RARITY_ORDER: {[string]: number} = {
	Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Divine = 7,
}

local MOD_PRIORITY: {[string]: number} = {
	rainbow = 1, voidtouched = 2, golden = 3, bloodlust = 4, radioactive = 5,
	inferno = 6, frozen = 7, disco = 8, crystal = 9, ancientcore = 10,
	silver = 11, shocked = 12, colossal = 13, ghostly = 14, tiny = 15,
	moon_touched = 20, storm_forged = 21, dawn_blessed = 22, tide_kissed = 23, fog_shrouded = 24,
	prismatic = 30, shiny = 31, glowing = 32, giant = 33, elder = 34,
	ancient = 35, lucky = 36, magnetic = 37, cursed = 38, barnacled = 39,
}

local _modDisplayNames: {[string]: string} = {}
for _, mod in ipairs(GameConfig.FishModifiers) do
	_modDisplayNames[mod.id] = mod.displayName
end

local HEADER_H = 28
local THUMB_H = 110
local BTN_H = 44

local function requireChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[InventoryUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

local function modifierGlowCfg(modId: string): {Color: Color3, Thickness: number, Transparency: number}?
	local cfg = (GameConfig :: any).ModifierGlow
	if cfg and cfg[modId] then
		return cfg[modId]
	end
	return { Color = UIUtil.modifierColor(modId), Thickness = 2.0, Transparency = 0.3 }
end

local function cardGlowColor(mods: {string}): Color3?
	if #mods < 2 then
		return nil
	end
	local bestId: string? = nil
	local bestPri = math.huge
	for _, id in ipairs(mods) do
		local pri = MOD_PRIORITY[id] or 99
		if pri < bestPri then
			bestPri = pri
			bestId = id
		end
	end
	if not bestId then
		return nil
	end
	local g = modifierGlowCfg(bestId)
	return g and g.Color or nil
end

local function titleCaseSpecies(s: string): string
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a: string, b: string)
		return a:upper() .. b
	end))
end

local function readFilterId(chip: TextButton): string
	local fid = chip:FindFirstChild("FilterId")
	if fid and fid:IsA("StringValue") then
		return fid.Value
	end
	return chip.Name:gsub("FilterChip_", ""):lower()
end

function InventoryUI.show(
	items: {any},
	onListRequest: (string, number) -> (),
	onQuickSell: (string) -> (),
	suggestedPriceFor: (any) -> number,
	onHoldFish: ((string, string, {string}, number) -> ())?
): InventoryHandle
	local reducedMotion = MotionUtil.reducedMotionEnabled()

	local selectionMode = false
	local selected: {[string]: boolean} = {}
	local sortState = { key = "rarity", dir = -1 }
	local activeFilter = "all"
	local currentItems: {any} = items
	local cardSetters: {[string]: (boolean) -> ()} = {}
	local hoverConns: {RBXScriptConnection} = {}

	local gui = TemplateLoader.spawn("Inventory", { instanceName = "InventoryUI" })
	local backdrop = requireChild(gui, "Backdrop", "TextButton") :: TextButton
	local panel = requireChild(gui, "Panel", "Frame") :: Frame
	local header = requireChild(panel, "Header", "Frame") :: Frame
	local closeBtn = requireChild(header, "Close", "TextButton") :: TextButton
	local body = requireChild(panel, "Body", "Frame") :: Frame

	local normalBtns = requireChild(requireChild(body, "SelectionRow", "Frame"), "NormalBtns", "Frame")
	local selectBtn = requireChild(normalBtns, "SelectBtn", "TextButton") :: TextButton
	local selBtns = requireChild(requireChild(body, "SelectionRow", "Frame"), "SelBtns", "Frame")
	local selectAllBtn = requireChild(selBtns, "SelectAllBtn", "TextButton") :: TextButton
	local sellSelectedBtn = requireChild(selBtns, "SellSelectedBtn", "TextButton") :: TextButton
	local cancelBtn = requireChild(selBtns, "CancelBtn", "TextButton") :: TextButton

	local filterRow = requireChild(body, "FilterRow", "Frame")
	local filterChips: {[string]: TextButton} = {}
	for _, chip in ipairs(filterRow:GetChildren()) do
		if chip:IsA("TextButton") and chip.Name:match("^FilterChip_") then
			filterChips[readFilterId(chip)] = chip
		end
	end

	local raritySortBtn = requireChild(requireChild(body, "SortControls", "Frame"), "RaritySortBtn", "TextButton") :: TextButton
	local priceSortBtn = requireChild(requireChild(body, "SortControls", "Frame"), "PriceSortBtn", "TextButton") :: TextButton

	local gridContainer = requireChild(body, "GridContainer", "ScrollingFrame") :: ScrollingFrame
	local sectionList = requireChild(gridContainer, "SectionList", "Frame")
	local sectionTpl = requireChild(sectionList, "Section_Template", "Frame")
	local fishCardTpl = requireChild(body, "FishCard_Template", "Frame")

	local fadeDuration = M.FadeDuration
	local slideOffsetPx = M.SlideOffsetPx
	local meta = gui:FindFirstChild("Meta")
	if meta and meta:IsA("Folder") then
		local fadeVal = meta:FindFirstChild("FadeDuration")
		if fadeVal and fadeVal:IsA("NumberValue") then
			fadeDuration = fadeVal.Value
		end
		local slideVal = meta:FindFirstChild("SlideOffsetPx")
		if slideVal and slideVal:IsA("NumberValue") then
			slideOffsetPx = slideVal.Value
		end
	end

	local closed = false
	local restPos = panel.Position
	local fromPos = UDim2.new(
		restPos.X.Scale, restPos.X.Offset,
		restPos.Y.Scale, restPos.Y.Offset + slideOffsetPx
	)
	local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function destroy()
		if closed then
			return
		end
		closed = true
		for _, conn in ipairs(hoverConns) do
			conn:Disconnect()
		end
		table.clear(hoverConns)
		if gui.Parent then
			gui:Destroy()
		end
	end

	local function syncSellBtn()
		local count = 0
		for _ in pairs(selected) do
			count += 1
		end
		sellSelectedBtn.Text = "Sell (" .. count .. ")"
		local disabled = count == 0
		sellSelectedBtn.BackgroundTransparency = disabled and 0.5 or 0
		sellSelectedBtn.TextTransparency = disabled and 0.4 or 0
	end

	local function updateFilterChips()
		for fid, chip in pairs(filterChips) do
			chip.BackgroundColor3 = (fid == activeFilter) and P.TealLight or P.Teal
		end
	end

	local function sortDirSuffix(active: boolean, dir: number): string
		if not active then
			return ""
		end
		return if dir == -1 then " (high first)" else " (low first)"
	end

	local function updateSortBtns()
		local rarityActive = sortState.key == "rarity"
		raritySortBtn.BackgroundColor3 = rarityActive and P.TealLight or P.Teal
		raritySortBtn.Text = "Rarity" .. sortDirSuffix(rarityActive, sortState.dir)
		local priceActive = sortState.key == "price"
		priceSortBtn.BackgroundColor3 = priceActive and P.TealLight or P.Teal
		priceSortBtn.Text = "Price" .. sortDirSuffix(priceActive, sortState.dir)
	end

	local function speciesForItem(item: any): string?
		if item.kind == "Fish" then
			return item.speciesId
		end
		if item.kind == "Good" then
			return EconomyUtil.parsePreservedSpeciesId(item.goodId)
		end
		return nil
	end

	local function sortItems(its: {any}): {any}
		local copy = table.clone(its)
		table.sort(copy, function(a, b)
			if sortState.key == "rarity" then
				local fa = _fishById[speciesForItem(a) or ""]
				local fb = _fishById[speciesForItem(b) or ""]
				local ra = RARITY_ORDER[(fa and fa.rarity) or "Common"] or 1
				local rb = RARITY_ORDER[(fb and fb.rarity) or "Common"] or 1
				if ra == rb then
					return false
				end
				if sortState.dir == -1 then
					return ra > rb
				else
					return ra < rb
				end
			else
				local pa = suggestedPriceFor(a)
				local pb = suggestedPriceFor(b)
				if pa == pb then
					return false
				end
				if sortState.dir == -1 then
					return pa > pb
				else
					return pa < pb
				end
			end
		end)
		return copy
	end

	local function showSelectionOnCards(root: Instance)
		for _, c in ipairs(root:GetDescendants()) do
			if c:IsA("Frame") and c.Name ~= "FishCard_Template" and c:FindFirstChild("CardStroke") then
				local chk = c:FindFirstChild("Checkbox")
				local ov = c:FindFirstChild("SelectOverlay")
				if chk then
					chk.Visible = true
				end
				if ov and ov:IsA("GuiButton") then
					ov.Visible = true
				end
			end
		end
	end

	local function enterSelectionMode()
		selectionMode = true
		selected = {}
		normalBtns.Visible = false
		selBtns.Visible = true
		syncSellBtn()
		showSelectionOnCards(sectionList)
	end

	local function exitSelectionMode()
		selectionMode = false
		selected = {}
		normalBtns.Visible = true
		selBtns.Visible = false
		for _, c in ipairs(sectionList:GetDescendants()) do
			if c:IsA("Frame") and c:FindFirstChild("CardStroke") then
				local chk = c:FindFirstChild("Checkbox")
				local ov = c:FindFirstChild("SelectOverlay")
				local chkMark = chk and chk:FindFirstChild("CheckMark")
				if chk then
					chk.Visible = false
				end
				if ov and ov:IsA("GuiButton") then
					ov.Visible = false
				end
				if chkMark and chkMark:IsA("TextLabel") then
					chkMark.Visible = false
				end
				local stroke = c:FindFirstChild("CardStroke")
				if stroke and stroke:IsA("UIStroke") then
					stroke.Color = P.TealDeeper
					stroke.Thickness = 1
					stroke.Transparency = 0.5
				end
			end
		end
	end

	local function sectionVisible(sectionKey: string): boolean
		if activeFilter == "all" then
			return true
		end
		return activeFilter == sectionKey
	end

	local function clearSections()
		for _, child in ipairs(sectionList:GetChildren()) do
			if child:IsA("Frame") and child ~= sectionTpl and child.Name ~= "UIListLayout" then
				child:Destroy()
			end
		end
	end

	local function populateModifierPills(container: Frame, mods: {string})
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Frame") and child.Name == "ModifierPill" then
				child:Destroy()
			elseif child:IsA("TextLabel") and child.Name == "OverflowLabel" then
				child:Destroy()
			end
		end
		if #mods == 0 then
			container.Visible = false
			return
		end
		container.Visible = true
		local maxVis = math.min(#mods, 3)
		for i = 1, maxVis do
			local modId = mods[i]
			local pill = UIKit.ModifierPill(modId, _modDisplayNames[modId] or modId, {
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = i,
				BackgroundTransparency = 0.2,
				Parent = container,
			})
			local gCfg = modifierGlowCfg(modId)
			if gCfg then
				local gs = Instance.new("UIStroke")
				gs.Color = gCfg.Color
				gs.Thickness = gCfg.Thickness
				gs.Transparency = gCfg.Transparency
				gs.Parent = pill
			end
		end
		if #mods > 3 then
			local oLbl = UIUtil.makeLabel("+" .. (#mods - 3), "caption", {
				Name = "OverflowLabel",
				Size = UDim2.fromOffset(36, 20),
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 4,
				Parent = container,
			})
			oLbl = oLbl
		end
	end

	local function wireCardHover(card: Frame, thumbVpf: ViewportFrame, thumbResult: UIKit.FishThumbResult)
		if not thumbResult.clone or not thumbResult.initPivot or reducedMotion then
			return
		end
		local clone = thumbResult.clone
		local initPivot = thumbResult.initPivot
		local baseSize = thumbVpf.Size
		local popSize = UDim2.new(
			baseSize.X.Scale + 0.06, baseSize.X.Offset,
			baseSize.Y.Scale, baseSize.Y.Offset + 8
		)
		local popTI = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local dropTI = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local rotConn: RBXScriptConnection? = nil
		local rotAngle = 0

		table.insert(hoverConns, card.MouseEnter:Connect(function()
			MotionUtil.tween(thumbVpf, popTI, { Size = popSize })
			rotConn = RunService.Heartbeat:Connect(function(dt)
				if not card.Parent then
					if rotConn then
						rotConn:Disconnect()
						rotConn = nil
					end
					return
				end
				rotAngle += dt * 1.5
				clone:PivotTo(CFrame.new(initPivot.Position) * CFrame.Angles(0, rotAngle, 0))
			end)
		end))

		table.insert(hoverConns, card.MouseLeave:Connect(function()
			MotionUtil.tween(thumbVpf, dropTI, { Size = baseSize })
			if rotConn then
				rotConn:Disconnect()
				rotConn = nil
			end
			rotAngle = 0
			clone:PivotTo(initPivot)
		end))
	end

	local function buildCard(item: any, idx: number, gridHost: Frame): (boolean) -> ()
		local card = fishCardTpl:Clone()
		card.Name = "Card_" .. (item.uid or idx)
		card.Visible = true
		card.LayoutOrder = idx
		card.Parent = gridHost

		local isFish = item.kind == "Fish"
		local isPreserved = item.kind == "Good" and EconomyUtil.isPreservedGoodId(item.goodId)
		local preservedSpecies = if isPreserved
			then EconomyUtil.parsePreservedSpeciesId(item.goodId)
			else nil
		local fishData = if isFish
			then _fishById[item.speciesId or ""]
			elseif preservedSpecies then _fishById[preservedSpecies]
			else nil
		local fishRarity = (fishData and fishData.rarity) or "Common"
		local rCol = UIUtil.rarityColor(fishRarity)
		local mods: {string} = if isFish then (item.modifiers or {}) else {}
		local showAsFish = isFish or isPreserved

		local cs = requireChild(card, "CardStroke", "UIStroke") :: UIStroke
		if isFish and #mods >= 2 then
			local gc = cardGlowColor(mods)
			if gc then
				cs.Color = gc
				cs.Thickness = 2.5
				cs.Transparency = 0.2
			end
		end

		local rarityHeader = card:FindFirstChild("RarityHeader")
		local rarityLabel = requireChild(card, "RarityLabel", "TextLabel") :: TextLabel
		if showAsFish then
			if rarityHeader and rarityHeader:IsA("Frame") then
				rarityHeader.BackgroundColor3 = rCol
				rarityHeader.Visible = true
			end
			rarityLabel.Visible = true
			rarityLabel.Text = if isPreserved then "SMOKED" else fishRarity:upper()
		else
			if rarityHeader and rarityHeader:IsA("Frame") then
				rarityHeader.Visible = false
			end
			rarityLabel.Visible = false
		end

		local contentY = if showAsFish then HEADER_H else 0
		local thumbVpf = requireChild(card, "ThumbView", "ViewportFrame") :: ViewportFrame
		local thumbResult: UIKit.FishThumbResult = { clone = nil, initPivot = nil }
		if showAsFish then
			thumbVpf.Position = UDim2.new(0.5, 0, 0, contentY + 4)
			thumbVpf.Visible = true
			local thumbSpecies = if isFish then item.speciesId else preservedSpecies
			thumbResult = UIKit.attachFishThumb(thumbVpf, thumbSpecies or "", { modifiers = mods })
			wireCardHover(card, thumbVpf, thumbResult)
		else
			thumbVpf.Visible = false
		end

		local nameLbl = requireChild(card, "NameLabel", "TextLabel") :: TextLabel
		local wLbl = requireChild(card, "WeightLabel", "TextLabel") :: TextLabel
		local nameY = if showAsFish then (contentY + 4 + THUMB_H + 8) else (contentY + 8)
		nameLbl.Position = UDim2.new(0, 10, 0, nameY)
		wLbl.Position = if isFish or isPreserved
			then UDim2.new(1, -10, 0, nameY)
			else UDim2.new(1, -10, 0, nameY + 2)

		if isFish then
			nameLbl.Text = titleCaseSpecies(item.speciesId or "fish")
			wLbl.Text = ("%.1f kg"):format(item.weightKg or 0)
		elseif isPreserved then
			local base = (fishData and fishData.displayName) or (preservedSpecies or "fish"):gsub("_", " ")
			nameLbl.Text = base .. " (Smoked)"
			wLbl.Text = ("%.1f kg"):format(item.weightKg or 0)
		else
			nameLbl.Text = titleCaseSpecies(item.goodId or "Item")
			wLbl.Text = ("× %d"):format(item.count or 1)
		end

		local pillContainer = requireChild(card, "ModifierPillContainer", "Frame")
		if isFish then
			pillContainer.Position = UDim2.new(0, 10, 0, nameY + 22)
			populateModifierPills(pillContainer, mods)
		else
			pillContainer.Visible = false
		end

		local checkbox = requireChild(card, "Checkbox", "Frame")
		local chkMark = requireChild(checkbox, "CheckMark", "TextLabel") :: TextLabel
		local overlay = requireChild(card, "SelectOverlay", "TextButton") :: TextButton

		local function setSelected(v: boolean)
			selected[item.uid] = v or nil :: any
			chkMark.Visible = v
			checkbox.BackgroundColor3 = if v then P.TealLight else P.TealDark
			checkbox.BackgroundTransparency = if v then 0 else 0.2
			if v then
				cs.Color = P.TealLight
				cs.Thickness = 3
				cs.Transparency = 0.1
			else
				local gc = if isFish and #mods >= 2 then cardGlowColor(mods) else nil
				cs.Color = gc or P.TealDeeper
				cs.Thickness = if gc then 2.5 else 1
				cs.Transparency = if gc then 0.2 else 0.5
			end
			syncSellBtn()
		end

		overlay.Activated:Connect(function()
			if selectionMode then
				setSelected(not selected[item.uid])
			end
		end)

		local actionRow = requireChild(card, "ActionRow", "Frame")
		local sellBtn = requireChild(actionRow, "SellBtn", "TextButton") :: TextButton
		local listBtn = requireChild(actionRow, "ListBtn", "TextButton") :: TextButton
		local holdBtn = actionRow:FindFirstChild("HoldBtn")
		local numBtns = if isFish then (if onHoldFish then 3 else 2) elseif isPreserved then 2 else 2
		local bw = math.floor((260 - 16 - (numBtns - 1) * 4) / numBtns)
		sellBtn.Size = UDim2.fromOffset(bw, BTN_H)
		listBtn.Size = UDim2.fromOffset(bw, BTN_H)
		sellBtn.Activated:Connect(function()
			onQuickSell(item.uid)
		end)
		listBtn.Activated:Connect(function()
			onListRequest(item.uid, suggestedPriceFor(item))
		end)
		if holdBtn and holdBtn:IsA("TextButton") then
			if isFish and onHoldFish then
				holdBtn.Visible = true
				holdBtn.Size = UDim2.fromOffset(bw, BTN_H)
				holdBtn.Activated:Connect(function()
					onHoldFish(item.uid, item.speciesId or "", mods, item.weightKg or 0)
					destroy()
				end)
			else
				holdBtn.Visible = false
			end
		end

		return setSelected
	end

	local refresh: (items_: {any}) -> ()

	refresh = function(items_: {any})
		currentItems = items_
		local prevSel = table.clone(selected)
		cardSetters = {}

		clearSections()

		if #items_ == 0 then
			local empty = UIUtil.makeLabel("No catches yet — head to the dock!", "body", {
				Size = UDim2.new(1, 0, 0, 60),
				TextColor3 = P.CreamSoft,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 1,
				Parent = sectionList,
			})
			empty = empty
			return
		end

		local preserved: {any} = {}
		local fish: {any} = {}
		local otherGoods: {any} = {}
		for _, item in ipairs(items_) do
			if item.kind == "Good" and EconomyUtil.isPreservedGoodId(item.goodId) then
				table.insert(preserved, item)
			elseif item.kind == "Fish" then
				table.insert(fish, item)
			elseif item.kind == "Good" then
				table.insert(otherGoods, item)
			end
		end

		local buckets: {{key: string, title: string, items: {any}}} = {
			{ key = "preserved", title = "Preserved", items = preserved },
			{ key = "catch", title = "Catch", items = fish },
			{ key = "goods", title = "Goods", items = otherGoods },
		}

		local sectionOrder = 0
		for _, bucket in ipairs(buckets) do
			if #bucket.items == 0 or not sectionVisible(bucket.key) then
				continue
			end
			sectionOrder += 1
			local section = sectionTpl:Clone()
			section.Name = "Section_" .. bucket.title
			section.Visible = true
			section.LayoutOrder = sectionOrder
			section.Parent = sectionList

			local titleLbl = requireChild(section, "SectionTitle", "TextLabel") :: TextLabel
			titleLbl.Text = bucket.title:upper()

			local gridHost = requireChild(section, "SectionGrid", "Frame")
			local sorted = sortItems(bucket.items)
			for i, item in ipairs(sorted) do
				local setter = buildCard(item, i, gridHost)
				if item.uid then
					cardSetters[item.uid] = setter
				end
			end
		end

		for uid in pairs(prevSel) do
			local setter = cardSetters[uid]
			if setter then
				setter(true)
			end
		end

		if selectionMode then
			showSelectionOnCards(sectionList)
		end
	end

	selectBtn.Activated:Connect(enterSelectionMode)
	cancelBtn.Activated:Connect(exitSelectionMode)
	selectAllBtn.Activated:Connect(function()
		for _, item in ipairs(currentItems) do
			local setter = cardSetters[item.uid]
			if setter then
				setter(true)
			end
		end
	end)
	sellSelectedBtn.Activated:Connect(function()
		local count = 0
		for _ in pairs(selected) do
			count += 1
		end
		if count == 0 then
			return
		end
		local uids: {string} = {}
		for uid in pairs(selected) do
			table.insert(uids, uid)
		end
		for _, uid in ipairs(uids) do
			onQuickSell(uid)
		end
		selected = {}
		syncSellBtn()
		for _, setter in pairs(cardSetters) do
			setter(false)
		end
	end)

	for fid, chip in pairs(filterChips) do
		chip.Activated:Connect(function()
			activeFilter = fid
			updateFilterChips()
			refresh(currentItems)
		end)
	end

	raritySortBtn.Activated:Connect(function()
		if sortState.key == "rarity" then
			sortState.dir = -sortState.dir
		else
			sortState.key = "rarity"
			sortState.dir = -1
		end
		updateSortBtns()
		refresh(currentItems)
	end)

	priceSortBtn.Activated:Connect(function()
		if sortState.key == "price" then
			sortState.dir = -sortState.dir
		else
			sortState.key = "price"
			sortState.dir = -1
		end
		updateSortBtns()
		refresh(currentItems)
	end)

	local function requestClose()
		destroy()
	end

	backdrop.Activated:Connect(requestClose)
	closeBtn.Activated:Connect(requestClose)

	panel.BackgroundTransparency = 1
	backdrop.BackgroundTransparency = 1
	if reducedMotion then
		panel.Position = restPos
		panel.BackgroundTransparency = 0
		backdrop.BackgroundTransparency = M.BackdropAlpha
	else
		panel.Position = fromPos
		MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = M.BackdropAlpha })
		MotionUtil.tweenOrSnap(panel, fadeInfo, { BackgroundTransparency = 0, Position = restPos })
	end

	updateFilterChips()
	updateSortBtns()
	refresh(items)

	return {
		gui = gui,
		close = requestClose,
		refresh = refresh,
	}
end

return InventoryUI
