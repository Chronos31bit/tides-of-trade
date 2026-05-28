-- Command bar: build AdminWeatherUI_Template under StarterGui.StarterGuiAssets.
-- Canonical source: src/StarterGuiAssets/AdminWeatherUI_Template.model.json (Rojo).

local StarterGui = game:GetService("StarterGui")

warn("[AdminWeatherUI] Use Rojo-synced AdminWeatherUI_Template.model.json as canonical. Re-run only for emergency Studio rebuild.")

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("StarterGuiAssets missing", 0)
end
if not assets:FindFirstChild("AdminWeatherUI_Template") then
	error("AdminWeatherUI_Template missing — sync Rojo first", 0)
end
print("[AdminWeatherUI] Template present.")
