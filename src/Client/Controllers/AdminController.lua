--!strict
-- AdminController.lua
-- Client half of the admin command system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local Knit              = require(ReplicatedStorage.Packages.Knit)
local GameConfig        = require(ReplicatedStorage.Shared.Config.GameConfig)
local Trove             = require(ReplicatedStorage.Packages.Trove)
local UIUtil            = require(script.Parent.Parent.UI.UIUtil)
local AdminWeatherUI    = require(script.Parent.Parent.UI.AdminWeatherUI)

local ATTR_WEATHER = GameConfig.Weather.WorkspaceAttribute
local REMOTES_FOLDER = "TidesRemotes"
local REMOTE_FORCE_WEATHER = "ForceWeather"

local AdminController = Knit.CreateController({
	Name = "AdminController",
	_flying = false,
	_flyVelocity = nil :: BodyVelocity?,
	_flyGyro = nil :: BodyGyro?,
	_flyHeartbeat = nil :: RBXScriptConnection?,
	_flyInput = { fwd = 0, side = 0, up = 0 },
	_announceGui = nil :: ScreenGui?,
	_announceLabel = nil :: TextLabel?,
	_announceClearTask = nil :: thread?,
	_weatherUi = nil :: AdminWeatherUI.AdminWeatherUI?,
	_adminTrove = nil :: any,
	_lastRequestedWeather = nil :: string?,
})

local FLY_SPEED = 80
local FLY_GYRO_POWER = 100_000

local function readAttrWeather(): string
	local v = Workspace:GetAttribute(ATTR_WEATHER)
	return if type(v) == "string" then v else "?"
end

local function getForceWeatherRemote(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER)
	local remote = folder and folder:FindFirstChild(REMOTE_FORCE_WEATHER)
	return if remote and remote:IsA("RemoteEvent") then remote else nil
end

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
		local fwd  = self._flyInput.fwd
		local side = self._flyInput.side
		local up   = self._flyInput.up
		local lookFlat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
		local rightFlat = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit
		local dir = (lookFlat * fwd) + (rightFlat * side) + Vector3.new(0, up, 0)
		if dir.Magnitude > 0 then dir = dir.Unit end
		self._flyVelocity.Velocity = dir * FLY_SPEED
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

function AdminController:_ensureAnnounceGui()
	if self._announceGui then return end
	local gui = UIUtil.makeScreenGui("AdminAnnouncement")
	self._announceGui = gui
	local panel = UIUtil.makePanel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -80),
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
	if self._announceClearTask then
		pcall(task.cancel, self._announceClearTask)
	end
	panel.Position = UDim2.new(0.5, 0, 0, -80)
	TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 36),
	}):Play()
	self._announceClearTask = task.delay(duration, function()
		TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -80),
		}):Play()
		self._announceClearTask = nil
	end)
end

function AdminController:_updateStatusFromAttr(locked: boolean?, mismatch: boolean?)
	if not self._weatherUi then return end
	local attr = readAttrWeather()
	local lockedVal = if locked ~= nil then locked else (Workspace:GetAttribute(GameConfig.Weather.WorkspaceLockedAttribute) == true)
	self._weatherUi.setStatus(attr, lockedVal, attr, mismatch)
end

function AdminController:_checkAttrMismatch(requested: string)
	task.delay(0.25, function()
		if not self._weatherUi or self._lastRequestedWeather ~= requested then return end
		local attr = readAttrWeather()
		local mismatch = attr ~= requested
		if RunService:IsStudio() then
			print(("[AdminController] weather requested=%s attr=%s mismatch=%s"):format(
				requested, attr, tostring(mismatch)
			))
		end
		self:_updateStatusFromAttr(true, mismatch)
		if mismatch then
			self:_announce(("Attr still %s (wanted %s)"):format(attr, requested), 3)
		end
	end)
end

function AdminController:_refreshWeatherStatus()
	local WeatherService = Knit.GetService("WeatherService")
	WeatherService:GetWeatherState():andThen(function(payload: { weather: string, timeOfDay: string })
		local locked = Workspace:GetAttribute(GameConfig.Weather.WorkspaceLockedAttribute) == true
		self:_updateStatusFromAttr(locked, false)
	end):catch(function(err)
		warn("[AdminController] GetWeatherState failed:", err)
	end)
end

function AdminController:_setWeather(weather: string)
	self._lastRequestedWeather = weather
	if RunService:IsStudio() then
		print(("[AdminController] requesting weather=%s"):format(weather))
	end

	local remote = getForceWeatherRemote()
	if remote then
		remote:FireServer(weather, true)
	end

	local WeatherService = Knit.GetService("WeatherService")
	WeatherService:ForceWeather(weather, true):andThen(function(res: any)
		if type(res) ~= "table" then
			warn("[AdminController] ForceWeather unexpected return:", res, typeof(res))
			self:_announce("Weather RPC returned unexpected data — see Output", 3)
			return
		end
		if res.ok and res.weather then
			self:_announce(("Weather → %s (locked)"):format(res.weather), 2)
			if RunService:IsStudio() then
				print(("[AdminController] ForceWeather ok → %s"):format(res.weather))
			end
		elseif res.reason then
			self:_announce(("Weather failed: %s"):format(res.reason), 3)
			warn("[AdminController] ForceWeather:", res.reason)
		end
		self:_checkAttrMismatch(weather)
	end):catch(function(err)
		warn("[AdminController] ForceWeather failed:", err)
		self:_announce("Weather RPC failed — see Output", 3)
	end)

	self:_checkAttrMismatch(weather)
end

function AdminController:_setWeatherAuto()
	local AdminService = Knit.GetService("AdminService")
	AdminService:SetWeatherAuto():andThen(function(res: { ok: boolean, reason: string?, weather: string? })
		if res.ok and res.weather then
			self:_announce(("Weather auto (now %s)"):format(res.weather), 2)
			self:_updateStatusFromAttr(false, false)
		elseif res.reason then
			self:_announce(("Weather auto failed: %s"):format(res.reason), 3)
		end
	end):catch(function(err)
		warn("[AdminController] SetWeatherAuto failed:", err)
	end)
end

function AdminController:_toggleWeatherPanel()
	if not self._weatherUi then return end
	local show = not self._weatherUi.isPanelVisible()
	self._weatherUi.setPanelVisible(show)
	if show then
		self:_refreshWeatherStatus()
	end
end

function AdminController:_initWeatherPanel()
	self._weatherUi = AdminWeatherUI.build(
		function(weather: string) self:_setWeather(weather) end,
		function() self:_setWeatherAuto() end,
		function() self:_toggleWeatherPanel() end
	)

	local openInStudio = RunService:IsStudio() and GameConfig.Admin.OpenWeatherPanelInStudio
	self._weatherUi.setPanelVisible(openInStudio)
	self:_refreshWeatherStatus()

	self._adminTrove:Add(Workspace:GetAttributeChangedSignal(ATTR_WEATHER):Connect(function()
		self:_updateStatusFromAttr(nil, false)
	end))

	self._adminTrove:Add(Workspace:GetAttributeChangedSignal(GameConfig.Weather.WorkspaceLockedAttribute):Connect(function()
		self:_updateStatusFromAttr(nil, false)
	end))

	local WeatherService = Knit.GetService("WeatherService")
	self._adminTrove:Add(WeatherService.WeatherChanged:Connect(function()
		self:_updateStatusFromAttr(nil, false)
	end))

	if RunService:IsStudio() then
		print(("[AdminController] Weather admin ready — %d states: %s"):format(
			#GameConfig.Admin.WeatherStates,
			table.concat(GameConfig.Admin.WeatherStates, ", ")
		))
	end
end

function AdminController:KnitStart()
	local AdminService = Knit.GetService("AdminService")
	self._adminTrove = Trove.new()

	AdminService:IsAdmin():andThen(function(isAdmin: boolean)
		if not isAdmin then
			if RunService:IsStudio() then
				warn("[AdminController] Not admin — add your UserId to ADMIN_USER_IDS in AdminService.lua")
			end
			return
		end
		self:_initWeatherPanel()

		ContextActionService:BindAction(
			"TidesAdminWeatherToggle",
			function(_name, state)
				if state == Enum.UserInputState.Begin then
					self:_toggleWeatherPanel()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.KeyCode.F8
		)
		self._adminTrove:Add(function()
			ContextActionService:UnbindAction("TidesAdminWeatherToggle")
		end)
	end):catch(function(err)
		warn("[AdminController] IsAdmin failed:", err)
	end)

	AdminService.FlyToggled:Connect(function(on)
		if on then self:_startFly() else self:_stopFly() end
	end)

	AdminService.Announcement:Connect(function(text, duration)
		self:_announce(text, duration or 4)
	end)

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
