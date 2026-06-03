--!strict
-- NotificationController.lua
-- Subscribes to server toast signals and exposes Toast() for local-only
-- messages (e.g. market buy errors).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local FishCatalog = require(ReplicatedStorage.Shared.Config.FishCatalog)

local NotificationUI = require(script.Parent.Parent.UI.NotificationUI)

local fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalog.fish) do
	fishById[f.id] = f
end

local function speciesDisplayName(speciesId: string?): string
	if not speciesId then return "Item" end
	local f = fishById[speciesId]
	return (f and f.displayName) or speciesId
end

local NotificationController = Knit.CreateController({
	Name = "NotificationController",
	_ui = nil :: any,
	_trove = nil :: any,
	_demandToastShown = false,
})

function NotificationController:Toast(text: string)
	if self._ui then
		self._ui.push(text)
	end
end

function NotificationController:_showDemandToast(payload: { speciesId: string?, displayName: string? })
	if self._demandToastShown then return end
	if not payload or not payload.displayName then return end
	self._demandToastShown = true
	self:Toast(("Today's hot catch: %s!"):format(payload.displayName))
end

function NotificationController:KnitStart()
	self._trove = Trove.new()

	local uiOk, uiOrErr = pcall(function()
		self._ui = NotificationUI.create()
	end)
	if not uiOk then
		warn("[NotificationController] NotificationUI.create failed:", uiOrErr)
		return
	end
	self._trove:Add(function()
		if self._ui then
			self._ui.destroy()
			self._ui = nil
		end
	end)

	local MarketService = Knit.GetService("MarketService")
	local QuestService = Knit.GetService("QuestService")

	self._trove:Add(MarketService.ItemSold:Connect(function(payload: { displayName: string, price: number })
		if not payload or not payload.displayName then return end
		self:Toast(("Sold %s for %d coins"):format(payload.displayName, payload.price or 0))
	end))

	self._trove:Add(MarketService.DemandSpike:Connect(function(payload: { speciesId: string, displayName: string })
		self:_showDemandToast(payload)
	end))

	-- Server refresh / join replay can race KnitStart; fetch canonical demand once.
	MarketService:GetDemand():andThen(function(demand: { speciesId: string?, expiresAt: number? })
		if self._demandToastShown then return end
		if not demand or not demand.speciesId then return end
		if os.time() >= (demand.expiresAt or 0) then return end
		self:_showDemandToast({
			speciesId = demand.speciesId,
			displayName = speciesDisplayName(demand.speciesId),
		})
	end):catch(warn)

	self._trove:Add(QuestService.QuestCompletedToast:Connect(function(payload: { questId: string, renderedText: string })
		if not payload then return end
		self:Toast(("Quest complete! %s"):format(payload.renderedText or ""))
	end))

	self._trove:Add(QuestService.StreakMilestone:Connect(function(payload: { day: number })
		if not payload or not payload.day then return end
		self:Toast(("%d-day login streak!"):format(payload.day))
	end))

	local AchievementService = Knit.GetService("AchievementService")
	self._trove:Add(AchievementService.AchievementUnlocked:Connect(function(payload: {id: string, displayName: string, description: string, reward: any})
		if not payload or not payload.displayName then return end
		self:Toast(("Achievement unlocked: %s!"):format(payload.displayName))
	end))
end

return NotificationController
