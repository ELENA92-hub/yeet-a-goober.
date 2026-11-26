--!strict
--[[
	MapGenerator.lua
	Авто-генератор тестовой 3D-карты при старте сервера (если карта ещё не создана):
	- Платформа на вершине горы со спавном
	- Зона инкубатора с капсулой и ProximityPrompt
	- 6 слотов баз игроков (по 4 пьедестала в каждой) для пассивного дохода
	- Край обрыва (зона заряда пинка)
	- Длинный наклонный спуск (5 плавных секций) с бортиками
	- Батуты-ускорители, воздушные кольца-множители (x1.5) и разрушаемые препятствия
	- Размеченная зона приземления внизу
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
	{ Z1 = -47, Y1 = 259.0, Z2 = -260, Y2 = 186.0 },
	{ Z1 = -260, Y1 = 186.0, Z2 = -490, Y2 = 122.0 },
	{ Z1 = -490, Y1 = 122.0, Z2 = -730, Y2 = 70.0 },
	{ Z1 = -730, Y1 = 70.0, Z2 = -970, Y2 = 32.0 },
	{ Z1 = -970, Y1 = 32.0, Z2 = -1200, Y2 = 10.0 },
}

local SLOPE_WIDTH = 136

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

local function addOverheadSign(parent: Instance, text: string, subText: string?, offset: Vector3, textColor: Color3?)
	local bg = Instance.new("BillboardGui")
	bg.Name = "SignGui"
	bg.Size = UDim2.fromOffset(240, subText and 68 or 42)
	bg.StudsOffset = offset
	bg.MaxDistance = 220
	bg.AlwaysOnTop = false
	bg.Parent = parent

	local mainLabel = Instance.new("TextLabel")
	mainLabel.Name = "MainLabel"
	mainLabel.Size = UDim2.fromScale(1, subText and 0.58 or 1)
	mainLabel.BackgroundTransparency = 1
	mainLabel.Font = Enum.Font.GothamBlack
	mainLabel.TextScaled = true
	mainLabel.TextColor3 = textColor or Color3.new(1, 1, 1)
	mainLabel.TextStrokeTransparency = 0.15
	mainLabel.Text = text
	mainLabel.Parent = bg

	if subText then
		local sub = Instance.new("TextLabel")
		sub.Name = "SubLabel"
		sub.Position = UDim2.fromScale(0, 0.58)
		sub.Size = UDim2.fromScale(1, 0.42)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(235, 240, 255)
		sub.TextStrokeTransparency = 0.25
		sub.Text = subText
		sub.Parent = bg
	end

	return bg
end

-- Возвращает высоту поверхности склона и ориентацию в точке Z
local function getSlopeSurfaceFrame(z: number, x: number): CFrame
	for _, seg in ipairs(SLOPE_SEGMENTS) do
		if z <= seg.Z1 and z >= seg.Z2 then
			local alpha = (z - seg.Z1) / (seg.Z2 - seg.Z1)
			local y = seg.Y1 + (seg.Y2 - seg.Y1) * alpha
			local p1 = Vector3.new(x, seg.Y1, seg.Z1)
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
		then Color3.fromRGB(92, 175, 95)
		else Color3.fromRGB(82, 160, 88)

	makePart({
		Name = "SlopeSegment_" .. tostring(index),
		Size = Vector3.new(SLOPE_WIDTH, thickness, length),
		CFrame = cfTop * CFrame.new(0, -thickness * 0.5, 0),
		Color = color,
		Material = Enum.Material.Grass,
		CastShadow = true,
		Parent = parent,
	})

	-- Боковые бортики, чтобы Губер не вылетал в пустоту по краям
	local wallHeight = 16
	local wallThickness = 4
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = string.format("SlopeWall_%d_%s", index, side == -1 and "L" or "R"),
			Size = Vector3.new(wallThickness, wallHeight, length),
			CFrame = cfTop * CFrame.new(side * (SLOPE_WIDTH * 0.5 + wallThickness * 0.5), wallHeight * 0.35, 0),
			Color = Color3.fromRGB(110, 115, 130),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end
end

local function createTrampoline(x: number, z: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)

	local pad = makePart({
		Name = "Trampoline_" .. tostring(index),
		Size = Vector3.new(18, 1.6, 20),
		CFrame = surfaceCF * CFrame.new(0, 0.8, 0),
		Color = Color3.fromRGB(255, 55, 195),
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	pad:SetAttribute("IsTrampoline", true)
	pad:SetAttribute("TrampolineId", index)

	-- Чёрная рамка вокруг батута
	makePart({
		Name = "TrampolineFrame_" .. tostring(index),
		Size = Vector3.new(20, 1.0, 22),
		CFrame = surfaceCF * CFrame.new(0, 0.4, 0),
		Color = Color3.fromRGB(35, 35, 45),
		Material = Enum.Material.Metal,
		CanTouch = false,
		Parent = parent,
	})

	addOverheadSign(pad, "⚡ БАТУТ x1.5", nil, Vector3.new(0, 5.5, 0), Color3.fromRGB(255, 120, 235))
end

local function createMultiplierRing(x: number, z: number, heightAboveSlope: number, radius: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)
	local centerPos = surfaceCF.Position + Vector3.new(0, heightAboveSlope, 0)

	local ringModel = Instance.new("Model")
	ringModel.Name = "MultiplierRing_" .. tostring(index)
	ringModel.Parent = parent

	-- Невидимый сенсор касания внутри кольца
	local sensor = makePart({
		Name = "RingSensor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.5, radius * 1.9, radius * 1.9),
		CFrame = CFrame.new(centerPos) * CFrame.Angles(0, math.rad(90), 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = true,
		Parent = ringModel,
	})
	sensor:SetAttribute("IsMultiplierRing", true)
	sensor:SetAttribute("RingId", index)
	ringModel.PrimaryPart = sensor

	-- 8 неоновых сегментов восьмиугольного кольца (оптимизировано для мобильных)
	local segmentCount = 8
	local segLen = 2 * radius * math.tan(math.pi / segmentCount) + 1.0
	for i = 1, segmentCount do
		local angle = (i - 1) * (2 * math.pi / segmentCount)
		local offset = Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
		makePart({
			Name = "RingSegment_" .. tostring(i),
			Size = Vector3.new(1.8, segLen, 2.2),
			CFrame = CFrame.new(centerPos + offset) * CFrame.Angles(0, 0, angle),
			Color = Color3.fromRGB(255, 210, 45),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Parent = ringModel,
		})
	end

	addOverheadSign(sensor, "⭕ КОЛЬЦО x1.5", "Пролети сквозь!", Vector3.new(0, radius + 3.5, 0), Color3.fromRGB(255, 225, 75))
end

local function createObstacleCluster(x: number, z: number, index: number, parent: Instance)
	local surfaceCF = getSlopeSurfaceFrame(z, x)

	local block = makePart({
		Name = "Obstacle_" .. tostring(index),
		Size = Vector3.new(14, 10, 4.5),
		CFrame = surfaceCF * CFrame.new(0, 5.0, 0),
		Color = Color3.fromRGB(165, 105, 60),
		Material = Enum.Material.WoodPlanks,
		CastShadow = true,
		Parent = parent,
	})
	block:SetAttribute("IsObstacle", true)
	block:SetAttribute("ObstacleId", index)

	addOverheadSign(block, "🧱 ПРЕГРАДА", "Тяжёлая мутация пробивает!", Vector3.new(0, 7.5, 0), Color3.fromRGB(255, 165, 95))
end

local function createBasePlot(plotIndex: number, plotOrigin: Vector3, parent: Instance): Model
	local plotModel = Instance.new("Model")
	plotModel.Name = "BasePlot_" .. tostring(plotIndex)
	plotModel:SetAttribute("PlotIndex", plotIndex)
	plotModel.Parent = parent

	local basePad = makePart({
		Name = "PlotPad",
		Size = Vector3.new(26, 0.8, 20),
		Position = plotOrigin + Vector3.new(0, 0.4, 0),
		Color = Color3.fromRGB(55, 65, 85),
		Material = Enum.Material.SmoothPlastic,
		Parent = plotModel,
	})
	plotModel.PrimaryPart = basePad

	addOverheadSign(basePad, "🏠 Свободная база #" .. tostring(plotIndex), "Пассивный доход Губеров", Vector3.new(0, 8.5, 0), Color3.fromRGB(140, 220, 255))

	local pedestalsFolder = Instance.new("Folder")
	pedestalsFolder.Name = "Pedestals"
	pedestalsFolder.Parent = plotModel

	local offsets = {
		Vector3.new(-7.5, 0, -4.5),
		Vector3.new(7.5, 0, -4.5),
		Vector3.new(-7.5, 0, 4.5),
		Vector3.new(7.5, 0, 4.5),
	}

	for slot = 1, 4 do
		local pedModel = Instance.new("Model")
		pedModel.Name = "Pedestal_" .. tostring(slot)
		pedModel:SetAttribute("SlotIndex", slot)
		pedModel.Parent = pedestalsFolder

		makePart({
			Name = "Pillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.0, 5.2, 5.2),
			CFrame = CFrame.new(plotOrigin + offsets[slot] + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(215, 220, 235),
			Material = Enum.Material.Marble,
			Parent = pedModel,
		})

		local topRing = makePart({
			Name = "TopPlate",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 5.8, 5.8),
			CFrame = CFrame.new(plotOrigin + offsets[slot] + Vector3.new(0, 3.55, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(85, 200, 255),
			Material = Enum.Material.Neon,
			Parent = pedModel,
		})
		pedModel.PrimaryPart = topRing

		addOverheadSign(topRing, "Слот #" .. tostring(slot), "Пусто", Vector3.new(0, 3.2, 0), Color3.fromRGB(200, 210, 225))
	end

	return plotModel
end

function MapGenerator.EnsureMap(): Folder
	local existing = workspace:FindFirstChild(MapGenerator.MAP_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	-- Удаляем стандартный Baseplate внизу, если он мешает обзору горы
	local defaultBaseplate = workspace:FindFirstChild("Baseplate")
	if defaultBaseplate and defaultBaseplate:IsA("BasePart") then
		defaultBaseplate:Destroy()
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MapGenerator.MAP_NAME
	mapFolder.Parent = workspace

	-- Папка для летящих Губеров
	if not workspace:FindFirstChild("ActiveGoobers") then
		local activeFolder = Instance.new("Folder")
		activeFolder.Name = "ActiveGoobers"
		activeFolder.Parent = workspace
	end

	-- 1. ПЛАТФОРМА НА ВЕРШИНЕ ГОРЫ
	local summitFolder = Instance.new("Folder")
	summitFolder.Name = "Summit"
	summitFolder.Parent = mapFolder

	makePart({
		Name = "SummitPlatform",
		Size = Vector3.new(156, 8, 96),
		Position = Vector3.new(0, 256, 0),
		Color = Color3.fromRGB(95, 175, 95),
		Material = Enum.Material.Grass,
		CastShadow = true,
		Parent = summitFolder,
	})

	-- Скальное основание под вершиной для красивого силуэта горы
	makePart({
		Name = "MountainPillar",
		Size = Vector3.new(152, 252, 92),
		Position = Vector3.new(0, 126, 2),
		Color = Color3.fromRGB(105, 108, 120),
		Material = Enum.Material.Slate,
		Parent = summitFolder,
	})

	-- Ограждения по бокам и сзади вершины (спереди обрыв открыт!)
	makePart({
		Name = "BackFence",
		Size = Vector3.new(156, 6, 3),
		Position = Vector3.new(0, 263, 46.5),
		Color = Color3.fromRGB(120, 125, 140),
		Material = Enum.Material.Slate,
		Parent = summitFolder,
	})
	makePart({
		Name = "LeftFence",
		Size = Vector3.new(3, 6, 96),
		Position = Vector3.new(-76.5, 263, 0),
		Color = Color3.fromRGB(120, 125, 140),
		Material = Enum.Material.Slate,
		Parent = summitFolder,
	})
	makePart({
		Name = "RightFence",
		Size = Vector3.new(3, 6, 96),
		Position = Vector3.new(76.5, 263, 0),
		Color = Color3.fromRGB(120, 125, 140),
		Material = Enum.Material.Slate,
		Parent = summitFolder,
	})

	-- Точка спавна игроков на вершине лицом к обрыву (-Z)
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

	-- 2. КРАЙ ОБРЫВА (ЗОНА ЗАПУСКА / YEET ZONE)
	local yeetZone = makePart({
		Name = "YeetZone",
		Size = Vector3.new(48, 0.5, 14),
		Position = Vector3.new(0, 260.25, -41),
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.Neon,
		Parent = summitFolder,
	})
	addOverheadSign(
		yeetZone,
		"🦵 ЗОНА ПИНКА (КРАЙ ОБРЫВА)",
		"Возьми Губера и зажми ЛКМ / экран!",
		Vector3.new(0, 7.5, 0),
		Color3.fromRGB(255, 230, 75)
	)

	-- 3. ЗОНА ИНКУБАТОРА
	local incubatorModel = Instance.new("Model")
	incubatorModel.Name = "IncubatorZone"
	incubatorModel.Parent = summitFolder

	local incBase = makePart({
		Name = "IncubatorBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.2, 14, 14),
		CFrame = CFrame.new(-42, 261.1, -12) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(65, 75, 95),
		Material = Enum.Material.Metal,
		Parent = incubatorModel,
	})
	incubatorModel.PrimaryPart = incBase

	local incGlass = makePart({
		Name = "IncubatorPod",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(11, 11, 11),
		CFrame = CFrame.new(-42, 267.5, -12) * CFrame.Angles(0, 0, math.rad(90)),
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
		CFrame = CFrame.new(-42, 273.5, -12) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(85, 245, 185),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = incubatorModel,
	})

	addOverheadSign(
		incGlass,
		"🥚 ИНКУБАТОР МУТАЦИЙ",
		"Нажми кнопку «Вырастить» (5 сек)",
		Vector3.new(0, 9.5, 0),
		Color3.fromRGB(110, 255, 190)
	)

	local incPrompt = Instance.new("ProximityPrompt")
	incPrompt.Name = "IncubatorPrompt"
	incPrompt.ActionText = "Вырастить / Взять Губера"
	incPrompt.ObjectText = "Инкубатор"
	incPrompt.MaxActivationDistance = 18
	incPrompt.HoldDuration = 0
	incPrompt.RequiresLineOfSight = false
	incPrompt.Parent = incBase

	-- 4. ЗОНА БАЗ ИГРОКОВ (6 баз по 4 пьедестала)
	local basesFolder = Instance.new("Folder")
	basesFolder.Name = "PlayerBases"
	basesFolder.Parent = summitFolder

	local baseLocations = {
		Vector3.new(48, 260, -24),
		Vector3.new(48, 260, 4),
		Vector3.new(48, 260, 32),
		Vector3.new(-48, 260, 24),
		Vector3.new(-16, 260, 34),
		Vector3.new(16, 260, 34),
	}
	for i, pos in ipairs(baseLocations) do
		createBasePlot(i, pos, basesFolder)
	end

	-- 5. ДЛИННЫЙ НАКЛОННЫЙ СПУСК С БАТУТАМИ, КОЛЬЦАМИ И ПРЕГРАДАМИ
	local slopeFolder = Instance.new("Folder")
	slopeFolder.Name = "Slope"
	slopeFolder.Parent = mapFolder

	for idx, seg in ipairs(SLOPE_SEGMENTS) do
		createRampSegment(seg, idx, slopeFolder)
	end

	local boostersFolder = Instance.new("Folder")
	boostersFolder.Name = "BoostersAndRings"
	boostersFolder.Parent = mapFolder

	-- 12 батутов-ускорителей вдоль всего склона
	local trampolineLayout = {
		{ X = 0, Z = -140 },
		{ X = -28, Z = -235 },
		{ X = 28, Z = -310 },
		{ X = 0, Z = -405 },
		{ X = -34, Z = -505 },
		{ X = 32, Z = -595 },
		{ X = 0, Z = -685 },
		{ X = -26, Z = -785 },
		{ X = 26, Z = -875 },
		{ X = 0, Z = -965 },
		{ X = -24, Z = -1060 },
		{ X = 22, Z = -1140 },
	}
	for idx, item in ipairs(trampolineLayout) do
		createTrampoline(item.X, item.Z, idx, boostersFolder)
	end

	-- 10 воздушных колец-множителей (x1.5)
	local ringLayout = {
		{ X = 0, Z = -105, H = 22, R = 14 },
		{ X = 0, Z = -195, H = 26, R = 15 },
		{ X = -26, Z = -285, H = 25, R = 15 },
		{ X = 26, Z = -365, H = 25, R = 15 },
		{ X = 0, Z = -460, H = 26, R = 16 },
		{ X = -30, Z = -565, H = 24, R = 16 },
		{ X = 28, Z = -660, H = 24, R = 16 },
		{ X = 0, Z = -760, H = 24, R = 16 },
		{ X = 0, Z = -920, H = 22, R = 17 },
		{ X = 0, Z = -1100, H = 20, R = 18 },
	}
	for idx, item in ipairs(ringLayout) do
		createMultiplierRing(item.X, item.Z, item.H, item.R, idx, boostersFolder)
	end

	-- 8 разрушаемых преград (пробиваются мутацией «Тяжёлая»)
	local obstacleLayout = {
		{ X = 22, Z = -180 },
		{ X = -22, Z = -340 },
		{ X = 18, Z = -450 },
		{ X = -18, Z = -635 },
		{ X = 24, Z = -735 },
		{ X = -20, Z = -840 },
		{ X = 18, Z = -1015 },
		{ X = -16, Z = -1165 },
	}
	for idx, item in ipairs(obstacleLayout) do
		createObstacleCluster(item.X, item.Z, idx, boostersFolder)
	end

	-- 6. ЗОНА ПРИЗЕМЛЕНИЯ ВНИЗУ (от Z = -1200 до Z = -2600)
	local landingFolder = Instance.new("Folder")
	landingFolder.Name = "LandingZone"
	landingFolder.Parent = mapFolder

	makePart({
		Name = "LandingRunway",
		Size = Vector3.new(160, 8, 1400),
		Position = Vector3.new(0, 6, -1900),
		Color = Color3.fromRGB(60, 68, 86),
		Material = Enum.Material.Concrete,
		CastShadow = true,
		Parent = landingFolder,
	})

	-- Бортики и задняя стена зоны приземления
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "LandingWall_" .. (side == -1 and "L" or "R"),
			Size = Vector3.new(4, 18, 1400),
			Position = Vector3.new(side * 82, 15, -1900),
			Color = Color3.fromRGB(95, 105, 125),
			Material = Enum.Material.Slate,
			Parent = landingFolder,
		})
	end
	makePart({
		Name = "LandingBackstop",
		Size = Vector3.new(168, 36, 8),
		Position = Vector3.new(0, 24, -2602),
		Color = Color3.fromRGB(255, 75, 75),
		Material = Enum.Material.Neon,
		Parent = landingFolder,
	})

	-- Разметка дистанции каждые 200 стадов
	for z = -1250, -2450, -200 do
		local distMeters = math.abs(z - MapGenerator.CLIFF_EDGE_Z)
		local stripe = makePart({
			Name = "DistanceMarker_" .. tostring(distMeters),
			Size = Vector3.new(156, 0.3, 3),
			Position = Vector3.new(0, 10.15, z),
			Color = Color3.fromRGB(90, 220, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = false,
			Parent = landingFolder,
		})
		addOverheadSign(stripe, string.format("🏁 %d м", distMeters), nil, Vector3.new(0, 8, 0), Color3.fromRGB(130, 235, 255))
	end

	return mapFolder
end

return MapGenerator
