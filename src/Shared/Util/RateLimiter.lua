--!strict
-- RateLimiter.lua
-- Cheap per-key sliding-window rate limiter used by services to throttle
-- exploiter-driven RemoteEvent spam. Not cryptographically anything — just
-- "more than N hits in the last 60s? drop." Memory is freed on player leave
-- by the caller (services nil out their entries in PlayerRemoving).

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: {
	_windows: {[any]: {number}},  -- key -> array of os.clock() timestamps
	_max: number,
	_windowSec: number,
}, RateLimiter))

function RateLimiter.new(maxPerWindow: number, windowSeconds: number): RateLimiter
	local self = setmetatable({
		_windows = {},
		_max = maxPerWindow,
		_windowSec = windowSeconds,
	}, RateLimiter)
	return self
end

-- Returns true if the action is allowed (and records it). Returns false if
-- the caller has exceeded the rate. Old timestamps outside the window are
-- pruned lazily on each check so we don't need a background cleaner thread.
function RateLimiter:check(key: any): boolean
	local now = os.clock()
	local cutoff = now - self._windowSec
	local hits = self._windows[key]
	if not hits then
		hits = {}
		self._windows[key] = hits
	end
	-- Prune expired entries from the front. Since hits are appended in time
	-- order, we can just walk from the start until we hit one inside the window.
	local pruneTo = 0
	for i, t in ipairs(hits) do
		if t >= cutoff then
			pruneTo = i - 1
			break
		end
		pruneTo = i
	end
	if pruneTo > 0 then
		-- Rebuild without the expired prefix. table.remove in a loop is O(n^2);
		-- for our small N (max ~60) this naive rebuild is fine and clearer.
		local kept = {}
		for i = pruneTo + 1, #hits do
			kept[#kept + 1] = hits[i]
		end
		self._windows[key] = kept
		hits = kept
	end
	if #hits >= self._max then
		return false
	end
	hits[#hits + 1] = now
	return true
end

-- Drop a key's history (call on player leave to free memory).
function RateLimiter:reset(key: any)
	self._windows[key] = nil
end

return RateLimiter
