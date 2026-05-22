--!strict
-- ScreenGuiAutoScale.lua — viewport UIScale binding shared by UIKit.makeScreenGui and TemplateLoader.

local DESIGN_HEIGHT = 720
local MIN_PHONE_WIDTH = 380

local ScreenGuiAutoScale = {}

function ScreenGuiAutoScale.apply(gui: ScreenGui): UIScale
	local existing = gui:FindFirstChild("AutoScale")
	local scale: UIScale
	if existing and existing:IsA("UIScale") then
		scale = existing
	else
		scale = Instance.new("UIScale")
		scale.Name = "AutoScale"
		scale.Parent = gui
	end

	local connections: { RBXScriptConnection } = {}

	local function refresh()
		local cam = workspace.CurrentCamera
		if not cam then
			scale.Scale = 1
			return
		end
		local size = cam.ViewportSize
		if size.X <= 1 or size.Y <= 1 then
			scale.Scale = 1
			return
		end
		local s = size.Y / DESIGN_HEIGHT
		if size.X < MIN_PHONE_WIDTH * s then
			s = s * (MIN_PHONE_WIDTH / math.max(size.X, 1))
		end
		scale.Scale = math.clamp(s, 0.35, 2)
	end

	local function bindCamera(cam: Camera)
		table.insert(connections, cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh))
		refresh()
	end

	local cam = workspace.CurrentCamera
	if cam then
		bindCamera(cam)
	else
		scale.Scale = 1
		local conn: RBXScriptConnection? = nil
		conn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			local c = workspace.CurrentCamera
			if not c then return end
			if conn then conn:Disconnect(); conn = nil end
			bindCamera(c)
		end)
		table.insert(connections, conn)
	end

	gui.Destroying:Connect(function()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end)

	return scale
end

return ScreenGuiAutoScale
