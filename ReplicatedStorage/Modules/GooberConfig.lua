--!strict
--[[
	GooberConfig.lua
	Конфигурация видов Губеров (6 базовых + 2 редких гостя), генератора веса (0.5–1000 кг),
	физических мутаций полёта, формул наград, прокачки Ботинка и Game Pass'ов.
]]

local HttpService = game:GetService("HttpService")

local GooberConfig = {}

export type GooberData = {
	Id: string,
	SpeciesId: string,
	Weight: number,
	MutationId: string,
	CreatedAt: number,
}

GooberConfig.MIN_WEIGHT = 0.5
GooberConfig.MAX_WEIGHT = 1000.0
GooberConfig.MAX_INVENTORY_SIZE = 30
GooberConfig.INCUBATION_TIME = 5 -- секунд (для теста по ТЗ)
GooberConfig.PEDESTAL_COUNT = 4

--============================================================================
-- 1. ВИДЫ ГУБЕРОВ: 6 базовых + 2 редких гостя (Жирный Арбуз, Проклятый Носок)
--============================================================================
GooberConfig.Species = {
	-- 6 базовых видов
	Slimey = {
		Id = "Slimey",
		Name = "Слаймик",
		Color = Color3.fromRGB(95, 235, 85),
		Material = Enum.Material.SmoothPlastic,
		FaceDecal = "rbxasset://textures/face.png",
		BaseValue = 12,
		SpawnWeight = 24,
		IsRareGuest = false,
	},
	Berry = {
		Id = "Berry",
		Name = "Черничка",
		Color = Color3.fromRGB(75, 135, 255),
		Material = Enum.Material.SmoothPlastic,
		FaceDecal = "rbxassetid://7074764",
		BaseValue = 18,
		SpawnWeight = 20,
		IsRareGuest = false,
	},
	Sunny = {
		Id = "Sunny",
		Name = "Солнышко",
		Color = Color3.fromRGB(255, 210, 55),
		Material = Enum.Material.Neon,
		FaceDecal = "rbxassetid://7074786",
		BaseValue = 26,
		SpawnWeight = 17,
		IsRareGuest = false,
	},
	Bubblegum = {
		Id = "Bubblegum",
		Name = "Жвачка",
		Color = Color3.fromRGB(255, 105, 190),
		Material = Enum.Material.SmoothPlastic,
		FaceDecal = "rbxassetid://7075142",
		BaseValue = 36,
		SpawnWeight = 14,
		IsRareGuest = false,
	},
	Magma = {
		Id = "Magma",
		Name = "Лавовик",
		Color = Color3.fromRGB(255, 85, 35),
		Material = Enum.Material.CrackedLava,
		FaceDecal = "rbxassetid://7074864",
		BaseValue = 52,
		SpawnWeight = 11,
		IsRareGuest = false,
	},
	Cosmic = {
		Id = "Cosmic",
		Name = "Космо-Пупс",
		Color = Color3.fromRGB(145, 70, 255),
		Material = Enum.Material.ForceField,
		FaceDecal = "rbxassetid://7075434",
		BaseValue = 75,
		SpawnWeight = 8,
		IsRareGuest = false,
	},

	-- 2 редких гостя
	FatWatermelon = {
		Id = "FatWatermelon",
		Name = "Жирный Арбуз",
		Color = Color3.fromRGB(45, 160, 60),
		Material = Enum.Material.SmoothPlastic,
		FaceDecal = "rbxasset://textures/face.png",
		BaseValue = 190,
		SpawnWeight = 4,
		IsRareGuest = true,
	},
	CursedSock = {
		Id = "CursedSock",
		Name = "Проклятый Носок",
		Color = Color3.fromRGB(135, 120, 150),
		Material = Enum.Material.Fabric,
		FaceDecal = "rbxassetid://7074864",
		BaseValue = 320,
		SpawnWeight = 2,
		IsRareGuest = true,
	},
}

GooberConfig.SpeciesOrder = {
	"Slimey",
	"Berry",
	"Sunny",
	"Bubblegum",
	"Magma",
	"Cosmic",
	"FatWatermelon",
	"CursedSock",
}

--============================================================================
-- 2. МУТАЦИИ, МЕНЯЮЩИЕ ФИЗИКУ ПОЛЁТА
--============================================================================
GooberConfig.Mutations = {
	Normal = {
		Id = "Normal",
		Name = "Обычная",
		BadgeColor = Color3.fromRGB(215, 220, 230),
		ChanceWeight = 52,
		PriceMultiplier = 1.0,
		LaunchSpeedMultiplier = 1.0,
		Density = 0.8,
		Friction = 0.22,
		Elasticity = 0.45,
		FrictionWeight = 1,
		ElasticityWeight = 1,
		GravityScale = 1.0, -- обычная гравитация
		UseVectorForce = false,
		BreaksObstacles = false,
		Description = "Стандартная баллистика и качение",
	},
	Springy = {
		Id = "Springy",
		Name = "Пружинная",
		BadgeColor = Color3.fromRGB(65, 255, 160),
		ChanceWeight = 18,
		PriceMultiplier = 1.65,
		LaunchSpeedMultiplier = 1.08,
		Density = 0.65,
		Friction = 0.12,
		Elasticity = 1.0, -- максимальный физический отскок по ТЗ
		FrictionWeight = 1,
		ElasticityWeight = 100,
		GravityScale = 1.0,
		UseVectorForce = false,
		BreaksObstacles = false,
		Description = "Высокий отскок (Elasticity = 1)",
	},
	Heavy = {
		Id = "Heavy",
		Name = "Тяжёлая",
		BadgeColor = Color3.fromRGB(255, 130, 55),
		ChanceWeight = 15,
		PriceMultiplier = 2.1,
		LaunchSpeedMultiplier = 1.15,
		Density = 6.0, -- высокая плотность по ТЗ
		Friction = 0.2,
		Elasticity = 0.25,
		FrictionWeight = 1,
		ElasticityWeight = 1,
		GravityScale = 1.0,
		UseVectorForce = false,
		BreaksObstacles = true, -- пробивает препятствия на склоне
		Description = "Высокая плотность, пробивает препятствия",
	},
	Airy = {
		Id = "Airy",
		Name = "Воздушная",
		BadgeColor = Color3.fromRGB(115, 220, 255),
		ChanceWeight = 15,
		PriceMultiplier = 1.85,
		LaunchSpeedMultiplier = 1.06,
		Density = 0.35,
		Friction = 0.08,
		Elasticity = 0.6,
		FrictionWeight = 1,
		ElasticityWeight = 1,
		GravityScale = 0.30, -- 30% от обычной гравитации через VectorForce
		UseVectorForce = true,
		BreaksObstacles = false,
		Description = "Низкая гравитация через VectorForce",
	},
}

GooberConfig.MutationOrder = { "Normal", "Springy", "Heavy", "Airy" }

--============================================================================
-- 3. КОНФИГ ПРОКАЧКИ БОТИНКА И GAME PASS'ОВ
--============================================================================
GooberConfig.BootNames = {
	[1] = "Дырявый Кед",
	[2] = "Дворовый Кроссовок",
	[3] = "Кожаный Ботинок",
	[4] = "Стальной Берц",
	[5] = "Пружинный Сапог",
	[6] = "Реактивная Бутса",
	[7] = "Турбо-Пинчище",
	[8] = "Плазменный Тапок",
	[9] = "Квантовый Сапожище",
	[10] = "Ботинок Титана",
}

GooberConfig.GamePasses = {
	MemeSoundPack = {
		Key = "MemeSoundPack",
		PassId = 0, -- Вставьте реальный ID Game Pass после публикации плейса
		Name = "Meme Sound Pack",
		Description = "Мемные звуки при пинке, отскоках и приземлении Губера!",
		IconText = "📯",
	},
	JetpackSteering = {
		Key = "JetpackSteering",
		PassId = 0, -- Вставьте реальный ID Game Pass после публикации плейса
		Name = "Jetpack Steering",
		Description = "Реактивное подруливание Губером прямо в полёте (Влево/Рывок/Вправо)!",
		IconText = "🚀",
	},
}

GooberConfig.Sounds = {
	StandardKick = "rbxassetid://12222200",
	MemeKick = "rbxassetid://12222242",
	StandardBounce = "rbxassetid://12222124",
	MemeBounce = "rbxassetid://12222058",
	RingChime = "rbxassetid://12221967",
	LandCoin = "rbxassetid://12222084",
}

--============================================================================
-- 4. ГЕНЕРАТОРЫ ВЕСА, РАЗМЕРА, ЦЕНЫ И РАНДОМА
--============================================================================

local rng = Random.new()

function GooberConfig.RollSpeciesId(): string
	local totalWeight = 0
	for _, id in ipairs(GooberConfig.SpeciesOrder) do
		totalWeight += GooberConfig.Species[id].SpawnWeight
	end

	local pick = rng:NextNumber(0, totalWeight)
	local cumulative = 0
	for _, id in ipairs(GooberConfig.SpeciesOrder) do
		cumulative += GooberConfig.Species[id].SpawnWeight
		if pick <= cumulative then
			return id
		end
	end
	return "Slimey"
end

function GooberConfig.RollMutationId(): string
	local totalWeight = 0
	for _, id in ipairs(GooberConfig.MutationOrder) do
		totalWeight += GooberConfig.Mutations[id].ChanceWeight
	end

	local pick = rng:NextNumber(0, totalWeight)
	local cumulative = 0
	for _, id in ipairs(GooberConfig.MutationOrder) do
		cumulative += GooberConfig.Mutations[id].ChanceWeight
		if pick <= cumulative then
			return id
		end
	end
	return "Normal"
end

-- Генерация веса от 0.5 кг до 1000 кг со смещённым распределением редкости
function GooberConfig.GenerateWeight(speciesId: string?): number
	local tierRoll = rng:NextNumber(0, 1)
	local rawWeight: number

	if speciesId == "FatWatermelon" then
		-- Жирный Арбуз чаще выпадает увесистым
		rawWeight = rng:NextNumber(45.0, GooberConfig.MAX_WEIGHT)
	elseif tierRoll < 0.55 then
		rawWeight = rng:NextNumber(GooberConfig.MIN_WEIGHT, 35.0)
	elseif tierRoll < 0.83 then
		rawWeight = rng:NextNumber(35.0, 180.0)
	elseif tierRoll < 0.95 then
		rawWeight = rng:NextNumber(180.0, 550.0)
	else
		rawWeight = rng:NextNumber(550.0, GooberConfig.MAX_WEIGHT)
	end

	local rounded = math.floor(rawWeight * 10 + 0.5) / 10
	return math.clamp(rounded, GooberConfig.MIN_WEIGHT, GooberConfig.MAX_WEIGHT)
end

-- Чем больше вес, тем физически больше диаметр сферы Губера (от 1.8 до 11.5 стадов)
function GooberConfig.GetDiameterFromWeight(weight: number): number
	local w = math.clamp(tonumber(weight) or GooberConfig.MIN_WEIGHT, GooberConfig.MIN_WEIGHT, GooberConfig.MAX_WEIGHT)
	local normalized = math.log(w / GooberConfig.MIN_WEIGHT) / math.log(GooberConfig.MAX_WEIGHT / GooberConfig.MIN_WEIGHT)
	local diameter = 1.8 + 9.7 * (normalized ^ 1.12)
	return math.clamp(diameter, 1.8, 11.5)
end

-- Чем больше вес, тем выше множитель цены (от ~1.23x при 0.5 кг до ~26.3x при 1000 кг)
function GooberConfig.GetWeightPriceMultiplier(weight: number): number
	local w = math.clamp(tonumber(weight) or GooberConfig.MIN_WEIGHT, GooberConfig.MIN_WEIGHT, GooberConfig.MAX_WEIGHT)
	return 1.0 + (w ^ 0.62) * 0.35
end

function GooberConfig.RollRandomGoober(): GooberData
	local speciesId = GooberConfig.RollSpeciesId()
	local mutationId = GooberConfig.RollMutationId()
	local weight = GooberConfig.GenerateWeight(speciesId)

	return {
		Id = HttpService:GenerateGUID(false),
		SpeciesId = speciesId,
		Weight = weight,
		MutationId = mutationId,
		CreatedAt = os.time(),
	}
end

-- Расчёт награды за полёт Губера
function GooberConfig.CalculateFlightReward(
	gooberData: GooberData,
	distanceStuds: number,
	perfectMultiplier: number,
	comboMultiplier: number
): number
	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal
	local weightMult = GooberConfig.GetWeightPriceMultiplier(gooberData.Weight)

	local distanceFactor = 1.0 + math.max(0, distanceStuds) / 95.0
	local raw = species.BaseValue * weightMult * mutation.PriceMultiplier * distanceFactor * perfectMultiplier * comboMultiplier
	return math.max(1, math.floor(raw + 0.5))
end

-- Пассивный доход Губера на пьедестале базы (монет в секунду)
function GooberConfig.CalculatePassiveIncome(gooberData: GooberData): number
	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal
	local weightMult = GooberConfig.GetWeightPriceMultiplier(gooberData.Weight)

	local perSec = (species.BaseValue * 0.16) * weightMult * mutation.PriceMultiplier
	return math.max(1, math.floor(perSec + 0.5))
end

-- Стоимость улучшения Ботинка и множитель силы удара
function GooberConfig.GetBootUpgradeCost(currentLevel: number): number
	local lvl = math.max(1, math.floor(currentLevel))
	return math.floor(65 * (1.68 ^ (lvl - 1)) + 0.5)
end

function GooberConfig.GetBootPowerMultiplier(level: number): number
	local lvl = math.max(1, math.floor(level))
	return 1.0 + (lvl - 1) * 0.22
end

function GooberConfig.GetBootTitle(level: number): string
	local lvl = math.max(1, math.floor(level))
	if GooberConfig.BootNames[lvl] then
		return GooberConfig.BootNames[lvl]
	end
	return "Ботинок Бога +" .. tostring(lvl - 10)
end

--============================================================================
-- 5. КОНСТРУКТОР 3D-МОДЕЛИ ГУБЕРА И ЕГО ФИЗИКИ МУТАЦИЙ
--============================================================================

function GooberConfig.ApplyFlightPhysics(model: Model, gooberData: GooberData)
	local body = model.PrimaryPart
	if not body then
		return
	end

	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal

	body.Massless = false
	body.CustomPhysicalProperties = PhysicalProperties.new(
		mutation.Density,
		mutation.Friction,
		mutation.Elasticity,
		mutation.FrictionWeight,
		mutation.ElasticityWeight
	)

	-- Очищаем старый VectorForce, если был
	local existingForce = body:FindFirstChild("AiryVectorForce")
	if existingForce then
		existingForce:Destroy()
	end
	local existingAttachment = body:FindFirstChild("FlightAttachment")
	if existingAttachment then
		existingAttachment:Destroy()
	end

	-- Мутация «Воздушная»: антигравитация через VectorForce в мировых осях
	if mutation.UseVectorForce then
		local attachment = Instance.new("Attachment")
		attachment.Name = "FlightAttachment"
		attachment.Parent = body

		local vectorForce = Instance.new("VectorForce")
		vectorForce.Name = "AiryVectorForce"
		vectorForce.Attachment0 = attachment
		vectorForce.ApplyAtCenterOfMass = true
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World

		local totalMass = body.AssemblyMass
		local counterGravity = totalMass * workspace.Gravity * (1.0 - mutation.GravityScale)
		vectorForce.Force = Vector3.new(0, counterGravity, 0)
		vectorForce.Parent = body
	end
end

function GooberConfig.BuildGooberModel(gooberData: GooberData, options: { ScaleOverride: number?, HideBillboard: boolean? }?): Model
	local opts = options or {}
	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal

	local diameter = opts.ScaleOverride or GooberConfig.GetDiameterFromWeight(gooberData.Weight)

	local model = Instance.new("Model")
	model.Name = "Goober_" .. species.Id
	model:SetAttribute("GooberId", gooberData.Id)
	model:SetAttribute("SpeciesId", species.Id)
	model:SetAttribute("MutationId", mutation.Id)
	model:SetAttribute("Weight", gooberData.Weight)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(diameter, diameter, diameter)
	body.Color = species.Color
	body.Material = species.Material
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CastShadow = true
	body.Parent = model

	model.PrimaryPart = body

	-- Лицо-декаль спереди сферы
	local face = Instance.new("Decal")
	face.Name = "Face"
	face.Face = Enum.NormalId.Front
	face.Texture = species.FaceDecal
	face.Parent = body

	-- Особый декор для редких гостей (не влияет на сферическую коллизию, Massless + CanCollide = false)
	if species.Id == "FatWatermelon" then
		-- Хвостик арбуза сверху и полосатая обводка
		local stem = Instance.new("Part")
		stem.Name = "Stem"
		stem.Size = Vector3.new(diameter * 0.12, diameter * 0.25, diameter * 0.12)
		stem.Color = Color3.fromRGB(30, 95, 35)
		stem.Material = Enum.Material.Wood
		stem.CanCollide = false
		stem.CanTouch = false
		stem.CanQuery = false
		stem.Massless = true
		stem.CastShadow = false
		stem.CFrame = body.CFrame * CFrame.new(0, diameter * 0.52, 0)
		stem.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = stem
		weld.Parent = stem

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.85
		highlight.FillColor = Color3.fromRGB(255, 70, 95)
		highlight.OutlineColor = Color3.fromRGB(20, 90, 30)
		highlight.Parent = model
	elseif species.Id == "CursedSock" then
		-- Проклятая аура + манжета носка сверху
		local cuff = Instance.new("Part")
		cuff.Name = "SockCuff"
		cuff.Shape = Enum.PartType.Cylinder
		cuff.Size = Vector3.new(diameter * 0.22, diameter * 0.55, diameter * 0.55)
		cuff.Color = Color3.fromRGB(95, 70, 120)
		cuff.Material = Enum.Material.Fabric
		cuff.CanCollide = false
		cuff.CanTouch = false
		cuff.CanQuery = false
		cuff.Massless = true
		cuff.CastShadow = false
		cuff.CFrame = body.CFrame * CFrame.new(0, diameter * 0.45, 0) * CFrame.Angles(0, 0, math.rad(90))
		cuff.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = cuff
		weld.Parent = cuff

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.72
		highlight.FillColor = Color3.fromRGB(160, 50, 255)
		highlight.OutlineColor = Color3.fromRGB(210, 110, 255)
		highlight.Parent = model
	elseif mutation.Id ~= "Normal" then
		-- Лёгкая подсветка для мутировавших Губеров
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.88
		highlight.FillColor = mutation.BadgeColor
		highlight.OutlineColor = mutation.BadgeColor
		highlight.OutlineTransparency = 0.25
		highlight.Parent = model
	end

	-- Информационный бейдж над Губером
	if not opts.HideBillboard then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "InfoTag"
		billboard.Size = UDim2.fromOffset(180, 54)
		billboard.StudsOffset = Vector3.new(0, diameter * 0.65 + 1.4, 0)
		billboard.MaxDistance = 120
		billboard.AlwaysOnTop = false
		billboard.Parent = body

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.fromScale(1, 0.55)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextScaled = true
		titleLabel.TextColor3 = species.IsRareGuest and Color3.fromRGB(255, 215, 65) or Color3.new(1, 1, 1)
		titleLabel.TextStrokeTransparency = 0.2
		titleLabel.Text = string.format("%s (%.1f кг)", species.Name, gooberData.Weight)
		titleLabel.Parent = billboard

		local mutLabel = Instance.new("TextLabel")
		mutLabel.Name = "Mutation"
		mutLabel.Position = UDim2.fromScale(0, 0.52)
		mutLabel.Size = UDim2.fromScale(1, 0.45)
		mutLabel.BackgroundTransparency = 1
		mutLabel.Font = Enum.Font.GothamMedium
		mutLabel.TextScaled = true
		mutLabel.TextColor3 = mutation.BadgeColor
		mutLabel.TextStrokeTransparency = 0.25
		mutLabel.Text = string.format("[%s]", mutation.Name)
		mutLabel.Parent = billboard
	end

	return model
end

return GooberConfig
