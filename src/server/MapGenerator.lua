--!strict
--[[
	MapGenerator.lua
	Авто-генератор драйвовой 3D-трассы «YEET A GOOBER! [MUTATIONS]»:
	- Вершина горы со спавном, Мастерской/Инкубатором и 6 базами игроков (4 пьедестала, компактные BillboardGui с MaxDistance = 45).
	- Край обрыва (YeetZone).
	- Длинный каньон-спуск и размеченная полоса приземления.
	- Поощрения в воздухе на разной высоте и дистанции:
	  * Золотые кольца ускорения
	  * Батуты-облака (наземные и небесные)
	  * Воздушные потоки (восходящие вихри)
	  * Парящие монеты (дуги в воздухе)
	  * Редкие кристаллы мутаций (выдают Щит и комбо)
	- Препятствия на трассе:
	  * Крутящиеся лопасти вентиляторов
	  * Грозовые тучи (бьют током и замедляют, а со Щитом дают СУПЕР-МУТАЦИЮ!)
	  * Летающие преграды (патрулируют воздух)
	  * Стены, которые можно пробить на высокой скорости
]]

local MapGenerator = {}

MapGenerator.MAP_NAME = "YeetAGooberMap"
MapGenerator.SUMMIT_SPAWN_POS = Vector3.new(0, 264, 20)
MapGenerator.CLIFF_EDGE_Z = -48
MapGenerator.YEET_ORIGIN = Vector3.new(0, 264, -49)

type SlopeSegment = {
	Z1: number,
	Y1: number,
	Z2: number,
	Y2: number,
}

local SLOPE_SEGMENTS: { SlopeSegment } = {
	{ Z1 = -47, Y1 = 259.0, Z2 = -280, Y2 = 186.0 },
	{ Z1 = -280, Y1 = 186.0, Z2 = -530, Y2 = 122.0 },
	{ Z1 = -530, Y1 = 122.0, Z2 = -790, Y2 = 70.0 },
	{ Z1 = -790, Y1 = 70.0, Z2 = -1030, Y2 = 32.0 },
	{ Z1 = -1030, Y1 = 32.0, Z2 = -1260, Y2 = 10.0 },
}

local SLOPE_WIDTH = 148

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = if props.Anchored ~= nil then props.Anchored else true
	part.CanCollide = if props.CanCollide ~= nil then props.CanCollide else true
	part.CanTouch = if props.CanTouch ~= nil then props.CanTouch else true
	part.CanQuery = if props.CanQuery ~= nil then props.CanQuery else true
	part.CastShadow = if props.CastShadow ~= nil then props.CastShadow else false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Color = props.Color or Color3.fromRGB(160, 165, 175)
	if props.Shape then
		part.Shape = props.Shape
	end
	part.Size = props.Size or Vector3.new(4, 1, 4)
	if props.CFrame then
		part.CFrame = props.CFrame
	elseif props.Position then
		part.Position = props.Position
	end
	if props.Transparency then
		part.Transparency = props.Transparency
	end
	part.Name = props.Name or "Part"
	if props.Parent then
		part.Parent = props.Parent
	end
	return part
end

local function addOverheadSign(
	parent: Instance,
	text: string,
	subText: string?,
	offset: Vector3,
	textColor: Color3?,
	options: { MaxDistance: number?, GuiSize: UDim2?, MaxMainText: number?, MaxSubText: number? }?
): BillboardGui
	local opts = options or {}
	local bg = Instance.new("BillboardGui")
	bg.Name = "SignGui"
	bg.Size = opts.GuiSize or UDim2.fromOffset(200, subText and 54 or 34)
	bg.StudsOffset = offset
	bg.MaxDistance = opts.MaxDistance or 180
	bg.AlwaysOnTop = false
	bg.Parent = parent

	local mainLabel = Instance.new("TextLabel")
	mainLabel.Name = "MainLabel"
	mainLabel.Size = UDim2.fromScale(1, subText and 0.56 or 1)
	mainLabel.BackgroundTransparency = 1
	mainLabel.Font = Enum.Font.GothamBlack
	mainLabel.TextScaled = true
	mainLabel.TextColor3 = textColor or Color3.new(1, 1, 1)
	mainLabel.TextStrokeTransparency = 0.2
	mainLabel.Text = text
	mainLabel.Parent = bg

	local tcMain = Instance.new("UITextSizeConstraint")
	tcMain.MaxTextSize = opts.MaxMainText or 18
	tcMain.MinTextSize = 8
	tcMain.Parent = mainLabel

	if subText then
		local sub = Instance.new("TextLabel")
		sub.Name = "SubLabel"
		sub.Position = UDim2.fromScale(0, 0.56)
		sub.Size = UDim2.fromScale(1, 0.44)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(230, 238, 255)
		sub.TextStrokeTransparency = 0.28
		sub.Text = subText
		sub.Parent = bg

		local tcSub = Instance.new("UITextSizeConstraint")
		tcSub.MaxTextSize = opts.MaxSubText or 13
		tcSub.MinTextSize = 7
		tcSub.Parent = sub
	end

	return bg
end

local function getSlopeSurfaceFrame(z: number, x: number): CFrame
	for _, seg in ipairs(SLOPE_SEGMENTS) do
		if z <= seg.Z1 and z >= seg.Z2 then
			local alpha = (z - seg.Z1) / (seg.Z2 - seg.Z1)
			local y = seg.Y1 + (seg.Y2 - seg.Y1) * alpha
			local p2 = Vector3.new(x, seg.Y2, seg.Z2)
			return CFrame.lookAt(Vector3.new(x, y, z), p2)
		end
	end
	return CFrame.new(x, 10, z)
end

local function createRampSegment(seg: SlopeSegment, index: number, parent: Instance)
	local pStart = Vector3.new(0, seg.Y1, seg.Z1)
	local pEnd = Vector3.new(0, seg.Y2, seg.Z2)
	local length = (pEnd - pStart).Magnitude + 3.0
	local thickness = 8
	local midTop = (pStart + pEnd) * 0.5
	local cfTop = CFrame.lookAt(midTop, pEnd)

	local color = if index % 2 == 1
		then Color3.fromRGB(92, 178, 95)
		else Color3.fromRGB(80, 162, 88)

	local ground = makePart({
		Name = "SlopeSegment_" .. tostring(index),
		Size = Vector3.new(SLOPE_WIDTH, thickness, length),
		CFrame = cfTop * CFrame.new(0, -thickness * 0.5, 0),
		Color = color,
		Material = Enum.Material.Grass,
		CastShadow = true,
		Parent = parent,
	})
	ground:SetAttribute("IsSlopeGround", true)

	local wallHeight = 26
	local wallThickness = 4
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = string.format("SlopeWall_%d_%s", index, side == -1 and "L" or "R"),
			Size = Vector3.new(wallThickness, wallHeight, length),
			CFrame = cfTop * CFrame.new(side * (SLOPE_WIDTH * 0.5 + wallThickness * 0.5), wallHeight * 0.4, 0),
			Color = Color3.fromRGB(108, 114, 132),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end
end

--============================================================================
-- ПООЩРЕНИЯ НА ТРАССЕ ПОЛЁТА
--============================================================================

-- 1. Золотые кольца ускорения
local function createGoldenRing(x: number, z: number, heightAboveSlope: number, radius: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)
	local centerPos = surfaceCF.Position + Vector3.new(0, heightAboveSlope, 0)

	local ringModel = Instance.new("Model")
	ringModel.Name = "GoldenRing_" .. tostring(index)
	ringModel.Parent = parent

	local sensor = makePart({
		Name = "RingSensor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4.0, radius * 1.92, radius * 1.92),
		CFrame = CFrame.new(centerPos) * CFrame.Angles(0, math.rad(90), 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = true,
		Parent = ringModel,
	})
	sensor:SetAttribute("IsGoldenRing", true)
	sensor:SetAttribute("RingId", index)
	ringModel.PrimaryPart = sensor

	local segmentCount = 8
	local segLen = 2 * radius * math.tan(math.pi / segmentCount) + 1.1
	for i = 1, segmentCount do
		local angle = (i - 1) * (2 * math.pi / segmentCount)
		local offset = Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
		makePart({
			Name = "GoldSeg_" .. tostring(i),
			Size = Vector3.new(2.0, segLen, 2.4),
			CFrame = CFrame.new(centerPos + offset) * CFrame.Angles(0, 0, angle),
			Color = Color3.fromRGB(255, 212, 45),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Parent = ringModel,
		})
	end

	addOverheadSign(sensor, "⭕ УСКОРЕНИЕ x1.5", nil, Vector3.new(0, radius + 3.2, 0), Color3.fromRGB(255, 225, 70))
end

-- 2. Батуты-облака (пушистые облака на склоне и в небе!)
local function createCloudTrampoline(x: number, z: number, heightAboveSlope: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)
	local centerPos = surfaceCF.Position + Vector3.new(0, heightAboveSlope, 0)

	local cloudModel = Instance.new("Model")
	cloudModel.Name = "CloudTrampoline_" .. tostring(index)
	cloudModel.Parent = parent

	local pad = makePart({
		Name = "CloudCore",
		Size = Vector3.new(22, 4.5, 22),
		Position = centerPos,
		Color = Color3.fromRGB(235, 250, 255),
		Material = Enum.Material.SmoothPlastic,
		Parent = cloudModel,
	})
	pad:SetAttribute("IsCloudTrampoline", true)
	pad:SetAttribute("CloudId", index)
	cloudModel.PrimaryPart = pad

	-- Пушистые сферы вокруг ядра облака
	local puffs = {
		{ Pos = Vector3.new(-7, 0.6, -4), S = 11 },
		{ Pos = Vector3.new(7, 0.8, -3), S = 11.5 },
		{ Pos = Vector3.new(-6, 0.5, 5), S = 10.5 },
		{ Pos = Vector3.new(6, 0.7, 5), S = 11 },
		{ Pos = Vector3.new(0, 1.8, 0), S = 13.5 },
	}
	for i, pf in ipairs(puffs) do
		makePart({
			Name = "CloudPuff_" .. tostring(i),
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(pf.S, pf.S * 0.65, pf.S),
			Position = centerPos + pf.Pos,
			Color = i == 5 and Color3.fromRGB(165, 240, 255) or Color3.fromRGB(245, 252, 255),
			Material = i == 5 and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Parent = cloudModel,
		})
	end

	addOverheadSign(pad, "☁️ БАТУТ-ОБЛАКО", nil, Vector3.new(0, 6.5, 0), Color3.fromRGB(145, 235, 255))
end

-- 3. Воздушные потоки (восходящие ветряные колонны)
local function createAirCurrent(x: number, z: number, heightAboveSlope: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)
	local centerPos = surfaceCF.Position + Vector3.new(0, heightAboveSlope + 18, 0)

	local stream = makePart({
		Name = "AirCurrent_" .. tostring(index),
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(38, 18, 18),
		CFrame = CFrame.new(centerPos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(115, 235, 255),
		Material = Enum.Material.ForceField,
		Transparency = 0.48,
		CanCollide = false,
		CanQuery = false,
		CanTouch = true,
		Parent = parent,
	})
	stream:SetAttribute("IsAirCurrent", true)

	local windParticles = Instance.new("ParticleEmitter")
	windParticles.Color = ColorSequence.new(Color3.fromRGB(180, 248, 255))
	windParticles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	windParticles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	windParticles.Lifetime = NumberRange.new(0.6, 1.0)
	windParticles.Rate = 18
	windParticles.Speed = NumberRange.new(28, 42)
	windParticles.EmissionDirection = Enum.NormalId.Right -- +X цилиндра = вверх!
	windParticles.Parent = stream

	addOverheadSign(stream, "🌪️ ПОТОК ВЕТРА", nil, Vector3.new(0, 21, 0), Color3.fromRGB(155, 245, 255))
end

-- 4. Парящие монеты (дуги в воздухе)
local function createFloatingCoinArc(x: number, startZ: number, baseH: number, arcPeak: number, count: number, arcIndex: number, parent: Instance)
	for i = 1, count do
		local alpha = (i - 1) / math.max(1, count - 1)
		local z = startZ - (i - 1) * 14
		local parabola = 4 * alpha * (1 - alpha) * arcPeak
		local surfaceCF = getSlopeSurfaceFrame(z, x)
		local pos = surfaceCF.Position + Vector3.new(0, baseH + parabola, 0)

		local coin = makePart({
			Name = string.format("FloatingCoin_%d_%d", arcIndex, i),
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 5.2, 5.2),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.fromRGB(255, 215, 35),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CanTouch = true,
			Parent = parent,
		})
		coin:SetAttribute("IsFloatingCoin", true)
		coin:SetAttribute("CoinBonus", 35)
	end
end

-- 5. Редкие кристаллы мутаций (дают Щит + рост Комбо!)
local function createMutationCrystal(x: number, z: number, heightAboveSlope: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)
	local pos = surfaceCF.Position + Vector3.new(0, heightAboveSlope, 0)

	local crystal = makePart({
		Name = "MutationCrystal_" .. tostring(index),
		Size = Vector3.new(6.5, 9.5, 6.5),
		CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(35), math.rad(45), math.rad(35)),
		Color = Color3.fromRGB(235, 65, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CanTouch = true,
		Parent = parent,
	})
	crystal:SetAttribute("IsMutationCrystal", true)

	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.55
	hl.FillColor = Color3.fromRGB(255, 110, 255)
	hl.OutlineColor = Color3.fromRGB(95, 245, 255)
	hl.Parent = crystal

	addOverheadSign(crystal, "💎 КРИСТАЛЛ МУТАЦИИ", "+Щит и Комбо x1.75!", Vector3.new(0, 7.5, 0), Color3.fromRGB(250, 125, 255))
end

--============================================================================
-- ПРЕПЯТСТВИЯ НА ТРАССЕ ПОЛЁТА
--============================================================================

-- 6. Крутящиеся лопасти вентиляторов
local function createSpinningFan(x: number, z: number, heightAboveSlope: number, bladeRadius: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)
	local centerPos = surfaceCF.Position + Vector3.new(0, heightAboveSlope, 0)

	local fanModel = Instance.new("Model")
	fanModel.Name = "SpinningFan_" .. tostring(index)
	fanModel:SetAttribute("IsSpinningFanModel", true)
	fanModel:SetAttribute("SpinSpeed", (index % 2 == 0 and -1 or 1) * 2.4)
	fanModel.Parent = parent

	local hub = makePart({
		Name = "FanHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.6, 6.5, 6.5),
		CFrame = CFrame.new(centerPos) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(45, 50, 65),
		Material = Enum.Material.Metal,
		Parent = fanModel,
	})
	fanModel.PrimaryPart = hub

	for b = 1, 4 do
		local ang = (b - 1) * (math.pi * 0.5)
		local offset = Vector3.new(math.cos(ang) * (bladeRadius * 0.55), math.sin(ang) * (bladeRadius * 0.55), 0)
		local blade = makePart({
			Name = "FanBlade_" .. tostring(b),
			Size = Vector3.new(bladeRadius, 3.6, 1.4),
			CFrame = CFrame.new(centerPos + offset) * CFrame.Angles(0, 0, ang),
			Color = b % 2 == 1 and Color3.fromRGB(245, 65, 65) or Color3.fromRGB(255, 190, 45),
			Material = Enum.Material.Metal,
			Parent = fanModel,
		})
		blade:SetAttribute("IsSpinningFan", true)
	end

	addOverheadSign(hub, "🌀 ВЕНТИЛЯТОР!", "Облетай лопасти!", Vector3.new(0, bladeRadius + 4, 0), Color3.fromRGB(255, 95, 95))
end

-- 7. Грозовые тучи (бьют током и замедляют, но со Щитом дают СУПЕР-МУТАЦИЮ!)
local function createThunderCloud(x: number, z: number, heightAboveSlope: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)
	local centerPos = surfaceCF.Position + Vector3.new(0, heightAboveSlope, 0)

	local stormModel = Instance.new("Model")
	stormModel.Name = "ThunderCloud_" .. tostring(index)
	stormModel.Parent = parent

	local core = makePart({
		Name = "StormCore",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(24, 13, 20),
		Position = centerPos,
		Color = Color3.fromRGB(48, 44, 68),
		Material = Enum.Material.Slate,
		CanCollide = false,
		CanQuery = false,
		CanTouch = true,
		Transparency = 0.12,
		Parent = stormModel,
	})
	core:SetAttribute("IsThunderCloud", true)
	stormModel.PrimaryPart = core

	for i, off in ipairs({ Vector3.new(-8, 1, 0), Vector3.new(8, 1.2, 0), Vector3.new(0, 3.5, -2) }) do
		makePart({
			Name = "StormPuff_" .. tostring(i),
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(15, 10, 14),
			Position = centerPos + off,
			Color = Color3.fromRGB(58, 52, 82),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Parent = stormModel,
		})
	end

	-- Яркая неоновая молния снизу тучи
	makePart({
		Name = "LightningBolt",
		Size = Vector3.new(1.8, 10, 1.8),
		CFrame = CFrame.new(centerPos + Vector3.new(0, -8, 0)) * CFrame.Angles(0, 0, math.rad(18)),
		Color = Color3.fromRGB(255, 235, 55),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Parent = stormModel,
	})

	addOverheadSign(
		core,
		"⛈️ ГРОЗОВАЯ ТУЧА",
		"Без щита: ШОК! Со щитом: СУПЕР-МУТАЦИЯ!",
		Vector3.new(0, 11, 0),
		Color3.fromRGB(255, 230, 75)
	)
end

-- 8. Летающие преграды (патрулируют каньон влево-вправо)
local function createFlyingHazard(x: number, z: number, heightAboveSlope: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)
	local centerPos = surfaceCF.Position + Vector3.new(0, heightAboveSlope, 0)

	local drone = makePart({
		Name = "FlyingHazard_" .. tostring(index),
		Size = Vector3.new(18, 5.5, 5.5),
		Position = centerPos,
		Color = Color3.fromRGB(235, 95, 40),
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	drone:SetAttribute("IsFlyingHazard", true)
	drone:SetAttribute("BaseX", centerPos.X)
	drone:SetAttribute("BaseY", centerPos.Y)
	drone:SetAttribute("BaseZ", centerPos.Z)
	drone:SetAttribute("PatrolAmp", 34)
	drone:SetAttribute("PatrolPhase", index * 1.1)

	addOverheadSign(drone, "🛸 ЛЕТАЮЩАЯ ПРЕГРАДА", nil, Vector3.new(0, 5.5, 0), Color3.fromRGB(255, 140, 75))
end

-- 9. Пробиваемые на высокой скорости стены
local function createBreakableWall(x: number, z: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)

	local wall = makePart({
		Name = "BreakableWall_" .. tostring(index),
		Size = Vector3.new(22, 15, 3.8),
		CFrame = surfaceCF * CFrame.new(0, 7.5, 0),
		Color = Color3.fromRGB(185, 115, 65),
		Material = Enum.Material.Brick,
		CastShadow = true,
		Parent = parent,
	})
	wall:SetAttribute("IsBreakableWall", true)
	wall:SetAttribute("WallId", index)

	addOverheadSign(wall, "🧱 СТЕНКА-ТАРАН", "Пробей на высокой скорости / Рывком!", Vector3.new(0, 10.5, 0), Color3.fromRGB(255, 180, 95))
end

--============================================================================
-- БАЗЫ ИГРОКОВ (ИСПРАВЛЕННЫЙ ВИЗУАЛ: МЕЛКИЙ ШРИФТ + MaxDistance = 45)
--============================================================================

local function createBasePlot(plotIndex: number, plotOrigin: Vector3, parent: Instance): Model
	local plotModel = Instance.new("Model")
	plotModel.Name = "BasePlot_" .. tostring(plotIndex)
	plotModel:SetAttribute("PlotIndex", plotIndex)
	plotModel.Parent = parent

	local basePad = makePart({
		Name = "PlotPad",
		Size = Vector3.new(28, 0.8, 22),
		Position = plotOrigin + Vector3.new(0, 0.4, 0),
		Color = Color3.fromRGB(52, 62, 82),
		Material = Enum.Material.SmoothPlastic,
		Parent = plotModel,
	})
	plotModel.PrimaryPart = basePad

	-- Компактная табличка базы с MaxDistance = 45 (не перекрывает экран!)
	addOverheadSign(
		basePad,
		"🏠 База #" .. tostring(plotIndex),
		"Свободно",
		Vector3.new(0, 6.4, 0),
		Color3.fromRGB(140, 220, 255),
		{
			MaxDistance = 45,
			GuiSize = UDim2.fromOffset(140, 34),
			MaxMainText = 13,
			MaxSubText = 10,
		}
	)

	local pedestalsFolder = Instance.new("Folder")
	pedestalsFolder.Name = "Pedestals"
	pedestalsFolder.Parent = plotModel

	local offsets = {
		Vector3.new(-8.5, 0, -5.5),
		Vector3.new(8.5, 0, -5.5),
		Vector3.new(-8.5, 0, 5.5),
		Vector3.new(8.5, 0, 5.5),
	}

	for slot = 1, 4 do
		local pedModel = Instance.new("Model")
		pedModel.Name = "Pedestal_" .. tostring(slot)
		pedModel:SetAttribute("SlotIndex", slot)
		pedModel.Parent = pedestalsFolder

		makePart({
			Name = "Pillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.0, 5.0, 5.0),
			CFrame = CFrame.new(plotOrigin + offsets[slot] + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(215, 220, 235),
			Material = Enum.Material.Marble,
			Parent = pedModel,
		})

		local topRing = makePart({
			Name = "TopPlate",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 5.6, 5.6),
			CFrame = CFrame.new(plotOrigin + offsets[slot] + Vector3.new(0, 3.55, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(85, 200, 255),
			Material = Enum.Material.Neon,
			Parent = pedModel,
		})
		pedModel.PrimaryPart = topRing

		-- Уменьшенный шрифт и MaxDistance = 45 над каждым слотом пьедестала!
		addOverheadSign(
			topRing,
			"Слот #" .. tostring(slot),
			"Пусто",
			Vector3.new(0, 2.3, 0),
			Color3.fromRGB(200, 210, 225),
			{
				MaxDistance = 45,
				GuiSize = UDim2.fromOffset(104, 26),
				MaxMainText = 11,
				MaxSubText = 9,
			}
		)
	end

	return plotModel
end

--============================================================================
-- ГЛАВНАЯ СБОРКА КАРТЫ
--============================================================================

function MapGenerator.EnsureMap(): Folder
	local existing = workspace:FindFirstChild(MapGenerator.MAP_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local defaultBaseplate = workspace:FindFirstChild("Baseplate")
	if defaultBaseplate and defaultBaseplate:IsA("BasePart") then
		defaultBaseplate:Destroy()
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MapGenerator.MAP_NAME
	mapFolder.Parent = workspace

	if not workspace:FindFirstChild("ActiveGoobers") then
		local activeFolder = Instance.new("Folder")
		activeFolder.Name = "ActiveGoobers"
		activeFolder.Parent = workspace
	end

	-- 1. ВЕРШИНА ГОРЫ
	local summitFolder = Instance.new("Folder")
	summitFolder.Name = "Summit"
	summitFolder.Parent = mapFolder

	makePart({
		Name = "SummitPlatform",
		Size = Vector3.new(168, 8, 102),
		Position = Vector3.new(0, 256, 2),
		Color = Color3.fromRGB(95, 175, 95),
		Material = Enum.Material.Grass,
		CastShadow = true,
		Parent = summitFolder,
	})

	makePart({
		Name = "MountainPillar",
		Size = Vector3.new(164, 252, 98),
		Position = Vector3.new(0, 126, 4),
		Color = Color3.fromRGB(105, 108, 120),
		Material = Enum.Material.Slate,
		Parent = summitFolder,
	})

	makePart({
		Name = "BackFence",
		Size = Vector3.new(168, 6, 3),
		Position = Vector3.new(0, 263, 51.5),
		Color = Color3.fromRGB(120, 125, 140),
		Material = Enum.Material.Slate,
		Parent = summitFolder,
	})
	makePart({
		Name = "LeftFence",
		Size = Vector3.new(3, 6, 102),
		Position = Vector3.new(-82.5, 263, 2),
		Color = Color3.fromRGB(120, 125, 140),
		Material = Enum.Material.Slate,
		Parent = summitFolder,
	})
	makePart({
		Name = "RightFence",
		Size = Vector3.new(3, 6, 102),
		Position = Vector3.new(82.5, 263, 2),
		Color = Color3.fromRGB(120, 125, 140),
		Material = Enum.Material.Slate,
		Parent = summitFolder,
	})

	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "SummitSpawn"
	spawnLoc.Anchored = true
	spawnLoc.CanCollide = true
	spawnLoc.Neutral = true
	spawnLoc.Size = Vector3.new(14, 1, 14)
	spawnLoc.CFrame = CFrame.new(0, 260.5, 18)
	spawnLoc.Color = Color3.fromRGB(70, 180, 255)
	spawnLoc.Material = Enum.Material.Neon
	spawnLoc.TopSurface = Enum.SurfaceType.Smooth
	spawnLoc.Parent = summitFolder

	-- 2. КРАЙ ОБРЫВА (ЗОНА ПИНКА)
	local yeetZone = makePart({
		Name = "YeetZone",
		Size = Vector3.new(50, 0.5, 14),
		Position = Vector3.new(0, 260.25, -41),
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.Neon,
		Parent = summitFolder,
	})
	addOverheadSign(
		yeetZone,
		"🦵 КРАЙ ОБРЫВА — ПНИ ЧУДИКА!",
		"Зажми ЛКМ / экран • В полёте: A/D и ПРОБЕЛ (Рывок)!",
		Vector3.new(0, 7.0, 0),
		Color3.fromRGB(255, 230, 75),
		{ MaxDistance = 95 }
	)

	-- 3. ЗОНА ИНКУБАТОРА / МАСТЕРСКОЙ ГУБЕРА
	local incubatorModel = Instance.new("Model")
	incubatorModel.Name = "IncubatorZone"
	incubatorModel.Parent = summitFolder

	local incBase = makePart({
		Name = "IncubatorBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.2, 14, 14),
		CFrame = CFrame.new(-44, 261.1, -12) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(65, 75, 95),
		Material = Enum.Material.Metal,
		Parent = incubatorModel,
	})
	incubatorModel.PrimaryPart = incBase

	local incGlass = makePart({
		Name = "IncubatorPod",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(11, 11, 11),
		CFrame = CFrame.new(-44, 267.5, -12) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(95, 255, 205),
		Material = Enum.Material.Glass,
		Transparency = 0.65,
		CanCollide = false,
		CanTouch = false,
		Parent = incubatorModel,
	})

	makePart({
		Name = "IncubatorTopCap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.5, 12.5, 12.5),
		CFrame = CFrame.new(-44, 273.5, -12) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(85, 245, 185),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = incubatorModel,
	})

	addOverheadSign(
		incGlass,
		"🎨 МАСТЕРСКАЯ И ИНКУБАТОР",
		"Собери чудика из стикеров и вырасти!",
		Vector3.new(0, 8.5, 0),
		Color3.fromRGB(110, 255, 190),
		{ MaxDistance = 85 }
	)

	local incPrompt = Instance.new("ProximityPrompt")
	incPrompt.Name = "IncubatorPrompt"
	incPrompt.ActionText = "Вырастить / Взять чудика"
	incPrompt.ObjectText = "Мастерская Губера"
	incPrompt.MaxActivationDistance = 18
	incPrompt.HoldDuration = 0
	incPrompt.RequiresLineOfSight = false
	incPrompt.Parent = incBase

	-- 4. ЗОНА БАЗ ИГРОКОВ (6 слотов с аккуратным расстоянием между ними)
	local basesFolder = Instance.new("Folder")
	basesFolder.Name = "PlayerBases"
	basesFolder.Parent = summitFolder

	local baseLocations = {
		Vector3.new(54, 260, -24),
		Vector3.new(54, 260, 5),
		Vector3.new(54, 260, 34),
		Vector3.new(-54, 260, 28),
		Vector3.new(-19, 260, 37),
		Vector3.new(19, 260, 37),
	}
	for i, pos in ipairs(baseLocations) do
		createBasePlot(i, pos, basesFolder)
	end

	-- 5. НАКЛОННЫЙ СПУСК
	local slopeFolder = Instance.new("Folder")
	slopeFolder.Name = "Slope"
	slopeFolder.Parent = mapFolder

	for idx, seg in ipairs(SLOPE_SEGMENTS) do
		createRampSegment(seg, idx, slopeFolder)
	end

	-- 6. ПООЩРЕНИЯ И ПРЕПЯТСТВИЯ НА ТРАССЕ ПОЛЁТА
	local trackFolder = Instance.new("Folder")
	trackFolder.Name = "BoostersAndRings"
	trackFolder.Parent = mapFolder

	local fansFolder = Instance.new("Folder")
	fansFolder.Name = "SpinningFans"
	fansFolder.Parent = trackFolder

	local flyingHazardsFolder = Instance.new("Folder")
	flyingHazardsFolder.Name = "FlyingHazards"
	flyingHazardsFolder.Parent = trackFolder

	-- Золотые кольца ускорения (на разной высоте 18..62 стада и по всей ширине)
	local goldenRingsLayout = {
		{ X = 0, Z = -110, H = 22, R = 14 },
		{ X = -26, Z = -205, H = 34, R = 15 },
		{ X = 26, Z = -295, H = 28, R = 15 },
		{ X = 0, Z = -390, H = 48, R = 16 },
		{ X = -34, Z = -495, H = 26, R = 16 },
		{ X = 32, Z = -590, H = 54, R = 16 },
		{ X = 0, Z = -690, H = 32, R = 16 },
		{ X = -28, Z = -805, H = 46, R = 17 },
		{ X = 28, Z = -915, H = 28, R = 17 },
		{ X = 0, Z = -1035, H = 56, R = 18 },
		{ X = -24, Z = -1155, H = 24, R = 18 },
		{ X = 0, Z = -1340, H = 30, R = 19 },
	}
	for idx, item in ipairs(goldenRingsLayout) do
		createGoldenRing(item.X, item.Z, item.H, item.R, idx, trackFolder)
	end

	-- Батуты-облака (как низкие спасительные, так и высокие небесные!)
	local cloudsLayout = {
		{ X = 0, Z = -150, H = 3.5 },
		{ X = -30, Z = -245, H = 18 },
		{ X = 28, Z = -340, H = 4.0 },
		{ X = 0, Z = -440, H = 24 },
		{ X = -34, Z = -545, H = 4.0 },
		{ X = 30, Z = -640, H = 28 },
		{ X = 0, Z = -745, H = 4.0 },
		{ X = -28, Z = -855, H = 22 },
		{ X = 28, Z = -965, H = 4.0 },
		{ X = 0, Z = -1085, H = 26 },
		{ X = -22, Z = -1205, H = 4.0 },
		{ X = 22, Z = -1420, H = 6.0 },
		{ X = 0, Z = -1650, H = 8.0 },
		{ X = 0, Z = -1900, H = 8.0 },
	}
	for idx, item in ipairs(cloudsLayout) do
		createCloudTrampoline(item.X, item.Z, item.H, idx, trackFolder)
	end

	-- Восходящие воздушные потоки
	local airCurrentsLayout = {
		{ X = 24, Z = -175, H = 4 },
		{ X = -22, Z = -360, H = 6 },
		{ X = 28, Z = -520, H = 6 },
		{ X = -30, Z = -710, H = 6 },
		{ X = 24, Z = -890, H = 6 },
		{ X = -24, Z = -1060, H = 6 },
		{ X = 0, Z = -1280, H = 4 },
		{ X = 0, Z = -1540, H = 4 },
	}
	for idx, item in ipairs(airCurrentsLayout) do
		createAirCurrent(item.X, item.Z, item.H, idx, trackFolder)
	end

	-- Дуги парящих монет на разной высоте
	local coinArcs = {
		{ X = 0, Z = -95, H = 16, Peak = 14, Count = 5 },
		{ X = -26, Z = -220, H = 22, Peak = 18, Count = 5 },
		{ X = 26, Z = -310, H = 14, Peak = 16, Count = 5 },
		{ X = 0, Z = -460, H = 28, Peak = 20, Count = 6 },
		{ X = -30, Z = -620, H = 18, Peak = 16, Count = 5 },
		{ X = 28, Z = -780, H = 24, Peak = 18, Count = 5 },
		{ X = 0, Z = -990, H = 22, Peak = 22, Count = 6 },
		{ X = 0, Z = -1360, H = 16, Peak = 18, Count = 6 },
	}
	for idx, arc in ipairs(coinArcs) do
		createFloatingCoinArc(arc.X, arc.Z, arc.H, arc.Peak, arc.Count, idx, trackFolder)
	end

	-- Редкие кристаллы мутаций (высоко в воздухе — дают Щит перед грозовыми тучами!)
	local crystalsLayout = {
		{ X = 0, Z = -225, H = 48 },
		{ X = 28, Z = -420, H = 52 },
		{ X = -28, Z = -615, H = 54 },
		{ X = 0, Z = -825, H = 56 },
		{ X = 26, Z = -1015, H = 52 },
		{ X = 0, Z = -1240, H = 44 },
	}
	for idx, cr in ipairs(crystalsLayout) do
		createMutationCrystal(cr.X, cr.Z, cr.H, idx, trackFolder)
	end

	-- Крутящиеся вентиляторы
	local fansLayout = {
		{ X = -18, Z = -265, H = 28, R = 15 },
		{ X = 20, Z = -470, H = 34, R = 16 },
		{ X = -22, Z = -665, H = 30, R = 16 },
		{ X = 18, Z = -845, H = 36, R = 17 },
		{ X = -18, Z = -1005, H = 28, R = 17 },
		{ X = 22, Z = -1185, H = 26, R = 17 },
		{ X = 0, Z = -1480, H = 26, R = 18 },
	}
	for idx, fn in ipairs(fansLayout) do
		createSpinningFan(fn.X, fn.Z, fn.H, fn.R, idx, fansFolder)
	end

	-- Грозовые тучи (со Щитом дают СУПЕР-МУТАЦИЮ!)
	local stormsLayout = {
		{ X = 0, Z = -315, H = 42 },
		{ X = 24, Z = -535, H = 44 },
		{ X = -24, Z = -730, H = 46 },
		{ X = 0, Z = -940, H = 44 },
		{ X = 22, Z = -1125, H = 38 },
		{ X = 0, Z = -1395, H = 34 },
	}
	for idx, st in ipairs(stormsLayout) do
		createThunderCloud(st.X, st.Z, st.H, idx, trackFolder)
	end

	-- Летающие преграды
	local flyingLayout = {
		{ X = 0, Z = -190, H = 32 },
		{ X = 0, Z = -375, H = 26 },
		{ X = 0, Z = -575, H = 36 },
		{ X = 0, Z = -770, H = 28 },
		{ X = 0, Z = -960, H = 38 },
		{ X = 0, Z = -1145, H = 30 },
		{ X = 0, Z = -1590, H = 22 },
	}
	for idx, fl in ipairs(flyingLayout) do
		createFlyingHazard(fl.X, fl.Z, fl.H, idx, flyingHazardsFolder)
	end

	-- Пробиваемые на высокой скорости стены
	local wallsLayout = {
		{ X = 18, Z = -185 },
		{ X = -20, Z = -345 },
		{ X = 18, Z = -505 },
		{ X = -18, Z = -680 },
		{ X = 22, Z = -835 },
		{ X = -20, Z = -985 },
		{ X = 16, Z = -1170 },
		{ X = 0, Z = -1310 },
	}
	for idx, wl in ipairs(wallsLayout) do
		createBreakableWall(wl.X, wl.Z, idx, trackFolder)
	end

	-- 7. РАЗМЕЧЕННАЯ ЗОНА ПРИЗЕМЛЕНИЯ ВНИЗУ (Z = -1260 .. -2760)
	local landingFolder = Instance.new("Folder")
	landingFolder.Name = "LandingZone"
	landingFolder.Parent = mapFolder

	local runway = makePart({
		Name = "LandingRunway",
		Size = Vector3.new(168, 8, 1500),
		Position = Vector3.new(0, 6, -2010),
		Color = Color3.fromRGB(58, 66, 84),
		Material = Enum.Material.Concrete,
		CastShadow = true,
		Parent = landingFolder,
	})
	runway:SetAttribute("IsSlopeGround", true)

	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "LandingWall_" .. (side == -1 and "L" or "R"),
			Size = Vector3.new(4, 24, 1500),
			Position = Vector3.new(side * 86, 18, -2010),
			Color = Color3.fromRGB(95, 105, 125),
			Material = Enum.Material.Slate,
			Parent = landingFolder,
		})
	end
	makePart({
		Name = "LandingBackstop",
		Size = Vector3.new(176, 40, 8),
		Position = Vector3.new(0, 26, -2762),
		Color = Color3.fromRGB(255, 75, 75),
		Material = Enum.Material.Neon,
		Parent = landingFolder,
	})

	for z = -1300, -2700, -200 do
		local distMeters = math.abs(z - MapGenerator.CLIFF_EDGE_Z)
		local stripe = makePart({
			Name = "DistanceMarker_" .. tostring(distMeters),
			Size = Vector3.new(164, 0.3, 3),
			Position = Vector3.new(0, 10.15, z),
			Color = Color3.fromRGB(90, 220, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = false,
			Parent = landingFolder,
		})
		addOverheadSign(stripe, string.format("🏁 %d м", distMeters), nil, Vector3.new(0, 7, 0), Color3.fromRGB(130, 235, 255))
	end

	MapGenerator.StartTrackAnimator(mapFolder)
	return mapFolder
end

local animatorRunning = false

function MapGenerator.StartTrackAnimator(mapFolder: Folder)
	if animatorRunning then
		return
	end
	animatorRunning = true

	local trackFolder = mapFolder:FindFirstChild("BoostersAndRings")
	if not trackFolder then
		return
	end

	type CachedFan = {
		Center: Vector3,
		Speed: number,
		Radius: number,
		Blades: { BasePart },
	}
	local fans: { CachedFan } = {}
	local fansFolder = trackFolder:FindFirstChild("SpinningFans")
	if fansFolder then
		for _, fanModel in ipairs(fansFolder:GetChildren()) do
			local hub = fanModel:FindFirstChild("FanHub") :: BasePart?
			if hub then
				local blades: { BasePart } = {}
				local r = 16
				for b = 1, 4 do
					local bl = fanModel:FindFirstChild("FanBlade_" .. tostring(b)) :: BasePart?
					if bl then
						r = bl.Size.X
						table.insert(blades, bl)
					end
				end
				table.insert(fans, {
					Center = hub.Position,
					Speed = tonumber(fanModel:GetAttribute("SpinSpeed")) or 2.4,
					Radius = r,
					Blades = blades,
				})
			end
		end
	end

	local hazards: { BasePart } = {}
	local hazardsFolder = trackFolder:FindFirstChild("FlyingHazards")
	if hazardsFolder then
		for _, child in ipairs(hazardsFolder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(hazards, child)
			end
		end
	end

	-- Лёгкий цикл анимации (20 Гц по заранее закэшированному массиву без сканирования дерева)
	task.spawn(function()
		while mapFolder.Parent do
			local t = os.clock()
			for _, fan in ipairs(fans) do
				local spin = t * fan.Speed
				local armDist = fan.Radius * 0.55
				for idx, blade in ipairs(fan.Blades) do
					if blade.Parent then
						local ang = spin + (idx - 1) * (math.pi * 0.5)
						local off = Vector3.new(math.cos(ang) * armDist, math.sin(ang) * armDist, 0)
						blade.CFrame = CFrame.new(fan.Center + off) * CFrame.Angles(0, 0, ang)
					end
				end
			end

			for _, hz in ipairs(hazards) do
				if hz.Parent then
					local bx = tonumber(hz:GetAttribute("BaseX")) or 0
					local by = tonumber(hz:GetAttribute("BaseY")) or 30
					local bz = tonumber(hz:GetAttribute("BaseZ")) or -300
					local amp = tonumber(hz:GetAttribute("PatrolAmp")) or 32
					local phase = tonumber(hz:GetAttribute("PatrolPhase")) or 0
					local curX = bx + math.sin(t * 1.45 + phase) * amp
					hz.Position = Vector3.new(curX, by, bz)
				end
			end

			task.wait(0.05)
		end
		animatorRunning = false
	end)
end

return MapGenerator
