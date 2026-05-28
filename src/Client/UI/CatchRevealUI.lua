--!strict
-- CatchRevealUI.lua
-- "You caught X" reveal card. Layout from StarterGuiAssets.CatchRevealUI_Template;
-- behavior wiring only (fish thumb, modifiers, motion, dismiss).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIUtil = require(script.Parent.UIUtil)
local UIKit = require(script.Parent.UIKit)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local FishMutations = require(ReplicatedStorage.Shared.Util.FishMutations)

local CatchRevealUI = {}

local P = UIUtil.Palette
local FT = GameConfig.Fishing.FeelTuning
local CR = GameConfig.UI.CatchReveal

local function req(parent: Instance, name: string, class: string): Instance
	local c = parent:FindFirstChild(name)
	if not c or not c:IsA(class) then
		error(`[CatchRevealUI] Missing {class} "{name}" under {parent:GetFullName()}`, 2)
	end
	return c
end

local function _walletTopOffsetPx(): (number, boolean)
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("HUD")
	local wallet = hud and hud:FindFirstChild("Wallet")
	if wallet and wallet:IsA("GuiObject") then
		return wallet.Position.Y.Offset, true
	end
	return CR.RestTopOffsetPx, false
end

local _modDisplayNames: {[string]: string} = {}
local _modData: {[string]: any} = {}
for _, m in ipairs(GameConfig.FishModifiers) do
	_modDisplayNames[m.id] = m.displayName
	_modData[m.id] = m
end

local function _modEffectText(modId: string): string
	local m = _modData[modId]
	if not m then return "" end
	if m.sellPriceMul then
		local pct = math.round((m.sellPriceMul - 1) * 100)
		return (pct >= 0 and "+" or "") .. pct .. "% sell"
	elseif m.xpMul then
		return "×" .. m.xpMul .. " XP"
	elseif m.weightMul then
		return "×" .. m.weightMul .. " wt"
	elseif m.coinInstant then
		return "+" .. m.coinInstant .. "× gold"
	elseif m.lureBonus then
		return "+" .. m.lureBonus .. " lure"
	end
	return ""
end

local function sparkleFrameForRarity(rarity: string): string
	if rarity == "Common" or rarity == "Uncommon" then
		return "SparkleCommon"
	elseif rarity == "Rare" or rarity == "Epic" then
		return "SparkleRare"
	end
	return "SparkleLegendary"
end

local function sparkleColorForFrame(frameName: string): Color3
	if frameName == "SparkleRare" then
		return UIKit.rarityColor("Rare")
	elseif frameName == "SparkleLegendary" then
		return UIKit.rarityColor("Legendary")
	end
	return UIKit.rarityColor("Common")
end

-- UIGradient omitted from .model.json (Rojo ColorSequence format); created at runtime.
local function ensureSparkleGradient(sparkle: Frame): UIGradient
	local grad = sparkle:FindFirstChildOfClass("UIGradient")
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Name = "UIGradient"
		grad.Rotation = 25
		grad.Parent = sparkle
	end
	local c = sparkleColorForFrame(sparkle.Name)
	grad.Color = ColorSequence.new(c)
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Offset = Vector2.new(-0.5, 0)
	return grad
end

export type CatchPayload = {
	fish: { displayName: string, rarity: string, basePrice: number, id: string? },
	weightKg: number,
	coinsEarned: number?,
	xpGained: number?,
	perfect: boolean?,
	castPerfect: boolean?,
	modifiers: {string}?,
}

export type RevealHandle = {
	gui: ScreenGui,
	dismiss: () -> (),
}

local function titleCase(s: string?): string
	if not s then return "" end
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

function CatchRevealUI.show(payload: CatchPayload): RevealHandle
	local gui = TemplateLoader.spawn("CatchReveal", { instanceName = "CatchReveal" })

	local card = req(gui, "Card", "Frame") :: Frame
	local dismissBtn = req(card, "DismissButton", "TextButton") :: TextButton
	local vpf = req(card, "FishViewport", "ViewportFrame") :: ViewportFrame
	local nameLbl = req(card, "NameLabel", "TextLabel") :: TextLabel
	local pillStrip = req(card, "ModifierPillStrip", "Frame") :: Frame
	local coinLbl = req(card, "CoinPreviewLabel", "TextLabel") :: TextLabel
	local rarityChip = req(card, "RarityChip", "Frame") :: Frame
	local rarityLbl = req(rarityChip, "Label", "TextLabel") :: TextLabel
	local stroke = req(card, "CardStroke", "UIStroke") :: UIStroke

	local sparkleCommon = req(card, "SparkleCommon", "Frame") :: Frame
	local sparkleRare = req(card, "SparkleRare", "Frame") :: Frame
	local sparkleLegendary = req(card, "SparkleLegendary", "Frame") :: Frame
	sparkleCommon.Visible = false
	sparkleRare.Visible = false
	sparkleLegendary.Visible = false

	local rarity = payload.fish.rarity or "Common"
	local tierColor = UIUtil.rarityColor(rarity)
	local perfectColor = UIUtil.Palette.Legendary

	local mods = payload.modifiers or {}
	local cardExtraH = #mods > 0 and 24 or 0
	local cardH = 132 + cardExtraH

	local restTopPx = _walletTopOffsetPx()
	local offscreenTopPx = restTopPx - CR.OffscreenTopOffsetPx

	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, offscreenTopPx)
	card.Size = UDim2.fromOffset(360, cardH)

	stroke.Color = tierColor

	local nameTopY = 12
	local reelPerfect = payload.perfect == true
	local castPerfect = payload.castPerfect == true
	if reelPerfect or castPerfect then
		local perfectLbl = Instance.new("TextLabel")
		perfectLbl.BackgroundTransparency = 1
		perfectLbl.Position = UDim2.new(0, 108, 0, 8)
		perfectLbl.Size = UDim2.new(1, -120, 0, 14)
		perfectLbl.Font = Enum.Font.GothamBlack
		perfectLbl.TextSize = 12
		perfectLbl.TextColor3 = perfectColor
		perfectLbl.TextXAlignment = Enum.TextXAlignment.Left
		if reelPerfect and castPerfect then
			perfectLbl.Text = "PERFECT CATCH"
		elseif reelPerfect then
			perfectLbl.Text = "PERFECT REEL"
		else
			perfectLbl.Text = "PRECISION CAST"
		end
		perfectLbl.Parent = card
		nameTopY = 24
	end

	nameLbl.Position = UDim2.new(0, 108, 0, nameTopY)
	nameLbl.Text = (payload.fish.displayName or titleCase(payload.fish.id))
		.. ("\n%.1f kg"):format(payload.weightKg or 0)

	local earned = payload.coinsEarned or 0
	if earned > 0 then
		coinLbl.TextColor3 = perfectColor
		coinLbl.Text = ("+%d coins bonus!"):format(earned)
	else
		coinLbl.TextColor3 = P.Gold
		coinLbl.Text = ("~%d coins"):format(payload.fish.basePrice or 0)
	end

	rarityChip.BackgroundColor3 = tierColor
	local needsDarkText = rarity == "Common" or rarity == "Uncommon" or rarity == "Legendary" or rarity == "Divine"
	rarityLbl.TextColor3 = needsDarkText and P.Ink or P.Cream
	rarityLbl.Text = rarity:upper()

	-- Fish viewport
	local rotTask: thread? = nil
	local fishId = payload.fish.id
	local fishAssets = ReplicatedStorage:FindFirstChild("Assets")
		and (ReplicatedStorage.Assets :: Instance):FindFirstChild("Fish")
	local tmpl = fishAssets and fishId and fishAssets:FindFirstChild(fishId)
	if tmpl and tmpl:IsA("Model") then
		local wm = Instance.new("WorldModel")
		wm.Parent = vpf
		local clone = tmpl:Clone()
		clone.Parent = wm
		local revealAnchor: BasePart? = nil
		if clone.PrimaryPart and clone.PrimaryPart:IsA("BasePart") then
			revealAnchor = clone.PrimaryPart :: BasePart
		else
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then
					revealAnchor = d :: BasePart
					break
				end
			end
		end
		if revealAnchor and #mods > 0 then
			FishMutations.attach(revealAnchor, mods, { viewport = true, intensity = 1 })
		end

		local cam = Instance.new("Camera")
		cam.FieldOfView = 40
		vpf.CurrentCamera = cam
		cam.Parent = vpf

		local ok, pivotCF, extents = pcall(function(): (CFrame, Vector3)
			return clone:GetBoundingBox()
		end)
		if ok and pivotCF then
			local maxDim = math.max(extents.X, extents.Y, extents.Z)
			local dist = math.max(maxDim * 1.5, 4)
			local height = dist * 0.4
			local pivot = pivotCF.Position
			local angle = 0

			if MotionUtil.reducedMotionEnabled() then
				cam.CFrame = CFrame.lookAt(
					pivot + Vector3.new(dist * 0.7, height, dist * 0.7),
					pivot
				)
			else
				rotTask = task.spawn(function()
					local last = os.clock()
					while vpf.Parent do
						local now = os.clock()
						angle = (angle + 60 * (now - last)) % 360
						last = now
						local rad = math.rad(angle)
						cam.CFrame = CFrame.lookAt(
							pivot + Vector3.new(math.cos(rad) * dist, height, math.sin(rad) * dist),
							pivot
						)
						RunService.Heartbeat:Wait()
					end
				end)
			end
		end
	end

	-- Modifier pills
	for _, child in ipairs(pillStrip:GetChildren()) do
		if child:IsA("Frame") and child.Name == "ModifierPill" then
			child:Destroy()
		end
	end
	if #mods > 0 then
		pillStrip.Position = UDim2.new(0, 108, 0, nameTopY + 52)
		pillStrip.Visible = true
		local reduced = MotionUtil.reducedMotionEnabled()
		local maxVisible = math.min(#mods, 3)
		for i = 1, maxVisible do
			local modId = mods[i]
			local effectText = _modEffectText(modId)
			local labelText = (_modDisplayNames[modId] or modId) .. (effectText ~= "" and (" • " .. effectText) or "")
			local pill = UIKit.ModifierPill(modId, labelText, {
				Size = UDim2.fromOffset(0, 22),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = i,
				BackgroundTransparency = 0.2,
				Parent = pillStrip,
			})
			pill.Name = "ModifierPill"
			if reduced then
				pill.BackgroundTransparency = 0.25
				local lbl = pill:FindFirstChildWhichIsA("TextLabel")
				if lbl then lbl.TextTransparency = 0 end
			else
				task.delay((i - 1) * 0.08, function()
					if not pill.Parent then return end
					MotionUtil.tween(pill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						BackgroundTransparency = 0.25,
					})
					local lbl = pill:FindFirstChildWhichIsA("TextLabel")
					if lbl then
						MotionUtil.tween(lbl, TweenInfo.new(0.18), { TextTransparency = 0 })
					end
				end)
			end
		end
		if #mods > 3 then
			UIUtil.makeLabel("+" .. (#mods - 3), "caption", {
				Name = "OverflowLabel",
				Size = UDim2.fromOffset(32, 22),
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 4,
				Parent = pillStrip,
			})
		end
	else
		pillStrip.Visible = false
	end

	-- Rarity sparkle overlay (template); skipped under reduced motion.
	if not MotionUtil.reducedMotionEnabled() then
		local sparkleName = sparkleFrameForRarity(rarity)
		local sparkle = card:FindFirstChild(sparkleName)
		if sparkle and sparkle:IsA("Frame") then
			sparkle.Visible = true
			local grad = ensureSparkleGradient(sparkle)
			task.spawn(function()
					for _ = 1, 3 do
						if not sparkle.Parent then return end
						MotionUtil.tween(grad, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Offset = Vector2.new(0.5, 0),
						})
						task.wait(0.35)
						if not sparkle.Parent then return end
						grad.Offset = Vector2.new(-0.5, 0)
					end
					if sparkle.Parent then
						sparkle.Visible = false
					end
				end)
		end
	end

	-- Animated border cycle for high rarities
	local cycleTask: thread? = nil
	local thickTask: thread? = nil
	local cycleTarget = UIUtil.Palette.RarityCycle[rarity]
	if cycleTarget and not MotionUtil.reducedMotionEnabled() then
		cycleTask = task.spawn(function()
			local toTarget = true
			while card.Parent do
				local target = toTarget and cycleTarget or tierColor
				local tween = MotionUtil.tween(stroke, TweenInfo.new(FT.MythicBorderCycleDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Color = target,
				})
				tween.Completed:Wait()
				tween:Destroy()
				toTarget = not toTarget
			end
		end)
		if rarity == "Divine" then
			thickTask = task.spawn(function()
				local toThick = true
				while card.Parent do
					local target = toThick and 5 or 3
					local tween = MotionUtil.tween(stroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
						Thickness = target,
					})
					tween.Completed:Wait()
					tween:Destroy()
					toThick = not toThick
				end
			end)
		end
	end

	-- Perfect burst dots (behavior-only decoration)
	if (reelPerfect or castPerfect) and not MotionUtil.reducedMotionEnabled() then
		task.spawn(function()
			for i = 1, 10 do
				if not card.Parent then return end
				local dot = Instance.new("Frame")
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Position = UDim2.new(math.random(), math.random(-4, 4), 0, math.random(-2, 2))
				dot.Size = UDim2.fromOffset(4, 4)
				dot.BackgroundColor3 = perfectColor
				dot.BorderSizePixel = 0
				local dc = Instance.new("UICorner")
				dc.CornerRadius = UDim.new(1, 0)
				dc.Parent = dot
				dot.ZIndex = 6
				dot.Parent = card
				local rise = MotionUtil.tween(dot, TweenInfo.new(0.7 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = dot.Position + UDim2.fromOffset(math.random(-12, 12), -30),
					BackgroundTransparency = 1,
				})
				rise.Completed:Connect(function()
					rise:Destroy()
					dot:Destroy()
				end)
				task.wait(0.07)
			end
		end)
	end

	local restPosition = UDim2.new(0.5, 0, 0, restTopPx)
	local offscreenPosition = UDim2.new(0.5, 0, 0, offscreenTopPx)
	if MotionUtil.reducedMotionEnabled() then
		card.Position = restPosition
		card.BackgroundTransparency = 1
		MotionUtil.tween(card, TweenInfo.new(0.25), { BackgroundTransparency = 0 })
	else
		local slideIn = MotionUtil.tween(card, TweenInfo.new(FT.RevealSlideInDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = restPosition,
		})
		slideIn.Completed:Connect(function() slideIn:Destroy() end)
	end

	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		if rotTask then task.cancel(rotTask); rotTask = nil end
		if cycleTask then task.cancel(cycleTask); cycleTask = nil end
		if thickTask then task.cancel(thickTask); thickTask = nil end
		if MotionUtil.reducedMotionEnabled() then
			local fade = MotionUtil.tween(card, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
			fade.Completed:Connect(function() fade:Destroy(); gui:Destroy() end)
		else
			local slide = MotionUtil.tween(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = offscreenPosition,
			})
			slide.Completed:Connect(function() slide:Destroy(); gui:Destroy() end)
		end
	end

	dismissBtn.Activated:Connect(dismiss)
	task.delay(FT.RevealAutoDismissAfter, dismiss)

	return {
		gui = gui,
		dismiss = dismiss,
	}
end

return CatchRevealUI
