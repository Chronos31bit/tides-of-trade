--!strict
-- FishingController.lua
-- Owns the cast lifecycle on the client. The flow:
--   1. Player taps-and-holds (mobile) or holds left-click (PC) the Rod button.
--   2. Controller calls FishingService:StartCast() to ask the server for a
--      timing window. Server returns greenCenter/size + a castId.
--   3. CastMeter shows. While input is held, the marker oscillates.
--   4. On release, controller calls FishingService:ClaimCast(castId, marker).
--   5. Server responds with success/fail; we play SFX + show floating text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local CastMeter = require(script.Parent.Parent.UI.CastMeter)

local FishingController = Knit.CreateController({
	Name = "FishingController",
	_pendingCastId = nil :: string?,
	_meter = nil :: any,
	_holding = false,
})

function FishingController:KnitStart()
	local FishingService = Knit.GetService("FishingService")
	local RodService = Knit.GetService("RodService")

	-- Server-resolved cast result — either claim's response or a timeout.
	FishingService.CastResolved:Connect(function(result)
		if result.success then
			self:_celebrate(result)
		else
			self:_fail(result.reason)
		end
	end)

	-- The cast trigger is now gated by holding the rod tool. Server fires
	-- RodActivated on Tool.Activated (mouse click or mobile tap while rod
	-- equipped). On the *next* RodActivated the player releases the meter.
	-- This makes "do I have my rod out" the obvious mental model — no more
	-- random world-clicks turning into casts.
	RodService.RodActivated:Connect(function()
		self:CastOrRelease()
	end)
end

-- The unified entry point used by both PC click and mobile button. We start
-- a cast on the *first* call; the second call (release) claims.
function FishingController:CastOrRelease()
	if self._pendingCastId then
		self:_releaseClaim()
		return
	end
	self:_startCast()
end

function FishingController:_startCast()
	local FishingService = Knit.GetService("FishingService")
	FishingService:StartCast():andThen(function(window)
		if not window then
			-- Server said no fish biting, or rate-limited. Show a tiny "no bite"
			-- nudge — user-friendly but not annoying.
			self:_fail("no_bite")
			return
		end
		self._pendingCastId = window.castId
		self._meter = CastMeter.show(window.greenCenter, window.greenSize, window.period)
	end):catch(function(err)
		warn("[FishingController] StartCast failed:", err)
	end)
end

function FishingController:_releaseClaim()
	if not self._pendingCastId or not self._meter then return end
	local castId = self._pendingCastId
	self._pendingCastId = nil
	local marker = self._meter.stop()
	self._meter = nil
	local FishingService = Knit.GetService("FishingService")
	FishingService:ClaimCast(castId, marker):andThen(function(_result)
		-- Authoritative result also arrives via CastResolved signal — we let
		-- that path drive UI so server timeouts and direct claims behave
		-- identically. Nothing to do here.
	end):catch(function(err)
		warn("[FishingController] ClaimCast failed:", err)
	end)
end

function FishingController:_celebrate(result: any)
	-- TODO: SFX + floating text. For now just print a friendly line.
	-- Replace with SoundService:PlayLocalSound(<splash asset>) and a small
	-- toast UI. Asset IDs go in src/Client/AssetIds.lua (TODO).
	print(("[Fishing] Caught %s @ %.1f kg (+%d xp)"):format(result.fish.displayName, result.weightKg, result.xpGained))
end

function FishingController:_fail(reason: any)
	if reason == "missed" then
		print("[Fishing] Slipped off the line!")
	elseif reason == "no_bite" then
		print("[Fishing] Nothing's biting here right now.")
	else
		print("[Fishing] Cast failed:", reason)
	end
end

return FishingController
