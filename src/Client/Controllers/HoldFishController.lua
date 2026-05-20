--!strict
-- HoldFishController.lua
-- Purely cosmetic: lets the player pull a fish from their bag and hold it
-- in-world (welded to the right hand). The fish stays in their DataStore
-- inventory — no server state changes. Other players don't see the held fish
-- in this version (cross-client replication would need a server RemoteEvent).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit              = require(ReplicatedStorage.Packages.Knit)
local UIUtil            = require(script.Parent.Parent.UI.UIUtil)
local GameConfig        = require(ReplicatedStorage.Shared.Config.GameConfig)
local FishMutations     = require(ReplicatedStorage.Shared.Util.FishMutations)
local MotionUtil        = require(ReplicatedStorage.Shared.Util.MotionUtil)

local P = UIUtil.Palette

local HoldFishController = Knit.CreateController({ Name = "HoldFishController" })

local _heldModel: Model?          = nil
local _toastGui: ScreenGui?       = nil
local _mutHandle: any             = nil

local function destroyHeld()
	if _mutHandle then _mutHandle:Destroy(); _mutHandle = nil end
	if _heldModel then _heldModel:Destroy(); _heldModel = nil end
	if _toastGui  then _toastGui:Destroy();  _toastGui  = nil end
end

function HoldFishController:Release()
	destroyHeld()
end

function HoldFishController:HoldFish(
	uid: string,
	speciesId: string,
	modifiers: {string}?,
	weightKg: number?,
	weightMin: number?,
	weightMax: number?
)
	-- Drop any previously held fish.
	destroyHeld()

	local fishAssets = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("Fish")
	local tmpl = fishAssets and fishAssets:FindFirstChild(speciesId)
	if not tmpl then
		warn("[HoldFish] No model for species:", speciesId)
		return
	end

	local char = Players.LocalPlayer.Character
	if not char then return end

	-- Prefer R15 RightHand; fall back to R6 Right Arm.
	local hand: BasePart? = (char:FindFirstChild("RightHand") :: BasePart?)
		or (char:FindFirstChild("Right Arm") :: BasePart?)
	if not hand then
		warn("[HoldFish] Could not find hand part on character")
		return
	end

	local clone: Model = (tmpl :: Model):Clone()
	clone.Parent = workspace

	-- Scale uniformly if the model is a single BasePart (typical fish mesh).
	-- Target size lerps from FishHeld.MinStuds to MaxStuds based on weight.
	local parts: {BasePart} = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d :: BasePart) end
	end
	if #parts == 1 then
		local p = parts[1]
		local maxDim = math.max(p.Size.X, p.Size.Y, p.Size.Z)
		if maxDim > 0.01 then
			local heldCfg: {[string]: any} = (GameConfig :: any).FishHeld or {}
			local minStuds: number = heldCfg.MinStuds or 1.0
			local maxStuds: number = heldCfg.MaxStuds or 3.5
			local wKg  = weightKg  or 0
			local wMin = weightMin or 0
			local wMax = weightMax or 1
			local t = (wMax > wMin) and math.clamp((wKg - wMin) / (wMax - wMin), 0, 1) or 0.5
			local targetStuds = minStuds + t * (maxStuds - minStuds)
			p.Size = p.Size * (targetStuds / maxDim)
		end
	end

	-- Unanchor, no collision, massless — fish is purely cosmetic and must not
	-- push the holding player or obstruct other players' movement.
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			bp.Anchored    = false
			bp.CanCollide  = false
			bp.CanTouch    = false
			bp.Massless    = true
			bp.CastShadow  = false
		end
	end

	-- Position at hand, then weld.
	local attachPart: BasePart? = clone.PrimaryPart
	if not attachPart then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then attachPart = d :: BasePart; break end
		end
	end
	if not attachPart then clone:Destroy(); return end

	clone:PivotTo(hand.CFrame * CFrame.new(0, -0.5, -1.5))

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = attachPart
	weld.Parent = attachPart

	_mutHandle = FishMutations.attach(attachPart, modifiers or {})

	_heldModel = clone

	-- "Put Back" toast — small button anchored center-bottom, above the HUD bar.
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local toastGui = Instance.new("ScreenGui")
	toastGui.Name = "HoldFishToast"
	toastGui.ResetOnSpawn = false
	toastGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	toastGui.Parent = pg
	_toastGui = toastGui

	local toast = Instance.new("Frame")
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -108)
	toast.Size = UDim2.fromOffset(40, 48)
	toast.AutomaticSize = Enum.AutomaticSize.X
	toast.BackgroundColor3 = P.TealDark
	toast.BorderSizePixel = 0
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 12); tc.Parent = toast
	local ts = Instance.new("UIStroke"); ts.Color = P.TealDeeper; ts.Thickness = 1.5; ts.Transparency = 0.25; ts.Parent = toast
	local tp = Instance.new("UIPadding"); tp.PaddingLeft = UDim.new(0,10); tp.PaddingRight = UDim.new(0,10); tp.Parent = toast
	toast.Parent = toastGui

	local toastLayout = Instance.new("UIListLayout")
	toastLayout.FillDirection = Enum.FillDirection.Horizontal
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	toastLayout.Padding = UDim.new(0, 8)
	toastLayout.Parent = toast

	local fishLbl = Instance.new("TextLabel")
	fishLbl.BackgroundTransparency = 1
	fishLbl.Size = UDim2.fromOffset(20, 30)
	fishLbl.Font = Enum.Font.GothamBold
	fishLbl.TextSize = 18
	fishLbl.TextColor3 = P.Cream
	fishLbl.Text = "🐟"
	fishLbl.LayoutOrder = 1
	fishLbl.Parent = toast

	-- Modifier pills
	local mods = modifiers or {}
	local modDisplayNames: {[string]: string} = {}
	for _, m in ipairs(GameConfig.FishModifiers) do modDisplayNames[m.id] = m.displayName end
	for i = 1, math.min(#mods, 3) do
		local modId = mods[i]
		local glowCfg = (GameConfig :: any).ModifierGlow and (GameConfig :: any).ModifierGlow[modId]
		local color: Color3 = glowCfg and glowCfg.Color or Color3.fromRGB(160, 160, 160)
		local pill = Instance.new("Frame")
		pill.LayoutOrder = 1 + i
		pill.Size = UDim2.fromOffset(0, 28)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.BackgroundColor3 = color
		pill.BackgroundTransparency = 0.2
		pill.BorderSizePixel = 0
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 9); pc.Parent = pill
		local pp = Instance.new("UIPadding"); pp.PaddingLeft = UDim.new(0,6); pp.PaddingRight = UDim.new(0,6); pp.Parent = pill
		local pLbl = Instance.new("TextLabel")
		pLbl.BackgroundTransparency = 1
		pLbl.Size = UDim2.fromScale(1, 1)
		pLbl.Font = Enum.Font.GothamBold
		pLbl.TextSize = math.max(12, UIUtil.MinFontPx)
		pLbl.TextColor3 = Color3.new(1, 1, 1)
		pLbl.Text = modDisplayNames[modId] or modId
		pLbl.Parent = pill
		if glowCfg then
			local gs = Instance.new("UIStroke")
			gs.Color = glowCfg.Color
			gs.Thickness = glowCfg.Thickness
			gs.Transparency = glowCfg.Transparency
			gs.Parent = pill
		end
		pill.Parent = toast
	end

	local putBackBtn = UIUtil.makeButton("Put Back", function()
		HoldFishController:Release()
	end, {
		Size = UDim2.fromOffset(110, 34),
		BackgroundColor3 = P.Wood,
		TextSize = 13,
	})
	putBackBtn.LayoutOrder = 10
	putBackBtn.Parent = toast

	-- Fade toast in — routed through MotionUtil so ReducedMotion snaps.
	toastGui.Enabled = true
	toast.BackgroundTransparency = 1
	ts.Transparency = 1
	MotionUtil.tweenOrSnap(toast, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	})
	MotionUtil.tweenOrSnap(ts, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.25,
	})
end

function HoldFishController:KnitInit()
end

function HoldFishController:KnitStart()
end

return HoldFishController
