--!strict
-- Client bootstrap. Mirror of the server bootstrap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- With Rojo, src/Client/ + init.client.lua collapses into a single LocalScript
-- named "Client" inside StarterPlayerScripts, with sibling files (Controllers/,
-- UI/) becoming its children. So `script.Controllers` is the folder we want.
Knit.AddControllersDeep(script.Controllers)

Knit.Start()
	:catch(warn)
	:await()

print("[TidesOfTrade] Client controllers started.")
