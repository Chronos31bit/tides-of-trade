--!strict
-- Server bootstrap.
-- Knit's :AddServicesDeep walks our Services/ folder, requires each module,
-- and registers them. After Knit:Start() resolves, every service's KnitInit
-- has run and KnitStart begins on the first heartbeat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Rojo collapses src/Server/ + init.server.lua into a Script named "Server"
-- in ServerScriptService, with sibling files (Services/) becoming children.
-- So `script.Services` is the folder we want.
--
-- Order doesn't matter inside Services/ — Knit defers cross-service refs until
-- KnitStart. KnitInit should ONLY initialize internal state; KnitStart is
-- where you can call Knit.GetService() on peers.
Knit.AddServicesDeep(script.Services)

Knit.Start()
	:catch(warn)
	:await()

print("[TidesOfTrade] Server services started.")
