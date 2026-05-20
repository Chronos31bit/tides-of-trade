--!strict
-- Client bootstrap. Mirror of the server bootstrap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- ScreenGui scaling reads workspace.CurrentCamera.ViewportSize. That camera
-- is nil on the first frames after join; waiting here prevents HUD.create()
-- from throwing and leaving the player with only the default Roblox UI.
local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
player:WaitForChild("PlayerGui")
if not workspace.CurrentCamera then
	repeat task.wait() until workspace.CurrentCamera
end

-- With Rojo, src/Client/ + init.client.lua collapses into a single LocalScript
-- named "Client" inside StarterPlayerScripts, with sibling files (Controllers/,
-- UI/) becoming its children. So `script.Controllers` is the folder we want.
-- Duplicate ModuleScripts (e.g. two NotificationController siblings) break Knit
-- registration and can prevent HUD / harbor visuals from starting.
local controllersFolder = script.Controllers
local seenControllerNames: {[string]: boolean} = {}
for _, child in controllersFolder:GetChildren() do
	if seenControllerNames[child.Name] then
		warn("[TidesOfTrade] Removing duplicate controller:", child:GetFullName())
		child:Destroy()
	else
		seenControllerNames[child.Name] = true
	end
end

Knit.AddControllersDeep(controllersFolder)

local startOk, startErr = pcall(function()
	Knit.Start():await()
end)
if not startOk then
	warn("[TidesOfTrade] Knit.Start failed:", startErr)
else
	print("[TidesOfTrade] Client controllers started.")
end
