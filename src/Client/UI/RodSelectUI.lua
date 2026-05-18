--!strict
-- RodSelectUI.lua
-- Vertical list of horizontal rod rows inside a bottom-sheet panel.
-- Each row: coloured left strip (tier) | name + rank pill | stats | equip btn.
-- Locked rods are dimmed and non-interactive. Equipped rod has gold border.
--
-- Public API:
--   RodSelectUI.show(rods, playerXp, equippedRodId, onEquip) -> Handle
--   Handle.close()
--   Handle.refresh(equippedRodId, playerXp)

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local HEADER_H = 54
local ROW_H    = 72   -- height of each rod row
local ROW_PAD  = 10   -- inner horizontal padding
local STRIP_W  = 52   -- coloured left strip width
local BTN_W    = 82   -- equip button width
local LIST_PAD = 8    -- top/bottom padding inside scroll list

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
-- ROW BUILDER
-- ====================================================================

local function buildRow(
	parent:   ScrollingFrame,
	rod:      RodDef,
	playerXp: number,
	equipped: boolean,
	order:    number,
	onEquip:  () -> ()
): Frame
	local locked = playerXp < rod.unlockXp

	-- ── Outer row frame ──────────────────────────────────────────────────
	local row = Instance.new("Frame")
	row.Name             = rod.id
	row.Size             = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3 = locked and Color3.fromRGB(18, 40, 50) or P.TealDark
	row.BorderSizePixel  = 0
	row.LayoutOrder      = order

	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 10); rc.Parent = row

	-- Gold border for equipped; faint rarity border for available; none for locked.
	if equipped then
		local s = Instance.new("UIStroke")
		s.Color       = P.Gold
		s.Thickness   = 2
		s.Transparency = 0
		s.Parent = row
	elseif not locked then
		local s = Instance.new("UIStroke")
		s.Color       = rod.rankColor
		s.Thickness   = 1.5
		s.Transparency = 0.6
		s.Parent = row
	end
	row.Parent = parent

	-- ── Left coloured strip ───────────────────────────────────────────────
	local strip = Instance.new("Frame")
	strip.Size                   = UDim2.fromOffset(STRIP_W, ROW_H)
	strip.BackgroundColor3       = locked and P.WoodDark or rod.color
	strip.BackgroundTransparency = locked and 0.5 or 0
	strip.BorderSizePixel        = 0

	-- Round left corners to match the row, square off right side.
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 10); sc.Parent = strip
	local scSq = Instance.new("Frame")
	scSq.Size                   = UDim2.new(0.5, 0, 1, 0)
	scSq.Position               = UDim2.new(0.5, 0, 0, 0)
	scSq.BackgroundColor3       = locked and P.WoodDark or rod.color
	scSq.BackgroundTransparency = locked and 0.5 or 0
	scSq.BorderSizePixel        = 0
	scSq.Parent = strip

	-- Tier number centred in the strip.
	local tierLbl = Instance.new("TextLabel")
	tierLbl.BackgroundTransparency = 1
	tierLbl.Size             = UDim2.fromScale(1, 1)
	tierLbl.Font             = Enum.Font.GothamBold
	tierLbl.TextSize         = 22
	tierLbl.TextColor3       = Color3.new(1, 1, 1)
	tierLbl.TextXAlignment   = Enum.TextXAlignment.Center
	tierLbl.TextYAlignment   = Enum.TextYAlignment.Center
	tierLbl.Text             = tostring(rod.tier)
	tierLbl.ZIndex           = 2
	if not locked then
		local ts = Instance.new("UIStroke")
		ts.Color       = Color3.new(0, 0, 0)
		ts.Thickness   = 2
		ts.Transparency = 0.5
		ts.Parent = tierLbl
	end
	tierLbl.Parent = strip
	strip.Parent = row

	-- ── Centre text area ──────────────────────────────────────────────────
	-- Sits between the strip and the button; all text stacked vertically.
	local centerX = STRIP_W + ROW_PAD
	local centerW = -STRIP_W - ROW_PAD * 2 - BTN_W - ROW_PAD

	-- Rod name: bold, rarity-coloured for unlocked rods.
	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Position         = UDim2.new(0, centerX, 0, 9)
	nameLbl.Size             = UDim2.new(1, centerW, 0, 16)
	nameLbl.Font             = Enum.Font.GothamBold
	nameLbl.TextSize         = 13
	nameLbl.TextColor3       = locked and P.CreamSoft or rod.rankColor
	nameLbl.TextXAlignment   = Enum.TextXAlignment.Left
	nameLbl.TextTruncate     = Enum.TextTruncate.AtEnd
	nameLbl.Text             = rod.displayName
	nameLbl.Parent = row

	-- Rank pill: dark background + rarity-coloured border + rarity-coloured text.
	local pill = Instance.new("Frame")
	pill.BackgroundColor3       = locked and P.TealDark or P.TealDeeper
	pill.BackgroundTransparency = locked and 0.2 or 0.3
	pill.BorderSizePixel        = 0
	pill.AutomaticSize          = Enum.AutomaticSize.X
	pill.Size                   = UDim2.new(0, 0, 0, 16)
	pill.Position               = UDim2.new(0, centerX, 0, 28)
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1, 0); pc.Parent = pill
	local ps = Instance.new("UIStroke")
	ps.Color       = locked and P.CreamSoft or rod.rankColor
	ps.Thickness   = 1
	ps.Transparency = locked and 0.7 or 0.2
	ps.Parent = pill
	local pp = Instance.new("UIPadding")
	pp.PaddingLeft = UDim.new(0, 6); pp.PaddingRight = UDim.new(0, 6)
	pp.Parent = pill
	local pillText = Instance.new("TextLabel")
	pillText.BackgroundTransparency = 1
	pillText.Size             = UDim2.new(0, 0, 1, 0)
	pillText.AutomaticSize    = Enum.AutomaticSize.X
	pillText.Font             = Enum.Font.GothamBold
	pillText.TextSize         = 9
	pillText.TextColor3       = locked and P.CreamSoft or rod.rankColor
	pillText.Text             = rod.rank:upper()
	pillText.Parent = pill
	pill.Parent = row

	-- Stats line: cast window + weight, on one line.
	local windowStr = rod.castWindowBonus > 0
		and ("+%.0f%% window"):format(rod.castWindowBonus * 100)
		or "Base window"
	local weightStr = rod.catchWeightBonus > 0
		and ("+%.1f kg"):format(rod.catchWeightBonus)
		or "Base wt"
	local statsLbl = Instance.new("TextLabel")
	statsLbl.BackgroundTransparency = 1
	statsLbl.Position       = UDim2.new(0, centerX, 0, 47)
	statsLbl.Size           = UDim2.new(1, centerW, 0, 13)
	statsLbl.Font           = Enum.Font.Gotham
	statsLbl.TextSize       = 10
	statsLbl.TextColor3     = locked and P.WoodLight or P.TealLight
	statsLbl.TextXAlignment = Enum.TextXAlignment.Left
	statsLbl.Text           = windowStr .. "  ·  " .. weightStr
	statsLbl.Parent = row

	-- XP status line (below stats, small).
	local xpStr: string
	local xpColor: Color3
	if locked then
		xpStr   = ("%d XP to unlock"):format(rod.unlockXp)
		xpColor = P.Danger
	elseif rod.unlockXp == 0 then
		xpStr   = "Starter rod"
		xpColor = P.CreamSoft
	else
		xpStr   = "Unlocked"
		xpColor = P.Success
	end
	local xpLbl = Instance.new("TextLabel")
	xpLbl.BackgroundTransparency = 1
	xpLbl.Position       = UDim2.new(0, centerX, 0, 58)
	xpLbl.Size           = UDim2.new(1, centerW, 0, 12)
	xpLbl.Font           = Enum.Font.Gotham
	xpLbl.TextSize       = 9
	xpLbl.TextColor3     = xpColor
	xpLbl.TextXAlignment = Enum.TextXAlignment.Left
	xpLbl.Text           = xpStr
	xpLbl.Parent = row

	-- ── Equip button (right-anchored) ─────────────────────────────────────
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
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -ROW_PAD, 0.5, 0),
		Size             = UDim2.fromOffset(BTN_W, 42),
		BackgroundColor3 = btnColor,
		variant          = (equipped or locked) and "secondary" or "primary",
	})
	if locked then
		equipBtn.TextColor3 = P.CreamSoft
		equipBtn.Active     = false
	end
	equipBtn.Parent = row

	return row
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

	-- Panel height: header + up to 5 rows visible before scrolling.
	local maxVisible   = 5
	local listH        = LIST_PAD + #rods * (ROW_H + 8) - 8 + LIST_PAD
	local panelH       = HEADER_H + math.min(listH, maxVisible * (ROW_H + 8) + LIST_PAD * 2)

	local panel = UIUtil.makePanel({
		AnchorPoint      = Vector2.new(0.5, 1),
		Position         = UDim2.new(0.5, 0, 1, -16),
		Size             = UDim2.new(0.94, 0, 0, panelH),
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

	-- Vertical scroll list
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel        = 0
	list.Position               = UDim2.new(0, 0, 0, HEADER_H + 2)
	list.Size                   = UDim2.new(1, 0, 1, -(HEADER_H + 2))
	list.ScrollBarThickness     = 4
	list.ScrollBarImageColor3   = P.TealDeeper
	list.ScrollingDirection     = Enum.ScrollingDirection.Y
	list.CanvasSize             = UDim2.new(0, 0, 0, listH)
	list.AutomaticCanvasSize    = Enum.AutomaticSize.None
	list.Parent                 = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection    = Enum.FillDirection.Vertical
	layout.Padding          = UDim.new(0, 8)
	layout.SortOrder        = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent           = layout.Parent  -- assigned below

	local lp = Instance.new("UIPadding")
	lp.PaddingLeft   = UDim.new(0, 10)
	lp.PaddingRight  = UDim.new(0, 10)
	lp.PaddingTop    = UDim.new(0, LIST_PAD)
	lp.PaddingBottom = UDim.new(0, LIST_PAD)
	lp.Parent = list

	layout.Parent = list

	local function buildAll(curEquipped: string, curXp: number)
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, rod in ipairs(rods) do
			buildRow(list, rod, curXp, rod.id == curEquipped, i, function()
				onEquip(rod.id)
			end)
		end
		-- Recalculate canvas height based on actual layout.
		task.defer(function()
			local content = layout.AbsoluteContentSize
			list.CanvasSize = UDim2.fromOffset(0, content.Y + LIST_PAD * 2)
		end)
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
