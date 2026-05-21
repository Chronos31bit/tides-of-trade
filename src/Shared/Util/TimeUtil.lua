--!strict
-- TimeUtil.lua
-- Centralizes UTC date math. Daily quests, login streaks, and demand spikes
-- all key on "what UTC day is it?" — so they all need the same answer.
-- Doing this anywhere else risks one system rolling over at a different
-- moment than another and confusing players.

local TimeUtil = {}

-- Returns the UTC day key as "YYYY-MM-DD" — comparable as a string.
function TimeUtil.currentUTCDay(now: number?): string
	local t = os.date("!*t", now or os.time()) :: any
	return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

-- Seconds remaining until the next UTC midnight. Used by client UI countdowns.
function TimeUtil.secondsUntilUTCMidnight(now: number?): number
	local current = now or os.time()
	local t = os.date("!*t", current) :: any
	local secondsToday = t.hour * 3600 + t.min * 60 + t.sec
	return (24 * 3600) - secondsToday
end

-- Returns true if `lastDay` is exactly the UTC day before `currentDay`.
-- Used by login streak: streak resets if a player skips a day.
function TimeUtil.isConsecutiveUTCDay(lastDay: string, currentDay: string): boolean
	local function parse(s: string): number
		local y, m, d = s:match("(%d+)-(%d+)-(%d+)")
		return os.time({year = tonumber(y) :: number, month = tonumber(m) :: number, day = tonumber(d) :: number, hour = 12, min = 0, sec = 0})
	end
	local diff = parse(currentDay) - parse(lastDay)
	-- Allow a small fudge for DST-style weirdness — anything between 18h and 30h is "next day".
	return diff > 18 * 3600 and diff < 30 * 3600
end

return TimeUtil
