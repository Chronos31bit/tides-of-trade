--!strict
-- TemplateLoader.lua
-- ====================================================================
-- CONTRACT
-- ====================================================================
-- TemplateLoader.spawn(name, opts?) clones a StarterGui ScreenGui template
-- into PlayerGui (or opts.parent) and returns a live ScreenGui.
--
--   name  — template base id without suffix (e.g. "HUD" -> HUD_Template)
--   opts.parent — defaults to LocalPlayer.PlayerGui
--   opts.instanceName — PlayerGui child name; defaults to `name` (use for shared templates)
--
-- Lookup order:
--   1. game.StarterGui.StarterGuiAssets.<name>_Template
--   2. game.StarterGui.<name>_Template (fallback)
--
-- Before clone: destroys any existing ScreenGui named instanceName (or `name`) in parent.
-- After clone: renames to instanceName (or `name`), applies Meta values, attaches AutoScale
-- binding (same math as UIKit.makeScreenGui), sets Enabled = true.
--
-- Meta folder (child of template ScreenGui):
--   DisplayOrderKey  StringValue  -> GameConfig.UI.DisplayOrder[key]
--   ResetOnSpawn     BoolValue
--   RespectTopbar    BoolValue    -> IgnoreGuiInset = not RespectTopbar (wins over IgnoreGuiInset)
--   IgnoreGuiInset   BoolValue    -> used when RespectTopbar absent
--
-- Trove: parent the returned ScreenGui in a Trove; camera connections clean up on Destroy.
-- ====================================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local ScreenGuiAutoScale = require(script.Parent.ScreenGuiAutoScale)

local ASSETS_FOLDER_NAME = "StarterGuiAssets"

export type SpawnOptions = {
	parent: Instance?,
	instanceName: string?,
}

local TemplateLoader = {}

local function findTemplate(templateName: string): ScreenGui?
	local assets = StarterGui:FindFirstChild(ASSETS_FOLDER_NAME)
	if assets then
		local child = assets:FindFirstChild(templateName)
		if child and child:IsA("ScreenGui") then
			return child
		end
	end
	local direct = StarterGui:FindFirstChild(templateName)
	if direct and direct:IsA("ScreenGui") then
		return direct
	end
	return nil
end

local function readBool(meta: Folder, childName: string): boolean?
	local child = meta:FindFirstChild(childName)
	if child and child:IsA("BoolValue") then
		return child.Value
	end
	return nil
end

local function readString(meta: Folder, childName: string): string?
	local child = meta:FindFirstChild(childName)
	if child and child:IsA("StringValue") then
		return child.Value
	end
	return nil
end

local function applyMeta(gui: ScreenGui, meta: Folder)
	local orderKey = readString(meta, "DisplayOrderKey")
	if orderKey then
		local order = GameConfig.UI.DisplayOrder[orderKey]
		if type(order) == "number" then
			gui.DisplayOrder = order
		end
	end

	local resetOnSpawn = readBool(meta, "ResetOnSpawn")
	if resetOnSpawn ~= nil then
		gui.ResetOnSpawn = resetOnSpawn
	end

	local respectTopbar = readBool(meta, "RespectTopbar")
	if respectTopbar ~= nil then
		gui.IgnoreGuiInset = not respectTopbar
	else
		local ignoreInset = readBool(meta, "IgnoreGuiInset")
		if ignoreInset ~= nil then
			gui.IgnoreGuiInset = ignoreInset
		end
	end
end

local function resolveParent(opts: SpawnOptions?): PlayerGui | Instance
	if opts and opts.parent then
		return opts.parent
	end
	return Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

function TemplateLoader.spawn(name: string, opts: SpawnOptions?): ScreenGui
	local templateId = name .. "_Template"
	local template = findTemplate(templateId)
	if not template then
		error(`[TemplateLoader] Missing template "{templateId}" under StarterGui.StarterGuiAssets or StarterGui`, 2)
	end

	local parent = resolveParent(opts)
	local instanceName = (opts and opts.instanceName) or name
	local existing = parent:FindFirstChild(instanceName)
	if existing then
		existing:Destroy()
	end

	local gui = template:Clone()
	gui.Name = instanceName

	local meta = gui:FindFirstChild("Meta")
	if meta and meta:IsA("Folder") then
		applyMeta(gui, meta)
	end

	gui.Parent = parent
	ScreenGuiAutoScale.apply(gui)
	gui.Enabled = true

	return gui
end

return TemplateLoader
