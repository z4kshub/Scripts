-- Tunables for the Cinderwing dragon. Everything gameplay-facing lives here.
return {
	Tag = "Cinderwing", -- CollectionService tag put on every dragon model
	ModelName = "Cinderwing",

	-- Secret spawn. A zone is any instance tagged ZoneTag, or (fallback) the first
	-- instance in Workspace whose name matches one of ZoneNames.
	ZoneTag = "VolcanicBiome",
	ZoneNames = { "Volcanic", "VolcanicBiome", "Volcanic Biome", "Volcano" },
	SpawnCheckInterval = 60, -- seconds between spawn rolls
	SpawnChance = 0.04, -- chance per roll
	MaxWild = 1, -- unclaimed dragons allowed at once
	WildLifetime = 600, -- seconds before an unclaimed dragon vanishes
	ClaimHoldTime = 1.5,
	ClaimDistance = 30,

	-- Testing switches
	DebugSpawnOnStart = false, -- spawn one in the zone as soon as the server starts
	DebugMorphOnJoin = false, -- every player spawns as the dragon

	-- Stats
	MaxHealth = 2500,
	WalkSpeed = 16,

	-- Flight
	FlySpeed = 70,
	FlyBoostSpeed = 115, -- while holding BoostKey
	BoostKey = Enum.KeyCode.LeftShift,
	FlyAcceleration = 2.2, -- higher = snappier velocity changes
	TurnResponsiveness = 9, -- AlignOrientation responsiveness
	MaxPitch = 75, -- degrees the body pitches when climbing or diving
	TakeoffBoost = 35, -- upward launch speed on takeoff

	-- Camera
	CameraZoom = 70,
	CameraMaxZoom = 170,
}
