-- Command bar: build ShopUI_Template under StarterGui.StarterGuiAssets.

local StarterGui = game:GetService("StarterGui")

local function sv(parent: Instance, name: string, value: string | boolean)
	local cls = if type(value) == "boolean" then "BoolValue" else "StringValue"
	local v = Instance.new(cls)
	v.Name = name
	v.Value = value
	v.Parent = parent
end

local assets = StarterGui:WaitForChild("StarterGuiAssets")
local existing = assets:FindFirstChild("ShopUI_Template")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ShopUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
sv(meta, "DisplayOrderKey", "Modal")
sv(meta, "ResetOnSpawn", false)
sv(meta, "IgnoreGuiInset", true)
sv(meta, "ThemeKey", "modal-teal")

warn("[ShopUI] Rebuild ShopUI_Template.model.json via Rojo Save-to-File for canonical source; this command bar copy is for Studio preview only.")
gui.Parent = assets
