-- Skeleton definition shared by the builder and the animator.
-- Rest pose: model space, facing -Z, +X is the dragon's right, wings spread flat
-- (glide) and legs standing. Every joint frame is axis-aligned at rest.
local V3 = Vector3.new

local Rig = {}

Rig.GroundY = -11 -- ground plane in root space while standing
Rig.RootSize = V3(7, 5, 13)
Rig.HipHeight = -Rig.GroundY - Rig.RootSize.Y / 2
Rig.NeckCount = 5
Rig.TailCount = 10
Rig.FingerCount = 4
Rig.RibsPerGap = 2 -- invisible ribs between fingers so the membrane can fan shut
Rig.Sides = { { Suffix = "R", Sign = 1 }, { Suffix = "L", Sign = -1 } }

-- Walk cycle: stride is how far a planted foot travels under the body.
Rig.Stride = 8
Rig.Duty = 0.62
Rig.StrideTravel = Rig.Stride / Rig.Duty -- studs of travel per full cycle

local joints = {}
local rest = {}
local function J(name, parent, x, y, z)
	local pos = V3(x, y, z)
	table.insert(joints, { Name = name, Parent = parent, Position = pos })
	rest[name] = pos
end
rest.Root = V3(0, 0, 0)

J("Body", "Root", 0, 0, 0)
J("Chest", "Body", 0, 0.3, -3)
J("Hips", "Body", 0, 0, 4)

local neck = { { 1.6, -8.6 }, { 1.9, -11.2 }, { 2.15, -13.8 }, { 2.35, -16.3 }, { 2.5, -18.7 } }
for i, p in neck do
	J("Neck" .. i, i == 1 and "Chest" or "Neck" .. (i - 1), 0, p[1], p[2])
end
J("Head", "Neck5", 0, 2.6, -21.0)
J("Jaw", "Head", 0, 1.66, -22.1)

local tailZ = { 9.2, 11.9, 14.5, 17.0, 19.4, 21.7, 23.9, 26.0, 28.0, 29.9 }
for i, z in tailZ do
	J("Tail" .. i, i == 1 and "Hips" or "Tail" .. (i - 1), 0, 0.3 - 0.03 * (i - 1), z)
end
Rig.TailTip = V3(0, 0, 31.8)

-- Right-side reference points; the left side mirrors X.
Rig.Wing = {
	Shoulder = V3(3.8, 2.4, -5.6),
	Elbow = V3(11.5, 2.8, -7.0),
	Wrist = V3(21.5, 3.0, -10.0),
	Tips = { V3(40.0, 2.4, -6.0), V3(38.0, 2.2, 7.0), V3(31.0, 2.0, 16.5), V3(21.0, 2.0, 20.0) },
	Mids = {},
	BodyAttach = V3(2.2, 0.6, 8.6),
}
for i, tip in Rig.Wing.Tips do
	Rig.Wing.Mids[i] = Rig.Wing.Wrist:Lerp(tip, 0.5)
end

Rig.Leg = {
	Hip = V3(3.3, -0.8, 5.8),
	Knee = V3(4.0, -5.6, 2.4),
	Ankle = V3(4.0, -9.4, 6.4),
	ToeBase = V3(4.0, -10.5, 5.0),
}

function Rig.mirror(v, sign)
	return V3(v.X * sign, v.Y, v.Z)
end

for _, side in Rig.Sides do
	local s, sx = side.Suffix, side.Sign
	local function M(name, parent, v)
		J(name .. s, parent, v.X * sx, v.Y, v.Z)
	end
	local w = Rig.Wing
	M("WingArm", "Chest", w.Shoulder)
	M("WingFore", "WingArm" .. s, w.Elbow)
	M("WingHand", "WingFore" .. s, w.Wrist)
	for i = 1, Rig.FingerCount do
		M("F" .. i, "WingHand" .. s, w.Wrist)
	end
	for i = 1, Rig.FingerCount - 1 do
		for k = 1, Rig.RibsPerGap do
			M("Rib" .. i .. k, "WingHand" .. s, w.Wrist)
		end
	end
	local l = Rig.Leg
	M("Thigh", "Hips", l.Hip)
	M("Shin", "Thigh" .. s, l.Knee)
	M("Foot", "Shin" .. s, l.Ankle)
	M("Toes", "Foot" .. s, l.ToeBase)
end

Rig.Joints = joints
Rig.Rest = rest

return Rig
