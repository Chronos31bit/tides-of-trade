--!strict
-- Thin entrypoint (StarterPlayerScripts). All client code lives under
-- ReplicatedStorage.TidesClient — see Bootstrap.lua.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local tidesClient = ReplicatedStorage:WaitForChild("TidesClient", 30)
if not tidesClient then
	error("[TidesOfTrade] ReplicatedStorage.TidesClient missing. Run `rojo serve`, connect Rojo, sync, then Save.")
end
local bootstrap = tidesClient:WaitForChild("Bootstrap", 30)
if not bootstrap or not bootstrap:IsA("ModuleScript") then
	error("[TidesOfTrade] TidesClient.Bootstrap missing. Run `rojo serve`, connect Rojo, sync, then Save.")
end
require(bootstrap)
