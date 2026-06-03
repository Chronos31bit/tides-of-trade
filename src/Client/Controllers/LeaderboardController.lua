--!strict
-- LeaderboardController.lua
-- Client-side controller for the leaderboard panel. Fetches top-N entries
-- from LeaderboardService and passes them to LeaderboardUI for display.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit              = require(ReplicatedStorage.Packages.Knit)
local LeaderboardUI     = require(script.Parent.Parent.UI.LeaderboardUI)

local LeaderboardController = Knit.CreateController({
	Name = "LeaderboardController",
	_handle = nil :: any,
})

function LeaderboardController:Open()
	if self._handle then return end

	local LeaderboardService = Knit.GetService("LeaderboardService")

	local function fetchEntries(axis: string)
		return LeaderboardService:GetTopN(axis):andThen(function(res)
			return res.entries or {}
		end, function()
			return {}
		end)
	end

	local ok, handle = pcall(function()
		return LeaderboardUI.show(fetchEntries)
	end)
	if not ok then
		warn("[Leaderboard] UI failed:", handle)
		self._handle = nil
		return
	end
	self._handle = handle
end

function LeaderboardController:Close()
	if self._handle then self._handle.close(); self._handle = nil end
end

function LeaderboardController:KnitStart()
end

return LeaderboardController
