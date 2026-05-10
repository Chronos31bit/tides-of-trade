--!strict
-- UidUtil.lua
-- Generates short collision-resistant unique ids for inventory items, buildings,
-- and market listings. Uses HttpService:GenerateGUID under the hood and strips
-- braces/dashes so the ids are compact in DataStore JSON.

local HttpService = game:GetService("HttpService")

local UidUtil = {}

function UidUtil.new(prefix: string?): string
	-- HttpService:GenerateGUID returns "{XXXX-XXXX-...}" — strip the noise.
	local raw = HttpService:GenerateGUID(false):gsub("-", "")
	-- 32 hex chars is overkill — 16 is plenty for our scale and saves DataStore bytes.
	local short = raw:sub(1, 16)
	if prefix then
		return prefix .. "_" .. short
	end
	return short
end

return UidUtil
