-- Command bar: cycle all 5 weather states, print readback per state.
-- Paste into Studio command bar (or play-solo).  Holds 5 s on each so the
-- transition tween (~2.5 s) completes before printing the readback.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()

local WeatherService = Knit.GetService("WeatherService")

local STATES = { "Clear", "Cloudy", "Rain", "Storm", "Fog" }
local HOLD_SECONDS = 5

local function readback(label)
	print(("[TestWeather] === %s ==="):format(label))

	local attr = Workspace:GetAttribute("TidesWeather")
	print("[TestWeather] Workspace.TidesWeather =", attr)

	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		print(("[TestWeather] Atmosphere Density=%.2f Haze=%.2f Color=%s"):format(
			atm.Density, atm.Haze, tostring(atm.Color)
		))
	else
		warn("[TestWeather] No Atmosphere in Lighting")
	end

	print(("[TestWeather] Lighting Brightness=%.2f Exposure=%.2f"):format(
		Lighting.Brightness, Lighting.ExposureCompensation
	))

	-- Class name is ColorCorrectionEffect; original isA check used the wrong
	-- token and silently no-op'd, so weather CC values were never printed.
	local cc = Lighting:FindFirstChild("TidesWeatherColorCorrection")
	if cc and cc:IsA("ColorCorrectionEffect") then
		print(("[TestWeather] WeatherCC Enabled=%s Saturation=%.2f Contrast=%.2f Tint=%s"):format(
			tostring(cc.Enabled), cc.Saturation, cc.Contrast, tostring(cc.TintColor)
		))
	else
		print("[TestWeather] WeatherCC missing (client-only; run inside Play Solo to see it)")
	end

	local flash = Lighting:FindFirstChild("TidesLightningFlash")
	if flash and flash:IsA("ColorCorrectionEffect") then
		print(("[TestWeather] LightningCC Brightness=%.3f"):format(flash.Brightness))
	end

	local clouds = Lighting:FindFirstChildOfClass("Clouds")
	if clouds then
		print(("[TestWeather] Clouds Cover=%.2f Density=%.2f"):format(clouds.Cover, clouds.Density))
	end

	local rainDebug = Workspace:GetAttribute("TidesRainDebug")
	if rainDebug then
		print("[TestWeather] TidesRainDebug =", rainDebug)
	end

	local rainField = Workspace:FindFirstChild("WorldFX_RainField")
	if rainField then
		local totalRate = 0
		local count = 0
		for _, desc in ipairs(rainField:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				totalRate += desc.Rate
				count += 1
			end
		end
		print(("[TestWeather] Rain field cells=%d emitters=%d totalRate=%.1f"):format(
			#rainField:GetChildren(), count, totalRate
		))
	else
		print("[TestWeather] No WorldFX_RainField (client-only; run Play Solo)")
	end

	local fogField = Workspace:FindFirstChild("WorldFX_FogField")
	if fogField then
		local totalRate = 0
		for _, desc in ipairs(fogField:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				totalRate += desc.Rate
				print(("[TestWeather] Fog %s Rate=%.1f Enabled=%s Y=%.1f"):format(
					desc.Name, desc.Rate, tostring(desc.Enabled),
					desc.Parent and desc.Parent.Parent and (desc.Parent.Parent :: Part).Position.Y or 0
				))
			end
		end
		print(("[TestWeather] Fog field cells=%d totalRate=%.1f"):format(#fogField:GetChildren(), totalRate))
	else
		print("[TestWeather] No WorldFX_FogField (client-only; run Play Solo)")
	end
end

for _, state in ipairs(STATES) do
	local ok = WeatherService:SetWeather(state, true)
	print(("[TestWeather] SetWeather %s ok=%s"):format(state, tostring(ok)))
	task.wait(HOLD_SECONDS)
	readback(state)
end

print("[TestWeather] Done. Final state =", Workspace:GetAttribute("TidesWeather"))
