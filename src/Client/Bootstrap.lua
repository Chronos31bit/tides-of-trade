--!strict
-- Bootstrap.lua — client Knit startup. Lives under ReplicatedStorage.TidesClient
-- so Play works even when the StarterPlayer LocalScript has no child modules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CRITICAL_CONTROLLERS = { "HUDController", "HarborVisualController" }

if _G.__TidesClientBootstrapDone then
	warn("[TidesOfTrade] Bootstrap ran twice — remove duplicate Client LocalScripts in StarterPlayerScripts.")
	return nil
end
_G.__TidesClientBootstrapDone = true

local tidesClient = script.Parent :: Folder

local function countModuleScripts(folder: Instance): number
	local n = 0
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			n += 1
		end
	end
	return n
end

local function resolveControllersFolder(): Folder
	local underRs = tidesClient:FindFirstChild("Controllers")
	if underRs and underRs:IsA("Folder") and countModuleScripts(underRs) > 0 then
		return underRs
	end

	local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
	local ps = player:WaitForChild("PlayerScripts", 10)
	local client = ps and ps:FindFirstChild("Client")
	local underPs = client and client:FindFirstChild("Controllers")
	if underPs and underPs:IsA("Folder") and countModuleScripts(underPs) > 0 then
		warn("[TidesOfTrade] Using PlayerScripts.Client.Controllers — add ReplicatedStorage.TidesClient via Rojo.")
		return underPs
	end

	error("[TidesOfTrade] No client controllers in TidesClient.Controllers. Run `rojo serve`, connect Rojo, sync, Stop/Play.")
end

-- Knit.Start():await() finishes after KnitInit; KnitStart is task.spawn'd and not awaited.
local function isClientShellReady(playerGui: PlayerGui): boolean
	local hud = playerGui:FindFirstChild("HUD")
	return hud ~= nil and hud:IsA("ScreenGui") and workspace:FindFirstChild("HarborVisuals") ~= nil
end

local function ensureCriticalKnitStarts(playerGui: PlayerGui)
	for _ = 1, 60 do
		if isClientShellReady(playerGui) then
			return
		end
		RunService.Heartbeat:Wait()
	end

	for _, name in CRITICAL_CONTROLLERS do
		local ctrl = Knit.GetController(name)
		if type(ctrl.KnitStart) ~= "function" then
			continue
		end
		local hudReady = playerGui:FindFirstChild("HUD") ~= nil
		local harborReady = workspace:FindFirstChild("HarborVisuals") ~= nil
		local needsHud = name == "HUDController" and not hudReady
		local needsHarbor = name == "HarborVisualController" and not harborReady
		if needsHud or needsHarbor then
			warn(("[TidesOfTrade] %s KnitStart did not finish in time — invoking recovery"):format(name))
			local ok, err = pcall(function()
				ctrl:KnitStart()
			end)
			if not ok then
				warn(("[TidesOfTrade] %s:KnitStart recovery failed:"):format(name), err)
			end
		end
	end
end

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
player:WaitForChild("PlayerGui")
if not workspace.CurrentCamera then
	repeat task.wait() until workspace.CurrentCamera
end

local controllersFolder = resolveControllersFolder()
local moduleCount = countModuleScripts(controllersFolder)
if moduleCount == 0 then
	error("[TidesOfTrade] No controller ModuleScripts in TidesClient.Controllers.")
end
print(("[TidesOfTrade] Registering %d client controller(s) from %s"):format(
	moduleCount,
	controllersFolder:GetFullName()
))

local seenControllerNames: {[string]: boolean} = {}
for _, child in controllersFolder:GetChildren() do
	if not child:IsA("ModuleScript") then
		continue
	end
	if seenControllerNames[child.Name] then
		warn("[TidesOfTrade] Removing duplicate controller:", child:GetFullName())
		child:Destroy()
	else
		seenControllerNames[child.Name] = true
	end
end

Knit.AddControllersDeep(controllersFolder)

Knit.Start():catch(function(err)
	warn("[TidesOfTrade] Knit.Start failed:", err)
end):await()

ensureCriticalKnitStarts(player:FindFirstChild("PlayerGui") :: PlayerGui)

print("[TidesOfTrade] Client controllers started.")

return nil
