--!strict
-- HarborEditUI.lua — Layout from StarterGuiAssets.HarborEditUI_Template; behavior only.
-- HarborService (HarborEditController): Place, Upgrade, Remove; catalog from BuildingCatalog.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit = require(script.Parent.UIKit)
local UIUtil = require(script.Parent.UIUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local P = UIUtil.Palette
local SP = UIUtil.Spacing

local HarborEditUI = {}

export type HarborEditHandle = {
	gui: ScreenGui,
	close: () -> (),
	setHint: (text: string) -> (),
	setRotationHint: (degrees: number) -> (),
	setDemolishActive: (active: boolean) -> (),
	setUpgradeActive: (active: boolean) -> (),
}

local function req(parent: Instance, name: string, class: string): Instance
	local c = parent:FindFirstChild(name)
	if not c or not c:IsA(class) then
		error(`[HarborEditUI] Missing {class} "{name}" under {parent:GetFullName()}`, 2)
	end
	return c
end

local function rotationSuffix(degrees: number): string
	return ("  ·  facing %d°"):format(degrees % 360)
end

local function tierCost(kind: string, tier: number): number
	local cfg = GameConfig.Buildings[kind]
	return (cfg and cfg.tierCosts and cfg.tierCosts[tier]) or 0
end

local function fillTierBadges(badges: Frame, maxTier: number)
	for i = 1, 3 do
		local pip = badges:FindFirstChild("Tier" .. i)
		if pip and pip:IsA("Frame") then
			local pal = UIKit.tierPalette(i, maxTier)
			pip.BackgroundColor3 = if i <= maxTier then pal.accent else P.TealDeeper
			pip.BackgroundTransparency = if i <= maxTier then 0 else 0.5
		end
	end
end

local function bindBuildingRow(
	row: TextButton,
	kind: string,
	def: any,
	onSelect: (string) -> (),
	setHint: (string) -> ()
)
	local kindVal = row:FindFirstChild("BuildingKind")
	if kindVal and kindVal:IsA("StringValue") then
		kindVal.Value = kind
	end
	req(row, "NameLabel", "TextLabel").Text = def.displayName
	req(row, "FootprintLabel", "TextLabel").Text = ("%d × %d cells"):format(def.footprint[1], def.footprint[2])
	local tier1 = tierCost(kind, 1)
	req(row, "CostLabel", "TextLabel").Text = if tier1 == 0 then "FREE" else (`{tier1} coins`)
	fillTierBadges(req(row, "TierBadges", "Frame") :: Frame, #def.tiers)
	UIKit.attachBuildingThumb(req(row, "ThumbnailViewport", "ViewportFrame") :: ViewportFrame, kind, 1, def.footprint)
	UIKit.skinActionButton(row, P.Teal)
	row.Activated:Connect(function()
		onSelect(kind)
		setHint(("%s — %s  (tap Rotate, then Place)"):format(def.displayName, def.description))
	end)
end

function HarborEditUI.show(
	catalog: any,
	onSelect: (string) -> (),
	onRotate: () -> (),
	onConfirm: () -> (),
	onDemolish: () -> (),
	onUpgrade: () -> (),
	onCancel: () -> ()
): HarborEditHandle
	local gui = TemplateLoader.spawn("HarborEdit", { instanceName = "HarborEditUI" })
	local hintBanner = req(gui, "HintBanner", "Frame") :: Frame
	local hintLabel = req(hintBanner, "HintLabel", "TextLabel") :: TextLabel
	local rotateBtn = req(hintBanner, "RotateButton", "TextButton") :: TextButton
	local actions = req(gui, "ActionStack", "Frame") :: Frame
	local placeBtn = req(actions, "PlaceButton", "TextButton") :: TextButton
	local upgradeBtn = req(actions, "UpgradeButton", "TextButton") :: TextButton
	local demolishBtn = req(actions, "DemolishButton", "TextButton") :: TextButton
	local cancelBtn = req(actions, "CancelButton", "TextButton") :: TextButton
	local scroll = req(req(gui, "BuildingPalette", "Frame"), "BuildingScroll", "ScrollingFrame") :: ScrollingFrame
	local rowTpl = req(gui, "BuildingRow_Template", "TextButton") :: TextButton

	UIKit.skinActionButton(placeBtn, P.Sunset)
	UIKit.skinUpgradeButton(upgradeBtn, P.Gold)
	UIKit.skinActionButton(demolishBtn, P.Danger)
	UIKit.skinActionButton(cancelBtn, P.Wood)
	UIKit.skinActionButton(rotateBtn, P.Wood)

	local sorted: {{ kind: string, def: any }} = {}
	for kind, def in pairs(catalog) do
		table.insert(sorted, { kind = kind, def = def })
	end
	table.sort(sorted, function(a, b)
		local ca, cb = tierCost(a.kind, 1), tierCost(b.kind, 1)
		if ca ~= cb then
			return ca < cb
		end
		return (a.def.displayName or a.kind) < (b.def.displayName or b.kind)
	end)

	local function setHint(text: string)
		hintLabel.Text = text
	end

	for i, entry in ipairs(sorted) do
		local row = rowTpl:Clone()
		row.Name = "Row_" .. entry.kind
		row.Visible = true
		row.LayoutOrder = i
		row.Parent = scroll
		bindBuildingRow(row, entry.kind, entry.def, onSelect, setHint)
	end

	local demolishRest = P.Danger:Lerp(Color3.new(0, 0, 0), 0.25)
	local upgradeRest = P.Gold:Lerp(Color3.new(0, 0, 0), 0.25)

	rotateBtn.Activated:Connect(onRotate)
	placeBtn.Activated:Connect(onConfirm)
	upgradeBtn.Activated:Connect(onUpgrade)
	demolishBtn.Activated:Connect(onDemolish)
	cancelBtn.Activated:Connect(function()
		onCancel()
		gui:Destroy()
	end)

	return {
		gui = gui,
		close = function()
			if gui.Parent then gui:Destroy() end
		end,
		setHint = setHint,
		setRotationHint = function(degrees: number)
			local base = hintLabel.Text
			local cut = base:find("  ·  facing ")
			if cut then base = base:sub(1, cut - 1) end
			hintLabel.Text = base .. rotationSuffix(degrees)
		end,
		setDemolishActive = function(active: boolean)
			demolishBtn.BackgroundColor3 = if active then P.Danger else demolishRest
			demolishBtn.Text = if active then "Cancel Demolish" else "Demolish"
			if active then setHint("Click a placed building to remove it.") end
		end,
		setUpgradeActive = function(active: boolean)
			upgradeBtn.BackgroundColor3 = if active then P.Gold else upgradeRest
			upgradeBtn.Text = if active then "Cancel Upgrade" else "Upgrade"
			if active then setHint("Click a placed building to upgrade it (costs coins).") end
		end,
	}
end

function HarborEditUI.showDemolishConfirm(kind: string, onConfirm: () -> (), onCancel: (() -> ())?)
	local shell
	shell = UIKit.ModalShell({
		name = "DemolishConfirm",
		title = "Demolish " .. kind .. "?",
		onClose = function()
			if shell then shell.destroy() end
			if onCancel then onCancel() end
		end,
		width = 400,
		heightScale = 0.34,
	})
	local body = shell.body
	UIUtil.makeLabel(
		"This is permanent and you won't get the coins back.",
		"body",
		{
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, -UIUtil.MinTouchPx - SP.md),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = P.CreamSoft,
			Parent = body,
		}
	)
	local cancelBtn = UIUtil.makeGhostButton("Cancel", function()
		shell.destroy()
		if onCancel then onCancel() end
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.fromOffset(140, UIUtil.MinTouchPx),
	})
	cancelBtn.Parent = body
	local confirmBtn = UIUtil.makeDangerButton("Demolish", function()
		shell.destroy()
		onConfirm()
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(140, UIUtil.MinTouchPx),
	})
	confirmBtn.Parent = body
end

return HarborEditUI
