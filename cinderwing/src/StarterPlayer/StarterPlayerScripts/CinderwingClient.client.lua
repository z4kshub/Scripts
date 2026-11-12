-- Client side of the Cinderwing: animates every dragon in view and, when the
-- local player is one, replaces jumping with camera-relative flight.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local folder = ReplicatedStorage:WaitForChild("Cinderwing")
local Config = require(folder:WaitForChild("Config"))
local Rig = require(folder:WaitForChild("Rig"))
local Animator = require(folder:WaitForChild("Animator"))
local setFlying = folder:WaitForChild("SetFlying")

local player = Players.LocalPlayer
local STAND_HEIGHT = Rig.HipHeight + Rig.RootSize.Y / 2
local ANIMATE_DISTANCE = 900

local flight = {
	active = false,
	model = nil,
	velocity = Vector3.zero,
	heading = Vector3.new(0, 0, -1),
	startedAt = 0,
	lastToggle = 0,
}

-- Animation ------------------------------------------------------------------
local animators = {}

local function track(model)
	if model:IsA("Model") and not animators[model] then
		local animator = Animator.new(model)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { model }
		params.RespectCanCollide = true
		animators[model] = { animator = animator, params = params, lastBind = os.clock() }
	end
end

CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(track)
CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(model)
	animators[model] = nil
end)
for _, model in CollectionService:GetTagged(Config.Tag) do
	track(model)
end

-- Motor6D.Transform is applied right after Stepped, so poses are written here.
RunService.Stepped:Connect(function(_, dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local clock = Workspace:GetServerTimeNow()

	for model, entry in animators do
		local root = model.PrimaryPart
		if not root or not model:IsDescendantOf(Workspace) then
			continue
		end
		if (root.Position - cameraPosition).Magnitude > ANIMATE_DISTANCE then
			continue
		end
		local animator = entry.animator
		if not animator.bound and os.clock() - entry.lastBind > 0.5 then
			entry.lastBind = os.clock() -- parts are still replicating in
			animator:Bind()
		end

		local flying
		if model == player.Character then
			flying = flight.active
		else
			flying = model:GetAttribute("Flying") == true
		end
		local airborne = flying
		if not airborne then
			airborne = Workspace:Raycast(root.Position, Vector3.new(0, -(STAND_HEIGHT + 3.5), 0), entry.params) == nil
		end

		animator:Update(dt, {
			Velocity = root.AssemblyLinearVelocity,
			YawRate = root.AssemblyAngularVelocity.Y,
			Flying = flying,
			Airborne = airborne,
			Clock = clock,
		})
	end
end)

-- Flight ---------------------------------------------------------------------
local controls
local function getMoveVector()
	if not controls then
		local playerScripts = player:FindFirstChild("PlayerScripts")
		local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if playerModule then
			local ok, result = pcall(function()
				return require(playerModule):GetControls()
			end)
			controls = ok and result or nil
		end
	end
	if controls then
		return controls:GetMoveVector()
	end
	-- Fallback for games that replace the default control scripts.
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then z -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then z += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
	return Vector3.new(x, 0, z)
end

local function getDragon()
	local character = player.Character
	if character and character:HasTag(Config.Tag) and character.PrimaryPart then
		return character
	end
	return nil
end

local function stopFlight()
	if not flight.active then
		return
	end
	flight.active = false
	local model = flight.model
	flight.model = nil
	local root = model and model.PrimaryPart
	if root then
		root.FlightVelocity.Enabled = false
		root.FlightOrientation.Enabled = false
		root.AssemblyAngularVelocity = Vector3.zero
	end
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	setFlying:FireServer(false)
end

local function startFlight(model)
	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	flight.active = true
	flight.model = model
	flight.startedAt = os.clock()
	flight.velocity = root.AssemblyLinearVelocity + Vector3.new(0, Config.TakeoffBoost, 0)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flight.heading = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)

	humanoid.PlatformStand = true -- hands the body over to the constraints below
	root.FlightVelocity.VectorVelocity = flight.velocity
	root.FlightOrientation.CFrame = CFrame.lookAt(Vector3.zero, flight.heading)
	root.FlightVelocity.Enabled = true
	root.FlightOrientation.Enabled = true
	setFlying:FireServer(true)
end

-- Space (or the mobile/gamepad jump button) toggles flight instead of jumping.
UserInputService.JumpRequest:Connect(function()
	local model = getDragon()
	if not model or os.clock() - flight.lastToggle < 0.5 then
		return
	end
	flight.lastToggle = os.clock()
	if flight.active then
		stopFlight()
	else
		startFlight(model)
	end
end)

local function stepFlight(dt)
	local model = flight.model
	local root = model and model.PrimaryPart
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local camera = Workspace.CurrentCamera
	if not root or not humanoid or humanoid.Health <= 0 or model ~= player.Character or not camera then
		stopFlight()
		return
	end

	-- W/S follow where the camera looks (including up and down), A/D strafe.
	local move = getMoveVector()
	local wish = camera.CFrame.LookVector * -move.Z + camera.CFrame.RightVector * move.X
	if wish.Magnitude > 1 then
		wish = wish.Unit
	end
	local topSpeed = UserInputService:IsKeyDown(Config.BoostKey) and Config.FlyBoostSpeed or Config.FlySpeed
	flight.velocity = flight.velocity:Lerp(wish * topSpeed, 1 - math.exp(-Config.FlyAcceleration * dt))
	local velocity = flight.velocity
	root.FlightVelocity.VectorVelocity = velocity

	-- Face the direction of travel and pitch with the climb or dive.
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude > 3 then
		flight.heading = flat.Unit
	end
	local speed = velocity.Magnitude
	local pitch = 0
	if speed > 1 then
		local maxPitch = math.rad(Config.MaxPitch)
		pitch = math.clamp(math.asin(math.clamp(velocity.Y / speed, -1, 1)), -maxPitch, maxPitch) * math.clamp(speed / 25, 0, 1)
	end
	root.FlightOrientation.CFrame = CFrame.lookAt(Vector3.zero, flight.heading) * CFrame.Angles(pitch, 0, 0)

	-- Touch down when descending onto (or idling just above) the ground.
	if os.clock() - flight.startedAt > 0.8 and (velocity.Y < -1.5 or move.Magnitude < 0.1) then
		local entry = animators[model]
		local hit = entry and Workspace:Raycast(root.Position, Vector3.new(0, -(STAND_HEIGHT + 1), 0), entry.params)
		if hit then
			stopFlight()
		end
	end
end

-- Camera: pull back far enough to see a creature this size.
local currentDragon
local savedMaxZoom

local function onDragonChanged(model)
	currentDragon = model
	if model then
		savedMaxZoom = player.CameraMaxZoomDistance
		local savedMinZoom = player.CameraMinZoomDistance
		player.CameraMaxZoomDistance = math.max(savedMaxZoom, Config.CameraMaxZoom)
		player.CameraMinZoomDistance = Config.CameraZoom
		task.delay(0.2, function()
			player.CameraMinZoomDistance = savedMinZoom
		end)
	else
		stopFlight()
		if savedMaxZoom then
			player.CameraMaxZoomDistance = savedMaxZoom
			savedMaxZoom = nil
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	local model = getDragon()
	if model ~= currentDragon then
		onDragonChanged(model)
	end
	if flight.active then
		stepFlight(dt)
	end
end)
