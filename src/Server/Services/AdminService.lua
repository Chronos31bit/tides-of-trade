--!strict
-- AdminService.lua
-- Lightweight in-house admin commands. Restricted to whitelisted UserIds —
-- no external dependencies, no LoadUnownedAsset capability needed.
--
-- Configure ADMIN_USER_IDS below with your own UserId. To find it:
--   * Visit https://www.roblox.com/users/<your_username>/profile and read
--     the number from the URL once it resolves.
--   * Or in Studio, click your character in Explorer (under Players) and
--     read UserId in the Properties panel.
--
-- Commands supported:
--   /coins <amount>             grant coins
--   /lure <amount>              grant lure tokens
--   /xp <amount>                grant XP
--   /setlevel <level>           force level (clamps XP to that level's floor)
--   /fish <speciesId> [count]   spawn fish into inventory
--   /tp <username>              teleport to a player
--   /fly                        toggle flight (handled client-side)
--   /announce <text>            popup text on every player's screen
--   /weather <state|auto>       force Clear/Cloudy/Rain/Storm/Fog or resume Markov
--   /help                       list commands

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit        = require(ReplicatedStorage.Packages.Knit)
local GameConfig  = require(ReplicatedStorage.Shared.Config.GameConfig)
local FishCatalog = require(ReplicatedStorage.Shared.Config.FishCatalog)
local UidUtil     = require(ReplicatedStorage.Shared.Util.UidUtil)

local VALID_WEATHER: {[string]: boolean} = {}
for _, state in ipairs(GameConfig.Admin.WeatherStates) do
	VALID_WEATHER[state] = true
end

-- ====================================================================
-- WHITELIST — replace these with your real UserId(s).
-- ====================================================================
-- IMPORTANT: ship-blocking. Without your UserId here, the commands silently
-- ignore your messages. In Studio Play your UserId is whatever Studio
-- chose — print game.Players.LocalPlayer.UserId from the dev console if
-- unsure. Add multiple ids for co-developers.
local ADMIN_USER_IDS: {[number]: boolean} = {
	[10675658212] = true,   -- Derin (Chronos3131)
}

-- For Studio playtests we treat the *first* player who joins as admin so
-- you don't have to fish out your UserId before testing. This flag is
-- IGNORED in published places (RunService:IsStudio() is false there).
local STUDIO_FIRST_PLAYER_IS_ADMIN = true

local AdminService = Knit.CreateService({
	Name = "AdminService",
	Client = {
		-- Server -> single client: shows a popup announcement on screen.
		Announcement = Knit.CreateSignal(),
		-- Server -> single client: tells them their fly state changed.
		-- Client toggles its fly handler in response.
		FlyToggled = Knit.CreateSignal(),
	},
	_studioFirstPlayer = nil :: number?,
	_flyState = {} :: {[Player]: boolean},
	_weatherService = nil :: any,
})

local fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalog.fish) do fishById[f.id] = f end

-- Forward-declared so handlers (further below) can call it. We assign the
-- body right here, after AdminService exists so we can reference its
-- Client signal directly. Doing this without a forward decl confuses Lua's
-- parser on the leading parenthesis in `(AdminService :: any).Client...`.
local announceTo: (Player, string) -> ()
announceTo = function(player: Player, message: string)
	AdminService.Client.Announcement:Fire(player, message, 3)
end

-- ====================================================================
-- AUTH
-- ====================================================================
function AdminService:_isAdmin(player: Player): boolean
	if ADMIN_USER_IDS[player.UserId] then return true end
	if STUDIO_FIRST_PLAYER_IS_ADMIN
		and game:GetService("RunService"):IsStudio()
		and self._studioFirstPlayer == player.UserId
	then
		return true
	end
	return false
end

-- ====================================================================
-- COMMAND PARSER
-- Splits "/coins 1000" into { name = "coins", args = { "1000" } }.
-- Quoted args aren't supported (yolo it for v1; admin commands are typed
-- by humans so spaces in args aren't worth the parser complexity).
-- ====================================================================
local function parse(message: string): {name: string, args: {string}}?
	if message:sub(1, 1) ~= "/" then return nil end
	local parts = {}
	for token in string.gmatch(message:sub(2), "%S+") do
		table.insert(parts, token)
	end
	if #parts == 0 then return nil end
	return { name = parts[1]:lower(), args = { table.unpack(parts, 2) } }
end

-- ====================================================================
-- HANDLERS
-- ====================================================================
local Handlers: {[string]: (AdminService: any, issuer: Player, args: {string}) -> ()} = {}

Handlers.help = function(_self, issuer)
	announceTo(issuer, "Commands: /coins /lure /xp /setlevel /fish /tp /fly /weather /announce /help")
end

Handlers.weather = function(self, issuer, args)
	local ws = self._weatherService
	if not ws then
		return announceTo(issuer, "weather service not ready")
	end
	local arg = args[1]
	if not arg or arg == "" then
		return announceTo(issuer, "usage: /weather Clear|Cloudy|Rain|Storm|Fog|auto")
	end
	if string.lower(arg) == "auto" then
		ws:UnlockWeather()
		return announceTo(issuer, ("weather auto (current: %s)"):format(ws:GetWeather()))
	end
	local state: string? = nil
	local lower = string.lower(arg)
	for valid in pairs(VALID_WEATHER) do
		if string.lower(valid) == lower then
			state = valid
			break
		end
	end
	if not state then
		return announceTo(issuer, "unknown weather — use Clear Cloudy Rain Storm Fog or auto")
	end
	if ws:SetWeather(state, true) then
		announceTo(issuer, ("weather → %s (locked)"):format(state))
	else
		announceTo(issuer, "weather set failed")
	end
end

Handlers.coins = function(_self, issuer, args)
	local amount = tonumber(args[1]); if not amount then return announceTo(issuer, "usage: /coins <amount>") end
	Knit.GetService("PlayerDataService"):AddCoins(issuer, math.floor(amount), "admin")
	announceTo(issuer, ("+%d coins"):format(amount))
end

Handlers.lure = function(_self, issuer, args)
	local amount = tonumber(args[1]); if not amount then return announceTo(issuer, "usage: /lure <amount>") end
	Knit.GetService("PlayerDataService"):AddLureTokens(issuer, math.floor(amount))
	announceTo(issuer, ("+%d lure tokens"):format(amount))
end

Handlers.xp = function(_self, issuer, args)
	local amount = tonumber(args[1]); if not amount then return announceTo(issuer, "usage: /xp <amount>") end
	Knit.GetService("PlayerDataService"):AddXP(issuer, math.floor(amount))
	announceTo(issuer, ("+%d xp"):format(amount))
end

Handlers.setlevel = function(_self, issuer, args)
	local level = tonumber(args[1]); if not level then return announceTo(issuer, "usage: /setlevel <level>") end
	level = math.max(1, math.floor(level))
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(issuer); if not data then return end
	data.level = level
	-- Set XP to the floor of this level (so progress bar reads 0% at level start).
	data.xp = (level <= 1) and 0 or (50 * level * level)
	PlayerDataService.Client.XPChanged:Fire(issuer, level, data.xp, 50 * (level + 1) * (level + 1))
	announceTo(issuer, ("level set to %d"):format(level))
end

Handlers.fish = function(_self, issuer, args)
	local speciesId = args[1]
	if not speciesId then return announceTo(issuer, "usage: /fish <speciesId> [count]") end
	local fish = fishById[speciesId]
	if not fish then return announceTo(issuer, ("unknown species: %s"):format(speciesId)) end
	local count = tonumber(args[2]) or 1
	count = math.clamp(math.floor(count), 1, 50)

	local PlayerDataService = Knit.GetService("PlayerDataService")
	for _ = 1, count do
		local minW, maxW = fish.weightRange[1], fish.weightRange[2]
		local weight = minW + math.random() * (maxW - minW)
		PlayerDataService:AddItem(issuer, {
			uid = UidUtil.new("fish"),
			kind = "Fish",
			speciesId = speciesId,
			weightKg = math.floor(weight * 10 + 0.5) / 10,
			caughtAt = os.time(),
		})
	end
	announceTo(issuer, ("+%d %s"):format(count, fish.displayName))
end

Handlers.tp = function(_self, issuer, args)
	local target = args[1]
	if not target then return announceTo(issuer, "usage: /tp <username>") end
	local match: Player?
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower() == target:lower() or p.DisplayName:lower() == target:lower() then
			match = p; break
		end
	end
	if not match then return announceTo(issuer, ("no such player: %s"):format(target)) end
	local issuerChar = issuer.Character
	local targetChar = match.Character
	if not issuerChar or not targetChar then return announceTo(issuer, "characters not loaded") end
	local hrp = issuerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local thrp = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or not thrp then return announceTo(issuer, "no rootparts") end
	hrp.CFrame = thrp.CFrame * CFrame.new(0, 0, 4)
end

Handlers.fly = function(self, issuer, _args)
	-- Server just toggles the flag and tells the client. Client owns the
	-- input handling and physics — server-driven fly would either need a
	-- per-frame remote (wasteful) or break network ownership.
	self._flyState[issuer] = not self._flyState[issuer]
	self.Client.FlyToggled:Fire(issuer, self._flyState[issuer])
	announceTo(issuer, self._flyState[issuer] and "fly: on" or "fly: off")
end

Handlers.tutorialreset = function(_self, issuer)
	-- Wipe tutorial state so the flow re-bootstraps on next character
	-- spawn. Useful for dev testing the onboarding — every dev profile
	-- has stats from prior playtests, which auto-completes the
	-- returning-vet check in TutorialService:_bootstrapPlayer.
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local TutorialService   = Knit.GetService("TutorialService")
	local FishingService    = Knit.GetService("FishingService")
	local data = PlayerDataService:GetProfile(issuer); if not data then return end
	data.tutorial = {
		state = "not_started",
		lineIndex = 1,
		startedAt = nil,
		completedAt = nil,
		beginnerAssistsRemaining = 3,
		seededQuestId = nil,
		flags = { seenGlobalMarketHint = false },
	}
	-- Also zero out stats so the returning-vet auto-complete in
	-- TutorialService:_bootstrapPlayer doesn't immediately flip us back
	-- to "complete" on rejoin/load.
	if data.stats then
		data.stats.totalCatches = 0
		data.stats.totalSold = 0
	end
	-- Wipe any rolled daily quests so the HUD reflects the gated state
	-- (no quests until AcceptFirstQuest fires at beat 6). Also clear the
	-- yesterday-grace list so a fresh reset doesn't leak stale claimables.
	data.dailyQuests = {}
	data.yesterdayQuests = {}
	data.questsRefreshedDay = nil
	PlayerDataService:NudgeQuestsChanged(issuer)
	FishingService:SetAssistMultiplier(issuer, 1.8)
	TutorialService:_bootstrapPlayer(issuer)
	announceTo(issuer, "tutorial reset")
end

Handlers.announce = function(self, _issuer, args)
	local text = table.concat(args, " ")
	if text == "" then return end
	-- Broadcast to everyone — this IS the public-facing variant.
	for _, p in ipairs(Players:GetPlayers()) do
		self.Client.Announcement:Fire(p, text, 5)
	end
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================
function AdminService:KnitStart()
	self._weatherService = Knit.GetService("WeatherService")

	Players.PlayerAdded:Connect(function(player)
		if not self._studioFirstPlayer then
			self._studioFirstPlayer = player.UserId
		end
		player.Chatted:Connect(function(message)
			self:_handleChat(player, message)
		end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		if not self._studioFirstPlayer then self._studioFirstPlayer = p.UserId end
		p.Chatted:Connect(function(m) self:_handleChat(p, m) end)
	end

	Players.PlayerRemoving:Connect(function(player)
		self._flyState[player] = nil
	end)
end

function AdminService.Client:IsAdmin(player: Player): boolean
	return self.Server:_isAdmin(player)
end

function AdminService.Client:SetWeather(player: Player, weather: string): { ok: boolean, reason: string?, weather: string? }
	local server = self.Server
	if not server:_isAdmin(player) then
		return { ok = false, reason = "denied" }
	end
	if not VALID_WEATHER[weather] then
		return { ok = false, reason = "invalid" }
	end
	local ws = server._weatherService
	if not ws then
		return { ok = false, reason = "no_weather_service" }
	end
	if not ws:SetWeather(weather, true) then
		return { ok = false, reason = "failed" }
	end
	return { ok = true, weather = ws:GetWeather() }
end

function AdminService.Client:SetWeatherAuto(player: Player): { ok: boolean, reason: string?, weather: string? }
	local server = self.Server
	if not server:_isAdmin(player) then
		return { ok = false, reason = "denied" }
	end
	local ws = server._weatherService
	if not ws then
		return { ok = false, reason = "no_weather_service" }
	end
	ws:UnlockWeather()
	return { ok = true, weather = ws:GetWeather() }
end

function AdminService.Client:GetWeatherState(player: Player): { ok: boolean, weather: string, locked: boolean }
	local server = self.Server
	if not server:_isAdmin(player) then
		return { ok = false, weather = "Clear", locked = false }
	end
	local ws = server._weatherService
	if not ws then
		return { ok = false, weather = "Clear", locked = false }
	end
	return {
		ok = true,
		weather = ws:GetWeather(),
		locked = ws:IsWeatherLocked(),
	}
end

function AdminService:_handleChat(player: Player, message: string)
	local parsed = parse(message)
	if not parsed then return end
	if not self:_isAdmin(player) then
		-- Silent ignore. Don't tip off non-admins that admin commands exist.
		return
	end
	local handler = Handlers[parsed.name]
	if not handler then
		announceTo(player, ("unknown command: /%s"):format(parsed.name))
		return
	end
	-- Wrap in pcall so a buggy command can't crash the chat handler.
	local ok, err = pcall(handler, self, player, parsed.args)
	if not ok then
		warn("[AdminService] /" .. parsed.name .. " error:", err)
		announceTo(player, ("/%s errored — see Output"):format(parsed.name))
	end
end

return AdminService
