--!strict
-- ValidateStarterGui.lua (ModuleScript under ServerScriptService.Tools)
-- Studio-only lint for StarterGuiAssets templates.
-- Command bar: require(game.ServerScriptService.Tools.ValidateStarterGui).run()

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local MIN_TOUCH = 44
local MIN_FONT = 12
local ASSETS = "StarterGuiAssets"

local ValidateStarterGui = {}

function ValidateStarterGui.run(): {string}
	if not RunService:IsStudio() then
		warn("[ValidateStarterGui] Studio only.")
		return {}
	end

	local issues: {string} = {}

	local function add(path: string, msg: string)
		table.insert(issues, `{path}: {msg}`)
	end

	local function absHeight(guiObj: GuiObject): number?
		if guiObj.Size.Y.Scale > 0 then
			return nil
		end
		return guiObj.Size.Y.Offset
	end

	local folder = StarterGui:FindFirstChild(ASSETS)
	if not folder then
		warn("[ValidateStarterGui] StarterGui.StarterGuiAssets not found.")
		return { "StarterGuiAssets folder missing" }
	end

	for _, child in ipairs(folder:GetChildren()) do
		if not child:IsA("ScreenGui") or not child.Name:find("_Template") then
			continue
		end

		local gui = child
		local path = gui:GetFullName()

		if gui.ResetOnSpawn then
			add(path, "ResetOnSpawn must be false")
		end

		local meta = gui:FindFirstChild("Meta")
		if not meta or not meta:IsA("Folder") then
			add(path, "missing Meta folder")
		else
			local orderKey = meta:FindFirstChild("DisplayOrderKey")
			if not orderKey or not orderKey:IsA("StringValue") or orderKey.Value == "" then
				add(path, "Meta.DisplayOrderKey required")
			end
		end

		for _, desc in ipairs(gui:GetDescendants()) do
			local dpath = desc:GetFullName()

			if desc:IsA("TextLabel") then
				if desc.TextScaled then
					add(dpath, "TextScaled must be false")
				end
				if desc.TextSize > 0 and desc.TextSize < MIN_FONT then
					add(dpath, `TextSize {desc.TextSize} < {MIN_FONT}`)
				end
			end

			if desc:IsA("TextButton") or desc:IsA("ImageButton") then
				if not desc.Selectable then
					add(dpath, "Selectable must be true (set in template; integrateSpawnedGui also applies at runtime)")
				end
				local h = absHeight(desc)
				if h and h > 0 and h < MIN_TOUCH then
					add(dpath, `height {h}px < {MIN_TOUCH}px`)
				end
			end
		end
	end

	if #issues == 0 then
		print("[ValidateStarterGui] OK — all templates passed.")
	else
		warn(`[ValidateStarterGui] {#issues} issue(s):`)
		for _, line in ipairs(issues) do
			warn("  ", line)
		end
	end

	return issues
end

return ValidateStarterGui
