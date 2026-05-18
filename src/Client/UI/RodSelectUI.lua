--!strict
-- RodSelectUI.lua
-- Horizontal rod rack panel (380px portrait).
-- One card per rod, left-to-right by tier. Locked rods show XP requirement
-- and are non-interactive. The equipped rod gets a gold border.
--
-- Public API:
--   RodSelectUI.show(rods, playerXp, equippedRodId, onEquip) -> Handle
--   Handle.close()
--   Handle.refresh(equippedRodId, playerXp)  -- live update without a full rebuild

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local HEADER_H = 54
local CARD_W   = 140
local CARD_H   = 224
local STRIP_H  = 56
local CARD_PAD = 10
local RACK_PAD = 12

local RodSelectUI = {}

export type RodDef = {
	id: string,
	displayName: string,
	tier: number,
	rank: string,
	rankColor: Color3,
	unlockXp: number,
	castWindowBonus: number,
	catchWeightBonus: number,
	color: Color3,
}

export type Handle = {
	close:   () -> (),
	refresh: (equippedRodId: string, playerXp: number) -> (),
}

-- ====================================================================
-- CARD BUILDER
-- ====================================================================

local function buildCard(
	parent:   ScrollingFrame,
	rod:      RodDef,
	playerXp: number,
	equipped: boolean,
	order:    number,
	onEquip:  () -> ()
): Frame
	local locked  = playerXp < rod.unlockXp
	local rankTint = locked and P.CreamSoft or rod.rankColor

	-- ── Card frame ──────────────────────────────────────────────────────
	local card = Instance.new("Frame")
	card.Name             = rod.id
	card.Size             = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = locked and Color3.fromRGB(22, 48, 58) or P.Teal
	card.BorderSizePixel  = 0
	card.LayoutOrder      = order
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 14); cc.Parent = card

	-- Border: gold for equipped, rarity glow for available, none for locked.
	if equipped then
		local s = Instance.new("UIStroke")
		s.Color       = P.Gold
		s.Thickness   = 3
		s.Transparency = 0
		s.Parent = card
	elseif not locked then
		local s = Instance.new("UIStroke")
		s.Color       = rod.rankColor
		s.Thickness   = 1.5
		s.Transparency = 0.55
		s.Parent = card
	end
	card.Parent = parent

	-- ── Color header strip ───────────────────────────────────────────────
	local stripColor = locked and P.WoodDark or rod.color
	local stripAlpha = locked and 0.45 or 0

	local strip = Instance.new("Frame")
	strip.Size                   = UDim2.new(1, 0, 0, STRIP_H)
	strip.BackgroundColor3       = stripColor
	strip.BackgroundTransparency = stripAlpha
	strip.BorderSizePixel        = 0
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 14); sc.Parent = strip
	-- Square off bottom corners.
	local scSq = Instance.new("Frame")
	scSq.Size                   = UDim2.new(1, 0, 0.5, 0)
	scSq.Position               = UDim2.new(0, 0, 0.5, 0)
	scSq.BackgroundColor3       = stripColor
	scSq.BackgroundTransparency = stripAlpha
	scSq.BorderSizePixel        = 0
	scSq.Parent = strip
	strip.Parent = card

	-- Soft top-light highlight on the strip (depth, not garish).
	if not locked then
		local hl = Instance.new("Frame")
		hl.BackgroundColor3       = Color3.new(1, 1, 1)
		hl.BackgroundTransparency = 1  -- driven by UIGradient transparency
		hl.BorderSizePixel        = 0
		hl.Size                   = UDim2.fromScale(1, 1)
		hl.ZIndex                 = 2
		local hlGrad = Instance.new("UIGradient")
		hlGrad.Rotation     = 270  -- bright at top, transparent at bottom
		hlGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.0),
			NumberSequenceKeypoint.new(0.55, 0.85),
			NumberSequenceKeypoint.new(1, 1),
		})
		hlGrad.Color  = ColorSequence.new(Color3.new(1, 1, 1))
		hlGrad.Parent = hl
		hl.Parent = strip
	end

	-- Tier number.
	local tierLabel = Instance.new("TextLabel")
	tierLabel.BackgroundTransparency = 1
	tierLabel.Size             = UDim2.new(1, 0, 1, 0)
	tierLabel.Font             = Enum.Font.GothamBold
	tierLabel.TextSize         = 26
	tierLabel.TextColor3       = Color3.new(1, 1, 1)
	tierLabel.TextXAlignment   = Enum.TextXAlignment.Center
	tierLabel.TextYAlignment   = Enum.TextYAlignment.Center
	tierLabel.ZIndex           = 3
	tierLabel.Text             = tostring(rod.tier)
	tierLabel.Parent = strip
	if not locked then
		-- Dark outline keeps the number readable on any strip colour.
		local ts = Instance.new("UIStroke")
		ts.Color       = Color3.new(0, 0, 0)
		ts.Thickness   = 2
		ts.Transparency = 0.55
		ts.Parent = tierLabel
	end

	-- ── Body content (Y cursor starts below strip) ───────────────────────
	local Y = STRIP_H + 7

	-- Rod name (tinted by rarity; glow stroke for unlocked rods).
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position         = UDim2.new(0, 9, 0, Y)
	nameLabel.Size             = UDim2.fromOffset(CARD_W - 18, 20)
	nameLabel.Font             = Enum.Font.GothamBold
	nameLabel.TextSize         = 13
	nameLabel.TextColor3       = rankTint
	nameLabel.TextTruncate     = Enum.TextTruncate.AtEnd
	nameLabel.TextXAlignment   = Enum.TextXAlignment.Left
	nameLabel.Text             = rod.displayName
	nameLabel.Parent = card
	if not locked then
		local ns = Instance.new("UIStroke")
		ns.Color       = rod.rankColor
		ns.Thickness   = 1
		ns.Transparency = 0.45
		ns.Parent = nameLabel
	end
	Y += 23

	-- Rank pill badge: rounded tag with tinted background + matching border.
	local pill = Instance.new("Frame")
	pill.BackgroundColor3       = locked and P.TealDark or rod.rankColor
	pill.BackgroundTransparency = locked and 0.3 or 0.72
	pill.BorderSizePixel        = 0
	pill.AutomaticSize          = Enum.AutomaticSize.X
	pill.Size                   = UDim2.new(0, 0, 0, 18)
	pill.Position               = UDim2.new(0, 9, 0, Y)
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1, 0); pc.Parent = pill
	local ps = Instance.new("UIStroke")
	ps.Color       = locked and P.CreamSoft or rod.rankColor
	ps.Thickness   = 1
	ps.Transparency = locked and 0.65 or 0.15
	ps.Parent = pill
	local pp = Instance.new("UIPadding")
	pp.PaddingLeft  = UDim.new(0, 7)
	pp.PaddingRight = UDim.new(0, 7)
	pp.Parent = pill
	local pillText = Instance.new("TextLabel")
	pillText.BackgroundTransparency = 1
	pillText.Size             = UDim2.new(0, 0, 1, 0)
	pillText.AutomaticSize    = Enum.AutomaticSize.X
	pillText.Font             = Enum.Font.GothamBold
	pillText.TextSize         = 9
	pillText.TextColor3       = locked and P.CreamSoft or Color3.new(1, 1, 1)
	pillText.Text             = rod.rank:upper()
	pillText.Parent = pill
	pill.Parent = card
	Y += 25

	-- Thin rarity-coloured separator.
	local sep = Instance.new("Frame")
	sep.BackgroundColor3       = locked and P.TealDeeper or rod.rankColor
	sep.BackgroundTransparency = locked and 0.6 or 0.7
	sep.BorderSizePixel        = 0
	sep.Position               = UDim2.new(0, 9, 0, Y)
	sep.Size                   = UDim2.new(1, -18, 0, 1)
	sep.Parent = card
	Y += 8

	-- Cast window stat.
	local cwLabel = Instance.new("TextLabel")
	cwLabel.BackgroundTransparency = 1
	cwLabel.Position       = UDim2.new(0, 9, 0, Y)
	cwLabel.Size           = UDim2.fromOffset(CARD_W - 18, 15)
	cwLabel.Font           = Enum.Font.Gotham
	cwLabel.TextSize       = 10
	cwLabel.TextColor3     = locked and P.WoodLight or P.TealLight
	cwLabel.TextXAlignment = Enum.TextXAlignment.Left
	cwLabel.Text = rod.castWindowBonus > 0
		and ("+%.0f%% window"):format(rod.castWindowBonus * 100)
		or "Base window"
	cwLabel.Parent = card
	Y += 17

	-- Weight stat.
	local wbLabel = Instance.new("TextLabel")
	wbLabel.BackgroundTransparency = 1
	wbLabel.Position       = UDim2.new(0, 9, 0, Y)
	wbLabel.Size           = UDim2.fromOffset(CARD_W - 18, 15)
	wbLabel.Font           = Enum.Font.Gotham
	wbLabel.TextSize       = 10
	wbLabel.TextColor3     = locked and P.WoodLight or P.TealLight
	wbLabel.TextXAlignment = Enum.TextXAlignment.Left
	wbLabel.Text = rod.catchWeightBonus > 0
		and ("+%.1f kg weight"):format(rod.catchWeightBonus)
		or "Base weight"
	wbLabel.Parent = card
	Y += 17

	-- XP / unlock status.
	local xpLabel = Instance.new("TextLabel")
	xpLabel.BackgroundTransparency = 1
	xpLabel.Position       = UDim2.new(0, 9, 0, Y)
	xpLabel.Size           = UDim2.fromOffset(CARD_W - 18, 15)
	xpLabel.Font           = Enum.Font.Gotham
	xpLabel.TextSize       = 10
	xpLabel.TextXAlignment = Enum.TextXAlignment.Left
	if locked then
		xpLabel.TextColor3 = P.Danger
		xpLabel.Text = ("%d XP needed"):format(rod.unlockXp)
	elseif rod.unlockXp == 0 then
		xpLabel.TextColor3 = P.CreamSoft
		xpLabel.Text = "Starter rod"
	else
		xpLabel.TextColor3 = P.Success
		xpLabel.Text = "Unlocked"
	end
	xpLabel.Parent = card

	-- ── Equip button — anchored to card bottom ───────────────────────────
	local btnText, btnColor
	if equipped then
		btnText = "Equipped"; btnColor = P.GoldDeep
	elseif locked then
		btnText = "Locked";   btnColor = P.TealDark
	else
		btnText = "Equip";    btnColor = P.Sunset
	end

	local equipBtn = UIUtil.makeButton(btnText, function()
		if not locked and not equipped then onEquip() end
	end, {
		AnchorPoint      = Vector2.new(0.5, 1),
		Position         = UDim2.new(0.5, 0, 1, -9),
		Size             = UDim2.fromOffset(CARD_W - 18, 38),
		BackgroundColor3 = btnColor,
		variant          = (equipped or locked) and "secondary" or "primary",
	})
	if locked then
		equipBtn.TextColor3 = P.CreamSoft
		equipBtn.Active     = false
	end
	equipBtn.Parent = card

	return card
end

-- ====================================================================
-- PUBLIC
-- ====================================================================

function RodSelectUI.show(
	rods:          {RodDef},
	playerXp:      number,
	equippedRodId: string,
	onEquip:       (rodId: string) -> ()
): Handle

	local gui = UIUtil.makeScreenGui("RodSelectUI")
	gui.DisplayOrder = 20

	local backdrop = Instance.new("TextButton")
	backdrop.Text                  = ""
	backdrop.AutoButtonColor       = false
	backdrop.BackgroundColor3      = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel       = 0
	backdrop.Size                  = UDim2.fromScale(1, 1)
	backdrop.Parent                = gui

	local panel = UIUtil.makePanel({
		AnchorPoint      = Vector2.new(0.5, 1),
		Position         = UDim2.new(0.5, 0, 1, -16),
		Size             = UDim2.new(0.96, 0, 0, HEADER_H + RACK_PAD * 2 + CARD_H + 10),
		ClipsDescendants = true,
	})
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(420, 9999)
	cap.Parent  = panel
	panel.Parent = gui

	-- Header
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size                   = UDim2.new(1, 0, 0, HEADER_H)
	header.Parent                 = panel

	local titleLabel = UIUtil.makeLabel("Rod Rack", "title", {
		Position = UDim2.new(0, 14, 0, 0),
		Size     = UDim2.new(1, -64, 1, 0),
	})
	titleLabel.Parent = header

	local closeBtn = UIUtil.makeButton("✕", function() gui:Destroy() end, {
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -8, 0.5, 0),
		Size             = UDim2.fromOffset(44, 44),
		BackgroundColor3 = P.Wood,
		variant          = "secondary",
	})
	closeBtn.Parent = header

	local divider = Instance.new("Frame")
	divider.BackgroundColor3       = P.TealDeeper
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel        = 0
	divider.Position               = UDim2.new(0, 0, 0, HEADER_H)
	divider.Size                   = UDim2.new(1, 0, 0, 1)
	divider.Parent                 = panel

	-- Horizontal rod rack
	local totalCards = #rods
	local canvasWidth = RACK_PAD + totalCards * (CARD_W + CARD_PAD) - CARD_PAD + RACK_PAD

	local rack = Instance.new("ScrollingFrame")
	rack.BackgroundTransparency = 1
	rack.BorderSizePixel        = 0
	rack.Position               = UDim2.new(0, 0, 0, HEADER_H + 2)
	rack.Size                   = UDim2.new(1, 0, 1, -(HEADER_H + 2))
	rack.ScrollBarThickness     = 4
	rack.ScrollBarImageColor3   = P.TealDeeper
	rack.ScrollingDirection     = Enum.ScrollingDirection.X
	rack.CanvasSize             = UDim2.fromOffset(canvasWidth, 0)
	rack.AutomaticCanvasSize    = Enum.AutomaticSize.None
	rack.Parent                 = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection    = Enum.FillDirection.Horizontal
	layout.Padding          = UDim.new(0, CARD_PAD)
	layout.SortOrder        = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent           = rack

	local leftPad = Instance.new("UIPadding")
	leftPad.PaddingLeft  = UDim.new(0, RACK_PAD)
	leftPad.PaddingRight = UDim.new(0, RACK_PAD)
	leftPad.PaddingTop   = UDim.new(0, RACK_PAD + 4)
	leftPad.Parent       = rack

	local function buildAll(curEquipped: string, curXp: number)
		for _, c in ipairs(rack:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, rod in ipairs(rods) do
			buildCard(rack, rod, curXp, rod.id == curEquipped, i, function()
				onEquip(rod.id)
			end)
		end
	end

	buildAll(equippedRodId, playerXp)

	backdrop.Activated:Connect(function() gui:Destroy() end)

	return {
		close = function() gui:Destroy() end,
		refresh = function(newEquipped: string, newXp: number)
			if gui.Parent then buildAll(newEquipped, newXp) end
		end,
	}
end

return RodSelectUI
