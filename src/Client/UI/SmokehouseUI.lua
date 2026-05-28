--!strict
-- SmokehouseUI.lua — Layout from StarterGuiAssets.SmokehouseUI_Template; behavior only.
-- SmokehouseService (SmokehouseController): SmokehouseChanged
-- Place / Cancel / Claim preserved fish; quest progress via server claim flow.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit = require(script.Parent.UIKit)
local UIUtil = require(script.Parent.UIUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local P, M = UIUtil.Palette, UIUtil.Modal
local PRESERVE_TIME = GameConfig.Buildings.Smokehouse.PreserveTimeSec

local SmokehouseUI = {}

export type SmokehouseHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (slots: {[number]: any}, inventory: {any}, capacity: number) -> (),
	destroy: () -> (),
}

local _layoutSkip = { UIListLayout = true, UIPadding = true, UICorner = true, UIStroke = true, UISizeConstraint = true }

local function req(parent: Instance, name: string, class: string): Instance
	local c = parent:FindFirstChild(name)
	if not c or not c:IsA(class) then
		error(`[SmokehouseUI] Missing {class} "{name}" under {parent:GetFullName()}`, 2)
	end
	return c
end

local function reqAny(parent: Instance, names: {string}, class: string): Instance
	for _, name in names do
		local c = parent:FindFirstChild(name)
		if c and c:IsA(class) then
			return c
		end
	end
	error(`[SmokehouseUI] Missing {class} ({table.concat(names, " | ")}) under {parent:GetFullName()}`, 2)
end

local function columnScroll(body: Frame, columnNames: {string}, scrollNames: {string}): ScrollingFrame
	local col = reqAny(body, columnNames, "Frame") :: Frame
	return reqAny(col, scrollNames, "ScrollingFrame") :: ScrollingFrame
end

local function metaNum(meta: Folder?, key: string, def: number): number
	local v = meta and meta:FindFirstChild(key)
	return (v and v:IsA("NumberValue")) and v.Value or def
end

local function catalogMaxSmokeSlots(): number
	local maxSlots = 10
	local sh = BuildingCatalog.Smokehouse
	if sh and sh.tiers then
		for _, t in ipairs(sh.tiers) do
			maxSlots = math.max(maxSlots, t.smokehouseSlots or 0)
		end
	end
	return math.max(1, maxSlots)
end

local function resolveSlotPoolCap(meta: Folder?, smokeColumnName: string): number
	local fromMeta = metaNum(meta, "MaxSmokehouseSlots", 0)
	if fromMeta >= 1 then
		return fromMeta
	end
	if smokeColumnName == "AquariumColumn" or metaNum(meta, "MaxAquariumCapacity", 0) >= 1 then
		return catalogMaxSmokeSlots()
	end
	return catalogMaxSmokeSlots()
end

local function patchColumnHeader(col: Frame, text: string)
	local hdr = col:FindFirstChild("ColumnHeader")
	if hdr and hdr:IsA("TextLabel") then
		hdr.Text = text
	end
end

local function titleCase(s: string): string
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

local function normalizeSlots(slots: {[any]: any}, capacity: number): {[number]: any}
	local out: {[number]: any} = {}
	for i = 1, capacity do
		out[i] = slots[i] or slots[tostring(i)]
	end
	return out
end

local function isSlotClaimable(slot: any): boolean
	if slot.ready == true then return true end
	if slot.startedAt then
		return os.time() - slot.startedAt >= PRESERVE_TIME
	end
	return false
end

local function formatCountdown(secondsLeft: number): string
	if secondsLeft <= 0 then return "Ready" end
	local m = math.floor(secondsLeft / 60)
	local s = secondsLeft % 60
	if m > 0 then return ("%dm %ds"):format(m, s) end
	return ("%ds"):format(s)
end

local function progress01(slot: any): number
	if isSlotClaimable(slot) then return 1 end
	if slot.startedAt then
		return math.clamp((os.time() - slot.startedAt) / PRESERVE_TIME, 0, 1)
	end
	return 0
end

local function findThumb(slot: Frame): ViewportFrame?
	local direct = slot:FindFirstChild("ThumbViewport")
	if direct and direct:IsA("ViewportFrame") then return direct end
	return nil
end

local function bindSmokeSlot(
	slot: Frame,
	index: number,
	data: any?,
	onCancel: (number) -> (),
	onClaim: (number) -> (),
	conns: {[TextButton]: RBXScriptConnection}
)
	local empty = req(slot, "EmptyHint", "TextLabel") :: TextLabel
	local nameLbl = reqAny(slot, { "FishNameLabel", "NameLabel" }, "TextLabel") :: TextLabel
	local btn = reqAny(slot, { "CollectButton", "ActionButton" }, "TextButton") :: TextButton
	local ring = req(slot, "ProgressRing", "Frame") :: Frame
	local fill = req(ring, "ProgressFill", "Frame") :: Frame
	local timeLbl = req(slot, "TimeLabel", "TextLabel") :: TextLabel
	local thumb = findThumb(slot)

	if not data then
		empty.Visible = true
		empty.Text = ("Slot %d — empty"):format(index)
		if thumb then thumb.Visible = false end
		ring.Visible = false
		timeLbl.Visible = false
		nameLbl.Visible = false
		btn.Visible = false
		return
	end

	empty.Visible = false
	nameLbl.Visible = true
	nameLbl.Text = titleCase(data.speciesId or "fish")
	if thumb then
		thumb.Visible = true
		UIKit.attachFishThumb(thumb, data.speciesId or "", { modifiers = data.modifiers or {}, scaleTarget = 1.4 })
	end

	if isSlotClaimable(data) then
		ring.Visible = true
		fill.Size = UDim2.fromScale(1, 1)
		timeLbl.Visible = true
		timeLbl.Text = "Preserved — ready to claim"
		btn.Visible = true
		btn.Text = "Claim"
		btn.BackgroundColor3 = P.TealLight
		if conns[btn] then conns[btn]:Disconnect() end
		conns[btn] = btn.Activated:Connect(function() onClaim(index) end)
	else
		ring.Visible = true
		local p = progress01(data)
		fill.Size = UDim2.fromScale(p, 1)
		timeLbl.Visible = true
		local left = PRESERVE_TIME - (os.time() - (data.startedAt or os.time()))
		timeLbl.Text = formatCountdown(left)
		btn.Visible = true
		btn.Text = "Cancel"
		btn.BackgroundColor3 = P.Wood
		if conns[btn] then conns[btn]:Disconnect() end
		conns[btn] = btn.Activated:Connect(function() onCancel(index) end)
	end
end

function SmokehouseUI.show(
	slots: {[number]: any},
	inventory: {any},
	capacity: number,
	onPlace: (string) -> (),
	onCancel: (number) -> (),
	onClaim: (number) -> (),
	onDismiss: (() -> ())?
): SmokehouseHandle
	local rm = MotionUtil.reducedMotionEnabled()
	local gui = TemplateLoader.spawn("Smokehouse", { instanceName = "SmokehouseUI" })
	local backdrop = req(gui, "Backdrop", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local header = req(panel, "Header", "Frame")
	local capLbl = req(header, "CapacityLabel", "TextLabel") :: TextLabel
	local collectAllBtn = header:FindFirstChild("CollectAllButton") :: TextButton?
	local closeBtn = req(header, "Close", "TextButton") :: TextButton
	local body = req(panel, "Body", "Frame") :: Frame
	local smokeScroll = columnScroll(body, { "SmokeColumn", "AquariumColumn" }, { "SmokeSlotGrid", "AquariumSlotGrid" })
	local invScroll = columnScroll(body, { "InventoryColumn" }, { "InventorySlotGrid" })
	local smokeCol = smokeScroll.Parent :: Frame
	patchColumnHeader(smokeCol, "SLOTS")
	patchColumnHeader(invScroll.Parent :: Frame, "INVENTORY (TAP TO SMOKE)")
	local slotTpl = reqAny(body, { "SmokeSlot_Template", "Slot_Template" }, "Frame") :: Frame
	local invTpl = body:FindFirstChild("InvFishRow_Template")
	local meta = if gui:FindFirstChild("Meta") and gui.Meta:IsA("Folder") then gui.Meta else nil
	local fadeDur = metaNum(meta, "FadeDuration", M.FadeDuration)
	local slidePx = metaNum(meta, "SlideOffsetPx", M.SlideOffsetPx)
	local maxCap = resolveSlotPoolCap(meta, smokeCol.Name)

	local closed = false
	local conns: {[TextButton]: RBXScriptConnection} = {}
	local smokeSlots: {Frame} = {}
	for i = 1, maxCap do
		local slot = slotTpl:Clone()
		slot.Name = ("SmokeSlot_%02d"):format(i)
		slot.LayoutOrder = i
		slot.Parent = smokeScroll
		smokeSlots[i] = slot
	end

	local lastSlots: {[number]: any} = normalizeSlots(slots, capacity)
	local lastInv: {any} = inventory
	local lastCap = capacity
	local claimUiRebuilt = false
	local heartbeatConn: RBXScriptConnection? = nil

	local restPos = panel.Position
	local fromPos = UDim2.new(restPos.X.Scale, restPos.X.Offset, restPos.Y.Scale, restPos.Y.Offset + slidePx)
	local fadeInfo = TweenInfo.new(fadeDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function destroy()
		if closed then return end
		closed = true
		if heartbeatConn then heartbeatConn:Disconnect() end
		for _, c in conns do c:Disconnect() end
		table.clear(conns)
		if gui.Parent then gui:Destroy() end
	end

	local function refresh(slots_: {[number]: any}, inv: {any}, cap_: number)
		slots_ = normalizeSlots(slots_, cap_)
		lastSlots, lastInv, lastCap = slots_, inv, cap_
		local used = 0
		for i = 1, cap_ do if slots_[i] then used += 1 end end
		capLbl.Text = ("%d / %d"):format(used, cap_)

		for i = 1, maxCap do
			local slot = smokeSlots[i]
			slot.Visible = i <= cap_
			if i <= cap_ then
				bindSmokeSlot(slot, i, slots_[i], onCancel, onClaim, conns)
			end
		end

		local anyReady = false
		for i = 1, cap_ do
			if slots_[i] and isSlotClaimable(slots_[i]) then anyReady = true break end
		end
		if collectAllBtn then
			collectAllBtn.Visible = anyReady
		end

		for _, c in invScroll:GetChildren() do
			if c:IsA("GuiObject") and not _layoutSkip[c.ClassName] then c:Destroy() end
		end
		local fish: {any} = {}
		for _, it in inv do if it.kind == "Fish" then table.insert(fish, it) end end
		if #fish == 0 then
			UIUtil.makeLabel("No fish in inventory.", "subtitle", {
				Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = P.CreamSoft, LayoutOrder = 1, Parent = invScroll,
			})
		else
			for i, it in fish do
				if invTpl and invTpl:IsA("Frame") then
					local row = invTpl:Clone()
					row.Name = "Inv_" .. (it.uid or i)
					row.Visible = true
					row.LayoutOrder = i
					row.Parent = invScroll
					local nm = titleCase(it.speciesId or "fish")
					reqAny(row, { "FishNameLabel", "NameLabel" }, "TextLabel").Text = nm .. "\n" .. ("%.1f kg"):format(it.weightKg or 0)
					local vpf = row:FindFirstChild("ThumbViewport")
					if vpf and vpf:IsA("ViewportFrame") then
						UIKit.attachFishThumb(vpf, it.speciesId or "", { modifiers = it.modifiers or {}, scaleTarget = 1.2 })
					end
					local smokeBtn = req(row, "SmokeButton", "TextButton") :: TextButton
					if conns[smokeBtn] then conns[smokeBtn]:Disconnect() end
					conns[smokeBtn] = smokeBtn.Activated:Connect(function() onPlace(it.uid) end)
				else
					local row = Instance.new("Frame")
					row.Size = UDim2.new(1, 0, 0, 56)
					row.BackgroundColor3 = P.TealDark
					row.LayoutOrder = i
					row.Parent = invScroll
					local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = row
					UIUtil.makeLabel(titleCase(it.speciesId or "fish"), "body", {
						Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -110, 0, 40),
						Font = Enum.Font.GothamBold, Parent = row,
					})
					local smokeBtn = UIUtil.makePrimaryButton("Smoke", function() onPlace(it.uid) end, {
						AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
						Size = UDim2.fromOffset(80, UIUtil.MinTouchPx), Parent = row,
					})
					if conns[smokeBtn] then conns[smokeBtn]:Disconnect() end
					conns[smokeBtn] = smokeBtn.Activated:Connect(function() onPlace(it.uid) end)
				end
			end
		end
	end

	if collectAllBtn then
		collectAllBtn.Activated:Connect(function()
			for i = 1, lastCap do
				local slot = lastSlots[i]
				if slot and isSlotClaimable(slot) then onClaim(i) end
			end
		end)
	end

	backdrop.Activated:Connect(function()
		if onDismiss then onDismiss() end
		destroy()
	end)
	closeBtn.Activated:Connect(function()
		if onDismiss then onDismiss() end
		destroy()
	end)

	panel.BackgroundTransparency = 1
	backdrop.BackgroundTransparency = 1
	if rm then
		panel.Position = restPos
		panel.BackgroundTransparency = 0
		backdrop.BackgroundTransparency = M.BackdropAlpha
	else
		panel.Position = fromPos
		MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = M.BackdropAlpha })
		MotionUtil.tweenOrSnap(panel, fadeInfo, { BackgroundTransparency = 0, Position = restPos })
	end

	refresh(slots, inventory, capacity)

	heartbeatConn = RunService.Heartbeat:Connect(function()
		if closed then return end
		local now = os.time()
		local needRebuild = false
		for i = 1, lastCap do
			local slot = lastSlots[i]
			if slot and slot.startedAt and not isSlotClaimable(slot) then
				local left = PRESERVE_TIME - (now - slot.startedAt)
				if left <= 0 then needRebuild = true end
			end
		end
		if needRebuild and not claimUiRebuilt then
			claimUiRebuilt = true
			refresh(lastSlots, lastInv, lastCap)
		elseif not needRebuild then
			claimUiRebuilt = false
			for i = 1, lastCap do
				local data = lastSlots[i]
				if data and smokeSlots[i] and smokeSlots[i].Visible and not isSlotClaimable(data) then
					local frame = smokeSlots[i]
					local fill = frame:FindFirstChild("ProgressRing")
						and (frame.ProgressRing :: Frame):FindFirstChild("ProgressFill")
					if fill and fill:IsA("Frame") then
						fill.Size = UDim2.fromScale(progress01(data), 1)
					end
					local tl = frame:FindFirstChild("TimeLabel")
					if tl and tl:IsA("TextLabel") and data.startedAt then
						tl.Text = formatCountdown(PRESERVE_TIME - (now - data.startedAt))
					end
				end
			end
		end
	end)

	return {
		gui = gui,
		close = destroy,
		destroy = destroy,
		refresh = refresh,
	}
end

return SmokehouseUI
