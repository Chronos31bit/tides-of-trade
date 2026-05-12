--!strict
-- AquariumController.lua
-- Listens for ProximityPrompt activations on aquarium parts. Opens the
-- AquariumUI for that specific aquarium. Subscribes to AquariumChanged so
-- the open panel updates live (e.g. when a deposit completes server-side).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local AquariumUI = require(script.Parent.Parent.UI.AquariumUI)
local UIUtil = require(script.Parent.Parent.UI.UIUtil)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)

local AquariumController = Knit.CreateController({
	Name = "AquariumController",
	_handle = nil :: any,
	_currentUid = nil :: string?,
	_toastGui = nil :: ScreenGui?,
	_toastLabel = nil :: TextLabel?,
	_toastClearTask = nil :: thread?,
})

local function capacityForBuilding(kind: string, tier: number): number
	local def = BuildingCatalog[kind]
	if not def then return 0 end
	local t = def.tiers[tier]
	return (t and t.aquariumCapacity) or 0
end

-- ====================================================================
-- INCOME TOAST — small slide-in from the bottom-left so the player can
-- see passive income arriving. Reuses one ScreenGui for every income
-- event to avoid garbage and to handle rapid ticks cleanly.
-- ====================================================================
function AquariumController:_ensureToast()
	if self._toastGui then return end
	local gui = UIUtil.makeScreenGui("AquariumIncomeToast", nil, { respectTopbar = true })
	self._toastGui = gui

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0, 1)
	toast.Position = UDim2.new(0, 16, 1, 100)  -- starts off-screen below
	toast.Size = UDim2.fromOffset(280, 52)
	toast.BackgroundColor3 = UIUtil.Palette.Rare
	toast.BorderSizePixel = 0
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = toast
	toast.Parent = gui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 12, 0, 0)
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = UIUtil.Palette.Cream
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = toast
	self._toastLabel = label
end

function AquariumController:_showToast(coins: number, xp: number, fishCount: number)
	self:_ensureToast()
	local toast = (self._toastGui :: ScreenGui):FindFirstChild("Toast") :: Frame
	if not toast or not self._toastLabel then return end
	if self._toastClearTask then task.cancel(self._toastClearTask) end

	-- Compose the message: lead with coins, mention xp only if positive.
	if xp > 0 then
		self._toastLabel.Text = ("Aquarium: +%d coins, +%d xp  (%d fish)"):format(coins, xp, fishCount)
	else
		self._toastLabel.Text = ("Aquarium: +%d coins  (%d fish)"):format(coins, fishCount)
	end

	toast.Position = UDim2.new(0, 16, 1, 100)
	local slideIn = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(toast, slideIn, { Position = UDim2.new(0, 16, 1, -120) }):Play()

	self._toastClearTask = task.delay(4, function()
		local slideOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(toast, slideOut, { Position = UDim2.new(0, 16, 1, 100) }):Play()
	end)
end

function AquariumController:KnitStart()
	local AquariumService = Knit.GetService("AquariumService")

	-- Passive income feedback — shown to the player every income tick.
	AquariumService.IncomeEarned:Connect(function(coins, xp, fishCount)
		self:_showToast(coins or 0, xp or 0, fishCount or 0)
	end)

	-- ProximityPrompt fires on the part the prompt is parented to. We use
	-- the part's name (= building uid) to identify which aquarium.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, _player)
		if prompt.ActionText ~= "Open Aquarium" then return end
		local part = prompt.Parent :: BasePart
		if not part or not part:IsA("BasePart") then return end
		local kind = part:GetAttribute("kind")
		local tier = part:GetAttribute("tier")
		if kind ~= "Aquarium" then return end
		self:Open(part.Name, capacityForBuilding(kind, tier or 1))
	end)

	-- Live updates if server pushes a change.
	AquariumService.AquariumChanged:Connect(function(uid, contents)
		if self._handle and self._currentUid == uid then
			-- Pull current inventory snapshot to refresh the right column too.
			local PlayerDataService = Knit.GetService("PlayerDataService")
			PlayerDataService:GetSnapshot():andThen(function(snap)
				local inv = (snap and snap.inventory) or {}
				local cap = self:_capacityFor(snap, uid)
				self._handle.refresh(contents, inv, cap)
			end)
		end
	end)

	-- Keyboard shortcut for PC players: Q opens the *first* aquarium they own.
	-- Faster than walking up to the prompt during testing.
	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Q then
			self:OpenFirstOwned()
		end
	end)
end

-- Look up capacity from the live snapshot — preferred over the cached
-- catalog value because tier upgrades shouldn't require re-opening UI.
function AquariumController:_capacityFor(snap: any, uid: string): number
	if not snap then return 0 end
	for _, b in ipairs(snap.buildings or {}) do
		if b.uid == uid and b.kind == "Aquarium" then
			return capacityForBuilding(b.kind, b.tier)
		end
	end
	return 0
end

function AquariumController:Open(aquariumUid: string, capacity: number)
	local AquariumService = Knit.GetService("AquariumService")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local snap = PlayerDataService:GetSnapshot():expect()
	local inv = (snap and snap.inventory) or {}
	AquariumService:GetContents(aquariumUid):andThen(function(contents)
		contents = contents or {}
		if self._handle then self._handle.close() end
		self._currentUid = aquariumUid
		self._handle = AquariumUI.show(contents, inv, capacity,
			function(itemUid)
				AquariumService:Deposit(aquariumUid, itemUid):andThen(function(res)
					if not res.ok then warn("[Aquarium] deposit:", res.reason) end
				end)
			end,
			function(itemUid)
				AquariumService:Withdraw(aquariumUid, itemUid):andThen(function(res)
					if not res.ok then warn("[Aquarium] withdraw:", res.reason) end
				end)
			end
		)
	end)
end

function AquariumController:OpenFirstOwned()
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local snap = PlayerDataService:GetSnapshot():expect()
	if not snap then return end
	for _, b in ipairs(snap.buildings or {}) do
		if b.kind == "Aquarium" then
			self:Open(b.uid, capacityForBuilding(b.kind, b.tier))
			return
		end
	end
	print("[Aquarium] You don't own an aquarium yet. Build one in Build mode (B).")
end

return AquariumController
