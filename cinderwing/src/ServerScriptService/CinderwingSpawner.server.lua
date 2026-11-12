-- Secret spawn for the Cinderwing. Rolls a small chance on a timer and, when it
-- hits, drops a dormant dragon somewhere inside the volcanic zone. A player who
-- finds it and holds the prompt becomes the dragon.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local folder = ReplicatedStorage:WaitForChild("Cinderwing")
local Config = require(folder.Config)
local Rig = require(folder.Rig)
local Builder = require(folder.Builder)

local setFlying = Instance.new("RemoteEvent")
setFlying.Name = "SetFlying"
setFlying.Parent = folder

local rng = Random.new()
local wild = {} -- unclaimed dragons
local warnedNoZone = false

local function findZones()
	local zones = CollectionService:GetTagged(Config.ZoneTag)
	if #zones == 0 then
		for _, name in Config.ZoneNames do
			local zone = Workspace:FindFirstChild(name, true)
			if zone then
				table.insert(zones, zone)
				break
			end
		end
	end
	return zones
end

-- Parts whose footprint we can drop a dragon onto.
local function zoneSurfaces(zone)
	if zone:IsA("BasePart") then
		return { zone }
	end
	local surfaces = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and d.Size.X >= 30 and d.Size.Z >= 30 then
			table.insert(surfaces, d)
		end
	end
	return surfaces
end

local function pickSpawnCFrame()
	local zones = findZones()
	if #zones == 0 then
		if not warnedNoZone then
			warnedNoZone = true
			warn(`[Cinderwing] No volcanic zone found. Tag a part or model "{Config.ZoneTag}" or name it one of Config.ZoneNames.`)
		end
		return nil
	end
	local surfaces = zoneSurfaces(zones[rng:NextInteger(1, #zones)])
	if #surfaces == 0 then
		return nil
	end

	local params = RaycastParams.new()
	params.RespectCanCollide = true -- lets a non-collidable marker part define the zone
	local exclude = CollectionService:GetTagged(Config.Tag)
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	params.FilterDescendantsInstances = exclude

	for _ = 1, 25 do
		local surface = surfaces[rng:NextInteger(1, #surfaces)]
		local size = surface.Size
		local point = surface.CFrame:PointToWorldSpace(Vector3.new((rng:NextNumber() - 0.5) * size.X * 0.8, 0, (rng:NextNumber() - 0.5) * size.Z * 0.8))
		local hit = Workspace:Raycast(point + Vector3.new(0, size.Magnitude / 2 + 300, 0), Vector3.new(0, -2000, 0), params)
		if hit and hit.Normal.Y > 0.8 and hit.Material ~= Enum.Material.Water then
			local standHeight = Rig.HipHeight + Rig.RootSize.Y / 2
			return CFrame.new(hit.Position + Vector3.new(0, standHeight, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
		end
	end
	return nil
end

local function morph(player, model)
	local root = model.PrimaryPart
	local old = player.Character
	wild[model] = nil
	model:SetAttribute("Wild", nil)
	local prompt = root:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt:Destroy()
	end
	model.Name = player.Name
	root.Anchored = false
	player.Character = model
	if old and old ~= model then
		old:Destroy()
	end
	root:SetNetworkOwner(player)
end

local function spawnWild(cf)
	cf = cf or pickSpawnCFrame()
	if not cf then
		return nil
	end
	local model = Builder.build()
	local root = model.PrimaryPart
	root.Anchored = true
	model:PivotTo(cf)
	model:SetAttribute("Wild", true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Bond"
	prompt.ObjectText = Config.ModelName
	prompt.HoldDuration = Config.ClaimHoldTime
	prompt.MaxActivationDistance = Config.ClaimDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if wild[model] and humanoid and humanoid.Health > 0 then
			morph(player, model)
		end
	end)

	wild[model] = true
	model.Parent = Workspace

	task.delay(Config.WildLifetime, function()
		if wild[model] then
			wild[model] = nil
			model:Destroy()
		end
	end)
	return model
end

setFlying.OnServerEvent:Connect(function(player, flying)
	local character = player.Character
	if typeof(flying) == "boolean" and character and character:HasTag(Config.Tag) then
		character:SetAttribute("Flying", flying)
	end
end)

if Config.DebugMorphOnJoin then
	local function onCharacter(player, character)
		if character:HasTag(Config.Tag) then
			return
		end
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		task.wait(0.5)
		if player.Character ~= character then
			return
		end
		local model = spawnWild(CFrame.new(root.Position + Vector3.new(0, Rig.HipHeight + 2, 0)))
		morph(player, model)
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
end

task.spawn(function()
	if Config.DebugSpawnOnStart then
		spawnWild()
	end
	while true do
		task.wait(Config.SpawnCheckInterval)
		local count = 0
		for _ in wild do
			count += 1
		end
		if count < Config.MaxWild and rng:NextNumber() < Config.SpawnChance then
			spawnWild()
		end
	end
end)
