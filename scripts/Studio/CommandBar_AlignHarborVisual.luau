-- Command Bar: re-align an existing Visual in Assets (fix baked mesh yaw without regen).
-- Edit constants, run once per kind (all tiers) or set TIER to 1|2|3 for one tier.

local KIND = "Dock"
local TIER: number? = nil -- nil = all tiers 1-3
local FOOTPRINT_W, FOOTPRINT_D = 4, 6
local FACING_YAW_EXTRA = 0

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

local kindFolder = game.ReplicatedStorage.Assets.Buildings:FindFirstChild(KIND)
if not kindFolder then
	warn("[AlignHarborVisual] Unknown kind:", KIND)
	return
end

for tier = 1, 3 do
	if TIER and tier ~= TIER then
		continue
	end
	local tierFolder = kindFolder:FindFirstChild("tier" .. tier)
	local visual = tierFolder and tierFolder:FindFirstChild("Visual")
	if not visual or not visual:IsA("Model") then
		continue
	end
	local before = getMeshYawDegrees(visual)
	alignVisualYaw(visual, FOOTPRINT_W, FOOTPRINT_D, FACING_YAW_EXTRA)
	anchorBottomCenter(visual)
	local after = getMeshYawDegrees(visual)
	print(("[AlignHarborVisual] %s tier%d yaw %.1f -> %.1f"):format(KIND, tier, before, after))
end
