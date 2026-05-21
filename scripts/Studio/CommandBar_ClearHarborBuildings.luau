-- Command Bar: clear harbor building Visual models before MCP regen.
-- Edit KIND below, paste into Studio Command Bar, run once.

local KIND: string? = "Dock" -- "Dock", "Lighthouse", etc. or nil / "*" for all kinds

local RS = game:GetService("ReplicatedStorage")
local assets = RS:FindFirstChild("Assets")
if not assets then
	warn("[ClearHarborBuildings] No ReplicatedStorage.Assets")
	return
end
local buildings = assets:FindFirstChild("Buildings")
if not buildings then
	warn("[ClearHarborBuildings] No Assets.Buildings")
	return
end

local clearAll = KIND == nil or KIND == "*"
local cleared: {string} = {}

for _, kindFolder in buildings:GetChildren() do
	if not clearAll and kindFolder.Name ~= KIND then
		continue
	end
	if not kindFolder:IsA("Folder") then
		continue
	end
	for _, tierFolder in kindFolder:GetChildren() do
		local visual = tierFolder:FindFirstChild("Visual")
		if visual then
			table.insert(cleared, visual:GetFullName())
			visual:Destroy()
		end
	end
end

print(("[ClearHarborBuildings] Cleared %d Visual(s)%s"):format(
	#cleared,
	if clearAll then " (all kinds)" else (" for " .. KIND) end
))
for _, path in cleared do
	print("  ", path)
end
