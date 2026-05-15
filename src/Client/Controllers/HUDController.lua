--!strict
-- HUDController.lua
-- Owns the single HUD ScreenGui. Subscribes to PlayerDataService signals
-- to keep coins / lure / level / XP fresh, and forwards action-bar taps
-- to feature controllers. Daily quests live in QuestTrackerUI, not here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Knit = require(ReplicatedStorage.Packages.Knit)

local HUD = require(script.Parent.Parent.UI.HUD)
local UIUtil = require(script.Parent.Parent.UI.UIUtil)

local HUDController = Knit.CreateController({
	Name = "HUDController",
	_hud = nil :: any,
})

-- Daily quests moved out of the HUD entirely — QuestTrackerUI owns them
-- now (separate ScreenGui, higher DisplayOrder, with streak + popups).
-- HUDController only handles coins / XP / level / the action bar.

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
end

function HUDController:_apply(profile: any)
	self._hud.coinsLabel.Text = tostring(profile.coins or 0)
	self._hud.lureLabel.Text = tostring(profile.lureTokens or 0)
	self._hud.levelLabel.Text = ("Lv %d"):format(profile.level or 1)
end

return HUDController
