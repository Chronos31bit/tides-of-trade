--!strict
-- SeasonPassController.lua
-- Opens/closes the season-pass panel and wires service signals to the UI.
-- Minimal scaffold ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â full tier-track UI deferred until cosmetics catalog ships.

local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local Trove        = require(ReplicatedStorage.Packages.Trove)
local SeasonPassUI = require(script.Parent.Parent.UI.SeasonPassUI)

local SeasonPassController = Knit.CreateController({
	Name = "SeasonPassController",
	_open = false,
	_handle = nil :: any,
	_trove = nil :: any,
})

function SeasonPassController:KnitStart()
	self._trove = Trove.new()

	local SeasonPassService = Knit.GetService("SeasonPassService")

	self._trove:Connect(SeasonPassService.SeasonPassUpdated, function(state)
		if self._open and self._handle then
			self._handle.refresh(state)
		end
	end)

	-- Open from Dock ProximityPrompt.
	self._trove:Connect(ProximityPromptService.PromptTriggered, function(prompt, _player)
		if prompt.ActionText == "Season Pass" then
			self:Open()
		end
	end)
end

function SeasonPassController:Open()
	if self._open then
		self:_close()
		return
	end

	local SeasonPassService = Knit.GetService("SeasonPassService")

	SeasonPassService:GetSeasonPass():andThen(function(state)
		if self._open and self._handle then
			self._handle.refresh(state)
			return
		end

		self._open = true
		self._handle = SeasonPassUI.show(state, function(tier)
			SeasonPassService:ClaimTier(tier):andThen(function(res)
				if res and res.ok then
					-- Refresh will come via SeasonPassUpdated signal.
				end
			end)
		end, function()
			-- User closed via X button or backdrop.
			self._open = false
			local h = self._handle
			self._handle = nil
			if h then h.close() end
		end)
	end):catch(function()
		-- Silently fail ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â UI won't open.
	end)
end

function SeasonPassController:_close()
	self._open = false
	if self._handle then
		self._handle.close()
		self._handle = nil
	end
end

function SeasonPassController:Close()
	if self._open then
		self:_close()
	end
end

return SeasonPassController
