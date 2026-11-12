-- Builds the Cinderwing model from parts in a low-poly style: flat-shaded
-- blocks and wedges, no curved meshes. Every joint is an invisible bone part
-- driven by a Motor6D; all visible geometry is welded to its bone.
local Rig = require(script.Parent.Rig)
local Config = require(script.Parent.Config)

local V3 = Vector3.new
local RGB = Color3.fromRGB

local Colors = {
	Scale = RGB(58, 52, 60),
	ScaleDark = RGB(38, 34, 40),
	Belly = RGB(118, 74, 56),
	Spine = RGB(176, 52, 32),
	SpineDark = RGB(122, 36, 28),
	Membrane = RGB(206, 74, 36),
	MembraneDark = RGB(150, 46, 30),
	Horn = RGB(128, 112, 98),
	Claw = RGB(30, 26, 28),
	Tooth = RGB(238, 230, 208),
	Mouth = RGB(156, 42, 46),
	Eye = RGB(255, 150, 30),
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
	-- Everything is flat-faced blocks and wedges in SmoothPlastic for a low-poly look.
	local FLAT = Enum.Material.SmoothPlastic

	local function block(bone, cf, size, color, material)
		local p = newPart("Part", "Plate")
		p.Size = size
		p.Color = color
		p.Material = material or FLAT
		p.CFrame = cf
		attach(bone, p)
		return p
	end

	local function wedge(bone, cf, size, color, material)
		local p = newPart("WedgePart", "Spine")
		p.Size = size
		p.Color = color
		p.Material = material or FLAT
		p.CFrame = cf
		attach(bone, p)
		return p
	end

	-- Right-triangle prism: right angle at P, legs u and v, extruded `len` along u x v.
	local function rtri(bone, P, u, v, len, color)
		local y, z = v.Unit, -u.Unit
		return wedge(bone, CFrame.fromMatrix(P + u / 2 + v / 2, y:Cross(z), y, z), V3(len, v.Magnitude, u.Magnitude), color)
	end

	-- Orthonormal frame running from a to b with `up` as close to upHint as possible.
	local function axes(a, b, upHint)
		local d = (b - a).Unit
		local hint = upHint or V3(0, 1, 0)
		local up = hint - d * hint:Dot(d)
		if up.Magnitude < 1e-3 then
			up = V3(0, 0, 1) - d * d.Z
		end
		up = up.Unit
		return d, up, d:Cross(up)
	end

	-- Box from a to b.
	local function bar(bone, a, b, w, h, color, upHint, lengthScale)
		local d, up, right = axes(a, b, upHint)
		local len = (b - a).Magnitude * (lengthScale or 1)
		return block(bone, CFrame.fromMatrix((a + b) / 2, right, up, -d), V3(w, h, len), color)
	end

	-- Hexagonal body segment from a to b: a box with a ridged roof and a keel.
	-- opt: up, scale (length), roof / keel (fractions of h), belly (keel colour).
	local function seg(bone, a, b, w, h, color, opt)
		opt = opt or {}
		local d, up, right = axes(a, b, opt.up)
		local len = (b - a).Magnitude * (opt.scale or 1.12)
		local roof, keel = h * (opt.roof or 0.26), h * (opt.keel or 0.26)
		local core = h - roof - keel
		local mid = (a + b) / 2
		block(bone, CFrame.fromMatrix(mid, right, up, -d), V3(w, core, len), color)
		for _, sx in { 1, -1 } do
			if roof > 0.01 then
				rtri(bone, mid + up * (core / 2), right * (w / 2 * sx), up * roof, len, color)
			end
			if keel > 0.01 then
				rtri(bone, mid - up * (core / 2), right * (w / 2 * sx), -up * keel, len, opt.belly or color)
			end
		end
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
		if len1 > 0.05 then
			local w1 = wedge(bone, CFrame.fromMatrix((a + b) / 2, right, up, back), V3(MEMBRANE_THICKNESS, height, len1), color)
			w1.Name = name or "Membrane"
		end
		if len2 > 0.05 then
			local w2 = wedge(bone, CFrame.fromMatrix((a + c) / 2, -right, up, -back), V3(MEMBRANE_THICKNESS, height, len2), color)
			w2.Name = name or "Membrane"
		end
	end

	local rest = Rig.Rest
	local FWD, BACK = V3(0, 0, -1), V3(0, 0, 1)

	-- Torso ------------------------------------------------------------------
	-- { bone, centre, width, height, length }
	local torso = {
		{ "Chest", V3(0, 0.3, -4.0), 8.2, 7.8, 11.0 },
		{ "Body", V3(0, -0.1, 1.6), 7.2, 6.6, 9.6 },
		{ "Hips", V3(0, 0.1, 6.4), 6.2, 5.8, 7.0 },
	}
	for _, t in torso do
		local c, half = t[2], V3(0, 0, t[5] / 2)
		seg(t[1], c + half, c - half, t[3], t[4], Colors.Scale, { scale = 1, belly = Colors.Belly })
	end
	seg("Chest", V3(0, 1.6, -6.0), V3(0, 2.0, -10.6), 5.8, 6.0, Colors.Scale, { scale = 1, belly = Colors.Belly }) -- neck root

	local function ridgeY(z)
		local best = -math.huge
		for _, t in torso do
			if math.abs(z - t[2].Z) < t[5] / 2 then
				best = math.max(best, t[2].Y + t[4] / 2)
			end
		end
		return best
	end

	-- Dorsal sail along the back, tallest over the shoulders.
	do
		local z, k = -8.0, 0
		while z <= 9.4 do
			local t = (z + 8.0) / 17.4
			local height = 3.0 - 1.4 * t
			local bone = z < -1 and "Chest" or (z < 4 and "Body" or "Hips")
			local base = V3(0, ridgeY(z) - 0.3, z)
			fin(bone, base, V3(0, 1, 0.5), BACK, 1.9, height, 0.35, Colors.Spine)
			if k % 2 == 0 then
				for _, sx in { 1, -1 } do
					spike(bone, base + V3(1.3 * sx, -0.7, 0.2), V3(0.6 * sx, 0.7, 0.6), height * 0.5, 0.7, 0.3, Colors.SpineDark)
				end
			end
			z += 1.75
			k += 1
		end
	end

	-- Neck -------------------------------------------------------------------
	do
		local widths = { 4.9, 4.4, 3.9, 3.5, 3.2 }
		for i = 1, Rig.NeckCount do
			local name = "Neck" .. i
			local a = rest[name]
			local b = i < Rig.NeckCount and rest["Neck" .. (i + 1)] or rest.Head
			local w = widths[i]
			local h = w * 1.05
			seg(name, a, b, w, h, Colors.Scale, { scale = 1.3, belly = Colors.Belly })
			local p = a:Lerp(b, 0.4)
			fin(name, p + V3(0, h * 0.42, 0), V3(0, 1, 0.55), BACK, 1.7, 2.4 - 0.15 * (i - 1), 0.32, Colors.Spine)
			for _, sx in { 1, -1 } do
				spike(name, p + V3(w * 0.42 * sx, h * 0.12, 0.3), V3(0.7 * sx, 0.35, 0.75), 1.6 - 0.12 * i, 0.7, 0.28, Colors.SpineDark)
			end
		end
	end

	-- Head -------------------------------------------------------------------
	do
		local H = rest.Head
		local HS = 1.25 -- head scale
		local function h(x, y, z)
			return H + V3(x, y, z) * HS
		end
		local function sz(x, y, z)
			return V3(x, y, z) * HS
		end
		local function hblock(bone, x, y, z, size, color, material)
			return block(bone, CFrame.new(h(x, y, z)), size, color, material)
		end

		seg("Head", h(0, 0.3, 0.5), h(0, 0.3, -3.1), 3.0 * HS, 2.6 * HS, Colors.Scale, { scale = 1, belly = Colors.Scale }) -- cranium
		hblock("Head", 0, -0.15, -4.6, sz(2.1, 1.1, 3.6), Colors.Scale) -- snout
		rtri("Head", h(0, 0.4, -2.8), sz(0, 0, -3.6), sz(0, 0.75, 0), 2.1 * HS, Colors.Scale) -- sloped bridge
		hblock("Head", 0, 0.15, -6.55, sz(1.7, 0.8, 0.5), Colors.ScaleDark) -- nose
		hblock("Head", 0, -0.75, -4.0, sz(1.5, 0.08, 4.4), Colors.Mouth) -- palate

		for _, sx in { 1, -1 } do
			bar("Head", h(0.85 * sx, 1.45, -0.9), h(1.25 * sx, 0.95, -3.7), 0.8 * HS, 0.55 * HS, Colors.ScaleDark) -- brow
			local eye = hblock("Head", 1.47 * sx, 0.5, -2.75, sz(0.16, 0.38, 0.75), Colors.Eye, Enum.Material.Neon)
			eye.Name = "Eye"
			hblock("Head", 1.53 * sx, 0.5, -2.8, sz(0.06, 0.34, 0.14), Colors.Claw) -- pupil
			hblock("Head", 1.15 * sx, -0.55, -1.0, sz(0.8, 1.5, 1.9), Colors.Scale) -- jaw muscle
			hblock("Head", 0.52 * sx, 0.47, -6.6, sz(0.3, 0.16, 0.3), Colors.Claw) -- nostril

			-- Horn crown, three tiers sweeping back.
			spike("Head", h(0.9 * sx, 1.1, -0.6), V3(1.05 * sx, 1.5, 5.0), 5.4 * HS, 0.95, 0.5, Colors.Horn)
			spike("Head", h(1.4 * sx, 0.45, -0.4), V3(1.65 * sx, 0.5, 3.9), 4.3 * HS, 0.8, 0.45, Colors.Horn)
			spike("Head", h(1.45 * sx, -0.3, -0.7), V3(1.5 * sx, -0.45, 2.9), 3.3 * HS, 0.65, 0.4, Colors.Horn)
			spike("Head", h(0.45 * sx, 1.35, -0.5), V3(0.35 * sx, 1.0, 3.4), 3.2 * HS, 0.6, 0.35, Colors.Horn)

			for k = 0, 2 do -- brow spikes
				spike("Head", h(1.1 * sx, 1.3, -3.0 + 1.0 * k), V3(0.45 * sx, 0.7, 0.75), (0.8 + 0.2 * k) * HS, 0.55, 0.22, Colors.SpineDark)
			end
			for k = 0, 2 do -- cheek frill
				spike("Head", h(1.4 * sx, -0.15 - 0.3 * k, -1.8 + 0.7 * k), V3(0.8 * sx, -0.15, 0.7), (1.5 - 0.15 * k) * HS, 0.6, 0.22, Colors.ScaleDark)
			end
			for k = 0, 4 do -- upper teeth
				local big = k == 3 and 0.3 or 0
				spike("Head", h((0.85 - 0.05 * k) * sx, -0.7, -2.2 - 0.85 * k), V3(0, -1, -0.12), (0.6 + big) * HS, 0.4, 0.22, Colors.Tooth, BACK)
			end
		end
		for k = 0, 2 do -- snout ridge
			spike("Head", h(0, 0.95, -5.0 + 1.0 * k), V3(0, 0.75, 0.65), (0.6 + 0.12 * k) * HS, 0.55, 0.22, Colors.SpineDark, BACK)
		end
		fin("Head", h(0, 1.55, -0.4), V3(0, 1, 0.6), BACK, 1.8, 2.2, 0.3, Colors.Spine)

		-- Lower jaw: flat top, keel underneath.
		seg("Jaw", h(0, -1.1, -0.8), h(0, -1.1, -6.3), 1.85 * HS, 0.95 * HS, Colors.Scale, { scale = 1, roof = 0, keel = 0.35, belly = Colors.Belly })
		hblock("Jaw", 0, -0.86, -3.3, sz(0.9, 0.1, 3.6), Colors.Mouth) -- tongue
		for _, sx in { 1, -1 } do
			for k = 0, 3 do
				local big = k == 3 and 0.3 or 0
				spike("Jaw", h((0.72 - 0.05 * k) * sx, -0.95, -2.6 - 0.9 * k), V3(0, 1, -0.1), (0.55 + big) * HS, 0.38, 0.2, Colors.Tooth, BACK)
			end
			for k = 0, 2 do -- chin spikes
				spike("Jaw", h(0.55 * sx, -1.45, -1.4 - 1.1 * k), V3(0.3 * sx, -1, 0.6), (1.0 - 0.1 * k) * HS, 0.5, 0.22, Colors.ScaleDark, BACK)
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
			seg(name, a, b, w, w, Colors.Scale, { scale = 1.25, belly = Colors.Belly })
			local p = a:Lerp(b, 0.4)
			fin(name, p + V3(0, w * 0.42, 0), V3(0, 1, 0.55), BACK, 1.6, math.max(0.6, 1.9 - 0.13 * i), 0.3, Colors.Spine)
			if i >= 3 and i % 2 == 1 then
				for _, sx in { 1, -1 } do
					spike(name, p + V3(w * 0.42 * sx, 0, 0), V3(0.8 * sx, 0.1, 0.8), 1.1, 0.55, 0.22, Colors.SpineDark)
				end
			end
		end
		local tip = Rig.TailTip
		local last = "Tail" .. Rig.TailCount
		spike(last, tip + V3(0, 0, -0.6), BACK, 3.0, 1.2, 0.3, Colors.Spine)
		for _, sx in { 1, -1 } do
			spike(last, tip + V3(0.1 * sx, 0, -1.2), V3(0.75 * sx, 0, 1), 2.2, 0.9, 0.26, Colors.Spine)
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

		seg("Chest", S + V3(-0.6 * sx, -0.4, 2.6), S + V3(-0.6 * sx, -0.4, -2.4), 4.0, 4.6, Colors.Scale, { scale = 1 }) -- shoulder mass
		seg(arm, S, E, 2.9, 2.5, Colors.Scale, { scale = 1.15, up = BACK })
		seg(fore, E, W, 2.0, 1.8, Colors.Scale, { scale = 1.08, up = BACK })
		block(fore, CFrame.new(E), V3(2.4, 2.3, 2.4), Colors.ScaleDark) -- elbow
		spike(fore, E, V3(-0.3 * sx, 0.15, 1), 2.2, 0.9, 0.4, Colors.Claw)
		block(hand, CFrame.new(W), V3(2.2, 2.0, 2.2), Colors.ScaleDark) -- wrist

		-- Thumb claws: these carry the weight when the dragon walks on its wings.
		for _, dx in { 0.4, -0.35 } do
			local a = W + V3(dx * sx, -0.2, -0.4)
			local b = a + V3(dx * 1.6 * sx, -0.5, -2.2)
			bar(hand, a, b, 0.75, 0.75, Colors.ScaleDark, nil, 1.1)
			spike(hand, b + V3(0, 0, 0.2), V3(dx * 0.4 * sx, -0.55, -1), 1.4, 0.6, 0.35, Colors.Claw)
		end

		for i = 1, Rig.FingerCount do
			local Wr, Tr = wing.Wrist, wing.Tips[i]
			-- Bow each finger slightly toward the leading edge.
			local M = m(wing.Mids[i] + V3(0, 1, 0):Cross(Tr - Wr).Unit * 0.7)
			local T = m(Tr)
			local f = "F" .. i .. s
			bar(f, W, M, 0.8, 0.6, Colors.ScaleDark, nil, 1.04)
			bar(f, M, T, 0.6, 0.45, Colors.ScaleDark, nil, 1.02)
			block(f, CFrame.new(M), V3(0.95, 0.75, 0.95), Colors.ScaleDark) -- knuckle
			spike(f, T - (T - M).Unit * 0.3, T - M, 1.5, 0.5, 0.28, Colors.Claw, BACK)
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
		seg("Hips", hip + V3(-0.5 * sx, 0.6, 2.8), hip + V3(-0.5 * sx, 0.6, -2.4), 3.8, 5.0, Colors.Scale, { scale = 1 }) -- haunch
		seg("Thigh" .. s, hip, knee, 3.4, 4.4, Colors.Scale, { up = FWD, scale = 1.25 })
		block("Shin" .. s, CFrame.new(knee), V3(2.4, 2.4, 2.4), Colors.ScaleDark)
		seg("Shin" .. s, knee, ankle, 2.2, 2.6, Colors.Scale, { up = BACK, scale = 1.12 })
		spike("Shin" .. s, ankle, V3(0, 0.45, 1), 1.7, 0.9, 0.35, Colors.Claw)
		seg("Foot" .. s, ankle, toeBase, 1.9, 2.0, Colors.Scale, { up = FWD, scale = 1.3 })
		block("Toes" .. s, CFrame.new(toeBase + V3(0, 0.05, 0.1)), V3(2.7, 1.1, 2.2), Colors.ScaleDark)
		for _, dx in { -0.42, 0, 0.42 } do
			local a = toeBase + V3(dx * 1.5, 0, -0.3)
			local b = a + V3(dx * 2.4, -0.05, -2.7)
			bar("Toes" .. s, a, b, 0.9, 0.85, Colors.ScaleDark, nil, 1.1)
			spike("Toes" .. s, b + V3(0, 0.1, 0.25), V3(dx * 0.5, -0.38, -1), 1.3, 0.6, 0.36, Colors.Claw)
		end
		spike("Foot" .. s, ankle + V3(0, -0.6, 0.3), V3(0, -0.5, 1), 1.4, 0.6, 0.3, Colors.Claw) -- dewclaw
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
