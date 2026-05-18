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
local CARD_W   = 128
local CARD_H   = 192
local CARD_PAD = 10   -- horizontal gap between cards
local RACK_PAD = 12   -- padding inside the scroll area

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
	parent:     ScrollingFrame,
	rod:        RodDef,
	playerXp:   number,
	equipped:   boolean,
	order:      number,
	onEquip:    () -> ()
): Frame
	local locked = playerXp < rod.unlockXp

	local card = Instance.new("Frame")
	card.Name             = rod.id
	card.Size             = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = locked and P.TealDark or P.Teal
	card.BorderSizePixel  = 0
	card.LayoutOrder      = order
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 12); cc.Parent = card

	-- Gold border for the equipped rod.
	if equipped then
		local stroke = Instance.new("UIStroke")
		stroke.Color       = P.Gold
		stroke.Thickness   = 2.5
		stroke.Transparency = 0
		stroke.Parent      = card
	end
	card.Parent = parent

	-- ── Color header strip ──
	local strip = Instance.new("Frame")
	strip.Size             = UDim2.new(1, 0, 0, 44)
	strip.BackgroundColor3 = locked and P.WoodDark or rod.color
	strip.BackgroundTransparency = locked and 0.4 or 0
	strip.BorderSizePixel  = 0
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 12)
	sc.Parent = strip
	-- Square off bottom corners of the strip so it joins the card body cleanly.
	local scSquare = Instance.new("Frame")
	scSquare.Size             = UDim2.new(1, 0, 0.5, 0)
	scSquare.Position         = UDim2.new(0, 0, 0.5, 0)
	scSquare.BackgroundColor3 = locked and P.WoodDark or rod.color
	scSquare.BackgroundTransparency = locked and 0.4 or 0
	scSquare.BorderSizePixel  = 0
	scSquare.Parent           = strip
	strip.Parent = card

	-- Tier number in the strip
	local tierLabel = Instance.new("TextLabel")
	tierLabel.BackgroundTransparency = 1
	tierLabel.Size         = UDim2.new(1, 0, 1, 0)
	tierLabel.Font         = Enum.Font.GothamBold
	tierLabel.TextSize     = 20
	tierLabel.TextColor3   = locked and P.CreamSoft or P.Cream
	tierLabel.Text         = tostring(rod.tier)
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	tierLabel.TextYAlignment = Enum.TextYAlignment.Center
	tierLabel.Parent       = strip

	-- Locked cards desaturate the rank tint so the rarity colour doesn't
	-- compete with the "Locked" treatment; unlocked cards show it at full.
	local rankTint = locked and P.CreamSoft or rod.rankColor

	-- ── Rod name ── (tinted by rarity rank when unlocked)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position   = UDim2.new(0, 8, 0, 48)
	nameLabel.Size       = UDim2.fromOffset(CARD_W - 16, 20)
	nameLabel.Font       = Enum.Font.GothamBold
	nameLabel.TextSize   = 13
	nameLabel.TextColor3 = rankTint
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text       = rod.displayName
	nameLabel.Parent     = card

	-- ── Rarity rank badge ──
	local rankLabel = Instance.new("TextLabel")
	rankLabel.BackgroundTransparency = 1
	rankLabel.Position   = UDim2.new(0, 8, 0, 68)
	rankLabel.Size       = UDim2.fromOffset(CARD_W - 16, 16)
	rankLabel.Font       = Enum.Font.GothamBold
	rankLabel.TextSize   = 11
	rankLabel.TextColor3 = rankTint
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.Text       = rod.rank:upper()
	rankLabel.Parent     = card

	-- ── Cast window bonus ──
	local cwLabel = Instance.new("TextLabel")
	cwLabel.BackgroundTransparency = 1
	cwLabel.Position   = UDim2.new(0, 8, 0, 88)
	cwLabel.Size       = UDim2.fromOffset(CARD_W - 16, 16)
	cwLabel.Font       = Enum.Font.Gotham
	cwLabel.TextSize   = 11
	cwLabel.TextColor3 = locked and P.WoodLight or P.TealLight
	cwLabel.TextXAlignment = Enum.TextXAlignment.Left
	cwLabel.Text = rod.castWindowBonus > 0
		and ("+%.0f%% cast window"):format(rod.castWindowBonus * 100)
		or "Base cast window"
	cwLabel.Parent = card

	-- ── Weight bonus ──
	local wbLabel = Instance.new("TextLabel")
	wbLabel.BackgroundTransparency = 1
	wbLabel.Position   = UDim2.new(0, 8, 0, 106)
	wbLabel.Size       = UDim2.fromOffset(CARD_W - 16, 16)
	wbLabel.Font       = Enum.Font.Gotham
	wbLabel.TextSize   = 11
	wbLabel.TextColor3 = locked and P.WoodLight or P.TealLight
	wbLabel.TextXAlignment = Enum.TextXAlignment.Left
	wbLabel.Text = rod.catchWeightBonus > 0
		and ("+%.1f kg weight"):format(rod.catchWeightBonus)
		or "Base weight"
	wbLabel.Parent = card

	-- ── XP status line ──
	local xpLabel = Instance.new("TextLabel")
	xpLabel.BackgroundTransparency = 1
	xpLabel.Position   = UDim2.new(0, 8, 0, 124)
	xpLabel.Size       = UDim2.fromOffset(CARD_W - 16, 16)
	xpLabel.Font       = Enum.Font.Gotham
	xpLabel.TextSize   = 10
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

	-- ── Equip button ──
	local btnText, btnColor
	if equipped then
		btnText  = "Equipped"
		btnColor = P.GoldDeep
	elseif locked then
		btnText  = "Locked"
		btnColor = P.TealDark
	else
		btnText  = "Equip"
		btnColor = P.Sunset
	end

	local equipBtn = UIUtil.makeButton(btnText, function()
		if not locked and not equipped then onEquip() end
	end, {
		AnchorPoint      = Vector2.new(0.5, 0),
		Position         = UDim2.new(0.5, 0, 0, CARD_H - 50),
		Size             = UDim2.fromOffset(CARD_W - 16, 40),
		BackgroundColor3 = btnColor,
		variant          = equipped and "secondary" or (locked and "secondary" or "primary"),
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

	-- Semi-transparent backdrop (tap outside to close).
	local backdrop = Instance.new("TextButton")
	backdrop.Text                  = ""
	backdrop.AutoButtonColor       = false
	backdrop.BackgroundColor3      = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel       = 0
	backdrop.Size                  = UDim2.fromScale(1, 1)
	backdrop.Parent                = gui

	-- Main panel — 380px cap, anchored near the bottom so the rod chip it
	-- relates to is visible above it on a phone.
	local panel = UIUtil.makePanel({
		AnchorPoint      = Vector2.new(0.5, 1),
		Position         = UDim2.new(0.5, 0, 1, -16),
		Size             = UDim2.new(0.96, 0, 0, HEADER_H + RACK_PAD * 2 + CARD_H + 8),
		ClipsDescendants = true,
	})
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(380, 9999)
	cap.Parent  = panel
	panel.Parent = gui

	-- ── Header ──
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

	-- ── Horizontal rod rack ──
	local totalCards = #rods
	local canvasWidth = RACK_PAD + totalCards * (CARD_W + CARD_PAD) - CARD_PAD + RACK_PAD

	local rack = Instance.new("ScrollingFrame")
	rack.BackgroundTransparency    = 1
	rack.BorderSizePixel           = 0
	rack.Position                  = UDim2.new(0, 0, 0, HEADER_H + 2)
	rack.Size                      = UDim2.new(1, 0, 1, -(HEADER_H + 2))
	rack.ScrollBarThickness        = 4
	rack.ScrollBarImageColor3      = P.TealDeeper
	rack.ScrollingDirection        = Enum.ScrollingDirection.X
	rack.CanvasSize                = UDim2.fromOffset(canvasWidth, 0)
	rack.AutomaticCanvasSize       = Enum.AutomaticSize.None
	rack.Parent                    = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding       = UDim.new(0, CARD_PAD)
	layout.SortOrder     = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent        = rack

	local leftPad = Instance.new("UIPadding")
	leftPad.PaddingLeft  = UDim.new(0, RACK_PAD)
	leftPad.PaddingRight = UDim.new(0, RACK_PAD)
	leftPad.PaddingTop   = UDim.new(0, (RACK_PAD + 4))
	leftPad.Parent       = rack

	-- Build cards once.
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
