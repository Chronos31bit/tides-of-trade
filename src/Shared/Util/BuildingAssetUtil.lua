--!strict
-- BuildingAssetUtil.lua
-- Resolves harbor building Visual templates under ReplicatedStorage.
-- Never clones — callers own Clone() + placement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local WARNED: {[string]: boolean} = {}
local _buildingsFolder: Folder? = nil

local BuildingAssetUtil = {}

local function warnOnce(kind: string, tier: number, reason: string)
	local key = kind .. ":tier" .. tier .. ":" .. reason
	if WARNED[key] then
		return
	end
	WARNED[key] = true
	warn(("[BuildingAssetUtil] Missing %s tier%d (%s). See scripts/Studio/MCP_HarborBuildings.md"):format(kind, tier, reason))
end

local function getBuildingsFolder(): Folder?
	if _buildingsFolder and _buildingsFolder.Parent then
		return _buildingsFolder
	end

	local current: Instance = ReplicatedStorage
	for segment in string.gmatch(GameConfig.Assets.BuildingModels, "[^%.]+") do
		local child = current:FindFirstChild(segment)
		if not child then
			child = current:WaitForChild(segment, 5)
		end
		if not child then
			return nil
		end
		current = child
	end

	if current:IsA("Folder") then
		_buildingsFolder = current
		return current
	end
	return nil
end

-- Returns the template Model at Assets.Buildings.<kind>.tier<N>.Visual, or nil.
function BuildingAssetUtil.getVisualTemplate(kind: string, tier: number): Model?
	local buildings = getBuildingsFolder()
	if not buildings then
		warnOnce(kind, tier, "Assets.Buildings folder")
		return nil
	end

	local kindFolder = buildings:FindFirstChild(kind)
	if not kindFolder then
		warnOnce(kind, tier, "kind folder")
		return nil
	end

	local tierFolder = kindFolder:FindFirstChild("tier" .. tier)
	if not tierFolder then
		warnOnce(kind, tier, "tier folder")
		return nil
	end

	local visual = tierFolder:FindFirstChild("Visual")
	if visual and visual:IsA("Model") then
		return visual
	end

	warnOnce(kind, tier, "Visual model")
	return nil
end

return BuildingAssetUtil
