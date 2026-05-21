-- Command bar: test server weather visuals (Storm). Paste into Studio command bar.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()

local WeatherService = Knit.GetService("WeatherService")
local ok = WeatherService:SetWeather("Storm", true)
print("[TestWeather] SetWeather Storm ok=", ok)

local attr = Workspace:GetAttribute("TidesWeather")
print("[TestWeather] Workspace.TidesWeather =", attr)

local atm = Lighting:FindFirstChildOfClass("Atmosphere")
if atm then
	print(("[TestWeather] Atmosphere Density=%.2f Haze=%.2f"):format(atm.Density, atm.Haze))
else
	warn("[TestWeather] No Atmosphere in Lighting")
end

print("[TestWeather] Lighting Brightness=", Lighting.Brightness, "Exposure=", Lighting.ExposureCompensation)

local cc = Lighting:FindFirstChild("TidesWeatherColorCorrection")
if cc and cc:IsA("ColorCorrection") then
	print("[TestWeather] ColorCorrection Enabled=", cc.Enabled, "Saturation=", cc.Saturation)
end
