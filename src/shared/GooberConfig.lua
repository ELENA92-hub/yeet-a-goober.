--!strict
--[[
	GooberConfig.lua
	Конфигурация «YEET A GOOBER! [MUTATIONS]»:
	- 6 базовых видов Губеров + 2 редких гостя (Жирный Арбуз, Проклятый Носок).
	- Конструктор «Мастерская Губера» («Собери чудика»):
	  * Формы тела: Желе, Кубик, Капля, Пончик
	  * Глаза: Выпученные, Злые, Аниме, Циклоп
	  * Рот: Кричащий, С языком, Усы
	  * Аксессуары: Пропеллер, Корона, Очки, Реактивный ранец
	- 3D-генератор всех кастомных частей/стикеров и расчёт реальных физических бонусов полёта.
	- Мутации (включая Супер-Мутацию «Грозовой Бог» при пролёте грозовой тучи со щитом).
]]

local HttpService = game:GetService("HttpService")

local GooberConfig = {}

export type WorkshopBuild = {
	BodyShapeId: string,
	EyesId: string,
	MouthId: string,
	AccessoryId: string,
}

export type GooberData = {
	Id: string,
	SpeciesId: string,
	Weight: number,
	MutationId: string,
	BodyShapeId: string,
	EyesId: string,
	MouthId: string,
	AccessoryId: string,
	CreatedAt: number,
}

export type ComputedFlightStats = {
	LaunchSpeedMult: number,
	GravityScale: number,
	UseVectorForce: boolean,
	Elasticity: number,
	Density: number,
	Friction: number,
	WallSmashSpeedThreshold: number,
	BreaksObstaclesAlways: boolean,
	DashPowerMult: number,
	DashCooldown: number,
	SteerForceMult: number,
	MagnetRadius: number,
	ComboGainMult: number,
	RingRewardMult: number,
	CoinPickupMult: number,
	TotalRewardMult: number,
	PassiveIncomeMult: number,
	StartsWithShield: boolean,
}

GooberConfig.MIN_WEIGHT = 0.5
GooberConfig.MAX_WEIGHT = 1000.0
GooberConfig.MAX_INVENTORY_SIZE = 35
GooberConfig.INCUBATION_TIME = 3.5 -- быстрый драйвовый крафт чудика
GooberConfig.PEDESTAL_COUNT = 4

--============================================================================
-- 1. ВИДЫ ГУБЕРОВ (ЦВЕТОВАЯ ТЕМА И РЕДКОСТЬ: 6 БАЗОВЫХ + 2 РЕДКИХ ГОСТЯ)
--============================================================================
GooberConfig.Species = {
	Slimey = {
		Id = "Slimey",
		Name = "Слаймик",
		Color = Color3.fromRGB(95, 235, 85),
		Material = Enum.Material.SmoothPlastic,
		BaseValue = 14,
		SpawnWeight = 24,
		IsRareGuest = false,
	},
	Berry = {
		Id = "Berry",
		Name = "Черничка",
		Color = Color3.fromRGB(75, 140, 255),
		Material = Enum.Material.SmoothPlastic,
		BaseValue = 20,
		SpawnWeight = 20,
		IsRareGuest = false,
	},
	Sunny = {
		Id = "Sunny",
		Name = "Солнышко",
		Color = Color3.fromRGB(255, 210, 55),
		Material = Enum.Material.Neon,
		BaseValue = 28,
		SpawnWeight = 17,
		IsRareGuest = false,
	},
	Bubblegum = {
		Id = "Bubblegum",
		Name = "Жвачка",
		Color = Color3.fromRGB(255, 105, 190),
		Material = Enum.Material.SmoothPlastic,
		BaseValue = 38,
		SpawnWeight = 14,
		IsRareGuest = false,
	},
	Magma = {
		Id = "Magma",
		Name = "Лавовик",
		Color = Color3.fromRGB(255, 85, 35),
		Material = Enum.Material.CrackedLava,
		BaseValue = 56,
		SpawnWeight = 11,
		IsRareGuest = false,
	},
	Cosmic = {
		Id = "Cosmic",
		Name = "Космо-Пупс",
		Color = Color3.fromRGB(145, 70, 255),
		Material = Enum.Material.ForceField,
		BaseValue = 80,
		SpawnWeight = 8,
		IsRareGuest = false,
	},
	FatWatermelon = {
		Id = "FatWatermelon",
		Name = "Жирный Арбуз",
		Color = Color3.fromRGB(45, 160, 60),
		Material = Enum.Material.SmoothPlastic,
		BaseValue = 200,
		SpawnWeight = 4,
		IsRareGuest = true,
	},
	CursedSock = {
		Id = "CursedSock",
		Name = "Проклятый Носок",
		Color = Color3.fromRGB(135, 120, 155),
		Material = Enum.Material.Fabric,
		BaseValue = 340,
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
-- 2. КОНСТРУКТОР ГУБЕРА («МАСТЕРСКАЯ ЧУДИКА»: ТЕЛО, ГЛАЗА, РОТ, АКСЕССУАРЫ)
--============================================================================

GooberConfig.BodyShapes = {
	Jelly = {
		Id = "Jelly",
		Name = "Желе",
		Icon = "🍮",
		BonusShort = "+Отскок и прыгучесть",
		Description = "Упругое желейное тело: +0.35 к отскоку от облаков и склона!",
	},
	Cube = {
		Id = "Cube",
		Name = "Кубик",
		Icon = "🧊",
		BonusShort = "Таран стен +18% монет",
		Description = "Тяжёлый кубик: легко пробивает стены на меньшей скорости и даёт +18% награды!",
	},
	Drop = {
		Id = "Drop",
		Name = "Капля",
		Icon = "💧",
		BonusShort = "+18% скорость и руление",
		Description = "Обтекаемая форма капли: +18% к стартовой скорости полёта и манёвренности!",
	},
	Donut = {
		Id = "Donut",
		Name = "Пончик",
		Icon = "🍩",
		BonusShort = "Магнит монет и поток",
		Description = "Глазированный пончик с посыпкой: притягивает парящие монеты и лучше ловит потоки!",
	},
}
GooberConfig.BodyShapeOrder = { "Jelly", "Cube", "Drop", "Donut" }

GooberConfig.Eyes = {
	Bulging = {
		Id = "Bulging",
		Name = "Выпученные",
		Icon = "👀",
		BonusShort = "+Радиус сбора монет",
		Description = "Огромные безумные глаза замечают и притягивают монеты и кристаллы издалека!",
	},
	Angry = {
		Id = "Angry",
		Name = "Злые",
		Icon = "😠",
		BonusShort = "+15% сила пинка",
		Description = "Суровый взгляд даёт +15% к начальному импульсу при пинке с обрыва!",
	},
	Anime = {
		Id = "Anime",
		Name = "Аниме",
		Icon = "✨",
		BonusShort = "+15% рост комбо трюков",
		Description = "Блестящие глаза с румянцем дают +15% к приросту комбо за каждый трюк в воздухе!",
	},
	Cyclops = {
		Id = "Cyclops",
		Name = "Циклоп",
		Icon = "👁️",
		BonusShort = "+25% бонус золотых колец",
		Description = "Снайперский глаз-прицел увеличивает ускорение и награду от золотых колец на 25%!",
	},
}
GooberConfig.EyesOrder = { "Bulging", "Angry", "Anime", "Cyclops" }

GooberConfig.Mouths = {
	Screaming = {
		Id = "Screaming",
		Name = "Кричащий",
		Icon = "😱",
		BonusShort = "+15% мощь рывка",
		Description = "Дикий крик усиливает воздушный «Рывок / Ускорение» на 15%!",
	},
	Tongue = {
		Id = "Tongue",
		Name = "С языком",
		Icon = "👅",
		BonusShort = "+30% ценность монет",
		Description = "Длинный весёлый язык ловит парящие монеты с бонусом +30%!",
	},
	Mustache = {
		Id = "Mustache",
		Name = "Усы",
		Icon = "🥸",
		BonusShort = "+25% доход на базе",
		Description = "Благородные усы дают +15% к полёту и +25% к пассивному доходу на пьедестале!",
	},
}
GooberConfig.MouthOrder = { "Screaming", "Tongue", "Mustache" }

GooberConfig.Accessories = {
	Propeller = {
		Id = "Propeller",
		Name = "Пропеллер",
		Icon = "🚁",
		BonusShort = "Планирование (-38% грав.)",
		Description = "Шапочка с крутящимся пропеллером снижает гравитацию на 38% и позволяет долго парить!",
	},
	Crown = {
		Id = "Crown",
		Name = "Корона",
		Icon = "👑",
		BonusShort = "+35% награда + Щит",
		Description = "Золотая корона даёт +35% монет и стартовый Щит (защита или супер-мутация в туче)!",
	},
	Sunglasses = {
		Id = "Sunglasses",
		Name = "Очки",
		Icon = "🕶️",
		BonusShort = "Энерго-Щит для туч",
		Description = "Крутые очки дают стартовый Щит: пролети сквозь грозовую тучу, чтобы получить СУПЕР-МУТАЦИЮ!",
	},
	Jetpack = {
		Id = "Jetpack",
		Name = "Реактивный ранец",
		Icon = "🚀",
		BonusShort = "Мощный рывок и -42% откат",
		Description = "Двойной турбо-ранец усиливает кнопку «Рывок» на 45% и ускоряет её перезарядку!",
	},
}
GooberConfig.AccessoryOrder = { "Propeller", "Crown", "Sunglasses", "Jetpack" }

function GooberConfig.GetDefaultWorkshopBuild(): WorkshopBuild
	return {
		BodyShapeId = "Jelly",
		EyesId = "Bulging",
		MouthId = "Screaming",
		AccessoryId = "Propeller",
	}
end

function GooberConfig.SanitizeWorkshopBuild(raw: any): WorkshopBuild
	local def = GooberConfig.GetDefaultWorkshopBuild()
	if type(raw) ~= "table" then
		return def
	end
	local shapeId = tostring(raw.BodyShapeId or def.BodyShapeId)
	local eyesId = tostring(raw.EyesId or def.EyesId)
	local mouthId = tostring(raw.MouthId or def.MouthId)
	local accId = tostring(raw.AccessoryId or def.AccessoryId)

	return {
		BodyShapeId = GooberConfig.BodyShapes[shapeId] and shapeId or def.BodyShapeId,
		EyesId = GooberConfig.Eyes[eyesId] and eyesId or def.EyesId,
		MouthId = GooberConfig.Mouths[mouthId] and mouthId or def.MouthId,
		AccessoryId = GooberConfig.Accessories[accId] and accId or def.AccessoryId,
	}
end

--============================================================================
-- 3. МУТАЦИИ (ВКЛЮЧАЯ ГРОЗОВУЮ СУПЕР-МУТАЦИЮ)
--============================================================================
GooberConfig.Mutations = {
	Normal = {
		Id = "Normal",
		Name = "Обычная",
		BadgeColor = Color3.fromRGB(215, 220, 230),
		ChanceWeight = 50,
		PriceMultiplier = 1.0,
		LaunchSpeedMultiplier = 1.0,
		Density = 0.8,
		Friction = 0.20,
		Elasticity = 0.48,
		GravityScale = 1.0,
		BreaksObstacles = false,
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
		Elasticity = 1.0,
		GravityScale = 1.0,
		BreaksObstacles = false,
	},
	Heavy = {
		Id = "Heavy",
		Name = "Тяжёлая",
		BadgeColor = Color3.fromRGB(255, 130, 55),
		ChanceWeight = 16,
		PriceMultiplier = 2.1,
		LaunchSpeedMultiplier = 1.15,
		Density = 5.5,
		Friction = 0.18,
		Elasticity = 0.30,
		GravityScale = 1.0,
		BreaksObstacles = true,
	},
	Airy = {
		Id = "Airy",
		Name = "Воздушная",
		BadgeColor = Color3.fromRGB(115, 220, 255),
		ChanceWeight = 16,
		PriceMultiplier = 1.85,
		LaunchSpeedMultiplier = 1.08,
		Density = 0.40,
		Friction = 0.08,
		Elasticity = 0.60,
		GravityScale = 0.35,
		BreaksObstacles = false,
	},
	SuperStorm = {
		Id = "SuperStorm",
		Name = "⚡ ГРОЗОВАЯ СУПЕР-МУТАЦИЯ",
		BadgeColor = Color3.fromRGB(255, 235, 60),
		ChanceWeight = 0, -- Выдаётся в полёте при пробитии грозовой тучи под Щитом!
		PriceMultiplier = 4.0,
		LaunchSpeedMultiplier = 1.35,
		Density = 1.1,
		Friction = 0.06,
		Elasticity = 0.88,
		GravityScale = 0.42,
		BreaksObstacles = true,
	},
}

GooberConfig.MutationOrder = { "Normal", "Springy", "Heavy", "Airy" }

--============================================================================
-- 4. ПРОКАЧКА БОТИНКА, ЗВУКИ И GAME PASS'Ы
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
		PassId = 0,
		Name = "Meme Sound Pack",
		Description = "Угарная озвучка пинков, криков, батутов и столкновений!",
		IconText = "📯",
	},
	JetpackSteering = {
		Key = "JetpackSteering",
		PassId = 0,
		Name = "Turbo Jetpack VIP",
		Description = "Удвоенная тяга манёвров A/D и +50% мощности кнопки «Рывок» с быстрым откатом!",
		IconText = "🚀",
	},
}

GooberConfig.Sounds = {
	StandardKick = "rbxassetid://12222200",
	MemeKick = "rbxassetid://12222242",
	StandardBounce = "rbxassetid://12222124",
	MemeBounce = "rbxassetid://12222058",
	RingChime = "rbxassetid://12221967",
	CoinPickup = "rbxassetid://138081500",
	DashWhoosh = "rbxassetid://12222216",
	WallSmash = "rbxassetid://12222084",
	ZapShock = "rbxassetid://12222152",
	FanBonk = "rbxassetid://12222058",
	LandCoin = "rbxassetid://12222084",
}

--============================================================================
-- 5. ГЕНЕРАЦИЯ ВЕСА, ХАРАКТЕРИСТИК ПОЛЁТА И РАСЧЁТ НАГРАД
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

function GooberConfig.RollRandomWorkshopBuild(): WorkshopBuild
	return {
		BodyShapeId = GooberConfig.BodyShapeOrder[rng:NextInteger(1, #GooberConfig.BodyShapeOrder)],
		EyesId = GooberConfig.EyesOrder[rng:NextInteger(1, #GooberConfig.EyesOrder)],
		MouthId = GooberConfig.MouthOrder[rng:NextInteger(1, #GooberConfig.MouthOrder)],
		AccessoryId = GooberConfig.AccessoryOrder[rng:NextInteger(1, #GooberConfig.AccessoryOrder)],
	}
end

function GooberConfig.GenerateWeight(speciesId: string?): number
	local tierRoll = rng:NextNumber(0, 1)
	local rawWeight: number

	if speciesId == "FatWatermelon" then
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

function GooberConfig.GetDiameterFromWeight(weight: number): number
	local w = math.clamp(tonumber(weight) or GooberConfig.MIN_WEIGHT, GooberConfig.MIN_WEIGHT, GooberConfig.MAX_WEIGHT)
	local normalized = math.log(w / GooberConfig.MIN_WEIGHT) / math.log(GooberConfig.MAX_WEIGHT / GooberConfig.MIN_WEIGHT)
	local diameter = 2.0 + 9.2 * (normalized ^ 1.12)
	return math.clamp(diameter, 2.0, 11.2)
end

function GooberConfig.GetWeightPriceMultiplier(weight: number): number
	local w = math.clamp(tonumber(weight) or GooberConfig.MIN_WEIGHT, GooberConfig.MIN_WEIGHT, GooberConfig.MAX_WEIGHT)
	return 1.0 + (w ^ 0.62) * 0.35
end

function GooberConfig.RollRandomGoober(customBuild: WorkshopBuild?): GooberData
	local speciesId = GooberConfig.RollSpeciesId()
	local mutationId = GooberConfig.RollMutationId()
	local weight = GooberConfig.GenerateWeight(speciesId)
	local build = customBuild and GooberConfig.SanitizeWorkshopBuild(customBuild) or GooberConfig.RollRandomWorkshopBuild()

	return {
		Id = HttpService:GenerateGUID(false),
		SpeciesId = speciesId,
		Weight = weight,
		MutationId = mutationId,
		BodyShapeId = build.BodyShapeId,
		EyesId = build.EyesId,
		MouthId = build.MouthId,
		AccessoryId = build.AccessoryId,
		CreatedAt = os.time(),
	}
end

-- Агрегирует реальные бонусы к полёту от выбранных в Мастерской частей и мутации
function GooberConfig.ComputeFlightStats(gooberData: GooberData): ComputedFlightStats
	local mut = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal
	local shapeId = gooberData.BodyShapeId or "Jelly"
	local eyesId = gooberData.EyesId or "Bulging"
	local mouthId = gooberData.MouthId or "Screaming"
	local accId = gooberData.AccessoryId or "Propeller"

	local launchSpeedMult = mut.LaunchSpeedMultiplier
	local gravityScale = mut.GravityScale
	local elasticity = mut.Elasticity
	local density = mut.Density
	local wallThreshold = 112.0
	local dashPowerMult = 1.0
	local dashCooldown = 2.8
	local steerForceMult = 1.0
	local magnetRadius = 11.0
	local comboGainMult = 1.0
	local ringRewardMult = 1.0
	local coinPickupMult = 1.0
	local totalRewardMult = 1.0
	local passiveIncomeMult = 1.0
	local startsWithShield = false

	-- Форма тела
	if shapeId == "Jelly" then
		elasticity = math.clamp(elasticity + 0.35, 0.1, 1.0)
	elseif shapeId == "Cube" then
		density *= 1.65
		wallThreshold -= 40.0 -- пробивает стены на меньшей скорости!
		totalRewardMult *= 1.18
	elseif shapeId == "Drop" then
		launchSpeedMult *= 1.18
		steerForceMult *= 1.18
	elseif shapeId == "Donut" then
		magnetRadius += 7.5
		gravityScale *= 0.90
	end

	-- Глаза
	if eyesId == "Bulging" then
		magnetRadius += 6.5
	elseif eyesId == "Angry" then
		launchSpeedMult *= 1.15
	elseif eyesId == "Anime" then
		comboGainMult += 0.15
	elseif eyesId == "Cyclops" then
		ringRewardMult += 0.25
	end

	-- Рот
	if mouthId == "Screaming" then
		dashPowerMult *= 1.15
	elseif mouthId == "Tongue" then
		coinPickupMult += 0.30
	elseif mouthId == "Mustache" then
		totalRewardMult *= 1.15
		passiveIncomeMult *= 1.25
	end

	-- Аксессуар
	if accId == "Propeller" then
		gravityScale *= 0.62 -- мощное планирование!
		steerForceMult *= 1.15
	elseif accId == "Crown" then
		totalRewardMult *= 1.35
		passiveIncomeMult *= 1.30
		startsWithShield = true
	elseif accId == "Sunglasses" then
		startsWithShield = true
	elseif accId == "Jetpack" then
		dashPowerMult *= 1.45
		dashCooldown *= 0.58 -- быстрый откат рывка!
	end

	if mut.BreaksObstacles then
		wallThreshold = math.min(wallThreshold, 60.0)
	end

	return {
		LaunchSpeedMult = launchSpeedMult,
		GravityScale = math.clamp(gravityScale, 0.18, 1.0),
		UseVectorForce = gravityScale < 0.98,
		Elasticity = elasticity,
		Density = density,
		Friction = mut.Friction,
		WallSmashSpeedThreshold = wallThreshold,
		BreaksObstaclesAlways = mut.BreaksObstacles,
		DashPowerMult = dashPowerMult,
		DashCooldown = dashCooldown,
		SteerForceMult = steerForceMult,
		MagnetRadius = magnetRadius,
		ComboGainMult = comboGainMult,
		RingRewardMult = ringRewardMult,
		CoinPickupMult = coinPickupMult,
		TotalRewardMult = totalRewardMult,
		PassiveIncomeMult = passiveIncomeMult,
		StartsWithShield = startsWithShield,
	}
end

function GooberConfig.CalculateFlightReward(
	gooberData: GooberData,
	distanceStuds: number,
	perfectMultiplier: number,
	comboMultiplier: number,
	bonusTrackCoins: number?
): number
	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal
	local weightMult = GooberConfig.GetWeightPriceMultiplier(gooberData.Weight)
	local stats = GooberConfig.ComputeFlightStats(gooberData)

	local distanceFactor = 1.0 + math.max(0, distanceStuds) / 90.0
	local raw = species.BaseValue
		* weightMult
		* mutation.PriceMultiplier
		* stats.TotalRewardMult
		* distanceFactor
		* perfectMultiplier
		* comboMultiplier

	local extra = math.max(0, math.floor(tonumber(bonusTrackCoins) or 0))
	return math.max(1, math.floor(raw + 0.5) + extra)
end

function GooberConfig.CalculatePassiveIncome(gooberData: GooberData): number
	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal
	local weightMult = GooberConfig.GetWeightPriceMultiplier(gooberData.Weight)
	local stats = GooberConfig.ComputeFlightStats(gooberData)

	local perSec = (species.BaseValue * 0.16) * weightMult * mutation.PriceMultiplier * stats.PassiveIncomeMult
	return math.max(1, math.floor(perSec + 0.5))
end

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
-- 6. 3D-СБОРКА КОНСТРУКТОРА ГУБЕРА И ФИЗИКИ ПОЛЁТА
--============================================================================

local function makeAttachmentPart(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType,
	relCF: CFrame,
	rootBody: BasePart,
	parent: Instance,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = rootBody.CFrame * relCF
	p.Parent = parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootBody
	weld.Part1 = p
	weld.Parent = p

	return p
end

function GooberConfig.ApplyFlightPhysics(model: Model, gooberData: GooberData)
	local body = model.PrimaryPart
	if not body then
		return
	end

	local stats = GooberConfig.ComputeFlightStats(gooberData)

	body.Massless = false
	body.CustomPhysicalProperties = PhysicalProperties.new(
		stats.Density,
		stats.Friction,
		stats.Elasticity,
		1,
		stats.Elasticity >= 0.8 and 100 or 1
	)

	-- Очищаем старые полётные силы
	for _, childName in ipairs({ "AiryVectorForce", "SteerVectorForce", "FlightAttachment" }) do
		local old = body:FindFirstChild(childName)
		if old then
			old:Destroy()
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = body

	-- Сила планирования / низкой гравитации (Воздушная мутация, Пропеллер, Пончик, Супер-Мутация)
	if stats.UseVectorForce then
		local vectorForce = Instance.new("VectorForce")
		vectorForce.Name = "AiryVectorForce"
		vectorForce.Attachment0 = attachment
		vectorForce.ApplyAtCenterOfMass = true
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World

		local totalMass = body.AssemblyMass
		local counterGravity = totalMass * workspace.Gravity * (1.0 - stats.GravityScale)
		vectorForce.Force = Vector3.new(0, counterGravity, 0)
		vectorForce.Parent = body
	end

	-- Боковая сила руления в воздухе (A/D или стрелки) в мировых координатах
	local steerForce = Instance.new("VectorForce")
	steerForce.Name = "SteerVectorForce"
	steerForce.Attachment0 = attachment
	steerForce.ApplyAtCenterOfMass = true
	steerForce.RelativeTo = Enum.ActuatorRelativeTo.World
	steerForce.Force = Vector3.zero
	steerForce.Parent = body
end

-- Добавляет яркий трейл и частицы ветра для летящего Губера
function GooberConfig.AttachFlightTrail(model: Model, color: Color3)
	local body = model.PrimaryPart
	if not body then
		return
	end

	local r = body.Size.Y * 0.42
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, r, 0)
	a0.Parent = body

	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -r, 0)
	a1.Parent = body

	local trail = Instance.new("Trail")
	trail.Name = "SpeedTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.MinLength = 0.2
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(1, 0.0),
	})
	trail.Parent = body
end

-- Визуальная сфера Энерго-Щита вокруг Губера
function GooberConfig.SetShieldVisual(model: Model, enabled: boolean)
	local body = model.PrimaryPart
	if not body then
		return
	end
	local existing = model:FindFirstChild("ShieldAura")
	if enabled then
		if not existing then
			local d = math.max(body.Size.X, body.Size.Y, body.Size.Z) * 1.38
			makeAttachmentPart(
				"ShieldAura",
				Vector3.new(d, d, d),
				Color3.fromRGB(70, 225, 255),
				Enum.Material.ForceField,
				Enum.PartType.Ball,
				CFrame.new(),
				body,
				model,
				0.35
			)
		end
	else
		if existing then
			existing:Destroy()
		end
	end
end

function GooberConfig.BuildGooberModel(
	gooberData: GooberData,
	options: { ScaleOverride: number?, HideBillboard: boolean? }?
): Model
	local opts = options or {}
	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal

	local shapeId = gooberData.BodyShapeId or "Jelly"
	local eyesId = gooberData.EyesId or "Bulging"
	local mouthId = gooberData.MouthId or "Screaming"
	local accId = gooberData.AccessoryId or "Propeller"

	local d = opts.ScaleOverride or GooberConfig.GetDiameterFromWeight(gooberData.Weight)

	local model = Instance.new("Model")
	model.Name = "Goober_" .. species.Id
	model:SetAttribute("GooberId", gooberData.Id)
	model:SetAttribute("SpeciesId", species.Id)
	model:SetAttribute("MutationId", mutation.Id)
	model:SetAttribute("BodyShapeId", shapeId)
	model:SetAttribute("AccessoryId", accId)
	model:SetAttribute("Weight", gooberData.Weight)

	-- 1. ОСНОВНАЯ ФОРМА ТЕЛА (Желе / Кубик / Капля / Пончик)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Color = species.Color
	body.Material = species.Material
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CastShadow = true

	local frontZ = d * 0.48
	local topY = d * 0.50

	if shapeId == "Cube" then
		local cubeSide = d * 0.86
		body.Shape = Enum.PartType.Block
		body.Size = Vector3.new(cubeSide, cubeSide, cubeSide)
		frontZ = cubeSide * 0.50
		topY = cubeSide * 0.50
	elseif shapeId == "Donut" then
		-- Невидимая сферическая физическая оболочка для идеального качения + 3D-кольцо пончика
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(d, d, d)
		body.Transparency = 1
		frontZ = d * 0.30
		topY = d * 0.50
	elseif shapeId == "Jelly" then
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(d, d, d)
		body.Transparency = 0.16
	else
		-- Drop («Капля»)
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(d, d, d)
		topY = d * 0.68
	end

	body.Parent = model
	model.PrimaryPart = body

	-- Дополнительные 3D-детали выбранной формы тела
	if shapeId == "Jelly" then
		makeAttachmentPart(
			"JellyCore",
			Vector3.new(d * 0.52, d * 0.52, d * 0.52),
			species.Color:Lerp(Color3.new(1, 1, 1), 0.35),
			Enum.Material.Neon,
			Enum.PartType.Ball,
			CFrame.new(),
			body,
			model,
			0.25
		)
	elseif shapeId == "Drop" then
		makeAttachmentPart(
			"DropMid",
			Vector3.new(d * 0.68, d * 0.68, d * 0.68),
			species.Color,
			species.Material,
			Enum.PartType.Ball,
			CFrame.new(0, d * 0.28, 0),
			body,
			model
		)
		makeAttachmentPart(
			"DropTip",
			Vector3.new(d * 0.38, d * 0.38, d * 0.38),
			species.Color,
			species.Material,
			Enum.PartType.Ball,
			CFrame.new(0, d * 0.54, 0),
			body,
			model
		)
	elseif shapeId == "Donut" then
		-- Тесто пончика (цилиндр вдоль оси Z)
		makeAttachmentPart(
			"DonutDough",
			Vector3.new(d * 0.54, d, d),
			Color3.fromRGB(225, 165, 95),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder,
			CFrame.Angles(0, math.rad(90), 0),
			body,
			model
		)
		-- Цветная глазурь вида Губера
		makeAttachmentPart(
			"DonutFrosting",
			Vector3.new(d * 0.57, d * 0.94, d * 0.94),
			species.Color,
			species.Material,
			Enum.PartType.Cylinder,
			CFrame.new(0, 0, -d * 0.02) * CFrame.Angles(0, math.rad(90), 0),
			body,
			model
		)
		-- Тёмная «дырка от бублика» в центре спереди и сзади
		makeAttachmentPart(
			"DonutHole",
			Vector3.new(d * 0.60, d * 0.36, d * 0.36),
			Color3.fromRGB(30, 24, 32),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder,
			CFrame.Angles(0, math.rad(90), 0),
			body,
			model
		)
		-- Разноцветная кондитерская посыпка сверху
		local sprinkleColors = {
			Color3.fromRGB(255, 80, 120),
			Color3.fromRGB(80, 230, 255),
			Color3.fromRGB(255, 230, 70),
			Color3.fromRGB(120, 255, 110),
		}
		for i = 1, 4 do
			local ang = math.rad(-55 + (i - 1) * 36)
			makeAttachmentPart(
				"Sprinkle_" .. tostring(i),
				Vector3.new(d * 0.07, d * 0.16, d * 0.07),
				sprinkleColors[i],
				Enum.Material.Neon,
				Enum.PartType.Block,
				CFrame.new(math.sin(ang) * d * 0.36, math.cos(ang) * d * 0.36, -d * 0.24) * CFrame.Angles(0, 0, ang),
				body,
				model
			)
		end
	end

	-- 2. СТИКЕРЫ / 3D-ГЛАЗА (Выпученные / Злые / Аниме / Циклоп)
	local eyeY = d * 0.14
	if shapeId == "Donut" then
		eyeY = d * 0.28
	end

	if eyesId == "Bulging" then
		-- Смешные асимметричные выпученные глаза навыкате
		local leftEye = makeAttachmentPart(
			"EyeLeft",
			Vector3.new(d * 0.28, d * 0.28, d * 0.24),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			CFrame.new(-d * 0.17, eyeY, -(frontZ + d * 0.05)),
			body,
			model
		)
		makeAttachmentPart(
			"PupilLeft",
			Vector3.new(d * 0.11, d * 0.11, d * 0.08),
			Color3.fromRGB(15, 15, 20),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			CFrame.new(d * 0.02, d * 0.02, -d * 0.11),
			leftEye,
			model
		)

		local rightEye = makeAttachmentPart(
			"EyeRight",
			Vector3.new(d * 0.22, d * 0.22, d * 0.20),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			CFrame.new(d * 0.17, eyeY + d * 0.02, -(frontZ + d * 0.04)),
			body,
			model
		)
		makeAttachmentPart(
			"PupilRight",
			Vector3.new(d * 0.09, d * 0.09, d * 0.07),
			Color3.fromRGB(15, 15, 20),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			CFrame.new(-d * 0.02, -d * 0.01, -d * 0.09),
			rightEye,
			model
		)
	elseif eyesId == "Angry" then
		for _, side in ipairs({ -1, 1 }) do
			makeAttachmentPart(
				"AngryEye_" .. tostring(side),
				Vector3.new(d * 0.21, d * 0.18, d * 0.12),
				Color3.fromRGB(255, 245, 180),
				Enum.Material.Neon,
				Enum.PartType.Ball,
				CFrame.new(side * d * 0.17, eyeY, -frontZ),
				body,
				model
			)
			makeAttachmentPart(
				"AngryPupil_" .. tostring(side),
				Vector3.new(d * 0.09, d * 0.09, d * 0.08),
				Color3.fromRGB(185, 25, 25),
				Enum.Material.Neon,
				Enum.PartType.Ball,
				CFrame.new(side * d * 0.16, eyeY - d * 0.01, -(frontZ + d * 0.05)),
				body,
				model
			)
			-- Сдвинутые брови домиком >:(
			makeAttachmentPart(
				"AngryBrow_" .. tostring(side),
				Vector3.new(d * 0.26, d * 0.06, d * 0.10),
				Color3.fromRGB(25, 20, 25),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Block,
				CFrame.new(side * d * 0.16, eyeY + d * 0.10, -(frontZ + d * 0.04))
					* CFrame.Angles(0, 0, side * math.rad(25)),
				body,
				model
			)
		end
	elseif eyesId == "Anime" then
		for _, side in ipairs({ -1, 1 }) do
			makeAttachmentPart(
				"AnimeEye_" .. tostring(side),
				Vector3.new(d * 0.22, d * 0.26, d * 0.10),
				Color3.fromRGB(35, 22, 65),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Ball,
				CFrame.new(side * d * 0.18, eyeY, -frontZ),
				body,
				model
			)
			-- Звёздный блик
			makeAttachmentPart(
				"AnimeSparkle_" .. tostring(side),
				Vector3.new(d * 0.08, d * 0.08, d * 0.06),
				Color3.new(1, 1, 1),
				Enum.Material.Neon,
				Enum.PartType.Ball,
				CFrame.new(side * d * 0.18 - d * 0.04, eyeY + d * 0.05, -(frontZ + d * 0.045)),
				body,
				model
			)
			-- Милый розовый румянец
			makeAttachmentPart(
				"AnimeBlush_" .. tostring(side),
				Vector3.new(d * 0.14, d * 0.07, d * 0.06),
				Color3.fromRGB(255, 115, 165),
				Enum.Material.Neon,
				Enum.PartType.Ball,
				CFrame.new(side * d * 0.27, eyeY - d * 0.11, -(frontZ - d * 0.02)),
				body,
				model
			)
		end
	elseif eyesId == "Cyclops" then
		makeAttachmentPart(
			"CyclopsRim",
			Vector3.new(d * 0.14, d * 0.44, d * 0.44),
			Color3.fromRGB(90, 95, 115),
			Enum.Material.Metal,
			Enum.PartType.Cylinder,
			CFrame.new(0, eyeY + d * 0.02, -frontZ) * CFrame.Angles(0, math.rad(90), 0),
			body,
			model
		)
		makeAttachmentPart(
			"CyclopsSclera",
			Vector3.new(d * 0.36, d * 0.36, d * 0.20),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			CFrame.new(0, eyeY + d * 0.02, -(frontZ + d * 0.03)),
			body,
			model
		)
		makeAttachmentPart(
			"CyclopsIris",
			Vector3.new(d * 0.17, d * 0.17, d * 0.10),
			Color3.fromRGB(45, 220, 255),
			Enum.Material.Neon,
			Enum.PartType.Ball,
			CFrame.new(0, eyeY + d * 0.02, -(frontZ + d * 0.11)),
			body,
			model
		)
	end

	-- 3. СТИКЕРЫ / 3D-РОТ (Кричащий / С языком / Усы)
	local mouthY = -d * 0.14
	if shapeId == "Donut" then
		mouthY = -d * 0.27
	end

	if mouthId == "Screaming" then
		makeAttachmentPart(
			"ScreamMouth",
			Vector3.new(d * 0.24, d * 0.30, d * 0.10),
			Color3.fromRGB(30, 12, 22),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			CFrame.new(0, mouthY, -frontZ),
			body,
			model
		)
		makeAttachmentPart(
			"ScreamTeeth",
			Vector3.new(d * 0.16, d * 0.05, d * 0.07),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Block,
			CFrame.new(0, mouthY + d * 0.09, -(frontZ + d * 0.04)),
			body,
			model
		)
	elseif mouthId == "Tongue" then
		makeAttachmentPart(
			"SmileBar",
			Vector3.new(d * 0.32, d * 0.07, d * 0.08),
			Color3.fromRGB(30, 18, 25),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Block,
			CFrame.new(0, mouthY + d * 0.03, -frontZ),
			body,
			model
		)
		makeAttachmentPart(
			"GoofyTongue",
			Vector3.new(d * 0.16, d * 0.24, d * 0.09),
			Color3.fromRGB(255, 90, 135),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			CFrame.new(d * 0.03, mouthY - d * 0.08, -(frontZ + d * 0.05)) * CFrame.Angles(math.rad(18), 0, math.rad(10)),
			body,
			model
		)
	elseif mouthId == "Mustache" then
		for _, side in ipairs({ -1, 1 }) do
			makeAttachmentPart(
				"MustacheWing_" .. tostring(side),
				Vector3.new(d * 0.28, d * 0.09, d * 0.10),
				Color3.fromRGB(65, 40, 24),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Block,
				CFrame.new(side * d * 0.13, mouthY + d * 0.03, -(frontZ + d * 0.04))
					* CFrame.Angles(0, 0, -side * math.rad(16)),
				body,
				model
			)
			makeAttachmentPart(
				"MustacheCurl_" .. tostring(side),
				Vector3.new(d * 0.10, d * 0.10, d * 0.10),
				Color3.fromRGB(65, 40, 24),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Ball,
				CFrame.new(side * d * 0.28, mouthY + d * 0.07, -(frontZ + d * 0.05)),
				body,
				model
			)
		end
	end

	-- 4. 3D-АКСЕССУАРЫ (Пропеллер / Корона / Очки / Реактивный ранец)
	if accId == "Propeller" then
		makeAttachmentPart(
			"BeanieCap",
			Vector3.new(d * 0.44, d * 0.22, d * 0.44),
			Color3.fromRGB(255, 75, 75),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball,
			CFrame.new(0, topY, 0),
			body,
			model
		)
		makeAttachmentPart(
			"PropellerPin",
			Vector3.new(d * 0.06, d * 0.16, d * 0.06),
			Color3.fromRGB(245, 210, 50),
			Enum.Material.Metal,
			Enum.PartType.Block,
			CFrame.new(0, topY + d * 0.14, 0),
			body,
			model
		)
		makeAttachmentPart(
			"PropellerBladeA",
			Vector3.new(d * 0.68, d * 0.03, d * 0.10),
			Color3.fromRGB(255, 225, 45),
			Enum.Material.Neon,
			Enum.PartType.Block,
			CFrame.new(0, topY + d * 0.21, 0) * CFrame.Angles(0, math.rad(25), 0),
			body,
			model
		)
		makeAttachmentPart(
			"PropellerBladeB",
			Vector3.new(d * 0.10, d * 0.03, d * 0.68),
			Color3.fromRGB(65, 215, 255),
			Enum.Material.Neon,
			Enum.PartType.Block,
			CFrame.new(0, topY + d * 0.21, 0) * CFrame.Angles(0, math.rad(25), 0),
			body,
			model
		)
	elseif accId == "Crown" then
		makeAttachmentPart(
			"CrownBase",
			Vector3.new(d * 0.20, d * 0.46, d * 0.46),
			Color3.fromRGB(255, 210, 45),
			Enum.Material.Neon,
			Enum.PartType.Cylinder,
			CFrame.new(0, topY + d * 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)),
			body,
			model
		)
		for i = 1, 4 do
			local ang = math.rad((i - 1) * 90)
			makeAttachmentPart(
				"CrownGem_" .. tostring(i),
				Vector3.new(d * 0.09, d * 0.13, d * 0.09),
				i % 2 == 0 and Color3.fromRGB(255, 50, 90) or Color3.fromRGB(50, 235, 255),
				Enum.Material.Neon,
				Enum.PartType.Ball,
				CFrame.new(math.cos(ang) * d * 0.22, topY + d * 0.18, math.sin(ang) * d * 0.22),
				body,
				model
			)
		end
	elseif accId == "Sunglasses" then
		makeAttachmentPart(
			"ShadesBar",
			Vector3.new(d * 0.66, d * 0.06, d * 0.08),
			Color3.fromRGB(15, 15, 20),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Block,
			CFrame.new(0, eyeY + d * 0.06, -(frontZ + d * 0.12)),
			body,
			model
		)
		for _, side in ipairs({ -1, 1 }) do
			makeAttachmentPart(
				"ShadesLens_" .. tostring(side),
				Vector3.new(d * 0.25, d * 0.16, d * 0.08),
				Color3.fromRGB(20, 25, 35),
				Enum.Material.Glass,
				Enum.PartType.Block,
				CFrame.new(side * d * 0.17, eyeY, -(frontZ + d * 0.12)),
				body,
				model
			)
		end
	elseif accId == "Jetpack" then
		local backZ = frontZ
		for _, side in ipairs({ -1, 1 }) do
			makeAttachmentPart(
				"JetTank_" .. tostring(side),
				Vector3.new(d * 0.48, d * 0.20, d * 0.20),
				Color3.fromRGB(190, 200, 215),
				Enum.Material.Metal,
				Enum.PartType.Cylinder,
				CFrame.new(side * d * 0.14, 0, backZ + d * 0.08) * CFrame.Angles(0, 0, math.rad(90)),
				body,
				model
			)
			local flame = makeAttachmentPart(
				"JetFlame_" .. tostring(side),
				Vector3.new(d * 0.15, d * 0.22, d * 0.15),
				Color3.fromRGB(255, 130, 35),
				Enum.Material.Neon,
				Enum.PartType.Ball,
				CFrame.new(side * d * 0.14, -d * 0.28, backZ + d * 0.08),
				body,
				model
			)
			local emitter = Instance.new("ParticleEmitter")
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 65, 25))
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, d * 0.12),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Lifetime = NumberRange.new(0.2, 0.35)
			emitter.Rate = 18
			emitter.Speed = NumberRange.new(4, 8)
			emitter.EmissionDirection = Enum.NormalId.Bottom
			emitter.Parent = flame
		end
	end

	-- Особая подсветка для редких гостей и мутаций
	if species.Id == "FatWatermelon" then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 0.85
		hl.FillColor = Color3.fromRGB(255, 70, 95)
		hl.OutlineColor = Color3.fromRGB(20, 95, 35)
		hl.Parent = model
	elseif species.Id == "CursedSock" then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 0.74
		hl.FillColor = Color3.fromRGB(160, 50, 255)
		hl.OutlineColor = Color3.fromRGB(215, 115, 255)
		hl.Parent = model
	elseif mutation.Id ~= "Normal" then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 0.88
		hl.FillColor = mutation.BadgeColor
		hl.OutlineColor = mutation.BadgeColor
		hl.OutlineTransparency = 0.25
		hl.Parent = model
	end

	-- Компактный информационный бейдж над Губером (MaxDistance = 45, аккуратный шрифт)
	if not opts.HideBillboard then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "InfoTag"
		billboard.Size = UDim2.fromOffset(145, 38)
		billboard.StudsOffset = Vector3.new(0, topY + 1.4, 0)
		billboard.MaxDistance = 45
		billboard.AlwaysOnTop = false
		billboard.Parent = body

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.fromScale(1, 0.55)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextScaled = true
		titleLabel.TextColor3 = species.IsRareGuest and Color3.fromRGB(255, 215, 65) or Color3.new(1, 1, 1)
		titleLabel.TextStrokeTransparency = 0.25
		titleLabel.Text = string.format("%s (%.1f кг)", species.Name, gooberData.Weight)
		titleLabel.Parent = billboard

		local tc1 = Instance.new("UITextSizeConstraint")
		tc1.MaxTextSize = 13
		tc1.MinTextSize = 8
		tc1.Parent = titleLabel

		local mutLabel = Instance.new("TextLabel")
		mutLabel.Name = "Mutation"
		mutLabel.Position = UDim2.fromScale(0, 0.54)
		mutLabel.Size = UDim2.fromScale(1, 0.46)
		mutLabel.BackgroundTransparency = 1
		mutLabel.Font = Enum.Font.GothamMedium
		mutLabel.TextScaled = true
		mutLabel.TextColor3 = mutation.BadgeColor
		mutLabel.TextStrokeTransparency = 0.3
		mutLabel.Text = string.format("[%s • %s]", mutation.Name, (GooberConfig.BodyShapes[shapeId] or GooberConfig.BodyShapes.Jelly).Name)
		mutLabel.Parent = billboard

		local tc2 = Instance.new("UITextSizeConstraint")
		tc2.MaxTextSize = 11
		tc2.MinTextSize = 8
		tc2.Parent = mutLabel
	end

	return model
end

return GooberConfig
