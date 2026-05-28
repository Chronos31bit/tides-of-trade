--!strict
-- RodSelectUI.lua
-- Rod rack bottom sheet. Layout from RodSelectUI_Template; rows clone
-- RodRow_Template. Locked rods use LockOverlay; equipped row gets gold stroke.
--
-- Public API:
--   RodSelectUI.show(rods, playerLevel, equippedRodId, onEquip) -> Handle
--   Handle.close()
--   Handle.refresh(equippedRodId, playerLevel)

local CollectionService = game:GetService("CollectionService")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local HEADER_H = 54
local ROW_H = 84
local LIST_PAD = 8
local MAX_VISIBLE = 5
local ROW_TAG = "TotRodRow"

local RodSelectUI = {}

export type RodDef = {
	id: string,
	displayName: string,
	tier: number,
	rank: string,
	rankColor: Color3,
	unlockLevel: number,
	castWindowBonus: number,
	rarityMultiplier: number?,
	catchWeightBonus: number,
	color: Color3,
}

export type Handle = {
	close: () -> (),
	refresh: (equippedRodId: string, playerLevel: number) -> (),
}

local function req(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[RodSelectUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

local function clearEquippedStroke(row: Frame)
	local stroke = row:FindFirstChild("EquippedStroke")
	if stroke then
		stroke:Destroy()
	end
end

local function setEquippedStroke(row: Frame)
	clearEquippedStroke(row)
	local s = Instance.new("UIStroke")
	s.Name = "EquippedStroke"
	s.Color = P.Gold
	s.Thickness = 2
	s.Transparency = 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = row
end

local function setRankStroke(row: Frame, color: Color3)
	clearEquippedStroke(row)
	local s = Instance.new("UIStroke")
	s.Name = "EquippedStroke"
	s.Color = color
	s.Thickness = 1.5
	s.Transparency = 0.6
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = row
end

local function effectSummary(rod: RodDef, locked: boolean): string
	local rankLine = rod.rank:upper()
	local rarityMul = rod.rarityMultiplier or 1.0
	local rarityStr = rarityMul > 1.0
		and ("\xC3\x97%.1f rarity"):format(rarityMul)
		or "Base rarity"
	local weightStr = rod.catchWeightBonus > 0
		and ("+%.1f kg"):format(rod.catchWeightBonus)
		or "Base wt"

	local lvlStr: string
	if locked then
		lvlStr = ("Level %d to unlock"):format(rod.unlockLevel)
	elseif rod.unlockLevel <= 1 then
		lvlStr = "Starter rod"
	else
		lvlStr = "Unlocked"
	end

	return rankLine .. "\n" .. rarityStr .. "  ·  " .. weightStr .. "\n" .. lvlStr
end

local function populateRow(
	list: ScrollingFrame,
	rowTpl: Frame,
	rod: RodDef,
	playerLevel: number,
	equipped: boolean,
	order: number,
	onEquip: () -> ()
)
	local locked = playerLevel < rod.unlockLevel

	local row = rowTpl:Clone()
	row.Name = rod.id
	row.Visible = true
	row.LayoutOrder = order
	row.BackgroundColor3 = locked and P.TealDeeper or P.TealDark
	row.Parent = list
	CollectionService:AddTag(row, ROW_TAG)

	local tierBadge = req(row, "TierBadge", "Frame") :: Frame
	local tierLbl = req(tierBadge, "TierLabel", "TextLabel") :: TextLabel
	local nameLbl = req(row, "NameLabel", "TextLabel") :: TextLabel
	local effectLbl = req(row, "EffectSummaryLabel", "TextLabel") :: TextLabel
	local equipBtn = req(row, "EquipButton", "TextButton") :: TextButton
	local lockOverlay = req(row, "LockOverlay", "Frame") :: Frame

	tierLbl.Text = tostring(rod.tier)
	tierBadge.BackgroundColor3 = locked and P.WoodDark or rod.color
	tierBadge.BackgroundTransparency = locked and 0.5 or 0

	nameLbl.Text = rod.displayName
	nameLbl.TextColor3 = locked and P.CreamSoft or rod.rankColor

	effectLbl.Text = effectSummary(rod, locked)
	effectLbl.TextColor3 = locked and P.WoodLight or P.TealLight

	lockOverlay.Visible = locked

	if equipped then
		setEquippedStroke(row)
	elseif not locked then
		setRankStroke(row, rod.rankColor)
	end

	local btnText: string
	local btnColor: Color3
	if equipped then
		btnText = "Equipped"
		btnColor = P.GoldDeep
	elseif locked then
		btnText = "Locked"
		btnColor = P.TealDark
	else
		btnText = "Equip"
		btnColor = P.Sunset
	end
	equipBtn.Text = btnText
	equipBtn.BackgroundColor3 = btnColor
	equipBtn.TextColor3 = (equipped or locked) and P.CreamSoft or P.Cream
	equipBtn.Active = not locked and not equipped

	equipBtn.Activated:Connect(function()
		if not locked and not equipped then
			onEquip()
		end
	end)
end

function RodSelectUI.show(
	rods: { RodDef },
	playerLevel: number,
	equippedRodId: string,
	onEquip: (rodId: string) -> ()
): Handle
	local gui = TemplateLoader.spawn("RodSelect", { instanceName = "RodSelectUI" })
	local backdrop = req(gui, "Backdrop", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local closeBtn = req(req(panel, "Header", "Frame"), "Close", "TextButton") :: TextButton
	local list = req(panel, "RodList", "ScrollingFrame") :: ScrollingFrame
	local rowTpl = req(gui, "RodRow_Template", "Frame") :: Frame
	local listLayout = req(list, "UIListLayout", "UIListLayout") :: UIListLayout

	local listH = LIST_PAD + #rods * (ROW_H + 8) - 8 + LIST_PAD
	local panelH = HEADER_H + math.min(listH, MAX_VISIBLE * (ROW_H + 8) + LIST_PAD * 2)
	panel.Size = UDim2.new(0.94, 0, 0, panelH)

	local function buildAll(curEquipped: string, curLevel: number)
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") and CollectionService:HasTag(c, ROW_TAG) then
				c:Destroy()
			end
		end

		for i, rod in ipairs(rods) do
			populateRow(list, rowTpl, rod, curLevel, rod.id == curEquipped, i, function()
				onEquip(rod.id)
			end)
		end

		task.defer(function()
			if list.Parent then
				local content = listLayout.AbsoluteContentSize
				list.CanvasSize = UDim2.fromOffset(0, content.Y + LIST_PAD * 2)
			end
		end)
	end

	buildAll(equippedRodId, playerLevel)

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
		close = destroy,
		refresh = function(newEquipped: string, newLevel: number)
			if gui.Parent then
				buildAll(newEquipped, newLevel)
			end
		end,
	}
end

return RodSelectUI
