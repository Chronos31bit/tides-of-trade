--!strict
-- RodService.lua
-- Spawns a fishing rod Tool into the player's Backpack on character spawn.
-- The Tool is the equipment-state gate: clicks/taps only trigger fishing
-- when the rod is *equipped* (Tool.Activated). Removing the rod tool from
-- the player while in Studio testing is a fast way to verify the gate
-- (clicks shouldn't cast).

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit             = require(ReplicatedStorage.Packages.Knit)

local RodService = Knit.CreateService({
	Name = "RodService",
	Client = {
		-- Fired when the player Activated the rod tool. Client controllers
		-- listen and trigger the cast/release flow.
		RodActivated = Knit.CreateSignal(),
	},
})

-- Build a placeholder rod Tool. Real game would clone a model with mesh +
-- weld setup; the wood handle here is enough to verify the equip flow.
local function buildRodTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Fishing Rod"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = "Tap or click to cast"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 0.4, 4)
	handle.Material = Enum.Material.Wood
	handle.Color = Color3.fromRGB(120, 80, 50)
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	-- Tip part welded to the handle, just for visual flair on the rod's end.
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.15, 0.15, 1.5)
	tip.Material = Enum.Material.Plastic
	tip.Color = Color3.fromRGB(220, 200, 180)
	tip.TopSurface = Enum.SurfaceType.Smooth
	tip.BottomSurface = Enum.SurfaceType.Smooth
	tip.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = tip
	weld.Parent = handle
	tip.CFrame = handle.CFrame * CFrame.new(0, 0, -2.5)

	return tool
end

function RodService:_grantRod(player: Player)
	-- Remove any stale rod (rejoin / respawn) before re-issuing.
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		local existing = backpack:FindFirstChild("Fishing Rod")
		if existing then existing:Destroy() end
	end
	local char = player.Character
	if char then
		local equipped = char:FindFirstChild("Fishing Rod")
		if equipped then equipped:Destroy() end
	end

	local tool = buildRodTool()
	-- Tool.Activated fires server-side when the player taps/clicks while the
	-- tool is equipped. We forward that to the client controller via Knit
	-- signal so the existing FishingController flow is preserved.
	tool.Activated:Connect(function()
		self.Client.RodActivated:Fire(player)
	end)
	tool.Parent = backpack
end

function RodService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function() self:_grantRod(player) end)
		if player.Character then self:_grantRod(player) end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function() self:_grantRod(p) end)
		if p.Character then self:_grantRod(p) end
	end
end

return RodService
