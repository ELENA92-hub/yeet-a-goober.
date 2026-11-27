--!strict
--[[
	LaunchService.lua
	Драйвовая серверная физика полёта, управления, трюков, препятствий и поощрений:
	- Учитывает все 3D-детали из «Мастерской Губера» (планирование Пропеллера, таран Кубика,
	  стартовый Щит Очков/Короны, мощный Рывок Реактивного ранца, магнит Пончика/Выпученных глаз).
	- Непрерывное руление в воздухе (A/D и стрелки) через мировую VectorForce.
	- Кнопка «Рывок / Ускорение» (Space / клик) с серверным откатом и взрывным импульсом.
	- Система серии трюков в воздухе без касания земли (TrickStreak) + Комбо-множитель.
	- Поощрения: золотые кольца, батуты-облака, воздушные потоки, парящие монеты, кристаллы мутаций.
	- Препятствия: крутящиеся вентиляторы, грозовые тучи (со Щитом дают СУПЕР-МУТАЦИЮ!),
	  летающие преграды и стены, пробиваемые на высокой скорости или Рывком.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local IncubatorService = require(script.Parent:WaitForChild("IncubatorService"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))

export type GooberData = GooberConfig.GooberData

type ActiveFlight = {
	Player: Player,
	GooberData: GooberData,
	Stats: GooberConfig.ComputedFlightStats,
	Model: Model,
	Body: BasePart,
	PerfectMultiplier: number,
	ComboMultiplier: number,
	TrickStreak: number,
	BestTrickStreak: number,
	BonusTrackCoins: number,
	HasShield: boolean,
	SteerInput: number,
	StartTime: number,
	LastDashTime: number,
	NextDashAvailableAt: number,
	LastGroundTouchTime: number,
	RecentSpeed: number,
	Finished: boolean,
	TouchConnection: RBXScriptConnection?,
}

type PendingLanding = {
	GooberData: GooberData,
	RewardCoins: number,
	PassiveIncome: number,
	Distance: number,
	ComboMultiplier: number,
	PerfectMultiplier: number,
	BestTrickStreak: number,
	Model: Model?,
}

local LaunchService = {}

local ActiveFlights: { [Player]: ActiveFlight } = {}
local PendingLandings: { [Player]: PendingLanding } = {}
local FloatingCoinsCache: { BasePart } = {}
local initialized = false

local MAX_FLIGHT_DURATION = 28.0
local MAX_COMBO_MULTIPLIER = 250.0

local function play3DSound(parent: Instance, soundId: string, volume: number?, playbackSpeed: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.85
	sound.PlaybackSpeed = playbackSpeed or 1.0
	sound.RollOffMaxDistance = 300
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function spawnFloatingRewardPopup(worldPos: Vector3, headline: string, subText: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Name = "RewardPopupAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Position = worldPos + Vector3.new(0, 4.5, 0)
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatingRewardGui"
	gui.Size = UDim2.fromOffset(230, 66)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 850
	gui.Parent = anchor

	local topLabel = Instance.new("TextLabel")
	topLabel.Size = UDim2.fromScale(1, 0.50)
	topLabel.BackgroundTransparency = 1
	topLabel.Font = Enum.Font.GothamBlack
	topLabel.TextScaled = true
	topLabel.TextColor3 = color
	topLabel.TextStrokeTransparency = 0.1
	topLabel.Text = headline
	topLabel.Parent = gui

	local bottomLabel = Instance.new("TextLabel")
	bottomLabel.Position = UDim2.fromScale(0, 0.50)
	bottomLabel.Size = UDim2.fromScale(1, 0.50)
	bottomLabel.BackgroundTransparency = 1
	bottomLabel.Font = Enum.Font.GothamBlack
	bottomLabel.TextScaled = true
	bottomLabel.TextColor3 = Color3.fromRGB(255, 225, 65)
	bottomLabel.TextStrokeTransparency = 0.12
	bottomLabel.Text = subText
	bottomLabel.Parent = gui

	local riseTween = TweenService:Create(
		anchor,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = anchor.Position + Vector3.new(0, 10.5, 0) }
	)
	riseTween:Play()
	Debris:AddItem(anchor, 1.15)
end

local function cleanupPendingModel(pending: PendingLanding?)
	if pending and pending.Model then
		if pending.Model.Parent then
			pending.Model:Destroy()
		end
		pending.Model = nil
	end
end

local function resolvePendingAutomatically(player: Player)
	local pending = PendingLandings[player]
	if not pending then
		return
	end
	PendingLandings[player] = nil
	cleanupPendingModel(pending)
	DataManager.AddCoins(player, pending.RewardCoins, false)
end

local function getDistanceStuds(pos: Vector3): number
	local dz = MapGenerator.CLIFF_EDGE_Z - pos.Z
	return math.max(1, math.floor(dz + 0.5))
end

local function temporarilyHideCollectible(part: BasePart, respawnDelay: number)
	if part:GetAttribute("Collected") then
		return false
	end
	part:SetAttribute("Collected", true)
	local origTrans = part.Transparency
	part.Transparency = 1
	part.CanTouch = false

	local sign = part:FindFirstChild("SignGui") :: BillboardGui?
	if sign then
		sign.Enabled = false
	end

	task.delay(respawnDelay, function()
		if part and part.Parent then
			part.Transparency = origTrans
			part.CanTouch = true
			part:SetAttribute("Collected", nil)
			if sign then
				sign.Enabled = true
			end
		end
	end)
	return true
end

local function shatterBreakableWall(wallPart: BasePart)
	if wallPart:GetAttribute("Broken") then
		return
	end
	wallPart:SetAttribute("Broken", true)
	local origTrans = wallPart.Transparency
	local origColor = wallPart.Color

	wallPart.CanCollide = false
	wallPart.Transparency = 0.78
	wallPart.Color = Color3.fromRGB(255, 130, 55)

	-- Несколько разлетающихся осколков (локальный визуальный фан без нагрузки)
	for i = 1, 4 do
		local debrisChunk = Instance.new("Part")
		debrisChunk.Size = Vector3.new(3.2, 3.2, 2.2)
		debrisChunk.Color = origColor
		debrisChunk.Material = Enum.Material.Brick
		debrisChunk.CanCollide = false
		debrisChunk.CanTouch = false
		debrisChunk.CanQuery = false
		debrisChunk.Position = wallPart.Position + Vector3.new((i - 2.5) * 3.5, 2, -2)
		debrisChunk.Parent = workspace
		debrisChunk:ApplyImpulse(Vector3.new((i - 2.5) * 45, 85, -140) * debrisChunk.AssemblyMass)
		debrisChunk:ApplyAngularImpulse(Vector3.new(30, 45, 25) * debrisChunk.AssemblyMass)
		Debris:AddItem(debrisChunk, 1.4)
	end

	task.delay(6.0, function()
		if wallPart and wallPart.Parent then
			wallPart.CanCollide = true
			wallPart.Transparency = origTrans
			wallPart.Color = origColor
			wallPart:SetAttribute("Broken", nil)
		end
	end)
end

local function updateSteerForceOnBody(flight: ActiveFlight)
	local body = flight.Body
	if not body or not body.Parent then
		return
	end
	local steerVF = body:FindFirstChild("SteerVectorForce") :: VectorForce?
	if not steerVF then
		return
	end

	local profile = DataManager.GetProfile(flight.Player)
	local vipMult = (profile and profile.OwnedPasses.JetpackSteering) and 1.65 or 1.0
	local forceX = flight.SteerInput * 105.0 * body.AssemblyMass * flight.Stats.SteerForceMult * vipMult
	steerVF.Force = Vector3.new(forceX, 0, 0)
end

local function registerAirTrick(flight: ActiveFlight, baseFactor: number): number
	flight.TrickStreak += 1
	if flight.TrickStreak > flight.BestTrickStreak then
		flight.BestTrickStreak = flight.TrickStreak
	end
	-- Чем длиннее серия трюков без касания земли, тем быстрее растёт Комбо!
	local streakBonus = math.min(flight.TrickStreak * 0.05, 0.45)
	local gain = (1.0 + (baseFactor - 1.0) * flight.Stats.ComboGainMult) + streakBonus
	flight.ComboMultiplier = math.min(flight.ComboMultiplier * gain, MAX_COMBO_MULTIPLIER)
	return flight.TrickStreak
end

local function collectCoinForFlight(flight: ActiveFlight, coinPart: BasePart, flightEvent: RemoteEvent)
	if not temporarilyHideCollectible(coinPart, 7.0) then
		return
	end
	local baseBonus = tonumber(coinPart:GetAttribute("CoinBonus")) or 35
	local gained = math.max(5, math.floor(baseBonus * flight.Stats.CoinPickupMult * math.sqrt(flight.ComboMultiplier)))
	flight.BonusTrackCoins += gained

	play3DSound(flight.Body, GooberConfig.Sounds.CoinPickup, 0.7, 1.15)
	spawnFloatingRewardPopup(
		coinPart.Position,
		"🪙 МОНЕТКА!",
		string.format("+%d 🪙", gained),
		Color3.fromRGB(255, 225, 55)
	)

	flightEvent:FireClient(flight.Player, "ComboUpdate", {
		ComboMultiplier = flight.ComboMultiplier,
		TrickStreak = flight.TrickStreak,
		Distance = getDistanceStuds(flight.Body.Position),
		HasShield = flight.HasShield,
		Source = "Coin",
	})
end

local function finishFlight(flight: ActiveFlight, flightEvent: RemoteEvent)
	if flight.Finished then
		return
	end
	flight.Finished = true

	if flight.TouchConnection then
		flight.TouchConnection:Disconnect()
		flight.TouchConnection = nil
	end

	local player = flight.Player
	ActiveFlights[player] = nil

	if not player:IsDescendantOf(Players) then
		if flight.Model and flight.Model.Parent then
			flight.Model:Destroy()
		end
		return
	end

	local finalPos = if flight.Body and flight.Body.Parent
		then flight.Body.Position
		else Vector3.new(0, 12, -200)

	if flight.Body and flight.Body.Parent then
		flight.Body.AssemblyLinearVelocity = Vector3.zero
		flight.Body.AssemblyAngularVelocity = Vector3.zero
		flight.Body.Anchored = true
		play3DSound(flight.Body, GooberConfig.Sounds.LandCoin, 0.9, 1.0)
	end

	local distance = getDistanceStuds(finalPos)
	local rewardCoins = GooberConfig.CalculateFlightReward(
		flight.GooberData,
		distance,
		flight.PerfectMultiplier,
		flight.ComboMultiplier,
		flight.BonusTrackCoins
	)
	local passiveIncome = GooberConfig.CalculatePassiveIncome(flight.GooberData)

	local profile = DataManager.GetProfile(player)
	local runtime = DataManager.GetRuntime(player)
	if profile and distance > profile.BestDistance then
		profile.BestDistance = distance
		if runtime then
			runtime.Dirty = true
		end
		DataManager.SyncToClient(player)
	end

	spawnFloatingRewardPopup(
		finalPos,
		string.format("🏁 %d м! ИТОГО:", distance),
		string.format("+%d 🪙", rewardCoins),
		Color3.fromRGB(110, 255, 150)
	)

	PendingLandings[player] = {
		GooberData = flight.GooberData,
		RewardCoins = rewardCoins,
		PassiveIncome = passiveIncome,
		Distance = distance,
		ComboMultiplier = flight.ComboMultiplier,
		PerfectMultiplier = flight.PerfectMultiplier,
		BestTrickStreak = flight.BestTrickStreak,
		Model = flight.Model,
	}

	flightEvent:FireClient(player, "Landed", {
		GooberData = flight.GooberData,
		RewardCoins = rewardCoins,
		PassiveIncome = passiveIncome,
		Distance = distance,
		ComboMultiplier = flight.ComboMultiplier,
		PerfectMultiplier = flight.PerfectMultiplier,
		BestTrickStreak = flight.BestTrickStreak,
	})
end

function LaunchService.HandleLaunch(player: Player, rawCharge: any, flightEvent: RemoteEvent)
	if ActiveFlights[player] then
		return
	end

	if PendingLandings[player] then
		resolvePendingAutomatically(player)
	end

	local profile = DataManager.GetProfile(player)
	local runtime = DataManager.GetRuntime(player)
	if not profile or not runtime then
		return
	end

	if not runtime.HeldGoober then
		DataManager.Notify(player, "Сначала собери и возьми чудика в руки!", "warn")
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	if rootPart.Position.Y < 245 or rootPart.Position.Z > -22 then
		DataManager.Notify(player, "Подойди к жёлтой зоне у края обрыва, чтобы пнуть чудика!", "warn")
		return
	end

	local chargePercent = math.clamp(tonumber(rawCharge) or 50, 1, 100)
	local isPerfect = chargePercent >= 85 and chargePercent <= 95
	local perfectMultiplier = isPerfect and 3 or 1

	local gooberData = IncubatorService.ConsumeHeldGoober(player)
	if not gooberData then
		return
	end

	local stats = GooberConfig.ComputeFlightStats(gooberData)
	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal
	local gooberModel = GooberConfig.BuildGooberModel(gooberData)
	local body = gooberModel.PrimaryPart
	if not body then
		gooberModel:Destroy()
		return
	end

	local flightId = string.format("Flight_%d_%d", player.UserId, math.floor(os.clock() * 1000))
	gooberModel.Name = flightId
	gooberModel:SetAttribute("FlightId", flightId)
	gooberModel:SetAttribute("OwnerUserId", player.UserId)

	local radius = math.max(body.Size.X, body.Size.Y, body.Size.Z) * 0.5
	local spawnX = math.clamp(rootPart.Position.X, -44, 44)
	local spawnPos = Vector3.new(spawnX, 262.5 + radius, MapGenerator.CLIFF_EDGE_Z - radius - 2.4)
	gooberModel:PivotTo(CFrame.new(spawnPos))

	local activeFolder = workspace:FindFirstChild("ActiveGoobers") or workspace
	gooberModel.Parent = activeFolder

	pcall(function()
		body:SetNetworkOwner(nil)
	end)

	-- Физика, трейл скорости и стартовый Энерго-Щит (если надеты Очки / Корона)
	GooberConfig.ApplyFlightPhysics(gooberModel, gooberData)
	GooberConfig.AttachFlightTrail(gooberModel, mutation.BadgeColor)
	if stats.StartsWithShield then
		GooberConfig.SetShieldVisual(gooberModel, true)
	end

	local chargeFactor = 0.38 + 0.62 * (chargePercent / 100.0)
	local bootMult = GooberConfig.GetBootPowerMultiplier(profile.BootLevel)
	local perfectSpeedMult = isPerfect and 1.30 or 1.0
	local targetSpeed = 135.0 * chargeFactor * bootMult * stats.LaunchSpeedMult * perfectSpeedMult

	local launchDir = Vector3.new(0, 0.40, -1.0).Unit
	local mass = body.AssemblyMass
	body:ApplyImpulse(launchDir * (targetSpeed * mass))
	body:ApplyAngularImpulse(Vector3.new(-mass * 22, mass * 6, mass * 4))

	local useMemeSounds = profile.OwnedPasses.MemeSoundPack == true
	play3DSound(
		body,
		useMemeSounds and GooberConfig.Sounds.MemeKick or GooberConfig.Sounds.StandardKick,
		1.0,
		isPerfect and 1.15 or 1.0
	)

	local vipDashMult = profile.OwnedPasses.JetpackSteering and 0.65 or 1.0
	local effectiveDashCooldown = math.max(0.85, stats.DashCooldown * vipDashMult)

	local flight: ActiveFlight = {
		Player = player,
		GooberData = gooberData,
		Stats = stats,
		Model = gooberModel,
		Body = body,
		PerfectMultiplier = perfectMultiplier,
		ComboMultiplier = 1.0,
		TrickStreak = 0,
		BestTrickStreak = 0,
		BonusTrackCoins = 0,
		HasShield = stats.StartsWithShield,
		SteerInput = 0,
		StartTime = os.clock(),
		LastDashTime = 0,
		NextDashAvailableAt = 0,
		LastGroundTouchTime = 0,
		RecentSpeed = targetSpeed,
		Finished = false,
		TouchConnection = nil,
	}
	ActiveFlights[player] = flight

	local hitCooldowns: { [Instance]: number } = {}

	flight.TouchConnection = body.Touched:Connect(function(hit: BasePart)
		if flight.Finished or not hit or not hit.Parent then
			return
		end

		local now = os.clock()

		-- 1. Парящая монетка
		if hit:GetAttribute("IsFloatingCoin") then
			collectCoinForFlight(flight, hit, flightEvent)
			return
		end

		-- 2. Касание голой земли сбрасывает активную воздушную серию трюков
		if hit:GetAttribute("IsSlopeGround") then
			if (now - flight.StartTime) > 1.2 and (now - flight.LastGroundTouchTime) > 0.9 then
				flight.LastGroundTouchTime = now
				if flight.TrickStreak >= 2 then
					local endedStreak = flight.TrickStreak
					flight.TrickStreak = 0
					play3DSound(body, GooberConfig.Sounds.StandardBounce, 0.55, 0.9)
					flightEvent:FireClient(player, "StreakReset", {
						EndedStreak = endedStreak,
						ComboMultiplier = flight.ComboMultiplier,
						Shake = 0.45,
					})
				end
			end
			return
		end

		if hitCooldowns[hit] and (now - hitCooldowns[hit]) < 0.85 then
			return
		end

		local currentMass = body.AssemblyMass

		-- 3. Золотое кольцо ускорения
		if hit:GetAttribute("IsGoldenRing") then
			hitCooldowns[hit] = now
			local streak = registerAirTrick(flight, 1.45 * flight.Stats.RingRewardMult)
			body:ApplyImpulse(Vector3.new(0, 28 * currentMass, -98 * currentMass * flight.Stats.RingRewardMult))
			play3DSound(body, GooberConfig.Sounds.RingChime, 1.0, 1.12)

			local dist = getDistanceStuds(body.Position)
			local liveReward = GooberConfig.CalculateFlightReward(
				flight.GooberData,
				dist,
				flight.PerfectMultiplier,
				flight.ComboMultiplier,
				flight.BonusTrackCoins
			)

			spawnFloatingRewardPopup(
				body.Position,
				string.format("⭕ КОЛЬЦО! ТРЮК #%d (x%.2f)", streak, flight.ComboMultiplier),
				string.format("+%d 🪙", liveReward),
				Color3.fromRGB(255, 225, 60)
			)

			flightEvent:FireClient(player, "ComboUpdate", {
				ComboMultiplier = flight.ComboMultiplier,
				TrickStreak = streak,
				Distance = dist,
				HasShield = flight.HasShield,
				Shake = 0.35,
				Source = "GoldenRing",
			})

		-- 4. Батут-облако
		elseif hit:GetAttribute("IsCloudTrampoline") then
			hitCooldowns[hit] = now
			local streak = registerAirTrick(flight, 1.40)
			body:ApplyImpulse(Vector3.new(0, 94 * currentMass, -88 * currentMass))
			body:ApplyAngularImpulse(Vector3.new(-28 * currentMass, 12 * currentMass, 8 * currentMass))
			play3DSound(
				body,
				useMemeSounds and GooberConfig.Sounds.MemeBounce or GooberConfig.Sounds.StandardBounce,
				0.95,
				1.1
			)

			local dist = getDistanceStuds(body.Position)
			local liveReward = GooberConfig.CalculateFlightReward(
				flight.GooberData,
				dist,
				flight.PerfectMultiplier,
				flight.ComboMultiplier,
				flight.BonusTrackCoins
			)

			spawnFloatingRewardPopup(
				body.Position,
				string.format("☁️ БАТУТ-ОБЛАКО! ТРЮК #%d", streak),
				string.format("КОМБО x%.2f • +%d 🪙", flight.ComboMultiplier, liveReward),
				Color3.fromRGB(135, 235, 255)
			)

			flightEvent:FireClient(player, "ComboUpdate", {
				ComboMultiplier = flight.ComboMultiplier,
				TrickStreak = streak,
				Distance = dist,
				HasShield = flight.HasShield,
				Shake = 0.55,
				Source = "CloudTrampoline",
			})

		-- 5. Воздушный поток
		elseif hit:GetAttribute("IsAirCurrent") then
			hitCooldowns[hit] = now
			local streak = registerAirTrick(flight, 1.35)
			body:ApplyImpulse(Vector3.new(0, 110 * currentMass, -78 * currentMass))
			play3DSound(body, GooberConfig.Sounds.DashWhoosh, 0.85, 1.25)

			spawnFloatingRewardPopup(
				body.Position,
				string.format("🌪️ ПОТОК ВЕТРА! ТРЮК #%d", streak),
				string.format("КОМБО x%.2f", flight.ComboMultiplier),
				Color3.fromRGB(155, 245, 255)
			)

			flightEvent:FireClient(player, "ComboUpdate", {
				ComboMultiplier = flight.ComboMultiplier,
				TrickStreak = streak,
				Distance = getDistanceStuds(body.Position),
				HasShield = flight.HasShield,
				Shake = 0.3,
				Source = "AirCurrent",
			})

		-- 6. Редкий кристалл мутаций (+Щит и Комбо!)
		elseif hit:GetAttribute("IsMutationCrystal") then
			if temporarilyHideCollectible(hit, 9.0) then
				flight.HasShield = true
				GooberConfig.SetShieldVisual(flight.Model, true)
				local streak = registerAirTrick(flight, 1.75)
				body:ApplyImpulse(Vector3.new(0, 42 * currentMass, -75 * currentMass))
				play3DSound(body, GooberConfig.Sounds.RingChime, 1.0, 1.35)

				spawnFloatingRewardPopup(
					body.Position,
					"💎 КРИСТАЛЛ МУТАЦИИ!",
					string.format("🛡️ ЩИТ АКТИВЕН! x%.2f", flight.ComboMultiplier),
					Color3.fromRGB(245, 105, 255)
				)

				DataManager.Notify(player, "💎 Получен Энерго-Щит! Влетай в грозовую тучу за СУПЕР-МУТАЦИЕЙ!", "rare")
				flightEvent:FireClient(player, "ComboUpdate", {
					ComboMultiplier = flight.ComboMultiplier,
					TrickStreak = streak,
					Distance = getDistanceStuds(body.Position),
					HasShield = true,
					Shake = 0.5,
					Source = "Crystal",
				})
			end

		-- 7. Грозовая туча (Без щита: Шок и замедление! Со щитом: СУПЕР-МУТАЦИЯ!)
		elseif hit:GetAttribute("IsThunderCloud") then
			hitCooldowns[hit] = now

			if flight.HasShield then
				-- СУПЕР-МУТАЦИЯ!
				flight.HasShield = false
				GooberConfig.SetShieldVisual(flight.Model, false)
				flight.GooberData.MutationId = "SuperStorm"
				flight.Stats = GooberConfig.ComputeFlightStats(flight.GooberData)
				GooberConfig.ApplyFlightPhysics(flight.Model, flight.GooberData)
				updateSteerForceOnBody(flight)

				local stormHl = Instance.new("Highlight")
				stormHl.Name = "SuperStormAura"
				stormHl.FillColor = Color3.fromRGB(255, 235, 60)
				stormHl.OutlineColor = Color3.fromRGB(80, 240, 255)
				stormHl.FillTransparency = 0.45
				stormHl.Parent = flight.Model

				local streak = registerAirTrick(flight, 2.50)
				local newMass = body.AssemblyMass
				body:ApplyImpulse(Vector3.new(0, 72 * newMass, -148 * newMass))
				play3DSound(body, GooberConfig.Sounds.RingChime, 1.0, 0.85)

				spawnFloatingRewardPopup(
					body.Position,
					"⚡🌟 СУПЕР-МУТАЦИЯ!",
					string.format("ГРОЗОВОЙ БОГ! КОМБО x%.2f", flight.ComboMultiplier),
					Color3.fromRGB(255, 235, 65)
				)

				DataManager.Notify(player, "⚡ СУПЕР-МУТАЦИЯ! Щит поглотил молнию и дал х4 к ценности Губера!", "rare")
				flightEvent:FireClient(player, "SuperMutation", {
					ComboMultiplier = flight.ComboMultiplier,
					TrickStreak = streak,
					Distance = getDistanceStuds(body.Position),
					HasShield = false,
					Shake = 1.25,
				})
			else
				-- Удар током и замедление!
				body.AssemblyLinearVelocity *= 0.52
				body:ApplyAngularImpulse(Vector3.new(45 * currentMass, 65 * currentMass, 50 * currentMass))
				flight.TrickStreak = 0
				play3DSound(body, GooberConfig.Sounds.ZapShock, 1.0, 1.05)

				spawnFloatingRewardPopup(
					body.Position,
					"⚡ УДАР ТОКОМ!",
					"Замедление! (Возьми Щит для Супер-Мутации)",
					Color3.fromRGB(255, 95, 75)
				)

				flightEvent:FireClient(player, "Impact", {
					Kind = "Zap",
					ComboMultiplier = flight.ComboMultiplier,
					TrickStreak = 0,
					HasShield = false,
					Shake = 1.15,
				})
			end

		-- 8. Крутящиеся лопасти вентилятора
		elseif hit:GetAttribute("IsSpinningFan") then
			hitCooldowns[hit] = now
			if flight.HasShield then
				flight.HasShield = false
				GooberConfig.SetShieldVisual(flight.Model, false)
				body:ApplyImpulse(Vector3.new(0, 35 * currentMass, -70 * currentMass))
				play3DSound(body, GooberConfig.Sounds.StandardBounce, 0.9, 1.2)
				spawnFloatingRewardPopup(body.Position, "🛡️ ЩИТ СПАС!", "Лопасти отражены!", Color3.fromRGB(95, 235, 255))
				flightEvent:FireClient(player, "Impact", {
					Kind = "ShieldBlock",
					ComboMultiplier = flight.ComboMultiplier,
					TrickStreak = flight.TrickStreak,
					HasShield = false,
					Shake = 0.65,
				})
			else
				local knockSide = (body.Position.X >= hit.Position.X) and 1 or -1
				body.AssemblyLinearVelocity *= 0.62
				body:ApplyImpulse(Vector3.new(knockSide * 68 * currentMass, 48 * currentMass, 24 * currentMass))
				body:ApplyAngularImpulse(Vector3.new(60 * currentMass, 80 * currentMass, 70 * currentMass))
				flight.TrickStreak = 0
				play3DSound(body, GooberConfig.Sounds.FanBonk, 1.0, 0.92)

				spawnFloatingRewardPopup(body.Position, "🌀 БОНК О ЛОПАСТЬ!", "Серия трюков сброшена!", Color3.fromRGB(255, 95, 95))
				flightEvent:FireClient(player, "Impact", {
					Kind = "FanBonk",
					ComboMultiplier = flight.ComboMultiplier,
					TrickStreak = 0,
					HasShield = false,
					Shake = 1.1,
				})
			end

		-- 9. Летающая преграда
		elseif hit:GetAttribute("IsFlyingHazard") then
			hitCooldowns[hit] = now
			local bounceX = (body.Position.X >= hit.Position.X) and 52 or -52
			body:ApplyImpulse(Vector3.new(bounceX * currentMass, 56 * currentMass, -25 * currentMass))
			body:ApplyAngularImpulse(Vector3.new(-55 * currentMass, 50 * currentMass, 65 * currentMass))
			play3DSound(
				body,
				useMemeSounds and GooberConfig.Sounds.MemeBounce or GooberConfig.Sounds.FanBonk,
				0.95,
				1.15
			)
			spawnFloatingRewardPopup(body.Position, "🛸 РИКОШЕТ!", "Держи курс A/D!", Color3.fromRGB(255, 165, 65))
			flightEvent:FireClient(player, "Impact", {
				Kind = "HazardBounce",
				ComboMultiplier = flight.ComboMultiplier,
				TrickStreak = flight.TrickStreak,
				HasShield = flight.HasShield,
				Shake = 0.85,
			})

		-- 10. Стенка, которую можно пробить на высокой скорости или Рывком!
		elseif hit:GetAttribute("IsBreakableWall") then
			hitCooldowns[hit] = now
			local currentSpeed = math.max(flight.RecentSpeed, body.AssemblyLinearVelocity.Magnitude)
			local isDashing = (now - flight.LastDashTime) < 1.25

			if isDashing or flight.Stats.BreaksObstaclesAlways or currentSpeed >= flight.Stats.WallSmashSpeedThreshold then
				shatterBreakableWall(hit)
				local streak = registerAirTrick(flight, 1.60)
				body:ApplyImpulse(Vector3.new(0, 22 * currentMass, -82 * currentMass))
				play3DSound(body, GooberConfig.Sounds.WallSmash, 1.0, 0.95)

				local dist = getDistanceStuds(body.Position)
				local liveReward = GooberConfig.CalculateFlightReward(
					flight.GooberData,
					dist,
					flight.PerfectMultiplier,
					flight.ComboMultiplier,
					flight.BonusTrackCoins
				)

				spawnFloatingRewardPopup(
					body.Position,
					string.format("💥 СТЕНКА ПРОБИТА! ТРЮК #%d", streak),
					string.format("КОМБО x%.2f • +%d 🪙", flight.ComboMultiplier, liveReward),
					Color3.fromRGB(255, 155, 55)
				)

				flightEvent:FireClient(player, "ComboUpdate", {
					ComboMultiplier = flight.ComboMultiplier,
					TrickStreak = streak,
					Distance = dist,
					HasShield = flight.HasShield,
					Shake = 0.95,
					Source = "WallSmash",
				})
			else
				body:ApplyImpulse(Vector3.new(0, 38 * currentMass, 42 * currentMass))
				body:ApplyAngularImpulse(Vector3.new(50 * currentMass, 30 * currentMass, 40 * currentMass))
				flight.TrickStreak = 0
				play3DSound(body, GooberConfig.Sounds.FanBonk, 0.95, 0.85)
				spawnFloatingRewardPopup(
					body.Position,
					"🧱 НЕ ХВАТИЛО СКОРОСТИ!",
					"Жми ПРОБЕЛ (Рывок) перед стеной!",
					Color3.fromRGB(255, 115, 85)
				)
				flightEvent:FireClient(player, "Impact", {
					Kind = "WallBonk",
					ComboMultiplier = flight.ComboMultiplier,
					TrickStreak = 0,
					HasShield = flight.HasShield,
					Shake = 0.9,
				})
			end
		end
	end)

	flightEvent:FireClient(player, "Started", {
		FlightId = flightId,
		Model = gooberModel,
		IsPerfect = isPerfect,
		PerfectMultiplier = perfectMultiplier,
		ChargePercent = chargePercent,
		DashCooldown = effectiveDashCooldown,
		HasShield = flight.HasShield,
		GooberData = gooberData,
	})

	if isPerfect then
		DataManager.Notify(player, "🔥 PERFECT YEET! Множитель награды x3!", "rare")
	end

	-- Цикл полёта: магнит монет + ограничение боковой скорости + проверка приземления
	task.spawn(function()
		local slowTicks = 0
		while not flight.Finished do
			task.wait(0.18)
			if flight.Finished then
				break
			end
			if not body or not body.Parent or not player:IsDescendantOf(Players) then
				finishFlight(flight, flightEvent)
				break
			end

			local vel = body.AssemblyLinearVelocity
			flight.RecentSpeed = vel.Magnitude

			-- Мягко ограничиваем боковую скорость, чтобы Губер не улетал за борта при долгом удержании A/D
			if math.abs(vel.X) > 92 then
				body.AssemblyLinearVelocity = Vector3.new(math.clamp(vel.X, -92, 92), vel.Y, vel.Z)
			end

			local pos = body.Position

			-- Магнит парящих монет (радиус зависит от формы Пончика и Выпученных глаз!)
			local magR = flight.Stats.MagnetRadius
			for _, coin in ipairs(FloatingCoinsCache) do
				if coin.Parent and not coin:GetAttribute("Collected") then
					if (coin.Position - pos).Magnitude <= magR then
						collectCoinForFlight(flight, coin, flightEvent)
					end
				end
			end

			if pos.Y < -25 then
				body.CFrame = CFrame.new(math.clamp(pos.X, -65, 65), 14, math.clamp(pos.Z, -2740, -1270))
				body.AssemblyLinearVelocity = Vector3.zero
				finishFlight(flight, flightEvent)
				break
			end

			local elapsed = os.clock() - flight.StartTime
			if elapsed >= 1.8 then
				if flight.RecentSpeed < 4.0 then
					slowTicks += 1
				else
					slowTicks = 0
				end

				if slowTicks >= 4 or elapsed >= MAX_FLIGHT_DURATION or pos.Z <= -2745 then
					finishFlight(flight, flightEvent)
					break
				end
			end
		end
	end)
end

-- Установка направления руления A/D (-1 = влево, 0 = прямо, +1 = вправо)
function LaunchService.HandleAirSteer(player: Player, rawDir: any)
	local flight = ActiveFlights[player]
	if not flight or flight.Finished then
		return
	end
	local dir = math.clamp(tonumber(rawDir) or 0, -1, 1)
	flight.SteerInput = dir
	updateSteerForceOnBody(flight)
end

-- Кнопка «Рывок / Ускорение» (Space / клик / мобильная кнопка) с откатом
function LaunchService.HandleAirDash(player: Player, flightEvent: RemoteEvent)
	local flight = ActiveFlights[player]
	if not flight or flight.Finished then
		return
	end

	local now = os.clock()
	if now < flight.NextDashAvailableAt then
		return
	end

	local body = flight.Body
	if not body or not body.Parent then
		return
	end

	local profile = DataManager.GetProfile(player)
	local vipPowerMult = (profile and profile.OwnedPasses.JetpackSteering) and 1.45 or 1.0
	local vipCooldownMult = (profile and profile.OwnedPasses.JetpackSteering) and 0.65 or 1.0
	local cooldown = math.max(0.85, flight.Stats.DashCooldown * vipCooldownMult)

	flight.LastDashTime = now
	flight.NextDashAvailableAt = now + cooldown

	local mass = body.AssemblyMass
	local power = flight.Stats.DashPowerMult * vipPowerMult
	local steerBiasX = flight.SteerInput * 36.0
	body:ApplyImpulse(Vector3.new(steerBiasX * mass, 34 * power * mass, -112 * power * mass))
	body:ApplyAngularImpulse(Vector3.new(-35 * mass, flight.SteerInput * 25 * mass, 0))
	flight.RecentSpeed = body.AssemblyLinearVelocity.Magnitude

	play3DSound(body, GooberConfig.Sounds.DashWhoosh, 1.0, 1.08)

	spawnFloatingRewardPopup(
		body.Position,
		"🚀 РЫВОК!",
		string.format("СКОРОСТЬ %d!", math.floor(flight.RecentSpeed)),
		Color3.fromRGB(255, 165, 50)
	)

	flightEvent:FireClient(player, "DashUsed", {
		Cooldown = cooldown,
		Shake = 0.55,
	})
end

function LaunchService.HandleLandingDecision(player: Player, choice: any, preferredSlot: any, flightEvent: RemoteEvent)
	local pending = PendingLandings[player]
	if not pending then
		flightEvent:FireClient(player, "ResetCamera", {})
		return
	end

	PendingLandings[player] = nil
	cleanupPendingModel(pending)

	if choice == "PlaceOnBase" then
		local slotNum = tonumber(preferredSlot)
		BaseService.PlaceGooberOnPedestal(player, pending.GooberData, slotNum)
	else
		DataManager.AddCoins(player, pending.RewardCoins, false)
		DataManager.Notify(
			player,
			string.format("💰 +%d 🪙 за полёт на %d м! (Макс. серия трюков: %d)", pending.RewardCoins, pending.Distance, pending.BestTrickStreak),
			"success"
		)
	end

	flightEvent:FireClient(player, "ResetCamera", {})
end

local function handleTeleport(player: Player, destination: any)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	if destination == "Base" then
		local basePos = BaseService.GetPlayerPlotPosition(player)
		if basePos then
			rootPart.CFrame = CFrame.new(basePos)
			return
		end
	end

	rootPart.CFrame = CFrame.new(0, 264, -18)
end

function LaunchService.Init()
	if initialized then
		return
	end
	initialized = true

	-- Кэшируем парящие монеты один раз при старте для быстрого магнита без перебора Workspace
	local map = MapGenerator.EnsureMap()
	local track = map:FindFirstChild("BoostersAndRings")
	if track then
		for _, child in ipairs(track:GetChildren()) do
			if child:IsA("BasePart") and child:GetAttribute("IsFloatingCoin") then
				table.insert(FloatingCoinsCache, child)
			end
		end
	end

	local remotes = ReplicatedStorage:WaitForChild(RemoteNames.FolderName)
	local launchRemote = remotes:WaitForChild(RemoteNames.LaunchGoober) :: RemoteEvent
	local steerRemote = remotes:WaitForChild(RemoteNames.AirSteer) :: RemoteEvent
	local dashRemote = remotes:WaitForChild(RemoteNames.AirDash) :: RemoteEvent
	local decisionRemote = remotes:WaitForChild(RemoteNames.LandingDecision) :: RemoteEvent
	local teleportRemote = remotes:WaitForChild(RemoteNames.TeleportRequest) :: RemoteEvent
	local flightEvent = remotes:WaitForChild(RemoteNames.FlightEvent) :: RemoteEvent

	launchRemote.OnServerEvent:Connect(function(player: Player, chargePercent: any)
		LaunchService.HandleLaunch(player, chargePercent, flightEvent)
	end)

	steerRemote.OnServerEvent:Connect(function(player: Player, steerDir: any)
		LaunchService.HandleAirSteer(player, steerDir)
	end)

	dashRemote.OnServerEvent:Connect(function(player: Player)
		LaunchService.HandleAirDash(player, flightEvent)
	end)

	decisionRemote.OnServerEvent:Connect(function(player: Player, choice: any, preferredSlot: any)
		LaunchService.HandleLandingDecision(player, choice, preferredSlot, flightEvent)
	end)

	teleportRemote.OnServerEvent:Connect(function(player: Player, destination: any)
		handleTeleport(player, destination)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local active = ActiveFlights[player]
		if active then
			active.Finished = true
			if active.TouchConnection then
				active.TouchConnection:Disconnect()
			end
			if active.Model and active.Model.Parent then
				active.Model:Destroy()
			end
			ActiveFlights[player] = nil
		end
		if PendingLandings[player] then
			resolvePendingAutomatically(player)
		end
	end)
end

return LaunchService
