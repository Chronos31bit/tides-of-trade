--!strict
-- SailController.lua
-- Wires the "Set Sail" ProximityPrompt (added by HarborService on Dock tier 2+)
-- to SailUI. Follows BaitShopController pattern: Trove + PromptTriggered.
-- Fade transition triggered by BoatService.SailResolved signal.

local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SailUI     = require(script.Parent.Parent.UI.SailUI)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

-- Guard: duplicate-require crash prevention.
do
	local ok, existing = pcall(Knit.GetController, "SailController")
	if ok and existing then return existing end
end

local SailController = Knit.CreateController({
	Name = "SailController",
	_trove        = nil :: any,  -- Trove for PromptTriggered + SailResolved connections
	_handle       = nil :: any,  -- SailUI.Handle while open
	_dockTier     = 1,
	_boatService  = nil :: any,
})

function SailController:KnitStart()
	self._trove = Trove.new()
	self._boatService = Knit.GetService("BoatService")

	local pds = Knit.GetService("PlayerDataService")

	-- ProximityPrompt: "Set Sail" on Dock tier 2+.
	self._trove:Connect(ProximityPromptService.PromptTriggered, function(prompt, _player)
		if prompt.ActionText == "Set Sail" then
			self:Open()
		end
	end)

	-- SailResolved: server confirms the teleport → play fade.
	self._trove:Connect(self._boatService.SailResolved, function(destination)
		self:_playSailFade(destination)
	end)

	-- Load dock tier from profile so the UI can show locked/unlocked state.
	pds:GetSnapshot():andThen(function(snap)
		if snap then
			self._dockTier = self:_resolveDockTier(snap)
		end
	end)

	-- ProfileLoaded provides buildings snapshot on join.
	self._trove:Connect(pds.ProfileLoaded, function(snap)
		self._dockTier = self:_resolveDockTier(snap)
	end)

	-- BuildingsChanged keeps dock tier current when upgrading.
	self._trove:Connect(pds.BuildingsChanged, function(buildings)
		self._dockTier = self:_resolveDockTierFromBuildings(buildings)
	end)
end

function SailController:KnitDestroy()
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end
end

function SailController:_resolveDockTier(snap: any): number
	local buildings = snap.buildings
	if not buildings then return 1 end
	return self:_resolveDockTierFromBuildings(buildings)
end

function SailController:_resolveDockTierFromBuildings(buildings: any): number
	if type(buildings) ~= "table" then return 1 end
	local best = 0
	for _, b in ipairs(buildings) do
		if b.kind == "Dock" and (b.tier or 0) > best then
			best = b.tier
		end
	end
	return best > 0 and best or 1
end

-- Fade cover during the sail transition. MotionUtil-safe: ReducedMotion
-- snaps (no animation).
function SailController:_playSailFade(_destination: string)
	local duration = GameConfig.Boats.SailFadeDuration
	-- Quick crossfade via a temporary full-screen black frame.
	local gui = Instance.new("ScreenGui")
	gui.Name = "SailFade"
	gui.DisplayOrder = 1000  -- above everything
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.Size = UDim2.fromScale(2, 2)
	cover.AnchorPoint = Vector2.new(0.5, 0.5)
	cover.Position = UDim2.fromScale(0.5, 0.5)
	cover.Parent = gui

	-- Fade to black, hold briefly, then fade out.
	local half = duration / 2
	MotionUtil.tweenOrSnap(cover, half, { BackgroundTransparency = 0 }, function()
		task.wait(0.1)
		MotionUtil.tweenOrSnap(cover, half, { BackgroundTransparency = 1 }, function()
			gui:Destroy()
		end)
	end)
end

-- ====================================================================
-- PUBLIC API
-- ====================================================================

function SailController:Open()
	if self._handle then return end

	local access = GameConfig.Boats.AccessByDockTier

	-- Build destination list: order shallow → deep, plus Home.
	local destinations = { "Shoreline", "Pier", "Reef", "DeepWater", "Trench" }

	self._handle = SailUI.show({
		destinations = destinations,
		access       = access,
		dockTier     = self._dockTier,
		onSail       = function(destination)
			self._boatService:SailTo(destination):andThen(function(res)
				if res.ok then
					-- Fade is triggered by SailResolved signal arriving separately.
					self._handle:close()
				elseif res.reason == "dock_tier_too_low" then
					warn("[SailController] SailTo rejected: dock tier too low for", destination)
				else
					warn("[SailController] SailTo rejected:", res.reason)
				end
			end):catch(function(err)
				warn("[SailController] SailTo error:", err)
			end)
		end,
		onClose = function()
			self._handle = nil
		end,
	})
end

function SailController:Close()
	if self._handle then
		self._handle.close()
		self._handle = nil
	end
end

function SailController:Toggle()
	if self._handle then
		self:Close()
	else
		self:Open()
	end
end

function SailController:IsOpen(): boolean
	return self._handle ~= nil
end

return SailController
