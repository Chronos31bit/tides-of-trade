--!strict
-- HUDController.lua
-- Owns the single HUD ScreenGui. Subscribes to PlayerDataService signals
-- to keep numbers fresh, builds quest rows in-place into HUD.questList,
-- and forwards action-bar taps to feature controllers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Knit = require(ReplicatedStorage.Packages.Knit)

local HUD = require(script.Parent.Parent.UI.HUD)
local UIUtil = require(script.Parent.Parent.UI.UIUtil)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local RodTierUtil = require(ReplicatedStorage.Shared.Util.RodTierUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local HUDController = Knit.CreateController({
	Name = "HUDController",
	_hud = nil :: any,
	_rodTier = 1,
	_rodCatalog = nil :: any,    -- { [tier] = { name, cost, description } } once fetched
	_rodTooltip = nil :: any,    -- UIUtil.TooltipHandle, rebuilt per open
	_rodCycleTween = nil :: any, -- looping max-tier accent shimmer
})

-- Pretty-print a quest's kind into a player-readable description.
local function questText(q: any): string
	if q.kind == "CatchAnyFish" then return ("Catch %d fish"):format(q.target) end
	if q.kind == "CatchSpecies" then
		local species = (q.speciesId or "?"):gsub("_", " ")
		return ("Catch %d %s"):format(q.target, species)
	end
	if q.kind == "SellAtMarket" then return ("Sell %d at market"):format(q.target) end
	if q.kind == "EarnCoins" then return ("Earn %d coins"):format(q.target) end
	if q.kind == "VisitHarbor" then return ("Visit %d harbors"):format(q.target) end
	return q.kind
end

function HUDController:KnitInit() end

-- Other controllers (HarborEditController in particular) call this to hide
-- the HUD while their own panels occupy the screen, then re-show on close.
function HUDController:SetVisible(visible: boolean)
	if self._hud and self._hud.gui then
		self._hud.gui.Enabled = visible
	end
end

function HUDController:KnitStart()
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local QuestService      = Knit.GetService("QuestService")

	self._hud = HUD.create()

	-- Hide Roblox's default Backpack UI. We have our own Rod button that
	-- auto-equips the tool, so the default hotbar at the bottom is redundant
	-- and was overlapping our action bar. pcall because some non-place
	-- contexts (e.g. Plugin) reject SetCoreGuiEnabled.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	-- ----------------------------------------------------------------
	-- Action bar wiring
	-- ----------------------------------------------------------------
	local FishingController    = Knit.GetController("FishingController")
	local InventoryController  = Knit.GetController("InventoryController")
	local MarketController     = Knit.GetController("MarketController")
	local HarborEditController = Knit.GetController("HarborEditController")
	local AquariumController   = Knit.GetController("AquariumController")
	local SocialController     = Knit.GetController("SocialController")

	-- Rod button TOGGLES equip state. Casting is triggered separately by
	-- tapping the screen / clicking the world while the rod is equipped
	-- (that fires Tool.Activated → RodService → FishingController). This
	-- gives players a clear way to put the rod *away* — the previous
	-- "tap to equip-and-cast" had no inverse.
	local function refreshRodButton()
		local char = Players.LocalPlayer.Character
		local equipped = char and char:FindFirstChild("Fishing Rod") ~= nil
		-- Visual cue: bright when equipped, muted when in backpack.
		self._hud.rodButton.BackgroundColor3 = equipped
			and UIUtil.Palette.Sunset
			or UIUtil.Palette.SunsetDeep
	end

	self._hud.rodButton.Activated:Connect(function()
		local char = Players.LocalPlayer.Character
		if not char then return end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		local equippedRod = char:FindFirstChild("Fishing Rod")
		if equippedRod then
			-- Currently equipped — put it away.
			humanoid:UnequipTools()
		else
			-- Pull rod from backpack and equip.
			local bp = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
			local rod = bp and bp:FindFirstChild("Fishing Rod")
			if rod and rod:IsA("Tool") then humanoid:EquipTool(rod) end
		end
		-- Tools take a frame to reparent; defer the visual refresh.
		task.defer(refreshRodButton)
	end)

	-- Also update the button when respawns / tool grants reshuffle things.
	Players.LocalPlayer.CharacterAdded:Connect(function() task.wait(0.5); refreshRodButton() end)
	refreshRodButton()

	self._hud.inventoryButton.Activated:Connect(function() InventoryController:Open() end)
	self._hud.marketButton.Activated:Connect(function() MarketController:Open() end)
	self._hud.harborButton.Activated:Connect(function() HarborEditController:Toggle() end)
	self._hud.aquariumButton.Activated:Connect(function() AquariumController:OpenFirstOwned() end)
	self._hud.socialButton.Activated:Connect(function() SocialController:Open() end)
	-- HOME button: server-authoritative teleport back to player's plot.
	self._hud.homeButton.Activated:Connect(function()
		Knit.GetService("HarborService"):GoHome():andThen(function(res)
			if not res.ok then warn("[HUD] GoHome:", res.reason) end
		end)
	end)

	-- Keyboard shortcuts for PC players.
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == Enum.KeyCode.I then InventoryController:Open()
		elseif input.KeyCode == Enum.KeyCode.M then MarketController:Open()
		elseif input.KeyCode == Enum.KeyCode.B then HarborEditController:Toggle()
		elseif input.KeyCode == Enum.KeyCode.C then SocialController:Open()
		end
	end)

	-- ----------------------------------------------------------------
	-- Data bindings
	-- ----------------------------------------------------------------
	-- Initial snapshot — covers the case where ProfileLoaded already fired
	-- before this controller's KnitStart ran.
	PlayerDataService:GetSnapshot():andThen(function(snap)
		if snap then self:_apply(snap) end
	end)

	PlayerDataService.ProfileLoaded:Connect(function(s) self:_apply(s) end)
	PlayerDataService.CoinsChanged:Connect(function(coins, lure)
		self._hud.coinsLabel.Text = tostring(coins)
		self._hud.lureLabel.Text = tostring(lure)
	end)
	PlayerDataService.XPChanged:Connect(function(level, xp, xpForNext)
		self._hud.levelLabel.Text = ("Lv %d"):format(level)
		local xpForCurrent = (level <= 1) and 0 or (50 * level * level)
		local progress = math.clamp((xp - xpForCurrent) / math.max(xpForNext - xpForCurrent, 1), 0, 1)
		self._hud.xpFill.Size = UDim2.new(progress, 0, 1, 0)
	end)
	PlayerDataService.QuestsChanged:Connect(function(quests)
		self:_renderQuests(quests, QuestService)
	end)

	self:_wireRodChip()
end

function HUDController:_apply(profile: any)
	self._hud.coinsLabel.Text = tostring(profile.coins or 0)
	self._hud.lureLabel.Text = tostring(profile.lureTokens or 0)
	self._hud.levelLabel.Text = ("Lv %d"):format(profile.level or 1)
	-- Initial paint (no pulse) — RodTierChanged handles later live changes.
	self:_applyRodTier(profile.rodTier or 1, false)
	self:_renderQuests(profile.dailyQuests or {}, Knit.GetService("QuestService"))
end

-- Rebuild the quest rows inside HUD.questList. Cheap (≤ 3 rows) so we just
-- nuke and recreate.
function HUDController:_renderQuests(quests: {any}, QuestService: any)
	local list = self._hud.questList
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	if #quests == 0 then
		local empty = UIUtil.makeLabel("Loading…", "caption", {
			Size = UDim2.new(1, 0, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		empty.Parent = list
		return
	end

	for i, q in ipairs(quests) do
		local row = Instance.new("Frame")
		row.Name = q.id
		row.BackgroundColor3 = UIUtil.Palette.Teal
		row.BackgroundTransparency = 0
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 32)
		row.LayoutOrder = i
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row
		row.Parent = list

		local txt = UIUtil.makeLabel(("%s (%d/%d)"):format(questText(q), q.progress, q.target), "body", {
			Position = UDim2.new(0, 10, 0, 0),
			Size = UDim2.new(1, -90, 1, 0),
			TextSize = 12,
		})
		txt.Parent = row

		if q.completed and not q.claimed then
			local claim = UIUtil.makeButton("Claim", function()
				QuestService:ClaimReward(q.id):andThen(function() end)
			end, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.fromOffset(72, 24),
				TextSize = 12,
			})
			claim.Parent = row
		elseif q.claimed then
			local done = UIUtil.makeLabel("Done", "caption", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(60, 24),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = UIUtil.Palette.Uncommon,
			})
			done.Parent = row
		end
	end
end

-- ====================================================================
-- ROD TIER CHIP
-- ====================================================================

-- Recolour the chip for `tier` and (if `animate`) play a one-shot glow
-- pulse. Background stays TealDark; the tier colour lives on the icon disc,
-- stroke, and value text. Tiers at/above max get a subtle accent shimmer.
function HUDController:_applyRodTier(tier: number, animate: boolean)
	tier = math.max(1, math.floor(tonumber(tier) or 1))
	-- compute() is cached, so reading maxTier here is cheap and avoids any
	-- ordering dependency on _wireRodChip having run first.
	local maxTier = RodTierUtil.compute().maxTier
	self._rodTier = tier

	local pal = UIUtil.tierPalette(tier, maxTier)
	local hud = self._hud
	hud.rodChipValue.Text = ("Tier %d"):format(tier)
	hud.rodChipValue.TextColor3 = pal.accent
	hud.rodChipIcon.BackgroundColor3 = pal.accent
	hud.rodChipStroke.Color = pal.accent

	-- Stop any prior shimmer so colours don't fight.
	if self._rodCycleTween then
		self._rodCycleTween:Cancel()
		self._rodCycleTween:Destroy()
		self._rodCycleTween = nil
	end
	-- Max-tier shimmer: gentle accent<->accent2 loop on the stroke. Decorative,
	-- so skipped entirely under ReducedMotion (static accent instead).
	if pal.isMax and not MotionUtil.reducedMotionEnabled() then
		local cfg = GameConfig.UI.RodTierChip
		local info = TweenInfo.new(
			cfg.MaxTierCycleDuration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1, true
		)
		self._rodCycleTween = game:GetService("TweenService"):Create(
			hud.rodChipStroke, info, { Color = pal.accent2 }
		)
		self._rodCycleTween:Play()
	end

	-- Tier-change glow pulse (not on the initial paint). Decorative: under
	-- ReducedMotion we skip it rather than snap (a snap would leave the
	-- stroke fully opaque).
	if animate and not MotionUtil.reducedMotionEnabled() then
		local cfg = GameConfig.UI.RodTierChip
		local info = TweenInfo.new(
			cfg.GlowPulseDuration / 2,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out,
			0, true
		)
		local t = game:GetService("TweenService"):Create(
			hud.rodChipStroke, info, { Transparency = 0 }
		)
		t.Completed:Connect(function() t:Destroy() end)
		t:Play()
	end
end

-- Build (fresh each open — content depends on current tier) the tooltip body.
function HUDController:_buildRodTooltip(content: Frame)
	local cfg = GameConfig.UI.RodTierChip
	local g = RodTierUtil.compute()
	local tier = self._rodTier
	local maxTier = g.maxTier

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14); pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- --- Current tier ---
	local header = UIUtil.makeLabel(("Tier %d"):format(tier), "display", {
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = nextOrder(),
	})
	header.Parent = content

	local catchable = g.countAtOrBelow[tier] or 0
	local sub = UIUtil.makeLabel(("Catches %d fish species"):format(catchable), "subtitle", {
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = nextOrder(),
	})
	sub.Parent = content

	-- --- Next tier preview ---
	if tier >= maxTier then
		local best = UIUtil.makeLabel("You've got the best rod available.", "body", {
			Size = UDim2.new(1, 0, 0, 40),
			TextWrapped = true,
			LayoutOrder = nextOrder(),
		})
		best.Parent = content
	else
		local nextTier = tier + 1
		local nextName = self._rodCatalog and self._rodCatalog[nextTier] and self._rodCatalog[nextTier].name
		local title = nextName
			and ("At Tier %d — %s"):format(nextTier, nextName)
			or ("At Tier %d"):format(nextTier)
		local nextHeader = UIUtil.makeLabel(title, "title", {
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = nextOrder(),
		})
		nextHeader.Parent = content

		local shown, remaining = RodTierUtil.examplesForTier(nextTier, cfg.NextTierExampleLimit)
		local plus = UIUtil.makeLabel(("+%d new species"):format(#(g.newAtTier[nextTier] or {})), "subtitle", {
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = nextOrder(),
		})
		plus.Parent = content

		-- Horizontal scroll of example species, rarity-coloured badges.
		local scroller = Instance.new("ScrollingFrame")
		scroller.BackgroundTransparency = 1
		scroller.BorderSizePixel = 0
		scroller.Size = UDim2.new(1, 0, 0, 30)
		scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
		scroller.ScrollBarThickness = 3
		scroller.ScrollingDirection = Enum.ScrollingDirection.X
		scroller.LayoutOrder = nextOrder()
		local sl = Instance.new("UIListLayout")
		sl.FillDirection = Enum.FillDirection.Horizontal
		sl.Padding = UDim.new(0, 6)
		sl.SortOrder = Enum.SortOrder.LayoutOrder
		sl.Parent = scroller
		scroller.Parent = content

		local badgeOrder = 0
		for _, sp in ipairs(shown) do
			badgeOrder += 1
			local rarityColor = (UIUtil.Palette :: any)[sp.rarity] or UIUtil.Palette.Common
			local badge = Instance.new("Frame")
			badge.BackgroundColor3 = UIUtil.Palette.TealDeeper
			badge.BorderSizePixel = 0
			badge.AutomaticSize = Enum.AutomaticSize.X
			badge.Size = UDim2.new(0, 0, 1, 0)
			badge.LayoutOrder = badgeOrder
			local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = badge
			local bs = Instance.new("UIStroke"); bs.Color = rarityColor; bs.Thickness = 1.5; bs.Parent = badge
			local bp = Instance.new("UIPadding")
			bp.PaddingLeft = UDim.new(0, 8); bp.PaddingRight = UDim.new(0, 8)
			bp.Parent = badge
			local bl = UIUtil.makeLabel(sp.displayName, "caption", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				TextColor3 = rarityColor,
			})
			bl.Parent = badge
			badge.Parent = scroller
		end
		if remaining > 0 then
			badgeOrder += 1
			local more = UIUtil.makeLabel(("and %d more"):format(remaining), "caption", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = badgeOrder,
			})
			more.Parent = scroller
		end
	end

	-- --- How to upgrade (single source of truth: GameConfig string) ---
	local up = UIUtil.makeLabel(cfg.UpgradeHintText, "caption", {
		Size = UDim2.new(1, 0, 0, 32),
		TextWrapped = true,
		LayoutOrder = nextOrder(),
	})
	up.Parent = content
end

function HUDController:_toggleRodTooltip()
	-- Open -> close (true toggle on a second tap).
	if self._rodTooltip and self._rodTooltip.isOpen() then
		self._rodTooltip.close()
		return
	end
	-- Rebuild every open so the content matches the current tier.
	if self._rodTooltip then
		self._rodTooltip.destroy()
		self._rodTooltip = nil
	end
	local cfg = GameConfig.UI.RodTierChip
	self._rodTooltip = UIUtil.makeTooltip({
		parent = self._hud.gui,
		size = UDim2.fromOffset(300, 320),
		-- Sit just left of the 260-wide status column (16 margin + 260 + 12 gap)
		-- so it never covers the chips it describes.
		position = UDim2.new(1, -(16 + 260 + 12), 0, 16),
		anchorPoint = Vector2.new(1, 0),
		build = function(c) self:_buildRodTooltip(c) end,
		inactivitySeconds = cfg.TooltipInactivitySeconds,
		fadeDuration = cfg.TooltipFadeDuration,
		slideOffsetPx = cfg.TooltipSlideOffsetPx,
	})
	self._rodTooltip.open()
end

function HUDController:_wireRodChip()
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local ShopService = Knit.GetService("ShopService")

	-- Tier names for the tooltip's "At Tier N — <name>" line. Single source
	-- of truth is the shop catalog (no duplication into GameConfig).
	ShopService:GetRodCatalog():andThen(function(catalog)
		self._rodCatalog = catalog
	end)

	-- Tap / click toggles the tooltip.
	self._hud.rodChip.Activated:Connect(function()
		self:_toggleRodTooltip()
	end)

	-- PC: hover opens (open-only — the full-screen dismiss backdrop would
	-- otherwise fight a leave-to-close handler and flicker). Dismiss is via
	-- tap-outside / Escape / inactivity / re-tapping the chip. Touch:
	-- long-press opens (tap already toggles via Activated above).
	if not UIUtil.isTouchDevice() then
		self._hud.rodChip.MouseEnter:Connect(function()
			if not (self._rodTooltip and self._rodTooltip.isOpen()) then
				self:_toggleRodTooltip()
			end
		end)
	else
		local cfg = GameConfig.UI.RodTierChip
		local pressThread: thread? = nil
		self._hud.rodChip.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			pressThread = task.delay(cfg.LongPressSeconds, function()
				pressThread = nil
				if not (self._rodTooltip and self._rodTooltip.isOpen()) then
					self:_toggleRodTooltip()
				end
			end)
		end)
		local function cancelPress()
			if pressThread then task.cancel(pressThread); pressThread = nil end
		end
		self._hud.rodChip.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then cancelPress() end
		end)
	end

	-- Live updates: dedicated signal (fires today from ShopService:BuyRodTier
	-- via PlayerDataService:SetRodTier; future upgrade paths route the same
	-- way). Pulse on real changes, not the initial paint.
	PlayerDataService.RodTierChanged:Connect(function(tier)
		self:_applyRodTier(tier, true)
	end)
end

return HUDController
