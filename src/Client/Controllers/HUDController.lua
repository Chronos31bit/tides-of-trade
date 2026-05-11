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

local HUDController = Knit.CreateController({
	Name = "HUDController",
	_hud = nil :: any,
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

	-- Rod button auto-equips the tool if needed, then triggers cast.
	-- Mobile players never have to think about the default Backpack UI.
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
				task.wait(0.1)  -- let the server register the equip before StartCast
			else
				return
			end
		end
		FishingController:CastOrRelease()
	end)

	self._hud.inventoryButton.Activated:Connect(function() InventoryController:Open() end)
	self._hud.marketButton.Activated:Connect(function() MarketController:Open() end)
	self._hud.harborButton.Activated:Connect(function() HarborEditController:Toggle() end)
	self._hud.aquariumButton.Activated:Connect(function() AquariumController:OpenFirstOwned() end)
	self._hud.socialButton.Activated:Connect(function() SocialController:Open() end)

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
end

function HUDController:_apply(profile: any)
	self._hud.coinsLabel.Text = tostring(profile.coins or 0)
	self._hud.lureLabel.Text = tostring(profile.lureTokens or 0)
	self._hud.levelLabel.Text = ("Lv %d"):format(profile.level or 1)
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

return HUDController
