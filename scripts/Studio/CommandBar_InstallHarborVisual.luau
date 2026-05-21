-- Command Bar: install latest RBX_AI_GENERATED mesh from Workspace into Assets.Buildings.
-- Run once after each generate_mesh. Edit constants below.

local KIND = "MarketStall"
local TIER = 1
local FOOTPRINT_W, FOOTPRINT_D = 3, 3
-- Extra Y rotation after align (0 or 180). Dock pier should extend toward +Z.
local FACING_YAW_EXTRA = 0

local CELL = 4
local TARGET_X = FOOTPRINT_W * CELL * 0.9
local TARGET_Z = FOOTPRINT_D * CELL * 0.9

local function getBottomCenter(model: Model): Vector3
	local bbCF, bbSize = model:GetBoundingBox()
	return Vector3.new(bbCF.Position.X, bbCF.Position.Y - bbSize.Y / 2, bbCF.Position.Z)
end

local function rotateModelY(model: Model, degrees: number, pivot: Vector3)
	local rot = CFrame.Angles(0, math.rad(degrees), 0)
	local pivotCF = CFrame.new(pivot)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CFrame = pivotCF * rot * pivotCF:Inverse() * desc.CFrame
		end
	end
end

local function getMeshYawDegrees(model: Model): number
	local mesh = model:FindFirstChildWhichIsA("MeshPart", true)
	if mesh then
		local _, y, _ = mesh.CFrame:ToEulerAnglesYXZ()
		return math.deg(y)
	end
	local bbCF, _ = model:GetBoundingBox()
	local _, y, _ = bbCF:ToEulerAnglesYXZ()
	return math.deg(y)
end

local function alignVisualYaw(model: Model, footprintW: number, footprintD: number, facingExtra: number)
	local pivot = getBottomCenter(model)

	local yaw = getMeshYawDegrees(model)
	if math.abs(yaw) > 0.5 then
		rotateModelY(model, -yaw, pivot)
		pivot = getBottomCenter(model)
	end

	local _, bbSize = model:GetBoundingBox()
	if footprintD >= footprintW and bbSize.X > bbSize.Z * 1.05 then
		rotateModelY(model, 90, pivot)
	elseif footprintW > footprintD and bbSize.Z > bbSize.X * 1.05 then
		rotateModelY(model, 90, pivot)
	end

	if facingExtra ~= 0 then
		pivot = getBottomCenter(model)
		rotateModelY(model, facingExtra, pivot)
	end
end

local function anchorBottomCenter(model: Model)
	local bbCF, bbSize = model:GetBoundingBox()
	local bottomCenter = Vector3.new(bbCF.Position.X, bbCF.Position.Y - bbSize.Y / 2, bbCF.Position.Z)
	local shift = CFrame.new(-bottomCenter)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CFrame = shift * desc.CFrame
			desc.Anchored = true
			desc.CanCollide = true
			desc.CanQuery = false
			desc.CanTouch = false
		end
	end
	local pp = model:FindFirstChild("PrimaryPart")
	if pp then
		pp:Destroy()
	end
	pp = Instance.new("Part")
	pp.Name = "PrimaryPart"
	pp.Size = Vector3.new(0.2, 0.2, 0.2)
	pp.Transparency = 1
	pp.Anchored = true
	pp.CanCollide = false
	pp.CanQuery = false
	pp.CanTouch = false
	pp.Parent = model
	bbCF, bbSize = model:GetBoundingBox()
	bottomCenter = Vector3.new(bbCF.Position.X, bbCF.Position.Y - bbSize.Y / 2, bbCF.Position.Z)
	pp.CFrame = CFrame.new(bottomCenter)
	model.PrimaryPart = pp
end

local function getSourceModel(): Model?
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("RBX_AI_GENERATED") then
			return child
		end
	end
	return nil
end

local function addTier3Lanterns(visual: Model)
	local bbCF, sz = visual:GetBoundingBox()
	local y = bbCF.Position.Y - sz.Y / 2 + math.min(sz.Y * 0.85, 4.5)
	for i, xz in ipairs({ { -sz.X * 0.35, -sz.Z * 0.35 }, { sz.X * 0.35, -sz.Z * 0.35 } }) do
		local anchor = Instance.new("Part")
		anchor.Name = "LanternAnchor" .. i
		anchor.Size = Vector3.new(0.35, 0.35, 0.35)
		anchor.Transparency = 0.25
		anchor.Color = Color3.fromRGB(210, 175, 60)
		anchor.Material = Enum.Material.Metal
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CFrame = CFrame.new(xz[1], y, xz[2])
		anchor.Parent = visual
		local pl = Instance.new("PointLight")
		pl.Brightness = 1.2
		pl.Range = 14
		pl.Color = Color3.fromRGB(255, 200, 120)
		pl.Parent = anchor
	end
end

local src = getSourceModel()
if not src then
	warn("[InstallHarborVisual] No RBX_AI_GENERATED model in Workspace")
	return
end

local visual = Instance.new("Model")
visual.Name = "Visual"
for _, desc in src:GetDescendants() do
	if desc:IsA("BasePart") then
		desc:Clone().Parent = visual
	end
end

alignVisualYaw(visual, FOOTPRINT_W, FOOTPRINT_D, FACING_YAW_EXTRA)

local _, bbSize = visual:GetBoundingBox()
local scale = math.min(TARGET_X / bbSize.X, TARGET_Z / bbSize.Z)
if scale > 0 and math.abs(scale - 1) > 0.001 then
	visual:ScaleTo(scale)
end
anchorBottomCenter(visual)

local fp = visual:FindFirstChild("Footprint")
if not fp then
	fp = Instance.new("StringValue")
	fp.Name = "Footprint"
	fp.Parent = visual
end
fp.Value = string.format("%dx%d", FOOTPRINT_W, FOOTPRINT_D)

local buildings = game.ReplicatedStorage.Assets.Buildings
local kindFolder = buildings:WaitForChild(KIND)
local tierFolder = kindFolder:WaitForChild("tier" .. TIER)
local old = tierFolder:FindFirstChild("Visual")
if old then
	old:Destroy()
end
visual.Parent = tierFolder
src:Destroy()

local tier3Lights = { Dock = true, BaitShop = true, MarketStall = true, Lighthouse = true, Guildhall = true }
if TIER == 3 and tier3Lights[KIND] and not visual:FindFirstChild("LanternAnchor1") then
	addTier3Lanterns(visual)
end

local meshYaw = getMeshYawDegrees(visual)
print(("[InstallHarborVisual] %s tier%d installed; meshYaw=%.1f"):format(KIND, TIER, meshYaw))
