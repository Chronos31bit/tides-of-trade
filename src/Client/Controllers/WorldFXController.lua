--!strict
-- WorldFXController.lua
-- Reacts to TideService and WeatherService server signals to drive purely
-- visual changes — water level lerp, ambient SFX swap. Server is still the
-- source of truth for *gameplay* effects (which fish bite, etc.).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService     = game:GetService("SoundService")
local Workspace        = game:GetService("Workspace")
local TweenService     = game:GetService("TweenService")
local Knit             = require(ReplicatedStorage.Packages.Knit)

local WorldFXController = Knit.CreateController({
	Name = "WorldFXController",
	_currentWeather = "Clear",
	_targetTideLevel = -1,
})

local function findOrMakeAmbientSound(): Sound
	-- TODO: replace SoundId with your audio asset for ocean ambience.
	-- We create a single shared Sound that plays globally from SoundService.
	local existing = SoundService:FindFirstChild("AmbientOcean") :: Sound?
	if existing then return existing end
	local s = Instance.new("Sound")
	s.Name = "AmbientOcean"
	s.SoundId = "rbxasset://sounds/uuhhh.mp3" -- placeholder; replace with real ID
	s.Looped = true
	s.Volume = 0.4
	s.Parent = SoundService
	s:Play()
	return s
end

function WorldFXController:KnitStart()
	local TideService    = Knit.GetService("TideService")
	local WeatherService = Knit.GetService("WeatherService")
	local ambient = findOrMakeAmbientSound()

	-- Tide visual: lerp the WaterLevel attribute on workspace which the
	-- world author can drive a Terrain water mesh from. We don't manipulate
	-- Terrain water directly because that's expensive; the world's water plane
	-- script reads workspace:GetAttribute("TideOffset").
	TideService.TideChanged:Connect(function(state, level)
		self._targetTideLevel = level
		Workspace:SetAttribute("TideState", state)
		Workspace:SetAttribute("TideOffset", level * 1.5) -- ±1.5 stud water level
	end)

	-- Weather visuals: the server already adjusts Atmosphere. Here we tweak
	-- ambient sound volume and could spawn rain particle emitters.
	WeatherService.WeatherChanged:Connect(function(weather)
		self._currentWeather = weather
		if weather == "Storm" then
			ambient.Volume = 0.7
		elseif weather == "Rain" then
			ambient.Volume = 0.55
		else
			ambient.Volume = 0.4
		end
		-- TODO: spawn rain ParticleEmitters under the camera when weather is
		-- Rain or Storm. Out of scope for v1 since it needs art.
	end)
end

return WorldFXController
