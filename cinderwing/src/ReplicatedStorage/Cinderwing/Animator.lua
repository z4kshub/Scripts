-- Procedural animation for the Cinderwing. Pure math: it turns motion state
-- (velocity, turn rate, flying or not) into a Motor6D.Transform for every joint.
-- Ground poses plant the wing wrists and hind feet with two-bone IK so the wings
-- really act as front legs; flight poses are layered sine waves that lag from
-- shoulder to fingertip.
local Rig = require(script.Parent.Rig)

local V3 = Vector3.new
local rad, deg, sin, cos, pi = math.rad, math.deg, math.sin, math.cos, math.pi
local min, max, clamp, exp, floor, abs, sqrt = math.min, math.max, math.clamp, math.exp, math.floor, math.abs, math.sqrt
local TAU = 2 * pi
local ZERO = V3(0, 0, 0)

local WALK_REF = 16 -- ground speed at which the walk cycle is fully blended in
local IDLE_PERIOD = 13 -- seconds between chances to play a special idle
local IDLE_LEN = 5.5

local STAND_PITCH = 12 -- chest carried higher than the hips
local NECK_GROUND = { 13, 12, 6, -8, -12 }
local HEAD_GROUND = -19
local TAIL_GROUND = { 12, 11, 7, -2, -10, -12, -9, -6, -2, 0 }
local NECK_FLIGHT = { 5, 3, 0, -3, -4 }
local FOLD_TARGET = { 84, 88, 92, 96 } -- finger bearings (degrees) when the fan is shut

local function A(x, y, z)
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

local function smooth(a, b, x)
	local t = clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function approach(current, target, rate, dt)
	return current + (target - current) * (1 - exp(-rate * dt))
end

-- Rotation whose X axis is `x` and whose Y axis leans toward `hint`.
local function basis(x, hint)
	x = x.Unit
	local z = x:Cross(hint)
	if z.Magnitude < 1e-4 then
		z = x:Cross(V3(0, 1, 0))
		if z.Magnitude < 1e-4 then
			z = x:Cross(V3(1, 0, 0))
		end
	end
	z = z.Unit
	return CFrame.fromMatrix(ZERO, x, z:Cross(x), z)
end

-- Middle joint of a two-bone chain from S to T, bent toward `pole`.
local function solveTwoBone(S, T, l1, l2, pole)
	local st = T - S
	local d = st.Magnitude
	local reach = (l1 + l2) * 0.995
	if d > reach then
		st = st.Unit * reach
		d = reach
		T = S + st
	end
	d = max(d, abs(l1 - l2) + 0.01)
	local dir = st.Unit
	local a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local h = sqrt(max(l1 * l1 - a * a, 0))
	local perp = pole - dir * pole:Dot(dir)
	perp = perp.Magnitude > 1e-4 and perp.Unit or V3(0, 1, 0)
	return S + dir * a + perp * h, T
end

-- One stride. Returns the foot's fore/aft offset (-0.5 front .. 0.5 back) and lift.
local function stride(p)
	p = p % 1
	if p < Rig.Duty then
		return p / Rig.Duty - 0.5, 0
	end
	local u = (p - Rig.Duty) / (1 - Rig.Duty)
	return 0.5 - u * u * (3 - 2 * u), sin(pi * u)
end

-- Static rig data ------------------------------------------------------------
local REST = Rig.Rest
local WING, LEG = Rig.Wing, Rig.Leg
local ARM_LEN = (WING.Elbow - WING.Shoulder).Magnitude
local FORE_LEN = (WING.Wrist - WING.Elbow).Magnitude
local THIGH_LEN = (LEG.Knee - LEG.Hip).Magnitude
local SHIN_LEN = (LEG.Ankle - LEG.Knee).Magnitude

local FOLD = {}
for i, tip in WING.Tips do
	local d = tip - WING.Wrist
	FOLD[i] = FOLD_TARGET[i] - deg(math.atan2(d.Z, d.X))
end

local NECK, TAIL = {}, {}
for i = 1, Rig.NeckCount do
	NECK[i] = "Neck" .. i
end
for i = 1, Rig.TailCount do
	TAIL[i] = "Tail" .. i
end

local SIDES = {}
for _, side in Rig.Sides do
	local s, sx = side.Suffix, side.Sign
	local function m(v)
		return Rig.mirror(v, sx)
	end
	local back, fwd = V3(0, 0, 1), V3(0, 0, -1)
	local bundle = V3(0.08 * sx, 0.42, 0.9).Unit
	local handX = V3(sx, 0.1, 0):Cross(bundle).Unit
	local data = {
		sx = sx,
		Arm = "WingArm" .. s,
		Fore = "WingFore" .. s,
		Hand = "WingHand" .. s,
		Thigh = "Thigh" .. s,
		Shin = "Shin" .. s,
		Foot = "Foot" .. s,
		Toes = "Toes" .. s,
		F = {},
		Ribs = {},
		shoulder = m(WING.Shoulder) - REST.Chest,
		armInv = basis(m(WING.Elbow - WING.Shoulder), back):Inverse(),
		foreInv = basis(m(WING.Wrist - WING.Elbow), back):Inverse(),
		-- Folded hand: fingers bundled up and back along the flank.
		handGround = CFrame.fromMatrix(ZERO, handX, bundle:Cross(handX), bundle),
		hip = m(LEG.Hip) - REST.Hips,
		ankle = m(LEG.Ankle),
		thighInv = basis(m(LEG.Knee - LEG.Hip), fwd):Inverse(),
		shinInv = basis(m(LEG.Ankle - LEG.Knee), fwd):Inverse(),
		-- Diagonal pairs move together, like a trotting quadruped.
		wingPhase = sx > 0 and 0 or 0.5,
		legPhase = sx > 0 and 0.5 or 0,
	}
	for i = 1, Rig.FingerCount do
		data.F[i] = "F" .. i .. s
	end
	for i = 1, Rig.FingerCount - 1 do
		for k = 1, Rig.RibsPerGap do
			table.insert(data.Ribs, { Name = "Rib" .. i .. k .. s, Finger = i, T = k / (Rig.RibsPerGap + 1) })
		end
	end
	table.insert(SIDES, data)
end

-- Closes the finger fan by `fold` (0 open .. 1 shut); ribs follow their neighbours.
local function setFan(out, side, fold)
	local k = -side.sx * fold
	for i = 1, Rig.FingerCount do
		out[side.F[i]] = A(0, k * FOLD[i], 0)
	end
	for _, rib in side.Ribs do
		out[rib.Name] = A(0, k * lerp(FOLD[rib.Finger], FOLD[rib.Finger + 1], rib.T), 0)
	end
end

-- Ground ---------------------------------------------------------------------
local function groundPose(self, out)
	local t = self.time
	local w = min(self.walk, 1)
	local ph = self.walkPhase
	local s1, s2 = sin(TAU * ph), sin(2 * TAU * ph)
	local breath = sin(t * 1.4)
	local sv, st = self.survey, self.stretch
	local frac = self.idleT / IDLE_LEN
	local lookDeg = clamp(deg(self.yaw) * 0.12, -9, 9)

	local pitch = STAND_PITCH + 0.5 * breath + 15 * st + 2 * sv
	local bodyCF = CFrame.new(0, 0.1 * breath + w * 0.25 * s2, 0) * A(pitch, w * 2 * s1, w * 1.5 * s1)
	local chestT = A(0.8 * breath, -w * 3 * s1, 0)
	local hipsT = A(0, w * 4 * s1, 0)
	out.Body, out.Chest, out.Hips = bodyCF, chestT, hipsT
	local chestCF = bodyCF * CFrame.new(REST.Chest) * chestT
	local hipsCF = bodyCF * CFrame.new(REST.Hips) * hipsT

	-- Neck, head, jaw
	local scan = sin(TAU * frac) * 42 * sv
	local growl = sv * smooth(0.3, 0.45, frac) * (1 - smooth(0.62, 0.8, frac)) * (0.85 + 0.15 * sin(t * 27))
	local roar = st * smooth(0.25, 0.4, frac) * (1 - smooth(0.7, 0.85, frac)) * (0.85 + 0.15 * sin(t * 31))
	for i = 1, Rig.NeckCount do
		local rx = NECK_GROUND[i] + (i <= 3 and (4 * sv + 4 * st) or 0) + 0.8 * sin(t * 1.4 - i * 0.5) - w * 1.2 * s2
		local ry = lookDeg + 2.2 * sin(t * 0.55 - i * 0.6) + scan * 0.11 + w * 1.5 * sin(TAU * ph - i * 0.4)
		out[NECK[i]] = A(rx, ry, 0)
	end
	out.Head = A(
		HEAD_GROUND - (pitch - STAND_PITCH) * 0.9 - 9 * sv - 2 * st + 10 * roar + 1.5 * sin(t * 0.7),
		lookDeg + scan * 0.45 + 3 * sin(t * 0.4),
		scan * 0.12
	)
	out.Jaw = A(-(2.5 + 1.5 * breath) - 17 * growl - 28 * roar, 0, 0)

	-- Tail: drapes to the ground, lazy travelling sway
	local swayAmp = 5 + 3 * w + 5 * sv + 4 * st
	local pitchComp = (pitch - STAND_PITCH) / 3
	for i = 1, Rig.TailCount do
		local rx = TAIL_GROUND[i] - (i <= 3 and pitchComp or 0) + 0.8 * sin(t * 1.1 - i * 0.6)
		local ry = swayAmp * sin(t * 0.9 + TAU * ph - i * 0.55) - lookDeg * 0.8
		out[TAIL[i]] = A(rx, ry, 0)
	end

	local hipsRotInv = hipsCF.Rotation:Inverse()
	local chestRotInv = chestCF.Rotation:Inverse()
	local kneeHint = hipsCF:VectorToObjectSpace(V3(0, -0.15, -1))

	for _, side in SIDES do
		local sx = side.sx

		-- Hind leg
		local zf, lift = stride(ph + side.legPhase)
		local ankle = hipsCF:PointToObjectSpace(side.ankle + V3(0, 1.5 * lift * w, Rig.Stride * zf * w))
		local knee
		knee, ankle = solveTwoBone(side.hip, ankle, THIGH_LEN, SHIN_LEN, kneeHint)
		local thigh = basis(knee - side.hip, kneeHint) * side.thighInv
		local shin = basis(ankle - knee, kneeHint) * side.shinInv
		out[side.Thigh] = thigh
		out[side.Shin] = thigh:Inverse() * shin
		out[side.Foot] = shin:Inverse() * hipsRotInv * A(-28 * lift * w, 0, 0)
		out[side.Toes] = A(-16 * lift * w, 0, 0)

		-- Wing arm planted as a front leg
		zf, lift = stride(ph + side.wingPhase)
		local wrist = chestCF:PointToObjectSpace(V3(6.8 * sx, Rig.GroundY + 0.9 + 2.2 * lift * w, -9.5 + Rig.Stride * zf * w))
		local elbow
		elbow, wrist = solveTwoBone(side.shoulder, wrist, ARM_LEN, FORE_LEN, chestCF:VectorToObjectSpace(V3(0.5 * sx, 0.6, 0.75)))
		local arm = basis(elbow - side.shoulder, chestCF:VectorToObjectSpace(V3(-0.3 * sx, -0.6, 0.75))) * side.armInv
		local fore = basis(wrist - elbow, chestCF:VectorToObjectSpace(V3(-0.2 * sx, 0.15, 1))) * side.foreInv
		local armT = arm
		local foreT = arm:Inverse() * fore
		local handT = fore:Inverse() * chestRotInv * side.handGround * A(0, 0, sx * 10 * lift * w)
		local fold = 1

		if st > 0.001 then
			-- Wing stretch idle: lift off the knuckles, half open the fan, shudder.
			local shake = 3.5 * sin(t * 23) * smooth(0.35, 0.5, frac) * (1 - smooth(0.7, 0.85, frac))
			armT = armT:Lerp(A(-8, -sx * 6, sx * (42 + shake)), st)
			foreT = foreT:Lerp(A(0, sx * 24, sx * (14 + shake)), st)
			handT = handT:Lerp(A(0, -sx * 34, sx * (-8 + shake)), st)
			fold = lerp(1, 0.38, st)
		end

		out[side.Arm], out[side.Fore], out[side.Hand] = armT, foreT, handT
		setFan(out, side, fold)
	end
end

-- Flight ---------------------------------------------------------------------
local function flightPose(self, out)
	local t = self.time
	local u = self.flapPhase
	local hover, climb, power = self.hover, self.climb, self.power
	local dive = smooth(0.3, 0.75, -climb) * (1 - hover)
	local amp = (lerp(25, 37, hover) + 8 * max(climb, 0)) * power * (1 - 0.75 * dive)
	local up = max(0, cos(u)) -- 1 mid-upstroke, 0 through the downstroke
	local lookDeg = clamp(deg(self.yaw) * 0.12, -9, 9)
	local bank = clamp(deg(self.yaw) * 0.38, -38, 38)

	out.Body = CFrame.new(0, -0.5 * power * (0.6 + 0.6 * hover) * sin(u - 0.9), 0) * A(30 * hover + 2 * sin(u - 0.6), 0, bank)
	out.Chest = A(1.5 * sin(u - 0.4), 0, 0)
	out.Hips = A(-1.5 * sin(u - 1.0), 0, 0)

	for i = 1, Rig.NeckCount do
		local rx = NECK_FLIGHT[i] - 5 * hover + 1.8 * sin(u - 0.5 - 0.45 * i)
		local ry = lookDeg + 1.5 * sin(t * 0.5 - i * 0.4)
		out[NECK[i]] = A(rx, ry, 0)
	end
	out.Head = A(-3 - 6 * hover + 1.5 * sin(u - 2.9), lookDeg + 2 * sin(t * 0.37), -bank * 0.35)
	out.Jaw = A(-3 - 1.5 * sin(t * 1.3), 0, 0)

	for i = 1, Rig.TailCount do
		local rx = (i <= 5 and 5.5 * hover or 0) + (1.5 + 0.35 * i) * sin(u - 1.2 - 0.5 * i)
		local ry = 3 * sin(t * 0.7 - i * 0.5) - lookDeg * 0.9
		out[TAIL[i]] = A(rx, ry, 0)
	end

	local twist = lerp(5, 12, hover) * power
	for _, side in SIDES do
		local sx = side.sx
		-- The stroke travels outward: each joint lags the one before it.
		out[side.Arm] = A(twist * cos(u), sx * (-18 * dive - 9 * hover * cos(u)), sx * (amp * sin(u) + 5 + 16 * (1 - power)))
		out[side.Fore] = A(0, sx * (27 * dive + 9 * up), sx * (0.5 * amp * sin(u - 0.7) - 4))
		out[side.Hand] = A(0, sx * (-42 * dive - 13 * up), sx * (0.45 * amp * sin(u - 1.3) - 3))
		setFan(out, side, 0.1 * up + 0.45 * dive)

		-- Legs trail behind, hanging lower in a hover.
		local dangle = sin(u - 1.4)
		out[side.Thigh] = A(-70 + 42 * hover + 3 * dangle, 0, -sx * 5)
		out[side.Shin] = A(35 - 18 * hover + 3 * sin(u - 2.0), 0, 0)
		out[side.Foot] = A(-60 + 32 * hover + 4 * sin(u - 2.6), 0, 0)
		out[side.Toes] = A(-25, 0, 0)
	end
end

-- Animator -------------------------------------------------------------------
local Animator = {}
Animator.__index = Animator

function Animator.new(model)
	local self = setmetatable({}, Animator)
	self.model = model
	self.motors = {}
	self.seed = model:GetAttribute("Seed") or 0
	self.time = 0
	self.walkPhase = 0
	self.flapPhase = 0
	self.walk = 0
	self.air = 0
	self.hover = 1
	self.climb = 0
	self.yaw = 0
	self.power = 1
	self.idleTime = 0
	self.idleT = 0
	self.survey = 0
	self.stretch = 0
	self.membraneHidden = -1
	self.poseA = {}
	self.poseB = {}
	self:Bind()
	return self
end

-- Collects the joint motors. Returns true once the whole skeleton has replicated.
function Animator:Bind()
	local count = 0
	for _, d in self.model:GetDescendants() do
		if d:IsA("Motor6D") and REST[d.Name] then
			self.motors[d.Name] = d
			count += 1
		end
	end
	self.armMembranes = {}
	for _, d in self.model:GetDescendants() do
		if d.Name == "MembraneArm" then
			table.insert(self.armMembranes, d)
		end
	end
	self.bound = count >= #Rig.Joints
	return self.bound
end

-- Which special idle (0 none, 1 survey and growl, 2 wing stretch) owns this
-- moment, and how far into it we are. Derived from the shared clock so every
-- client sees the same thing.
function Animator:IdleSlot(clock)
	local c = clock + self.seed * 1.7
	local slot = floor(c / IDLE_PERIOD)
	local h = abs(sin(slot * 12.9898 + self.seed * 78.233)) * 43758.5453
	return floor(h) % 3, c - slot * IDLE_PERIOD
end

-- input: Velocity (world Vector3), YawRate (rad/s, + is a left turn), Flying,
-- Airborne, Clock (shared time in seconds)
function Animator:Update(dt, input)
	dt = min(dt, 0.1)
	local vel = input.Velocity
	local ground = sqrt(vel.X * vel.X + vel.Z * vel.Z)
	local speed = vel.Magnitude
	local airborne = input.Airborne

	self.time += dt
	self.air = approach(self.air, airborne and 1 or 0, 3.2, dt)
	self.walk = approach(self.walk, airborne and 0 or clamp(ground / WALK_REF, 0, 1.2), 8, dt)
	self.hover = approach(self.hover, 1 - smooth(6, 30, speed), 3, dt)
	self.climb = approach(self.climb, clamp(vel.Y / max(speed, 12), -1, 1), 3, dt)
	self.yaw = approach(self.yaw, input.YawRate or 0, 5, dt)
	self.power = approach(self.power, input.Flying and 1 or 0.15, 4, dt)

	if not airborne then
		self.walkPhase = (self.walkPhase + ground * dt / Rig.StrideTravel) % 1
	end
	-- Slow, heavy beats when cruising; quicker when hovering or climbing.
	local freq = lerp(0.5, 0.82, self.hover) + 0.2 * max(self.climb, 0)
	self.flapPhase = (self.flapPhase + TAU * freq * dt) % TAU

	if not airborne and ground < 0.5 then
		self.idleTime += dt
	else
		self.idleTime = 0
	end
	local kind, tIn = self:IdleSlot(input.Clock or self.time)
	local envelope = 0
	if kind ~= 0 and tIn < IDLE_LEN and self.idleTime > tIn + 0.3 then
		envelope = smooth(0, 1.0, tIn) * (1 - smooth(IDLE_LEN - 1.1, IDLE_LEN, tIn))
	end
	self.idleT = min(tIn, IDLE_LEN)
	self.survey = approach(self.survey, kind == 1 and envelope or 0, 7, dt)
	self.stretch = approach(self.stretch, kind == 2 and envelope or 0, 7, dt)

	local pose = self.poseA
	local a = smooth(0, 1, self.air)
	if a < 0.999 then
		groundPose(self, pose)
		if a > 0.001 then
			local flight = self.poseB
			flightPose(self, flight)
			for name, cf in flight do
				pose[name] = pose[name]:Lerp(cf, a)
			end
		end
	else
		flightPose(self, pose)
	end

	-- The arm-to-flank membrane only exists while the wing is open.
	local hidden = 1 - smooth(0.1, 0.6, max(a, self.stretch))
	if abs(hidden - self.membraneHidden) > 0.01 or (hidden ~= self.membraneHidden and (hidden == 0 or hidden == 1)) then
		self.membraneHidden = hidden
		for _, part in self.armMembranes do
			part.Transparency = hidden
		end
	end

	for name, motor in self.motors do
		local cf = pose[name]
		if cf then
			motor.Transform = cf
		end
	end
end

return Animator
