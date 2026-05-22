-- Command bar: build ReplicatedStorage.Assets.Animations for SocialController.
-- Paste into Studio command bar (edit mode, not Play Solo).
-- Safe to re-run — replaces each named Animation instance.

local EMOTES: {{string}} = {
	{ "wave", "rbxassetid://507770239" },
	{ "dance", "rbxassetid://507771019" },
	{ "fish_pose", "rbxassetid://507768375" },
	{ "salute", "rbxassetid://507770453" },
	{ "bow", "rbxassetid://507771696" },
}

local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

local RS = game:GetService("ReplicatedStorage")
local assets = ensureFolder(RS, "Assets")
local animFolder = ensureFolder(assets, "Animations")

for _, entry in ipairs(EMOTES) do
	local name, animId = entry[1], entry[2]
	local existing = animFolder:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local anim = Instance.new("Animation")
	anim.Name = name
	anim.AnimationId = animId
	anim.Parent = animFolder
end

print("[SetupEmoteAnimations] Done — ReplicatedStorage.Assets.Animations:")
for _, child in ipairs(animFolder:GetChildren()) do
	if child:IsA("Animation") then
		print(("  %s (%s)"):format(child.Name, child.AnimationId))
	end
end
