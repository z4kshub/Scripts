-- Builds the Cinderwing model from parts. Every joint is an invisible bone part
-- driven by a Motor6D; all visible geometry is welded to its bone.
local Rig = require(script.Parent.Rig)
local Config = require(script.Parent.Config)

local V3 = Vector3.new
local RGB = Color3.fromRGB

local Colors = {
	Scale = RGB(40, 36, 38),
	ScaleDark = RGB(27, 24, 26),
	Belly = RGB(64, 50, 46),
	Spine = RGB(92, 26, 22),
	SpineDark = RGB(54, 20, 20),
	Membrane = RGB(142, 40, 22),
	MembraneDark = RGB(90, 28, 20),
	Horn = RGB(66, 58, 54),
	Claw = RGB(22, 20, 20),
	Tooth = RGB(222, 212, 188),
	Mouth = RGB(128, 28, 34),
	Eye = RGB(255, 128, 24),
}

local MEMBRANE_THICKNESS = 0.12

local Builder = {}

function Builder.build()
	local model = Instance.new("Model")
	model.Name = Config.ModelName
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- never stream in half a skeleton

	local bones = {}

	local function newPart(className, name)
		local p = Instance.new(className)
		p.Name = name
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		return p
	end

	local function attach(boneName, p)
		local bone = bones[boneName]
		local weld = Instance.new("Weld")
		weld.Part0 = bone
		weld.Part1 = p
		weld.C0 = bone.CFrame:ToObjectSpace(p.CFrame)
		weld.Parent = p
		p.Parent = model
	end

	-- Skeleton ---------------------------------------------------------------
	local root = newPart("Part", "HumanoidRootPart")
	root.Size = Rig.RootSize
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.CanCollide = true
	root.Massless = false
	root.Parent = model
	model.PrimaryPart = root
	bones.Root = root

	for _, joint in Rig.Joints do
		local bone = newPart("Part", joint.Name .. "Bone")
		bone.Size = V3(0.4, 0.4, 0.4)
		bone.Transparency = 1
		bone.CanQuery = false
		bone.CFrame = CFrame.new(joint.Position)
		bones[joint.Name] = bone

		local parent = bones[joint.Parent]
		local motor = Instance.new("Motor6D")
		motor.Name = joint.Name
		motor.Part0 = parent
		motor.Part1 = bone
		motor.C0 = CFrame.new(joint.Position - parent.CFrame.Position)
		motor.C1 = CFrame.new()
		motor.Parent = parent
		bone.Parent = model
	end

	-- Shape helpers ----------------------------------------------------------
	local function ell(bone, pos, size, color, cf, material)
		local p = newPart("Part", "Scale")
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Slate
		p.CFrame = cf and (cf.Rotation + pos) or CFrame.new(pos)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		attach(bone, p)
		return p
	end

	local function box(bone, pos, size, color, material)
		local p = newPart("Part", "Plate")
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Slate
		p.CFrame = CFrame.new(pos)
		attach(bone, p)
		return p
	end

	-- Ellipsoid stretched from a to b. w is the width across `up`, h along it.
	local function limb(bone, a, b, w, h, lengthScale, color, up, material)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, b, up or V3(0, 1, 0))
		return ell(bone, mid, V3(w, h, (b - a).Magnitude * lengthScale), color, cf, material)
	end

	local function wedge(bone, cf, size, color, material)
		local p = newPart("WedgePart", "Spine")
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Slate
		p.CFrame = cf
		attach(bone, p)
		return p
	end

	-- Swept dorsal fin: `base` is the middle of its foot, the tall edge is at the rear.
	local function fin(bone, base, up, back, baseLen, height, thick, color)
		local y = up.Unit
		local z = (back - y * back:Dot(y)).Unit
		local x = y:Cross(z)
		wedge(bone, CFrame.fromMatrix(base + y * (height / 2), x, y, z), V3(thick, height, baseLen), color)
	end

	-- Flat symmetric blade from `base` to a point `length` along `dir`.
	local function spike(bone, base, dir, length, width, thick, color, side, material)
		local d = dir.Unit
		local hint = side or V3(0, 1, 0)
		if math.abs(d:Dot(hint.Unit)) > 0.95 then
			hint = V3(1, 0, 0)
		end
		local w = (hint - d * hint:Dot(d)).Unit
		local z = -d
		local mid = base + d * (length / 2)
		local size = V3(thick, width / 2, length)
		wedge(bone, CFrame.fromMatrix(mid + w * (width / 4), w:Cross(z), w, z), size, color, material)
		wedge(bone, CFrame.fromMatrix(mid - w * (width / 4), (-w):Cross(z), -w, z), size, color, material)
	end

	-- Triangle a-b-c as two wedges (membrane panels).
	local function tri(bone, a, b, c, color, name)
		local ab, ac, bc = b - a, c - a, c - b
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local right = ac:Cross(ab).Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		local len1, len2 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
		if height < 0.05 then
			return
		end
		local material = Enum.Material.SmoothPlastic
		if len1 > 0.05 then
			local w1 = wedge(bone, CFrame.fromMatrix((a + b) / 2, right, up, back), V3(MEMBRANE_THICKNESS, height, len1), color, material)
			w1.Name = name or "Membrane"
		end
		if len2 > 0.05 then
			local w2 = wedge(bone, CFrame.fromMatrix((a + c) / 2, -right, up, -back), V3(MEMBRANE_THICKNESS, height, len2), color, material)
			w2.Name = name or "Membrane"
		end
	end

	-- Torso ------------------------------------------------------------------
	local torso = {
		{ "Chest", V3(0, 0.2, -4.2), V3(8.0, 7.4, 11.0) },
		{ "Body", V3(0, -0.2, 1.4), V3(7.2, 6.5, 10.4) },
		{ "Hips", V3(0, 0, 6.3), V3(6.4, 5.8, 7.6) },
	}
	for _, t in torso do
		ell(t[1], t[2], t[3], Colors.Scale)
	end
	ell("Chest", V3(0, -2.0, -4.8), V3(5.2, 4.2, 8.0), Colors.Belly) -- keel
	ell("Body", V3(0, -1.6, 1.2), V3(5.0, 4.2, 9.6), Colors.Belly)
	ell("Hips", V3(0, -1.1, 6.6), V3(4.0, 3.8, 6.4), Colors.Belly)
	ell("Chest", V3(0, 1.5, -7.8), V3(5.6, 5.8, 5.2), Colors.Scale) -- neck root

	local function topY(z)
		local best = -math.huge
		for _, t in torso do
			local u = (z - t[2].Z) / (t[3].Z / 2)
			if math.abs(u) < 1 then
				best = math.max(best, t[2].Y + t[3].Y / 2 * math.sqrt(1 - u * u))
			end
		end
		return best
	end

	-- Dorsal sail along the back, tallest over the shoulders.
	do
		local z = -8.2
		while z <= 9.6 do
			local t = (z + 8.2) / 17.8
			local height = 2.8 - 1.3 * t
			local bone = z < -1 and "Chest" or (z < 4 and "Body" or "Hips")
			local base = V3(0, topY(z) - 0.35, z)
			fin(bone, base, V3(0, 1, 0.5), V3(0, 0, 1), 1.5, height, 0.24, Colors.Spine)
			for _, sx in { 1, -1 } do
				spike(bone, base + V3(0.75 * sx, -0.3, 0.2), V3(0.45 * sx, 0.8, 0.6), height * 0.5, 0.5, 0.2, Colors.SpineDark)
			end
			z += 1.2
		end
	end

	-- Neck -------------------------------------------------------------------
	local rest = Rig.Rest
	do
		local widths = { 4.9, 4.4, 3.9, 3.5, 3.2 }
		for i = 1, Rig.NeckCount do
			local name = "Neck" .. i
			local a = rest[name]
			local b = i < Rig.NeckCount and rest["Neck" .. (i + 1)] or rest.Head
			local w = widths[i]
			local h = w * 1.04
			limb(name, a, b, w, h, 1.6, Colors.Scale)
			limb(name, a + V3(0, -h * 0.2, 0), b + V3(0, -h * 0.2, 0), w * 0.62, h * 0.66, 1.5, Colors.Belly)
			for k = 0, 1 do
				local p = a:Lerp(b, 0.15 + 0.5 * k)
				local height = 2.25 - 0.13 * (i - 1) - 0.06 * k
				fin(name, p + V3(0, h * 0.42, 0), V3(0, 1, 0.55), V3(0, 0, 1), 1.35, height, 0.22, Colors.Spine)
				for _, sx in { 1, -1 } do
					spike(name, p + V3(w * 0.36 * sx, h * 0.28, 0), V3(0.6 * sx, 0.5, 0.75), 1.5 - 0.1 * i, 0.5, 0.2, Colors.SpineDark)
					spike(name, p + V3(w * 0.45 * sx, -h * 0.05, 0.4), V3(0.85 * sx, 0.05, 0.7), 1.0 - 0.06 * i, 0.42, 0.18, Colors.ScaleDark)
				end
			end
		end
	end

	-- Head -------------------------------------------------------------------
	do
		local H = rest.Head
		local HS = 1.25 -- head scale
		local function sz(x, y, z)
			return V3(x, y, z) * HS
		end
		local function h(x, y, z)
			return H + V3(x, y, z) * HS
		end
		ell("Head", h(0, 0.25, -1.5), sz(3.1, 2.5, 4.4), Colors.Scale) -- cranium
		ell("Head", h(0, 0.0, -4.2), sz(2.3, 1.75, 5.0), Colors.Scale) -- snout
		ell("Head", h(0, 0.42, -5.9), sz(1.55, 0.95, 1.6), Colors.ScaleDark) -- nose
		box("Head", h(0, -0.6, -3.4), sz(1.3, 0.3, 4.2), Colors.Mouth, Enum.Material.SmoothPlastic) -- palate

		for _, sx in { 1, -1 } do
			ell("Head", h(1.02 * sx, 0.95, -2.5), sz(0.95, 0.75, 2.5), Colors.ScaleDark) -- brow ridge
			local eye = ell("Head", h(1.26 * sx, 0.52, -2.75), sz(0.4, 0.42, 0.66), Colors.Eye, nil, Enum.Material.Neon)
			eye.Name = "Eye"
			ell("Head", h(1.42 * sx, 0.52, -2.8), sz(0.14, 0.34, 0.2), Colors.Claw, nil, Enum.Material.SmoothPlastic) -- pupil
			ell("Head", h(1.05 * sx, -0.55, -1.0), sz(1.0, 1.7, 2.0), Colors.Scale) -- jaw muscle
			ell("Head", h(0.55 * sx, 0.5, -6.15), sz(0.3, 0.22, 0.45), Colors.Claw) -- nostril

			-- Horn crown, three tiers sweeping back.
			limb("Head", h(0.85 * sx, 1.0, -0.6), h(1.9 * sx, 2.5, 4.4), 0.85, 0.85, 1.05, Colors.Horn)
			limb("Head", h(1.35 * sx, 0.45, -0.3), h(3.0 * sx, 0.95, 3.6), 0.7, 0.7, 1.05, Colors.Horn)
			limb("Head", h(1.4 * sx, -0.3, -0.7), h(2.9 * sx, -0.75, 2.2), 0.55, 0.55, 1.05, Colors.Horn)
			limb("Head", h(0.45 * sx, 1.25, -0.5), h(0.8 * sx, 2.3, 2.9), 0.55, 0.55, 1.05, Colors.Horn)

			for k = 0, 3 do -- brow spikes
				spike("Head", h(1.1 * sx, 1.2, -3.3 + 0.75 * k), V3(0.45 * sx, 0.7, 0.75), 0.75 + 0.14 * k, 0.4, 0.16, Colors.SpineDark)
			end
			for k = 0, 3 do -- cheek frill
				spike("Head", h(1.35 * sx, -0.1 - 0.22 * k, -1.9 + 0.5 * k), V3(0.8 * sx, -0.15, 0.7), 1.5 - 0.12 * k, 0.45, 0.16, Colors.ScaleDark)
			end

			-- Upper teeth
			for k = 0, 8 do
				local z = -1.7 - 0.52 * k
				local big = (k == 7 or k == 5) and 0.3 or 0
				spike("Head", h((0.86 - 0.03 * k) * sx, -0.72, z), V3(0, -1, -0.12), 0.55 + big, 0.3, 0.16, Colors.Tooth, V3(0, 0, 1), Enum.Material.SmoothPlastic)
			end
		end
		for k = 0, 4 do -- snout ridge
			spike("Head", h(0, 0.85, -5.0 + 0.7 * k), V3(0, 0.75, 0.65), 0.55 + 0.1 * k, 0.4, 0.16, Colors.SpineDark, V3(0, 0, 1))
		end
		fin("Head", h(0, 1.35, -0.6), V3(0, 1, 0.6), V3(0, 0, 1), 1.4, 1.9, 0.22, Colors.Spine)

		-- Lower jaw
		ell("Jaw", h(0, -1.2, -3.4), sz(1.95, 0.95, 5.6), Colors.Scale)
		ell("Jaw", h(0, -0.92, -3.3), sz(1.0, 0.3, 3.8), Colors.Mouth, nil, Enum.Material.SmoothPlastic) -- tongue
		for _, sx in { 1, -1 } do
			for k = 0, 7 do
				local z = -1.95 - 0.52 * k
				local big = k == 6 and 0.3 or 0
				spike("Jaw", h((0.74 - 0.03 * k) * sx, -0.98, z), V3(0, 1, -0.1), 0.5 + big, 0.28, 0.15, Colors.Tooth, V3(0, 0, 1), Enum.Material.SmoothPlastic)
			end
			for k = 0, 5 do -- chin spikes
				spike("Jaw", h(0.55 * sx, -1.5, -1.3 - 0.72 * k), V3(0.3 * sx, -1, 0.6), 1.0 - 0.07 * k, 0.4, 0.16, Colors.ScaleDark, V3(0, 0, 1))
			end
		end
	end

	-- Tail -------------------------------------------------------------------
	do
		local widths = { 4.6, 4.0, 3.4, 2.9, 2.4, 2.0, 1.6, 1.25, 0.95, 0.7 }
		for i = 1, Rig.TailCount do
			local name = "Tail" .. i
			local a = rest[name]
			local b = i < Rig.TailCount and rest["Tail" .. (i + 1)] or Rig.TailTip
			local w = widths[i]
			limb(name, a, b, w, w * 0.96, 1.55, Colors.Scale)
			local count = i <= 6 and 2 or 1
			for k = 0, count - 1 do
				local p = a:Lerp(b, 0.2 + 0.5 * k)
				local height = math.max(0.5, 1.5 - 0.1 * i)
				fin(name, p + V3(0, w * 0.4, 0), V3(0, 1, 0.55), V3(0, 0, 1), 1.2, height, 0.2, Colors.Spine)
			end
			if i >= 4 then
				local p = a:Lerp(b, 0.5)
				for _, sx in { 1, -1 } do
					spike(name, p + V3(w * 0.38 * sx, 0, 0), V3(0.8 * sx, 0.1, 0.8), 0.95, 0.4, 0.16, Colors.SpineDark)
				end
			end
		end
		local tip = Rig.TailTip
		local last = "Tail" .. Rig.TailCount
		spike(last, tip + V3(0, 0, -0.6), V3(0, 0, 1), 2.6, 0.9, 0.24, Colors.Spine)
		for _, sx in { 1, -1 } do
			spike(last, tip + V3(0.1 * sx, 0, -1.2), V3(0.75 * sx, 0, 1), 1.9, 0.7, 0.2, Colors.Spine)
			spike(last, tip + V3(0, 0.1 * sx, -1.0), V3(0, 0.7 * sx, 1), 1.5, 0.6, 0.2, Colors.SpineDark, V3(1, 0, 0))
		end
	end

	-- Wings and legs ---------------------------------------------------------
	for _, side in Rig.Sides do
		local s, sx = side.Suffix, side.Sign
		local function m(v)
			return Rig.mirror(v, sx)
		end

		local wing = Rig.Wing
		local S, E, W, B = m(wing.Shoulder), m(wing.Elbow), m(wing.Wrist), m(wing.BodyAttach)
		local arm, fore, hand = "WingArm" .. s, "WingFore" .. s, "WingHand" .. s

		ell("Chest", S + V3(-0.5 * sx, -0.6, 0.4), V3(4.2, 4.4, 5.8), Colors.Scale) -- shoulder mass
		limb(arm, S, E, 3.1, 2.5, 1.2, Colors.Scale)
		limb(fore, E, W, 2.2, 1.8, 1.12, Colors.Scale)
		ell(fore, E, V3(2.5, 2.3, 2.5), Colors.ScaleDark)
		spike(fore, E, V3(-0.3 * sx, 0.15, 1), 2.0, 0.8, 0.3, Colors.Claw)
		ell(hand, W, V3(2.4, 2.1, 2.4), Colors.ScaleDark)

		-- Thumb claws: these carry the weight when the dragon walks on its wings.
		for _, dx in { 0.4, -0.35 } do
			local a = W + V3(dx * sx, -0.2, -0.4)
			local b = a + V3(dx * 1.6 * sx, -0.5, -2.2)
			limb(hand, a, b, 0.7, 0.7, 1.15, Colors.ScaleDark)
			spike(hand, b + V3(0, 0, 0.2), V3(dx * 0.4 * sx, -0.55, -1), 1.3, 0.5, 0.3, Colors.Claw)
		end

		for i = 1, Rig.FingerCount do
			local Wr, Tr = wing.Wrist, wing.Tips[i]
			-- Bow each finger slightly toward the leading edge.
			local M = m(wing.Mids[i] + V3(0, 1, 0):Cross(Tr - Wr).Unit * 0.7)
			local T = m(Tr)
			local f = "F" .. i .. s
			limb(f, W, M, 0.8, 0.62, 1.04, Colors.ScaleDark)
			limb(f, M, T, 0.58, 0.46, 1.04, Colors.ScaleDark)
			ell(f, M, V3(0.85, 0.7, 0.85), Colors.ScaleDark)
			spike(f, T - (T - M).Unit * 0.3, T - M, 1.3, 0.4, 0.22, Colors.Claw, V3(0, 0, 1))
		end

		-- Membrane between the fingers: slices on hidden ribs, scalloped along
		-- the trailing edge. Each slice hangs off the rib behind it so the fan
		-- drapes below the fingers when it folds.
		local slices = Rig.RibsPerGap + 1
		for i = 1, Rig.FingerCount - 1 do
			local T1, T2 = wing.Tips[i], wing.Tips[i + 1]
			local chord = (T1 + T2) / 2
			local control = chord:Lerp(wing.Wrist, 0.17) * 2 - chord
			local function edgePoint(t)
				return T1 * ((1 - t) ^ 2) + control * (2 * t * (1 - t)) + T2 * (t ^ 2)
			end
			for k = 0, slices - 1 do
				local a, b = m(edgePoint(k / slices)), m(edgePoint((k + 1) / slices))
				local bone = k + 1 == slices and ("F" .. (i + 1) .. s) or ("Rib" .. i .. (k + 1) .. s)
				local a2, b2 = W:Lerp(a, 0.42), W:Lerp(b, 0.42)
				tri(bone, W, a2, b2, Colors.MembraneDark)
				tri(bone, a2, a, b, Colors.Membrane)
				tri(bone, a2, b, b2, Colors.Membrane)
			end
		end

		-- Membrane from the last finger back to the flank.
		do
			local M4, T4 = m(wing.Mids[4]), m(wing.Tips[4])
			local edge = ((T4 + B) / 2):Lerp(E, 0.2)
			-- These panels cannot fold, so the animator fades them out on the ground.
			tri(arm, S, E, B, Colors.MembraneDark, "MembraneArm")
			tri(arm, E, edge, B, Colors.Membrane, "MembraneArm")
			tri(fore, E, W, M4, Colors.MembraneDark, "MembraneArm")
			tri(fore, E, M4, edge, Colors.Membrane, "MembraneArm")
			tri(fore, M4, T4, edge, Colors.Membrane, "MembraneArm")
			-- Skirt under the seam so no slit opens when the elbow flexes mid-stroke.
			local drop = V3(0, -0.06, 0)
			local inward = E + (CFrame.Angles(0, math.rad(-32 * sx), 0) * (edge - E))
			tri(fore, E + drop, edge + drop, inward + drop, Colors.Membrane, "MembraneArm")
		end

		-- Hind leg
		local leg = Rig.Leg
		local hip, knee, ankle, toeBase = m(leg.Hip), m(leg.Knee), m(leg.Ankle), m(leg.ToeBase)
		local fwd = V3(0, 0, -1)
		ell("Hips", hip + V3(-0.4 * sx, 0.4, 0.2), V3(3.6, 4.8, 5.4), Colors.Scale)
		limb("Thigh" .. s, hip, knee, 3.4, 4.6, 1.3, Colors.Scale, fwd)
		limb("Shin" .. s, knee, ankle, 2.2, 2.7, 1.2, Colors.Scale, fwd)
		ell("Shin" .. s, knee, V3(2.4, 2.4, 2.4), Colors.ScaleDark)
		spike("Shin" .. s, ankle, V3(0, 0.45, 1), 1.5, 0.7, 0.26, Colors.Claw)
		limb("Foot" .. s, ankle, toeBase, 1.9, 2.0, 1.5, Colors.Scale, fwd)
		ell("Toes" .. s, toeBase + V3(0, 0.05, 0.1), V3(2.7, 1.1, 2.2), Colors.ScaleDark)
		for _, dx in { -0.42, 0, 0.42 } do
			local a = toeBase + V3(dx * 1.5, 0, -0.3)
			local b = a + V3(dx * 2.4, -0.05, -2.7)
			limb("Toes" .. s, a, b, 0.9, 0.85, 1.15, Colors.ScaleDark)
			spike("Toes" .. s, b + V3(0, 0.1, 0.25), V3(dx * 0.5, -0.38, -1), 1.15, 0.5, 0.28, Colors.Claw)
		end
		spike("Foot" .. s, ankle + V3(0, -0.6, 0.3), V3(0, -0.5, 1), 1.3, 0.5, 0.26, Colors.Claw) -- dewclaw
	end

	-- Humanoid and flight constraints ---------------------------------------
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = Rig.HipHeight
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	humanoid.WalkSpeed = Config.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0 -- Space is takeoff, handled by the client
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "FlightVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = V3(0, 0, 0)
	velocity.Enabled = false
	velocity.Parent = root

	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "FlightOrientation"
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.MaxTorque = math.huge
	orientation.Responsiveness = Config.TurnResponsiveness
	orientation.Enabled = false
	orientation.Parent = root

	model:SetAttribute("Flying", false)
	model:SetAttribute("Seed", math.random(0, 999))
	model:AddTag(Config.Tag)

	return model
end

return Builder
