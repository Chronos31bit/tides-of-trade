--!strict
-- AdminController.lua
-- Client half of the admin command system. Server (AdminService) parses
-- /commands and either applies them directly to player data or, for
-- per-player presentational concerns (fly mode, popup text), fires Knit
-- signals that this controller responds to.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local Knit              = require(ReplicatedStorage.Packages.Knit)
local UIUtil            = require(script.Parent.Parent.UI.UIUtil)

local AdminController = Knit.CreateController({
	Name = "AdminController",

	-- fly state
	_flying = false,
	_flyVelocity = nil :: BodyVelocity?,
	_flyGyro = nil :: BodyGyro?,
	_flyHeartbeat = nil :: RBXScriptConnection?,
	_flyInput = { fwd = 0, side = 0, up = 0 },

	-- announcement gui (singleton; reused for each announce)
	_announceGui = nil :: ScreenGui?,
	_announceLabel = nil :: TextLabel?,
	_announceClearTask = nil :: thread?,
})

local FLY_SPEED = 80     -- studs per second, feels good for surveying a harbor
local FLY_GYRO_POWER = 100_000   -- enough to make the character face camera-forward smoothly

-- ====================================================================
-- FLY MODE
-- We attach a BodyVelocity + BodyGyro to the HumanoidRootPart. The
-- BodyVelocity's vector is updated each Heartbeat based on WASD + Space
-- (up) + LeftControl (down), camera-relative. We also set
-- Humanoid.PlatformStand = true so the default ground physics don't fight us.
-- ====================================================================

function AdminController:_startFly()
	if self._flying then return end
	local char = Players.LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end
	self._flying = true

	humanoid.PlatformStand = true

	local bv = Instance.new("BodyVelocity")
	bv.Name = "AdminFlyVelocity"
	bv.MaxForce = Vector3.new(1, 1, 1) * 1e6
	bv.Velocity = Vector3.zero
	bv.P = 5000
	bv.Parent = hrp
	self._flyVelocity = bv

	local bg = Instance.new("BodyGyro")
	bg.Name = "AdminFlyGyro"
	bg.D = 100
	bg.P = FLY_GYRO_POWER
	bg.MaxTorque = Vector3.new(1, 1, 1) * 1e6
	bg.CFrame = hrp.CFrame
	bg.Parent = hrp
	self._flyGyro = bg

	self._flyHeartbeat = RunService.Heartbeat:Connect(function()
		if not self._flying or not self._flyVelocity then return end
		local cam = Workspace.CurrentCamera
		if not cam then return end
		-- Compose direction from input keys, then transform by camera-yaw so
		-- W = "forward where you're looking".
		local fwd  = self._flyInput.fwd
		local side = self._flyInput.side
		local up   = self._flyInput.up
		local lookFlat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
		local rightFlat = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit
		local dir = (lookFlat * fwd) + (rightFlat * side) + Vector3.new(0, up, 0)
		if dir.Magnitude > 0 then dir = dir.Unit end
		self._flyVelocity.Velocity = dir * FLY_SPEED
		-- Face camera forward so the avatar isn't sliding sideways.
		self._flyGyro.CFrame = CFrame.new(Vector3.zero, lookFlat)
	end)
end

function AdminController:_stopFly()
	if not self._flying then return end
	self._flying = false
	if self._flyHeartbeat then self._flyHeartbeat:Disconnect(); self._flyHeartbeat = nil end
	if self._flyVelocity then self._flyVelocity:Destroy(); self._flyVelocity = nil end
	if self._flyGyro then self._flyGyro:Destroy(); self._flyGyro = nil end
	local char = Players.LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.PlatformStand = false end
	self._flyInput = { fwd = 0, side = 0, up = 0 }
end

-- ====================================================================
-- ANNOUNCEMENT POPUP
-- Singleton ScreenGui that tweens text in, holds, tweens out. Multiple
-- announcements in a row replace the previous (latest wins) rather than
-- queuing — admin spam stays readable.
-- ====================================================================
function AdminController:_ensureAnnounceGui()
	if self._announceGui then return end
	local gui = UIUtil.makeScreenGui("AdminAnnouncement")
	self._announceGui = gui

	local panel = UIUtil.makePanel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -80),  -- starts off-screen above; tweens down
		Size = UDim2.new(0.7, 0, 0, 64),
		BackgroundColor3 = UIUtil.Palette.SunsetDeep,
	})
	local pcap = Instance.new("UISizeConstraint")
	pcap.MaxSize = Vector2.new(640, 64); pcap.Parent = panel
	panel.Parent = gui

	local label = UIUtil.makeLabel("", "title", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
	})
	label.Parent = panel
	self._announceLabel = label
end

function AdminController:_announce(text: string, duration: number)
	self:_ensureAnnounceGui()
	local panel = (self._announceGui :: ScreenGui):FindFirstChild("Banner") :: Frame
	if not panel or not self._announceLabel then return end
	self._announceLabel.Text = text

	-- Cancel any pending fade-out so the new message doesn't get hidden early.
	if self._announceClearTask then task.cancel(self._announceClearTask) end

	-- Slide in from above the screen.
	panel.Position = UDim2.new(0.5, 0, 0, -80)
	local slideIn = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(panel, slideIn, { Position = UDim2.new(0.5, 0, 0, 36) }):Play()

	self._announceClearTask = task.delay(duration, function()
		local slideOut = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(panel, slideOut, { Position = UDim2.new(0.5, 0, 0, -80) }):Play()
	end)
end

-- ====================================================================
-- INPUT BINDINGS — only active while flying. We use ContextActionService
-- via UserInputService.InputBegan/Ended so we don't permanently steal
-- keys.
-- ====================================================================
function AdminController:KnitStart()
	local AdminService = Knit.GetService("AdminService")

	AdminService.FlyToggled:Connect(function(on)
		if on then self:_startFly() else self:_stopFly() end
	end)

	AdminService.Announcement:Connect(function(text, duration)
		self:_announce(text, duration or 4)
	end)

	-- Always-listening input handlers. They only mutate _flyInput when in
	-- fly mode, so non-admin keyboard usage isn't affected.
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if not self._flying then return end
		if input.KeyCode == Enum.KeyCode.W then self._flyInput.fwd = 1
		elseif input.KeyCode == Enum.KeyCode.S then self._flyInput.fwd = -1
		elseif input.KeyCode == Enum.KeyCode.D then self._flyInput.side = 1
		elseif input.KeyCode == Enum.KeyCode.A then self._flyInput.side = -1
		elseif input.KeyCode == Enum.KeyCode.Space then self._flyInput.up = 1
		elseif input.KeyCode == Enum.KeyCode.LeftControl then self._flyInput.up = -1
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not self._flying then return end
		if input.KeyCode == Enum.KeyCode.W and self._flyInput.fwd > 0 then self._flyInput.fwd = 0
		elseif input.KeyCode == Enum.KeyCode.S and self._flyInput.fwd < 0 then self._flyInput.fwd = 0
		elseif input.KeyCode == Enum.KeyCode.D and self._flyInput.side > 0 then self._flyInput.side = 0
		elseif input.KeyCode == Enum.KeyCode.A and self._flyInput.side < 0 then self._flyInput.side = 0
		elseif input.KeyCode == Enum.KeyCode.Space and self._flyInput.up > 0 then self._flyInput.up = 0
		elseif input.KeyCode == Enum.KeyCode.LeftControl and self._flyInput.up < 0 then self._flyInput.up = 0
		end
	end)
end

return AdminController
