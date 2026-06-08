--!strict
-- FishCodexUI.lua
-- Fish codex collection screen. Programmatic UI (no template) that renders
-- a scrollable grid of fish cards. Discovered species show full color +
-- rarity badge + count; undiscovered species show silhouette + "???".
--
-- Public API:
--   FishCodexUI.show(opts) -> CodexHandle
--     opts = {
--       fishCatalog   : { FishDef },       -- from FishCatalog.fish
--       caughtSpecies : {[string]: number}, -- from profile.stats.caughtSpecies
--       discovered    : number,             -- count of discovered species
--       totalSpecies  : number,             -- total species in catalog
--       onClose       : (() -> ())?,
--     }
--   handle.close()
--   handle.refresh(caughtSpecies, discovered)

local GuiService = game:GetService("GuiService")

local UIUtil     = require(script.Parent.UIUtil)
local MotionUtil = require(game:GetService("ReplicatedStorage").Shared.Util.MotionUtil)
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)

local P = UIUtil.Palette

local FishCodexUI = {}

export type CodexFishDef = {
	id: string,
	displayName: string,
	rarity: string,
}

export type CodexShowOpts = {
	fishCatalog:   { CodexFishDef },
	caughtSpecies: {[string]: number},
	personalBests: {[string]: { heaviestKg: number }}?,
	discovered:    number,
	totalSpecies:  number,
	onClose:       (() -> ())?,
}

export type CodexHandle = {
	gui:     ScreenGui,
	close:   () -> (),
	refresh: (caughtSpecies: {[string]: number}, discovered: number) -> (),
}

-- ====================================================================
-- PUBLIC
-- ====================================================================

function FishCodexUI.show(opts: CodexShowOpts): CodexHandle
	local cfg = GameConfig.Codex
	local fishCatalog = opts.fishCatalog
	local caughtSpecies = opts.caughtSpecies
	local personalBests = opts.personalBests or {}
	local onClose = opts.onClose
	local discovered = opts.discovered
	local totalSpecies = opts.totalSpecies

	-- Build byId lookup from the fish array so card rendering can O(1) look up
	-- individual fish by id when iterating caughtSpecies.
	local fishById: {[string]: CodexFishDef} = {}
	for _, f in ipairs(fishCatalog) do
		fishById[f.id] = f
	end

	-- ---- SCREEN GUI ----
	local gui = Instance.new("ScreenGui")
	gui.Name = "FishCodexUI"
	gui.DisplayOrder = UIUtil.DisplayOrder.Modal
	gui.ResetOnSpawn = false
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	-- ---- BACKDROP ----
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = P.Shadow
	backdrop.BackgroundTransparency = 0.55
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	-- ---- PANEL ----
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = P.TealDark
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	-- 90% width on mobile, capped at 420px logical (before UIScale). Height 85%.
	panel.Size = UDim2.new(0.9, 0, 0.85, 0)
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, UIUtil.Radii.lg)
	panelCorner.Parent = panel
	panel.Parent = gui

	-- ---- HEADER ----
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 50)
	header.Parent = panel

	local title = UIUtil.makeLabel("Fish Codex", "title", {
		Position = UDim2.new(0, UIUtil.Spacing.md, 0, 0),
		Size = UDim2.new(1, -(UIUtil.MinTouchPx + UIUtil.Spacing.md * 2), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	local closeBtn = UIUtil.makeLabel("×", "title", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -UIUtil.Spacing.sm, 0, 0),
		Size = UDim2.new(0, UIUtil.MinTouchPx, 0, UIUtil.MinTouchPx),
	})
	closeBtn.Name = "Close"
	closeBtn.Parent = header

	-- ---- PROGRESS BAR ----
	local progressFrame = Instance.new("Frame")
	progressFrame.Name = "ProgressFrame"
	progressFrame.BackgroundColor3 = P.Teal
	progressFrame.BorderSizePixel = 0
	progressFrame.Size = UDim2.new(1, -(UIUtil.Spacing.md * 2), 0, cfg.ProgressBarHeight)
	progressFrame.Position = UDim2.new(0, UIUtil.Spacing.md, 0, header.Size.Y.Offset + 4)
	local progCorner = Instance.new("UICorner")
	progCorner.CornerRadius = UDim.new(0, UIUtil.Radii.sm)
	progCorner.Parent = progressFrame
	progressFrame.Parent = panel

	local progressFill = Instance.new("Frame")
	progressFill.Name = "ProgressFill"
	progressFill.BackgroundColor3 = P.Sunset
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(math.max(0.01, discovered / math.max(totalSpecies, 1)), 0, 1, 0)
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, UIUtil.Radii.sm)
	fillCorner.Parent = progressFill
	progressFill.Parent = progressFrame

	local progressLabel = UIUtil.makeLabel(
		("Discovered %d / %d"):format(discovered, totalSpecies),
		"caption", {
			Size = UDim2.new(1, 0, 1, 0),
			Text = ("Discovered %d / %d"):format(discovered, totalSpecies),
			Parent = progressFrame,
		}
	)
	progressLabel.ZIndex = 2

	-- ---- SCROLLING GRID ----
	local bodyTop = header.Size.Y.Offset + cfg.ProgressBarHeight + UIUtil.Spacing.sm + 4
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CardScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Position = UDim2.new(0, UIUtil.Spacing.sm, 0, bodyTop)
	scroll.Size = UDim2.new(1, -(UIUtil.Spacing.sm * 2), 1, -(bodyTop + UIUtil.Spacing.sm))
	scroll.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.Name = "CardGrid"
	grid.CellSize = UDim2.new(0, cfg.CardWidth, 0, cfg.CardHeight)
	grid.CellPadding = UDim2.new(0, cfg.CardGap, 0, cfg.CardGap)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	-- ---- CARD BUILDER ----
	local cardCache = {} :: {[string]: Frame}

	local function buildCard(fish: CodexFishDef, count: number?, layoutOrder: number): Frame
		local isDiscovered = count ~= nil and count > 0
		local rarityColor = UIUtil.rarityColor(fish.rarity)

		local card = Instance.new("Frame")
		card.Name = "Card_" .. fish.id
		card.BackgroundColor3 = if isDiscovered then P.Teal else cfg.SilhouetteColor
		card.BorderSizePixel = 0
		card.LayoutOrder = layoutOrder

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, UIUtil.Radii.md)
		cardCorner.Parent = card

		-- Rarity badge (top-right corner, colored square)
		if isDiscovered then
			local badge = Instance.new("Frame")
			badge.Name = "RarityBadge"
			badge.BackgroundColor3 = rarityColor
			badge.BorderSizePixel = 0
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 0, 0, 0)
			badge.Size = UDim2.new(0, cfg.BadgeSize, 0, cfg.BadgeSize)
			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0, UIUtil.Radii.sm)
			badgeCorner.Parent = badge
			badge.Parent = card
		end

		-- Fish icon area (centered)
		local iconFrame = Instance.new("Frame")
		iconFrame.Name = "IconFrame"
		iconFrame.BackgroundTransparency = 1
		iconFrame.BorderSizePixel = 0
		iconFrame.Size = UDim2.new(1, -(UIUtil.Spacing.xs * 2), 0, cfg.CardHeight * 0.45)
		iconFrame.Position = UDim2.new(0, UIUtil.Spacing.xs, 0, UIUtil.Spacing.xs)
		iconFrame.Parent = card

		local iconText = if isDiscovered then string.sub(fish.displayName, 1, 1) else "?"
		local iconLabel = UIUtil.makeLabel(iconText, "title", {
			Size = UDim2.fromScale(1, 1),
			TextColor3 = if isDiscovered then rarityColor else cfg.SilhouetteTextColor,
		})
		iconLabel.Name = "IconLabel"
		iconLabel.Parent = iconFrame

		-- Fish name (bottom of card)
		local nameLabel = UIUtil.makeLabel(
			if isDiscovered then fish.displayName else "???",
			"caption", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, UIUtil.Spacing.xs, 1, -(UIUtil.Spacing.xs + (if isDiscovered then 18 else 0))),
				Size = UDim2.new(1, -(UIUtil.Spacing.xs * 2), 0, 16),
				TextWrapped = true,
				TextColor3 = if isDiscovered then P.Cream else cfg.SilhouetteTextColor,
			}
		)
		nameLabel.Parent = card

		-- Rarity label + count + heaviest-kg best (bottom of card, if discovered)
		if isDiscovered then
			local best = personalBests[fish.id]
			local infoText = if best and best.heaviestKg
				then ("%s  ·  %d caught  ·  %.1f kg best"):format(fish.rarity, count, best.heaviestKg)
				else ("%s  ·  %d caught"):format(fish.rarity, count)
			local infoLabel = UIUtil.makeLabel(
				infoText,
				"caption", {
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, UIUtil.Spacing.xs, 1, -UIUtil.Spacing.xs),
					Size = UDim2.new(1, -(UIUtil.Spacing.xs * 2), 0, 14),
					TextWrapped = true,
					TextColor3 = rarityColor,
				}
			)
			infoLabel.Name = "InfoLabel"
			infoLabel.Parent = card
		end

		return card
	end

	-- ---- POPULATE GRID ----
	local function refreshGrid()
		-- Destroy existing cards
		for _, c in pairs(cardCache) do
			c:Destroy()
		end
		table.clear(cardCache)

		for i, fish in ipairs(fishCatalog) do
			local count = caughtSpecies[fish.id]
			local card = buildCard(fish, count, i)
			card.Parent = scroll
			cardCache[fish.id] = card
		end
	end

	refreshGrid()

	-- ---- HELPERS ----
	local function updateProgress()
		local frac = math.max(0.01, discovered / math.max(totalSpecies, 1))
		local targetSize = UDim2.new(frac, 0, 1, 0)
		MotionUtil.tweenOrSnap(progressFill, 0.25, { Size = targetSize })
		progressLabel.Text = ("Discovered %d / %d"):format(discovered, totalSpecies)
	end

	-- ---- CLOSE LOGIC ----
	local closed = false
	local function destroy()
		if closed then return end
		closed = true
		if gui.Parent then
			gui:Destroy()
		end
		if onClose then
			onClose()
		end
	end

	backdrop.Activated:Connect(destroy)
	closeBtn.Activated:Connect(destroy)

	-- ---- HANDLE ----
	return {
		gui = gui,
		close = destroy,
		refresh = function(newCaughtSpecies: {[string]: number}, newDiscovered: number)
			caughtSpecies = newCaughtSpecies
			discovered = newDiscovered
			refreshGrid()
			updateProgress()
		end,
	}
end

return FishCodexUI
