--!strict
-- InventoryUI.lua
-- Modal grid of inventory cards. 260×260 square cards with full-width fish
-- thumbnails, hover scale-pop + spin, selection-based batch selling,
-- rarity/price sorting, per-modifier UIStroke glows, and hold-fish action.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UIUtil             = require(script.Parent.UIUtil)
local FishCatalogRaw     = require(ReplicatedStorage.Shared.Config.FishCatalog)
local GameConfig         = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil         = require(ReplicatedStorage.Shared.Util.MotionUtil)
local FishMutations      = require(ReplicatedStorage.Shared.Util.FishMutations)
local EconomyUtil        = require(ReplicatedStorage.Shared.Util.EconomyUtil)

local P = UIUtil.Palette

local InventoryUI = {}

export type InventoryHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (items: {any}) -> (),
}

local _fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalogRaw.fish) do _fishById[f.id] = f end

local RARITY_ORDER: {[string]: number} = {
	Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, Divine=7,
}
-- Rarity + modifier colors live in UIUtil.Palette (single source of truth).
-- Use UIUtil.rarityColor(rarity) and UIUtil.modifierColor(id).

-- Priority order for picking the card-frame glow color when 2+ modifiers stack.
-- Lower priority number = wins. Rarest/flashiest modifiers come first.
local MOD_PRIORITY: {[string]: number} = {
	rainbow=1, voidtouched=2, golden=3, bloodlust=4, radioactive=5,
	inferno=6, frozen=7, disco=8, crystal=9, ancientcore=10,
	silver=11, shocked=12, colossal=13, ghostly=14, tiny=15,
	moon_touched=20, storm_forged=21, dawn_blessed=22, tide_kissed=23, fog_shrouded=24,
	-- Deprecated trailing — lowest priority so legacy mods don't shadow new ones.
	prismatic=30, shiny=31, glowing=32, giant=33, elder=34,
	ancient=35, lucky=36, magnetic=37, cursed=38, barnacled=39,
}

local _modDisplayNames: {[string]: string} = {}
for _, m in ipairs(GameConfig.FishModifiers) do _modDisplayNames[m.id] = m.displayName end

local CARD_W    = 260
local CARD_H    = 260
local THUMB_H   = 110
local HEADER_H  = 28
local BTN_H     = 44

local function modifierGlowCfg(modId: string): {Color: Color3, Thickness: number, Transparency: number}?
	local cfg = (GameConfig :: any).ModifierGlow
	if cfg and cfg[modId] then return cfg[modId] end
	-- Fallback for unknown ids — UIUtil.modifierColor handles the lookup
	-- against Palette.Modifiers (built from GameConfig.ModifierGlow).
	return { Color = UIUtil.modifierColor(modId), Thickness = 2.0, Transparency = 0.3 }
end

local function cardGlowColor(mods: {string}): Color3?
	if #mods < 2 then return nil end
	local bestId: string? = nil
	local bestPri = math.huge
	for _, id in ipairs(mods) do
		local pri = MOD_PRIORITY[id] or 99
		if pri < bestPri then bestPri = pri; bestId = id end
	end
	if not bestId then return nil end
	local g = modifierGlowCfg(bestId)
	return g and g.Color or nil
end


function InventoryUI.show(
	items: {any},
	onListRequest: (string, number) -> (),
	onQuickSell: (string) -> (),
	suggestedPriceFor: (any) -> number,
	onHoldFish: ((string, string, {string}, number) -> ())?
): InventoryHandle

	local reducedMotion = MotionUtil.reducedMotionEnabled()

	-- Mutable state
	local selectionMode  = false
	local selected: {[string]: boolean} = {}
	local sortState = { key = "rarity", dir = -1 }   -- dir -1 = descending
	local currentItems: {any} = items
	local cardSetters: {[string]: (boolean) -> ()} = {}

	-- Modal chrome (backdrop + panel + header + close button) from the
	-- shared shell — keeps Inventory visually identical to every other
	-- modal in the game.
	local shell
	shell = UIUtil.makeModalShell({
		name = "InventoryUI",
		title = "Inventory",
		onClose = function() if shell then shell.destroy() end end,
		width = 700,
		heightScale = 0.88,
	})
	local gui = shell.gui
	local body = shell.body

	-- ── ACTION ROW (top of body) ──────────────────────────────────────
	-- Normal mode: [Select] (right-aligned). Selection mode: [Select All]
	-- [Sell (N)] [Cancel]. The two frames stack at the same anchor and
	-- toggle Visible.
	local normalBtns = Instance.new("Frame")
	normalBtns.BackgroundTransparency = 1
	normalBtns.AnchorPoint = Vector2.new(1, 0)
	normalBtns.Position = UDim2.new(1, 0, 0, 0)
	normalBtns.Size = UDim2.fromOffset(96, BTN_H)
	normalBtns.Parent = body

	local selectBtn = UIUtil.makeSecondaryButton("Select", function() end, {
		Size = UDim2.fromOffset(96, BTN_H),
	})
	selectBtn.Parent = normalBtns

	local selBtns = Instance.new("Frame")
	selBtns.BackgroundTransparency = 1
	selBtns.AnchorPoint = Vector2.new(1, 0)
	selBtns.Position = UDim2.new(1, 0, 0, 0)
	selBtns.Size = UDim2.fromOffset(296, BTN_H)
	selBtns.Visible = false
	selBtns.Parent = body
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	sl.VerticalAlignment = Enum.VerticalAlignment.Center
	sl.Padding = UDim.new(0, UIUtil.Spacing.sm)
	sl.Parent = selBtns

	local selectAllBtn = UIUtil.makeSecondaryButton("Select All", function() end, {
		Size = UDim2.fromOffset(96, BTN_H),
	})
	selectAllBtn.Parent = selBtns

	local sellSelectedBtn = UIUtil.makeDangerButton("Sell (0)", function() end, {
		Size = UDim2.fromOffset(104, BTN_H),
	})
	sellSelectedBtn.BackgroundTransparency = 0.5
	sellSelectedBtn.TextTransparency = 0.4
	sellSelectedBtn.Parent = selBtns

	local cancelBtn = UIUtil.makeGhostButton("Cancel", function() end, {
		Size = UDim2.fromOffset(88, BTN_H),
	})
	cancelBtn.Parent = selBtns

	-- ── SORT BAR (below action row) ───────────────────────────────────
	local sortBar = Instance.new("Frame")
	sortBar.BackgroundTransparency = 1
	sortBar.Position = UDim2.new(0, 0, 0, BTN_H + UIUtil.Spacing.sm)
	sortBar.Size = UDim2.new(1, 0, 0, BTN_H)
	sortBar.Parent = body
	local sortLayout = Instance.new("UIListLayout")
	sortLayout.FillDirection = Enum.FillDirection.Horizontal
	sortLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	sortLayout.Padding = UDim.new(0, UIUtil.Spacing.sm)
	sortLayout.Parent = sortBar

	-- ── SCROLLING GRID (fills remaining body) ─────────────────────────
	local listTop = (BTN_H + UIUtil.Spacing.sm) * 2
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, listTop)
	list.Size = UDim2.new(1, 0, 1, -listTop)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = P.TealDeeper
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, UIUtil.Spacing.md)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Parent = list

	local listPad = Instance.new("UIPadding")
	listPad.PaddingLeft = UDim.new(0, UIUtil.Spacing.sm)
	listPad.PaddingRight = UDim.new(0, UIUtil.Spacing.sm)
	listPad.PaddingTop = UDim.new(0, UIUtil.Spacing.sm)
	listPad.PaddingBottom = UDim.new(0, UIUtil.Spacing.sm)
	listPad.Parent = list

	-- ── SELECTION MODE HELPERS ─────────────────────────────────────────
	local function syncSellBtn()
		local count = 0
		for _ in pairs(selected) do count += 1 end
		sellSelectedBtn.Text = "Sell (" .. count .. ")"
		local disabled = count == 0
		sellSelectedBtn.BackgroundTransparency = disabled and 0.5 or 0
		sellSelectedBtn.TextTransparency = disabled and 0.4 or 0
	end

	local function enterSelectionMode()
		selectionMode = true
		selected = {}
		normalBtns.Visible = false
		selBtns.Visible = true
		syncSellBtn()
		for _, c in ipairs(list:GetDescendants()) do
			if c:IsA("Frame") and c:FindFirstChild("CardStroke") then
				local chk = c:FindFirstChild("Checkbox")
				local ov  = c:FindFirstChild("SelectOverlay")
				if chk then chk.Visible = true end
				if ov  then ov.Visible  = true end
			end
		end
	end

	local function exitSelectionMode()
		selectionMode = false
		selected = {}
		normalBtns.Visible = true
		selBtns.Visible = false
		for _, c in ipairs(list:GetDescendants()) do
			if c:IsA("Frame") and c:FindFirstChild("CardStroke") then
				local chk = c:FindFirstChild("Checkbox")
				local ov  = c:FindFirstChild("SelectOverlay")
				local chkMark = chk and chk:FindFirstChildOfClass("TextLabel")
				if chk then chk.Visible = false end
				if ov  then ov.Visible  = false end
				if chkMark then chkMark.Visible = false end
				local stroke = c:FindFirstChild("CardStroke")
				if stroke and stroke:IsA("UIStroke") then
					stroke.Color = P.TealDeeper
					stroke.Thickness = 1
					stroke.Transparency = 0.5
				end
			end
		end
	end

	selectBtn.Activated:Connect(enterSelectionMode)
	cancelBtn.Activated:Connect(exitSelectionMode)

	selectAllBtn.Activated:Connect(function()
		for _, item in ipairs(currentItems) do
			local setter = cardSetters[item.uid]
			if setter then setter(true) end
		end
	end)

	sellSelectedBtn.Activated:Connect(function()
		local count = 0
		for _ in pairs(selected) do count += 1 end
		if count == 0 then return end
		local uids: {string} = {}
		for uid in pairs(selected) do table.insert(uids, uid) end
		for _, uid in ipairs(uids) do onQuickSell(uid) end
		selected = {}
		syncSellBtn()
		-- Deselect all card visuals
		for _, setter in pairs(cardSetters) do setter(false) end
	end)

	-- ── SORT HELPERS ───────────────────────────────────────────────────
	-- Declared here; sort buttons created after refresh (forward ref satisfied).
	local rarityBtn: TextButton
	local priceBtn: TextButton

	local function updateSortBtns()
		if rarityBtn then
			local active = sortState.key == "rarity"
			rarityBtn.BackgroundColor3 = active and P.TealLight or P.Teal
			rarityBtn.Text = "Rarity " .. (active and (sortState.dir == -1 and "▼" or "▲") or "▼")
		end
		if priceBtn then
			local active = sortState.key == "price"
			priceBtn.BackgroundColor3 = active and P.TealLight or P.Teal
			priceBtn.Text = "Price " .. (active and (sortState.dir == -1 and "▼" or "▲") or "▼")
		end
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
				if ra == rb then return false end
				if sortState.dir == -1 then return ra > rb else return ra < rb end
			else
				local pa = suggestedPriceFor(a)
				local pb = suggestedPriceFor(b)
				if pa == pb then return false end
				if sortState.dir == -1 then return pa > pb else return pa < pb end
			end
		end)
		return copy
	end

	-- ── CARD BUILDER ───────────────────────────────────────────────────
	local function buildCard(item: any, idx: number, cardParent: Instance): (boolean) -> ()
		local isFish = item.kind == "Fish"
		local isPreserved = item.kind == "Good" and EconomyUtil.isPreservedGoodId(item.goodId)
		local preservedSpecies = isPreserved and EconomyUtil.parsePreservedSpeciesId(item.goodId) or nil
		local fishData = isFish and _fishById[item.speciesId or ""]
			or (preservedSpecies and _fishById[preservedSpecies])
			or nil
		local fishRarity = (fishData and fishData.rarity) or "Common"
		local rCol       = UIUtil.rarityColor(fishRarity)
		local mods: {string} = (isFish and item.modifiers) or {}
		local showAsFish = isFish or isPreserved

		-- Card frame
		local card = Instance.new("Frame")
		card.BackgroundColor3 = P.Teal
		card.BorderSizePixel = 0
		card.LayoutOrder = idx
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = card
		local cs = Instance.new("UIStroke")
		cs.Name = "CardStroke"
		cs.Color = P.TealDeeper
		cs.Thickness = 1
		cs.Transparency = 0.5
		cs.Parent = card

		-- Multi-modifier card-level glow
		if isFish and #mods >= 2 then
			local gc = cardGlowColor(mods)
			if gc then
				cs.Color = gc
				cs.Thickness = 2.5
				cs.Transparency = 0.2
			end
		end

		card.Parent = cardParent

		-- Rarity header band (fish + preserved goods)
		if showAsFish then
			local hBg = Instance.new("Frame")
			hBg.BackgroundColor3 = rCol
			hBg.BackgroundTransparency = 0.2
			hBg.BorderSizePixel = 0
			hBg.Size = UDim2.new(1, 0, 0, HEADER_H)
			local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 10); hc.Parent = hBg
			hBg.Parent = card

			local hLbl = Instance.new("TextLabel")
			hLbl.BackgroundTransparency = 1
			hLbl.Size = UDim2.new(1, 0, 0, HEADER_H)
			hLbl.Font = Enum.Font.GothamBold
			hLbl.TextSize = 12
			hLbl.TextColor3 = Color3.new(1, 1, 1)
			hLbl.Text = if isPreserved then "SMOKED" else fishRarity:upper()
			hLbl.Parent = card
		end

		local contentY = showAsFish and HEADER_H or 0

		-- Fish thumbnail ViewportFrame (full-width, anchored top-center)
		local thumbVpf: ViewportFrame? = nil
		local thumbClone: Model? = nil
		local thumbInitPivot: CFrame? = nil

		if isFish or isPreserved then
			local thumbSpecies = isFish and item.speciesId or preservedSpecies
			local vpf = Instance.new("ViewportFrame")
			vpf.Name = "FishThumb"
			vpf.AnchorPoint = Vector2.new(0.5, 0)
			vpf.Position = UDim2.new(0.5, 0, 0, contentY + 4)
			vpf.Size = UDim2.new(1, -16, 0, THUMB_H)
			vpf.BackgroundColor3 = P.TealDeeper
			vpf.BorderSizePixel = 0
			vpf.LightColor = P.ThumbLight
			vpf.LightDirection = Vector3.new(-1, -2, -1)
			local tvc = Instance.new("UICorner"); tvc.CornerRadius = UDim.new(0, 10); tvc.Parent = vpf
			vpf.Parent = card
			thumbVpf = vpf

			local fishAssets = ReplicatedStorage:FindFirstChild("Assets")
				and ReplicatedStorage.Assets:FindFirstChild("Fish")
			local tmpl = fishAssets and fishAssets:FindFirstChild(thumbSpecies or "")
			if tmpl then
				local wm = Instance.new("WorldModel"); wm.Parent = vpf
				local clone = (tmpl :: Model):Clone()
				clone.Parent = wm
				thumbClone = clone
				local thumbAnchor: BasePart? = clone.PrimaryPart
					and clone.PrimaryPart:IsA("BasePart") and (clone.PrimaryPart :: BasePart)
					or nil
				if not thumbAnchor then
					local named = clone:FindFirstChild("body_geom", true)
					if named and named:IsA("BasePart") then
						thumbAnchor = named :: BasePart
					end
				end
				if not thumbAnchor then
					for _, d in ipairs(clone:GetDescendants()) do
						if d:IsA("BasePart") then
							thumbAnchor = d :: BasePart
							break
						end
					end
				end
				if thumbAnchor then
					local okBB, _pivot, ext = pcall(function(): (CFrame, Vector3)
						return clone:GetBoundingBox()
					end)
					if okBB and ext then
						local maxDim = math.max(ext.X, ext.Y, ext.Z)
						if maxDim > 0.01 then
							pcall(function()
								clone:ScaleTo(2.2 / maxDim)
							end)
						end
					end
					if #mods > 0 then
						FishMutations.attach(thumbAnchor, mods, { viewport = true, intensity = 1 })
					end
				end
				local tcam = Instance.new("Camera")
				tcam.FieldOfView = 40
				vpf.CurrentCamera = tcam
				tcam.Parent = vpf
				local ok, pivot, ext = pcall(function(): (CFrame, Vector3)
					return clone:GetBoundingBox()
				end)
				if ok and pivot then
					local md   = math.max(ext.X, ext.Y, ext.Z)
					local dist = math.max(md * 1.5, 4)
					tcam.CFrame = CFrame.lookAt(
						pivot.Position + Vector3.new(dist * 0.7, dist * 0.4, dist * 0.7),
						pivot.Position
					)
					thumbInitPivot = clone:GetPivot()
				end
			end
		end

		-- Name label (left column)
		local nameText: string
		if isFish then
			nameText = (item.speciesId or "fish"):gsub("_", " ")
				:gsub("(%a)([%w]*)", function(a: string, b: string) return a:upper() .. b end)
		elseif isPreserved then
			local base = (fishData and fishData.displayName)
				or (preservedSpecies or "fish"):gsub("_", " ")
			nameText = base .. " (Smoked)"
		else
			nameText = (item.goodId or "Item"):gsub("_", " ")
				:gsub("(%a)([%w]*)", function(a: string, b: string) return a:upper() .. b end)
		end

		local nameY = showAsFish and (contentY + 4 + THUMB_H + 8) or (contentY + 8)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.Position = UDim2.new(0, 10, 0, nameY)
		nameLbl.Size = UDim2.new(1, -90, 0, 18)
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 13
		nameLbl.TextColor3 = P.Cream
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Text = nameText
		nameLbl.Parent = card

		-- Weight / count label
		local wLbl = Instance.new("TextLabel")
		wLbl.BackgroundTransparency = 1
		wLbl.Font = Enum.Font.Gotham
		wLbl.TextSize = 12
		wLbl.TextColor3 = P.CreamSoft
		if isFish or isPreserved then
			wLbl.AnchorPoint = Vector2.new(1, 0)
			wLbl.Position = UDim2.new(1, -10, 0, nameY)
			wLbl.Size = UDim2.fromOffset(76, 18)
			wLbl.TextXAlignment = Enum.TextXAlignment.Right
			wLbl.Text = ("%.1f kg"):format(item.weightKg or 0)
		else
			wLbl.AnchorPoint = Vector2.new(1, 0)
			wLbl.Position = UDim2.new(1, -10, 0, nameY + 2)
			wLbl.Size = UDim2.fromOffset(80, 16)
			wLbl.TextXAlignment = Enum.TextXAlignment.Right
			wLbl.Text = ("× %d"):format(item.count or 1)
		end
		wLbl.Parent = card

		-- Modifier pills (fish only)
		if isFish and #mods > 0 then
			local pillRow = Instance.new("Frame")
			pillRow.BackgroundTransparency = 1
			pillRow.ClipsDescendants = true
			pillRow.Position = UDim2.new(0, 10, 0, nameY + 22)
			pillRow.Size = UDim2.new(1, -20, 0, 24)
			pillRow.Parent = card
			local rl = Instance.new("UIListLayout")
			rl.FillDirection = Enum.FillDirection.Horizontal
			rl.SortOrder = Enum.SortOrder.LayoutOrder
			rl.Padding = UDim.new(0, 4)
			rl.VerticalAlignment = Enum.VerticalAlignment.Center
			rl.Parent = pillRow

			local maxVis = math.min(#mods, 3)
			for i = 1, maxVis do
				local modId = mods[i]
				local color = UIUtil.modifierColor(modId)
				local pill = Instance.new("Frame")
				pill.Size = UDim2.fromOffset(0, 22)
				pill.AutomaticSize = Enum.AutomaticSize.X
				pill.BackgroundColor3 = color
				pill.BackgroundTransparency = 0.2
				pill.BorderSizePixel = 0
				pill.LayoutOrder = i
				local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, UIUtil.Radii.sm); pc.Parent = pill
				local pp = Instance.new("UIPadding")
				pp.PaddingLeft  = UDim.new(0, UIUtil.Spacing.sm)
				pp.PaddingRight = UDim.new(0, UIUtil.Spacing.sm)
				pp.Parent = pill
				local pLbl = UIUtil.makeLabel(_modDisplayNames[modId] or modId, "caption", {
					Size = UDim2.fromScale(1, 1),
					TextXAlignment = Enum.TextXAlignment.Center,
					Font = Enum.Font.GothamBold,
					TextColor3 = UIUtil.Palette.Cream,
					Parent = pill,
				})
				pLbl = pLbl -- silence unused-variable lint
				-- Per-modifier glow stroke
				local gCfg = modifierGlowCfg(modId)
				if gCfg then
					local gs = Instance.new("UIStroke")
					gs.Color = gCfg.Color
					gs.Thickness = gCfg.Thickness
					gs.Transparency = gCfg.Transparency
					gs.Parent = pill
				end
				pill.Parent = pillRow
			end
			if #mods > 3 then
				local oLbl = UIUtil.makeLabel("+" .. (#mods - 3), "caption", {
					Size = UDim2.fromOffset(28, 22),
					Font = Enum.Font.GothamBold,
					TextXAlignment = Enum.TextXAlignment.Center,
					LayoutOrder = 4,
					Parent = pillRow,
				})
				oLbl = oLbl
			end
		end

		-- Checkbox (shown in selection mode, top-left of content area)
		local checkbox = Instance.new("Frame")
		checkbox.Name = "Checkbox"
		checkbox.Position = UDim2.new(0, 8, 0, contentY + 6)
		checkbox.Size = UDim2.fromOffset(24, 24)
		checkbox.BackgroundColor3 = P.TealDark
		checkbox.BackgroundTransparency = 0.2
		checkbox.BorderSizePixel = 0
		checkbox.Visible = false
		local chkC = Instance.new("UICorner"); chkC.CornerRadius = UDim.new(0.5, 0); chkC.Parent = checkbox
		local chkS = Instance.new("UIStroke"); chkS.Color = P.TealLight; chkS.Thickness = 2; chkS.Transparency = 0.2; chkS.Parent = checkbox
		local chkMark = Instance.new("TextLabel")
		chkMark.BackgroundTransparency = 1
		chkMark.Size = UDim2.fromScale(1, 1)
		chkMark.Font = Enum.Font.GothamBold
		chkMark.TextSize = 14
		chkMark.TextColor3 = P.TealLight
		chkMark.Text = "✓"
		chkMark.Visible = false
		chkMark.Parent = checkbox
		checkbox.Parent = card

		-- Invisible overlay button that handles selection taps (whole card area)
		local overlay = Instance.new("TextButton")
		overlay.Name = "SelectOverlay"
		overlay.BackgroundTransparency = 1
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.Text = ""
		overlay.Visible = false
		overlay.ZIndex = 5
		overlay.Parent = card

		-- setSelected closure: drives checkbox + card stroke + sell button text.
		local function setSelected(v: boolean)
			selected[item.uid] = v or nil :: any
			chkMark.Visible = v
			checkbox.BackgroundColor3 = v and P.TealLight or P.TealDark
			checkbox.BackgroundTransparency = v and 0 or 0.2
			if v then
				cs.Color = P.TealLight
				cs.Thickness = 3
				cs.Transparency = 0.1
			else
				local gc = (isFish and #mods >= 2) and cardGlowColor(mods) or nil
				cs.Color = gc or P.TealDeeper
				cs.Thickness = gc and 2.5 or 1
				cs.Transparency = gc and 0.2 or 0.5
			end
			syncSellBtn()
		end

		overlay.Activated:Connect(function()
			if selectionMode then setSelected(not selected[item.uid]) end
		end)

		-- Action buttons (bottom of card)
		local numBtns = isFish and (onHoldFish ~= nil and 3 or 2) or 2
		if isPreserved then numBtns = 2 end
		local bw = math.floor((CARD_W - 16 - (numBtns - 1) * 4) / numBtns)

		local btnsFrame = Instance.new("Frame")
		btnsFrame.BackgroundTransparency = 1
		btnsFrame.AnchorPoint = Vector2.new(0, 1)
		btnsFrame.Position = UDim2.new(0, 8, 1, -8)
		btnsFrame.Size = UDim2.new(1, -16, 0, BTN_H)
		btnsFrame.Parent = card
		local bl = Instance.new("UIListLayout")
		bl.FillDirection = Enum.FillDirection.Horizontal
		bl.VerticalAlignment = Enum.VerticalAlignment.Center
		bl.Padding = UDim.new(0, 4)
		bl.Parent = btnsFrame

		UIUtil.makeButton("Sell", function() onQuickSell(item.uid) end, {
			Size = UDim2.fromOffset(bw, BTN_H),
			BackgroundColor3 = P.Wood,
		}).Parent = btnsFrame

		UIUtil.makeButton("List", function()
			onListRequest(item.uid, suggestedPriceFor(item))
		end, {
			Size = UDim2.fromOffset(bw, BTN_H),
			BackgroundColor3 = P.Sunset,
		}).Parent = btnsFrame

		if isFish and onHoldFish then
			UIUtil.makeButton("Hold", function()
				onHoldFish(item.uid, item.speciesId or "", mods, item.weightKg or 0)
				shell.destroy()
			end, {
				Size = UDim2.fromOffset(bw, BTN_H),
				BackgroundColor3 = P.TealLight,
			}).Parent = btnsFrame
		end

		-- Hover effects: thumbnail scales out + fish spins (skipped under ReducedMotion)
		if isFish and thumbVpf and not reducedMotion then
			local vpf = thumbVpf :: ViewportFrame
			local baseSize = vpf.Size
			local popSize  = UDim2.new(
				baseSize.X.Scale + 0.06, baseSize.X.Offset,
				baseSize.Y.Scale, baseSize.Y.Offset + 8
			)
			local popTI   = TweenInfo.new(0.15, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
			local dropTI  = TweenInfo.new(0.10, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
			local rotConn: RBXScriptConnection? = nil
			local rotAngle = 0
			local initPivot = thumbInitPivot
			local clone = thumbClone

			card.MouseEnter:Connect(function()
				MotionUtil.tween(vpf, popTI, { Size = popSize })
				if clone and initPivot then
					rotConn = RunService.Heartbeat:Connect(function(dt)
						if not card.Parent then
							if rotConn then rotConn:Disconnect(); rotConn = nil end
							return
						end
						rotAngle += dt * 1.5
						clone:PivotTo(CFrame.new(initPivot.Position) * CFrame.Angles(0, rotAngle, 0))
					end)
				end
			end)

			card.MouseLeave:Connect(function()
				MotionUtil.tween(vpf, dropTI, { Size = baseSize })
				if rotConn then rotConn:Disconnect(); rotConn = nil end
				rotAngle = 0
				if clone and initPivot then
					clone:PivotTo(initPivot)
				end
			end)
		end

		return setSelected
	end

	local function makeSectionGrid(title: string, layoutOrder: number): Frame
		local section = Instance.new("Frame")
		section.Name = title
		section.BackgroundTransparency = 1
		section.Size = UDim2.new(1, -UIUtil.Spacing.md * 2, 0, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.LayoutOrder = layoutOrder
		section.Parent = list

		UIUtil.makeLabel(title:upper(), "subtitle", {
			Size = UDim2.new(1, 0, 0, 24),
			Font = Enum.Font.GothamBold,
			TextColor3 = P.CreamSoft,
			Parent = section,
		})

		local gridHost = Instance.new("Frame")
		gridHost.Name = "Grid"
		gridHost.BackgroundTransparency = 1
		gridHost.Position = UDim2.new(0, 0, 0, 28)
		gridHost.Size = UDim2.new(1, 0, 0, 0)
		gridHost.AutomaticSize = Enum.AutomaticSize.Y
		gridHost.Parent = section

		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
		grid.CellPadding = UDim2.fromOffset(10, 10)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = gridHost

		return gridHost
	end

	-- ── REFRESH ────────────────────────────────────────────────────────
	local refresh: (items_: {any}) -> ()
	refresh = function(items_: {any})
		currentItems = items_
		local prevSel = table.clone(selected)
		cardSetters = {}

		for _, c in ipairs(list:GetChildren()) do
			if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
				c:Destroy()
			end
		end

		if #items_ == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 60)
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 16
			empty.TextColor3 = P.CreamSoft
			empty.TextXAlignment = Enum.TextXAlignment.Center
			empty.Text = "No catches yet — head to the dock!"
			empty.LayoutOrder = 1
			empty.Parent = list
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

		local sectionOrder = 0
		local function renderSection(title: string, bucket: {any})
			if #bucket == 0 then return end
			sectionOrder += 1
			local gridHost = makeSectionGrid(title, sectionOrder)
			local sorted = sortItems(bucket)
			for i, item in ipairs(sorted) do
				local setter = buildCard(item, i, gridHost)
				if item.uid then cardSetters[item.uid] = setter end
			end
		end

		renderSection("Preserved", preserved)
		renderSection("Catch", fish)
		renderSection("Goods", otherGoods)

		-- Re-apply selection from before refresh
		for uid in pairs(prevSel) do
			local setter = cardSetters[uid]
			if setter then setter(true) end
		end

		-- Re-show checkboxes if in selection mode
		if selectionMode then
			local function showSelectionOnCards(root: Instance)
				for _, c in ipairs(root:GetDescendants()) do
					if c:IsA("Frame") and c:FindFirstChild("CardStroke") then
						local chk = c:FindFirstChild("Checkbox")
						local ov  = c:FindFirstChild("SelectOverlay")
						if chk then chk.Visible = true end
						if ov  then ov.Visible  = true end
					end
				end
			end
			showSelectionOnCards(list)
		end
	end

	-- ── SORT BUTTONS (created after refresh so handlers can call it) ───
	rarityBtn = UIUtil.makeButton("Rarity ▼", function()
		if sortState.key == "rarity" then
			sortState.dir = -sortState.dir
		else
			sortState.key = "rarity"
			sortState.dir = -1
		end
		updateSortBtns()
		refresh(currentItems)
	end, {
		Size = UDim2.fromOffset(104, BTN_H),
		BackgroundColor3 = P.TealLight,
		TextSize = 13,
	})
	rarityBtn.Parent = sortBar

	priceBtn = UIUtil.makeButton("Price ▼", function()
		if sortState.key == "price" then
			sortState.dir = -sortState.dir
		else
			sortState.key = "price"
			sortState.dir = -1
		end
		updateSortBtns()
		refresh(currentItems)
	end, {
		Size = UDim2.fromOffset(94, BTN_H),
		BackgroundColor3 = P.Teal,
		TextSize = 13,
	})
	priceBtn.Parent = sortBar

	updateSortBtns()
	refresh(items)

	return {
		gui     = gui,
		close   = function() shell.destroy() end,
		refresh = refresh,
	}
end

return InventoryUI
