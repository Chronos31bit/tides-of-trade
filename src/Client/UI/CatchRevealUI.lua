--!strict
-- CatchRevealUI.lua
-- The "you caught X" reveal card. Slides up from the bottom of the screen,
-- holds for 3 seconds, slides back down (or fades if reduced motion). Tap
-- the card to dismiss early. Tier-colored 3px border; Mythics get a slow
-- amber↔coral color cycle for the duration of the card's life.

local RunService   = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIUtil        = require(script.Parent.UIUtil)
local MotionUtil    = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig    = require(ReplicatedStorage.Shared.Config.GameConfig)
local FishMutations = require(ReplicatedStorage.Shared.Util.FishMutations)

local CatchRevealUI = {}

local P = UIUtil.Palette
local FT = GameConfig.Fishing.FeelTuning

-- Rarity + modifier colors live in UIUtil.Palette (single source of truth).
-- TIER_CYCLE_TARGETS used to live here too; it's now UIUtil.Palette.RarityCycle.

local _modDisplayNames: {[string]: string} = {}
local _modData: {[string]: any} = {}
for _, m in ipairs(GameConfig.FishModifiers) do
	_modDisplayNames[m.id] = m.displayName
	_modData[m.id] = m
end

local function _modEffectText(modId: string): string
	local m = _modData[modId]
	if not m then return "" end
	-- Priority: sellPriceMul > xpMul > weightMul > coinInstant > lureBonus
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

export type CatchPayload = {
	fish: { displayName: string, rarity: string, basePrice: number, id: string? },
	weightKg: number,
	coinsEarned: number?,   -- instant coin bonus from perfect reel (0 if not perfect)
	xpGained: number?,
	perfect: boolean?,      -- reel was perfect-zone (triggers coin bonus)
	castPerfect: boolean?,  -- cast marker hit the inner gold strip (triggers weight bonus)
	modifiers: {string}?,   -- modifier ids applied at catch time
}

export type RevealHandle = {
	gui: ScreenGui,
	dismiss: () -> (),
}

-- Convert a snake_case species id to Title Case ("harbor_mackerel" -> "Harbor Mackerel").
local function titleCase(s: string?): string
	if not s then return "" end
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

function CatchRevealUI.show(payload: CatchPayload): RevealHandle
	local gui = UIUtil.makeScreenGui("CatchReveal", nil, { respectTopbar = true })
	gui.DisplayOrder = UIUtil.DisplayOrder.CatchReveal

	local rarity = payload.fish.rarity or "Common"
	local tierColor    = UIUtil.rarityColor(rarity)
	local perfectColor = UIUtil.Palette.Legendary  -- gold for perfect catch indicators

	-- Expand card height by 24 px when modifiers are present so pills don't crowd the coin label.
	local mods = payload.modifiers or {}
	local cardExtraH = #mods > 0 and 24 or 0

	-- ----------------------------------------------------------------
	-- CARD — solid teal panel, tier-colored stroke, rounded.
	-- ----------------------------------------------------------------
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	-- Starts offscreen below; positioned to slide in.
	card.Position = UDim2.new(0.5, 0, 1, 240)
	card.Size = UDim2.fromOffset(360, 132 + cardExtraH)
	card.BackgroundColor3 = P.TealDark
	card.BorderSizePixel = 0
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 14); corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = tierColor
	stroke.Thickness = 3
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	card.Parent = gui

	-- A TextButton overlay so the whole card responds to taps without
	-- intercepting per-element clicks (we have no inner clickable bits).
	local tapCatcher = Instance.new("TextButton")
	tapCatcher.BackgroundTransparency = 1
	tapCatcher.Text = ""
	tapCatcher.Size = UDim2.fromScale(1, 1)
	tapCatcher.ZIndex = 5
	tapCatcher.Parent = card

	-- ----------------------------------------------------------------
	-- FISH MODEL VIEWPORT — 80×80 ViewportFrame rendering the species'
	-- 3D model from ReplicatedStorage.Assets.Fish.<id>.
	-- Camera auto-frames the bounding box from a slight angle.
	-- Falls back to a plain dark square if the model is missing.
	-- ----------------------------------------------------------------
	local vpf = Instance.new("ViewportFrame")
	vpf.Name = "FishViewport"
	vpf.Position = UDim2.new(0, 16, 0, 16)
	vpf.Size = UDim2.fromOffset(80, 80)
	vpf.BackgroundColor3 = P.TealDeeper
	vpf.BorderSizePixel = 0
	vpf.LightColor = P.ThumbLight
	vpf.LightDirection = Vector3.new(-1, -2, -1)
	local vc = Instance.new("UICorner"); vc.CornerRadius = UDim.new(0, 10); vc.Parent = vpf
	vpf.Parent = card

	local rotTask: thread? = nil

	local _fishId = payload.fish.id
	local _fishAssets = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("Fish")
	local _template = _fishAssets and _fishId and _fishAssets:FindFirstChild(_fishId)
	if _template then
		local wm = Instance.new("WorldModel")
		wm.Parent = vpf
		local clone = _template:Clone()
		clone.Parent = wm
		local revealAnchor: BasePart? = clone.PrimaryPart
			and clone.PrimaryPart:IsA("BasePart") and (clone.PrimaryPart :: BasePart)
			or nil
		if not revealAnchor then
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

		-- Auto-frame: calculate bounding box and step camera back enough to fit.
		local ok, pivotCF, extents = pcall(function(): (CFrame, Vector3)
			return clone:GetBoundingBox()
		end)
		if ok and pivotCF then
			local maxDim = math.max(extents.X, extents.Y, extents.Z)
			local dist   = math.max(maxDim * 1.5, 4)
			local height = dist * 0.4
			local pivot  = pivotCF.Position
			local angle  = 0

			if MotionUtil.reducedMotionEnabled() then
				-- Static angle under reduced motion.
				cam.CFrame = CFrame.lookAt(
					pivot + Vector3.new(dist * 0.7, height, dist * 0.7), pivot
				)
			else
				-- Orbit 60 °/s; cancelled in dismiss().
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

	-- ----------------------------------------------------------------
	-- TEXT BLOCK
	-- ----------------------------------------------------------------
	-- Perfect label — shows above the fish name whenever either phase was perfect.
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
			perfectLbl.Text = "PERFECT CATCH"      -- both phases nailed
		elseif reelPerfect then
			perfectLbl.Text = "PERFECT REEL"       -- reel mini-game only
		else
			perfectLbl.Text = "PRECISION CAST"     -- cast timing only
		end
		perfectLbl.Parent = card
		nameTopY = 24
	end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Position = UDim2.new(0, 108, 0, nameTopY)
	nameLbl.Size = UDim2.new(1, -120, 0, 28)
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 24
	nameLbl.TextColor3 = P.Cream
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = payload.fish.displayName or titleCase(payload.fish.id)
	nameLbl.Parent = card

	local weightLbl = Instance.new("TextLabel")
	weightLbl.BackgroundTransparency = 1
	weightLbl.Position = UDim2.new(0, 108, 0, nameTopY + 30)
	weightLbl.Size = UDim2.new(1, -120, 0, 18)
	weightLbl.Font = Enum.Font.GothamMedium
	weightLbl.TextSize = 16
	weightLbl.TextColor3 = P.CreamSoft
	weightLbl.TextXAlignment = Enum.TextXAlignment.Left
	weightLbl.Text = ("%.1f kg"):format(payload.weightKg or 0)
	weightLbl.Parent = card

	-- Coin label — shows the instant perfect-reel bonus if earned, otherwise
	-- shows the fish's market sell value as a reference.
	local coinLbl = Instance.new("TextLabel")
	coinLbl.BackgroundTransparency = 1
	coinLbl.AnchorPoint = Vector2.new(0, 1)
	coinLbl.Position = UDim2.new(0, 108, 1, -14)
	coinLbl.Size = UDim2.new(0, 180, 0, 22)
	coinLbl.Font = Enum.Font.GothamBold
	coinLbl.TextSize = 16
	coinLbl.TextXAlignment = Enum.TextXAlignment.Left
	local earned = payload.coinsEarned or 0
	if earned > 0 then
		coinLbl.TextColor3 = perfectColor   -- amber to match the perfect label
		coinLbl.Text = ("+%d coins bonus!"):format(earned)
	else
		coinLbl.TextColor3 = P.Gold
		coinLbl.Text = ("~%d coins"):format(payload.fish.basePrice or 0)
	end
	coinLbl.Parent = card

	-- ----------------------------------------------------------------
	-- MODIFIER PILLS — one pill per modifier id, below the weight label.
	-- Staggered fade-in (0.08s per pill). Capped at 3 visible; "+N" label.
	-- Each pill shows "Name • effect" (e.g. "Shiny • +25% sell").
	-- Skipped entirely if no modifiers.
	-- ----------------------------------------------------------------
	if #mods > 0 then
		local pillRow = Instance.new("Frame")
		pillRow.BackgroundTransparency = 1
		pillRow.Position = UDim2.new(0, 108, 0, nameTopY + 52)
		pillRow.Size = UDim2.new(1, -120, 0, 24)
		pillRow.Parent = card
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 4)
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Parent = pillRow

		local reduced = MotionUtil.reducedMotionEnabled()
		local maxVisible = math.min(#mods, 3)
		for i = 1, maxVisible do
			local modId = mods[i]
			local color = UIUtil.modifierColor(modId)
			local effectText = _modEffectText(modId)
			local labelText = (_modDisplayNames[modId] or modId) .. (effectText ~= "" and (" • " .. effectText) or "")
			local pill = Instance.new("Frame")
			pill.Size = UDim2.fromOffset(0, 22)
			pill.AutomaticSize = Enum.AutomaticSize.X
			pill.BackgroundColor3 = color
			pill.BackgroundTransparency = 1
			pill.BorderSizePixel = 0
			pill.LayoutOrder = i
			local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, UIUtil.Radii.sm); pc.Parent = pill
			local pp = Instance.new("UIPadding")
			pp.PaddingLeft  = UDim.new(0, UIUtil.Spacing.sm)
			pp.PaddingRight = UDim.new(0, UIUtil.Spacing.sm)
			pp.Parent = pill
			local pillLbl = UIUtil.makeLabel(labelText, "caption", {
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamBold,
				TextColor3 = P.Cream,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = 1,
				Parent = pill,
			})
			pill.Parent = pillRow
			if reduced then
				MotionUtil.tween(pill,    TweenInfo.new(0.2), { BackgroundTransparency = 0.25 })
				MotionUtil.tween(pillLbl, TweenInfo.new(0.2), { TextTransparency = 0 })
			else
				task.delay((i - 1) * 0.08, function()
					if not pill.Parent then return end
					MotionUtil.tween(pill,    TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.25 })
					MotionUtil.tween(pillLbl, TweenInfo.new(0.18), { TextTransparency = 0 })
				end)
			end
		end
		if #mods > 3 then
			UIUtil.makeLabel("+" .. (#mods - 3), "caption", {
				Size = UDim2.fromOffset(32, 22),
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 4,
				Parent = pillRow,
			})
		end
	end

	-- ----------------------------------------------------------------
	-- RARITY BADGE — small tier-tinted pill in the bottom-right corner.
	-- ----------------------------------------------------------------
	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Position = UDim2.new(1, -14, 1, -14)
	badge.Size = UDim2.fromOffset(96, 24)
	badge.BackgroundColor3 = tierColor
	badge.BorderSizePixel = 0
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = badge
	badge.Parent = card

	local badgeLbl = Instance.new("TextLabel")
	badgeLbl.BackgroundTransparency = 1
	badgeLbl.Size = UDim2.fromScale(1, 1)
	badgeLbl.Font = Enum.Font.GothamBold
	badgeLbl.TextSize = 12
	-- Dark text on light/gold backgrounds; light text on saturated dark backgrounds.
	local needsDarkText = rarity == "Common" or rarity == "Uncommon" or rarity == "Legendary" or rarity == "Divine"
	badgeLbl.TextColor3 = needsDarkText and P.Ink or P.Cream
	badgeLbl.Text = rarity:upper()
	badgeLbl.Parent = badge

	-- ----------------------------------------------------------------
	-- ANIMATED BORDER CYCLE — color ping-pong for Legendary, Mythic, Divine.
	-- Divine additionally oscillates stroke Thickness (3px ↔ 5px over 2s).
	-- Both tasks run for the card's lifetime and are killed in dismiss().
	-- ----------------------------------------------------------------
	local cycleTask: thread? = nil
	local thickTask: thread? = nil
	local cycleTarget = UIUtil.Palette.RarityCycle[rarity]
	if cycleTarget and not MotionUtil.reducedMotionEnabled() then
		cycleTask = task.spawn(function()
			local toTarget = true
			while card.Parent do
				local target = toTarget and cycleTarget or tierColor
				local tween = MotionUtil.tween(stroke, TweenInfo.new(FT.MythicBorderCycleDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Color = target })
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
					local tween = MotionUtil.tween(stroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Thickness = target })
					tween.Completed:Wait()
					tween:Destroy()
					toThick = not toThick
				end
			end)
		end
	end

	-- ----------------------------------------------------------------
	-- PERFECT SPARKLES — 1-second burst of tiny gold dots drifting up
	-- along the card border. We don't have a 2D ParticleEmitter, so we
	-- spawn ~10 short-lived Frames manually. Skipped under reduced motion.
	-- ----------------------------------------------------------------
	if (payload.perfect or payload.castPerfect) and not MotionUtil.reducedMotionEnabled() then
		task.spawn(function()
			for i = 1, 10 do
				if not card.Parent then return end
				local dot = Instance.new("Frame")
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				-- Spawn along the top edge, randomly distributed.
				dot.Position = UDim2.new(math.random(), math.random(-4, 4), 0, math.random(-2, 2))
				dot.Size = UDim2.fromOffset(4, 4)
				dot.BackgroundColor3 = perfectColor
				dot.BorderSizePixel = 0
				local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
				dot.ZIndex = 6
				dot.Parent = card
				local rise = MotionUtil.tween(dot, TweenInfo.new(0.7 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = dot.Position + UDim2.fromOffset(math.random(-12, 12), -30),
					BackgroundTransparency = 1,
				})
				rise.Completed:Connect(function() rise:Destroy(); dot:Destroy() end)
				task.wait(0.07)
			end
		end)
	end

	-- ----------------------------------------------------------------
	-- SLIDE IN — Back/Out for a satisfying overshoot. Reduced motion =
	-- fade in only.
	-- ----------------------------------------------------------------
	local restPosition = UDim2.new(0.5, 0, 1, -(110 + cardExtraH))
	if MotionUtil.reducedMotionEnabled() then
		card.Position = restPosition
		card.BackgroundTransparency = 1
		MotionUtil.tween(card, TweenInfo.new(0.25), { BackgroundTransparency = 0 })
	else
		MotionUtil.tween(card, TweenInfo.new(FT.RevealSlideInDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = restPosition,
		})
	end

	-- ----------------------------------------------------------------
	-- DISMISS — slide back down (or fade) and clean up tweens / cycle
	-- task / parent ScreenGui.
	-- ----------------------------------------------------------------
	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		if rotTask    then task.cancel(rotTask);    rotTask    = nil end
		if cycleTask  then task.cancel(cycleTask);  cycleTask  = nil end
		if thickTask  then task.cancel(thickTask);  thickTask  = nil end
		if MotionUtil.reducedMotionEnabled() then
			local fade = MotionUtil.tween(card, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
			fade.Completed:Connect(function() fade:Destroy(); gui:Destroy() end)
		else
			local slide = MotionUtil.tween(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, 0, 1, 240),
			})
			slide.Completed:Connect(function() slide:Destroy(); gui:Destroy() end)
		end
	end

	tapCatcher.Activated:Connect(dismiss)
	task.delay(FT.RevealAutoDismissAfter, dismiss)

	return {
		gui = gui,
		dismiss = dismiss,
	}
end

return CatchRevealUI
