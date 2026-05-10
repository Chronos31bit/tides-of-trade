--!strict
-- HUDController.lua
-- Owns the HUD ScreenGui and the QuestTracker. Subscribes to PlayerDataService
-- signals to keep numbers fresh, and forwards bottom-bar taps to the
-- corresponding feature controllers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local HUD = require(script.Parent.Parent.UI.HUD)
local QuestTrackerUI = require(script.Parent.Parent.UI.QuestTrackerUI)

local HUDController = Knit.CreateController({
	Name = "HUDController",
	_hud = nil :: any,
	_tracker = nil :: any,
})

function HUDController:KnitInit() end

function HUDController:KnitStart()
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local QuestService      = Knit.GetService("QuestService")

	-- Build HUD on session start.
	self._hud = HUD.create()

	-- Bottom action bar wiring — controllers expose Open* methods we call here.
	if self._hud.bottomBar then
		local FishingController = Knit.GetController("FishingController")
		local InventoryController = Knit.GetController("InventoryController")
		local MarketController = Knit.GetController("MarketController")
		local HarborEditController = Knit.GetController("HarborEditController")
		local AquariumController = Knit.GetController("AquariumController")
		local SocialController = Knit.GetController("SocialController")

		if self._hud.rodButton then
			-- Rod button auto-equips the tool if needed, then triggers cast.
			-- Mobile players never have to think about Roblox's default
			-- Backpack UI — one tap = "fish."
			self._hud.rodButton.Activated:Connect(function()
				local char = Players.LocalPlayer.Character
				if not char then return end
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if not humanoid then return end
				if not char:FindFirstChild("Fishing Rod") then
					local bp = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
					local rod = bp and bp:FindFirstChild("Fishing Rod")
					if rod and rod:IsA("Tool") then
						humanoid:EquipTool(rod)
						-- Wait a frame so the server sees the rod parented
						-- to character before StartCast's gate runs.
						task.wait(0.1)
					else
						return
					end
				end
				FishingController:CastOrRelease()
			end)
		end
		if self._hud.inventoryButton then
			self._hud.inventoryButton.Activated:Connect(function() InventoryController:Open() end)
		end
		if self._hud.marketButton then
			self._hud.marketButton.Activated:Connect(function() MarketController:Open() end)
		end
		if self._hud.harborButton then
			self._hud.harborButton.Activated:Connect(function() HarborEditController:Toggle() end)
		end
		if self._hud.aquariumButton then
			self._hud.aquariumButton.Activated:Connect(function() AquariumController:OpenFirstOwned() end)
		end
		if self._hud.socialButton then
			self._hud.socialButton.Activated:Connect(function() SocialController:Open() end)
		end

		-- Keyboard shortcuts for PC players. Match the action bar order so
		-- the muscle memory carries between devices.
		UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			if input.KeyCode == Enum.KeyCode.I then InventoryController:Open()
			elseif input.KeyCode == Enum.KeyCode.M then MarketController:Open()
			elseif input.KeyCode == Enum.KeyCode.B then HarborEditController:Toggle()
			elseif input.KeyCode == Enum.KeyCode.C then SocialController:Open()
			-- R reserved — rod is already on left-mouse for PC.
			end
		end)
	end

	-- ====================================================================
	-- DATA BINDINGS — keep HUD numbers fresh from server signals.
	-- ====================================================================
	-- We pull an initial snapshot in case ProfileLoaded fired before this
	-- controller was ready (KnitStart on the client races with the server's
	-- first signal).
	local snap = PlayerDataService:GetSnapshot():expect()
	if snap then self:_apply(snap) end

	PlayerDataService.ProfileLoaded:Connect(function(s) self:_apply(s) end)
	PlayerDataService.CoinsChanged:Connect(function(coins, lure)
		self._hud.coinsLabel.Text = tostring(coins)
		self._hud.lureLabel.Text = tostring(lure)
	end)
	PlayerDataService.XPChanged:Connect(function(level, xp, xpForNext)
		self._hud.levelLabel.Text = ("Lv %d"):format(level)
		-- xpForCurrent: total XP needed to *be* at this level. Server's
		-- threshold formula is 50*L^2 to *reach* level L, so the floor of
		-- level L is 50*L^2 — except at level 1, where you start with 0 XP
		-- without crossing any threshold.
		local xpForCurrent = (level <= 1) and 0 or (50 * level * level)
		local progress = math.clamp((xp - xpForCurrent) / math.max(xpForNext - xpForCurrent, 1), 0, 1)
		self._hud.xpFill.Size = UDim2.new(progress, 0, 1, 0)
	end)
	PlayerDataService.QuestsChanged:Connect(function(quests)
		self:_updateQuests(quests)
	end)

	-- Quest tracker overlay.
	self._tracker = QuestTrackerUI.show({}, function(questId)
		QuestService:ClaimReward(questId):andThen(function() end)
	end)
end

function HUDController:_apply(profile: any)
	self._hud.coinsLabel.Text = tostring(profile.coins or 0)
	self._hud.lureLabel.Text = tostring(profile.lureTokens or 0)
	self._hud.levelLabel.Text = ("Lv %d"):format(profile.level or 1)
	self:_updateQuests(profile.dailyQuests or {})
end

function HUDController:_updateQuests(quests: {any})
	-- Topbar shows the *first incomplete* quest as a one-liner.
	local firstActive
	for _, q in ipairs(quests) do
		if not q.completed then firstActive = q; break end
	end
	if firstActive then
		-- Pretty-print quest kinds: "VisitHarbor" -> "Visit harbor".
		local pretty = firstActive.kind:gsub("(%u)", " %1"):gsub("^%s+", ""):lower()
		pretty = pretty:sub(1, 1):upper() .. pretty:sub(2)
		self._hud.questLabel.Text = ("%s (%d/%d)"):format(pretty, firstActive.progress, firstActive.target)
	else
		self._hud.questLabel.Text = "All quests done — come back tomorrow!"
	end
	if self._tracker then self._tracker.refresh(quests) end
end

return HUDController
