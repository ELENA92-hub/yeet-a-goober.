--!strict
--[[
	LaunchService.lua
	Серверная физика пинка, полёта, комбо-множителей и приземления Губера:
	- Проверка зелёной зоны 85–95% -> PERFECT YEET (x3).
	- Применение импульса (ApplyImpulse) с учётом уровня Ботинка, заряда, массы и мутации.
	- Обработка касаний батутов и колец (рост комбо x1.5 + всплывающая цифра награды над Губером).
	- Пробивание преград мутацией «Тяжёлая».
	- Подруливание в воздухе для владельцев Game Pass «Jetpack Steering».
	- Выбор после приземления: забрать монеты ИЛИ поставить Губера на пьедестал базы.
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
	Model: Model,
	Body: BasePart,
	PerfectMultiplier: number,
	ComboMultiplier: number,
	StartTime: number,
	LastSteerTime: number,
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
	Model: Model?,
}

local LaunchService = {}

local ActiveFlights: { [Player]: ActiveFlight } = {}
local PendingLandings: { [Player]: PendingLanding } = {}
local initialized = false

local MAX_FLIGHT_DURATION = 22.0
local MAX_COMBO_MULTIPLIER = 150.0
local STEER_COOLDOWN = 0.35

local function play3DSound(parent: Instance, soundId: string, volume: number?, playbackSpeed: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.8
	sound.PlaybackSpeed = playbackSpeed or 1.0
	sound.RollOffMaxDistance = 260
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- Всплывающая цифра текущей награды и комбо прямо над летящим Губером
local function spawnFloatingRewardPopup(worldPos: Vector3, headline: string, rewardAmount: number, color: Color3)
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
	gui.Size = UDim2.fromOffset(240, 74)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 900
	gui.Parent = anchor

	local topLabel = Instance.new("TextLabel")
	topLabel.Size = UDim2.fromScale(1, 0.48)
	topLabel.BackgroundTransparency = 1
	topLabel.Font = Enum.Font.GothamBlack
	topLabel.TextScaled = true
	topLabel.TextColor3 = color
	topLabel.TextStrokeTransparency = 0.1
	topLabel.Text = headline
	topLabel.Parent = gui

	local coinLabel = Instance.new("TextLabel")
	coinLabel.Position = UDim2.fromScale(0, 0.48)
	coinLabel.Size = UDim2.fromScale(1, 0.52)
	coinLabel.BackgroundTransparency = 1
	coinLabel.Font = Enum.Font.GothamBlack
	coinLabel.TextScaled = true
	coinLabel.TextColor3 = Color3.fromRGB(255, 225, 65)
	coinLabel.TextStrokeTransparency = 0.1
	coinLabel.Text = string.format("+%d 🪙", rewardAmount)
	coinLabel.Parent = gui

	local riseTween = TweenService:Create(
		anchor,
		TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = anchor.Position + Vector3.new(0, 11, 0) }
	)
	riseTween:Play()
	Debris:AddItem(anchor, 1.2)
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

local function temporarilyBreakObstacle(obstaclePart: BasePart)
	if obstaclePart:GetAttribute("Broken") then
		return
	end
	obstaclePart:SetAttribute("Broken", true)
	local originalTransparency = obstaclePart.Transparency
	local originalColor = obstaclePart.Color

	obstaclePart.CanCollide = false
	obstaclePart.Transparency = 0.72
	obstaclePart.Color = Color3.fromRGB(255, 110, 55)

	task.delay(6.0, function()
		if obstaclePart and obstaclePart.Parent then
			obstaclePart.CanCollide = true
			obstaclePart.Transparency = originalTransparency
			obstaclePart.Color = originalColor
			obstaclePart:SetAttribute("Broken", nil)
		end
	end)
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
		flight.ComboMultiplier
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
		rewardCoins,
		Color3.fromRGB(110, 255, 150)
	)

	PendingLandings[player] = {
		GooberData = flight.GooberData,
		RewardCoins = rewardCoins,
		PassiveIncome = passiveIncome,
		Distance = distance,
		ComboMultiplier = flight.ComboMultiplier,
		PerfectMultiplier = flight.PerfectMultiplier,
		Model = flight.Model,
	}

	flightEvent:FireClient(player, "Landed", {
		GooberData = flight.GooberData,
		RewardCoins = rewardCoins,
		PassiveIncome = passiveIncome,
		Distance = distance,
		ComboMultiplier = flight.ComboMultiplier,
		PerfectMultiplier = flight.PerfectMultiplier,
	})
end

function LaunchService.HandleLaunch(player: Player, rawCharge: any, flightEvent: RemoteEvent)
	if ActiveFlights[player] then
		return
	end

	-- Если с прошлого броска окно не было закрыто, автоматически зачисляем прошлые монеты
	if PendingLandings[player] then
		resolvePendingAutomatically(player)
	end

	local profile = DataManager.GetProfile(player)
	local runtime = DataManager.GetRuntime(player)
	if not profile or not runtime then
		return
	end

	if not runtime.HeldGoober then
		DataManager.Notify(player, "Сначала вырасти и возьми Губера в руки!", "warn")
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	-- Проверяем, что игрок стоит у края обрыва на вершине горы
	if rootPart.Position.Y < 245 or rootPart.Position.Z > -22 then
		DataManager.Notify(player, "Подойди к жёлтой зоне у края обрыва, чтобы пнуть Губера!", "warn")
		return
	end

	local chargePercent = math.clamp(tonumber(rawCharge) or 50, 1, 100)
	local isPerfect = chargePercent >= 85 and chargePercent <= 95
	local perfectMultiplier = isPerfect and 3 or 1

	local gooberData = IncubatorService.ConsumeHeldGoober(player)
	if not gooberData then
		return
	end

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

	local radius = body.Size.X * 0.5
	local spawnX = math.clamp(rootPart.Position.X, -42, 42)
	local spawnPos = Vector3.new(spawnX, 262.5 + radius, MapGenerator.CLIFF_EDGE_Z - radius - 2.2)
	gooberModel:PivotTo(CFrame.new(spawnPos))

	local activeFolder = workspace:FindFirstChild("ActiveGoobers") or workspace
	gooberModel.Parent = activeFolder

	-- Передаём сетевое владение серверу, чтобы ApplyImpulse и .Touched работали мгновенно и честно
	pcall(function()
		body:SetNetworkOwner(nil)
	end)

	-- Применяем физику мутации (Elasticity / Density / VectorForce для «Воздушной»)
	GooberConfig.ApplyFlightPhysics(gooberModel, gooberData)

	-- Расчёт стартового физического импульса с учётом уровня Ботинка, заряда, массы и мутации
	local chargeFactor = 0.35 + 0.65 * (chargePercent / 100.0)
	local bootMult = GooberConfig.GetBootPowerMultiplier(profile.BootLevel)
	local perfectSpeedMult = isPerfect and 1.28 or 1.0
	local targetSpeed = 128.0 * chargeFactor * bootMult * mutation.LaunchSpeedMultiplier * perfectSpeedMult

	local launchDir = Vector3.new(0, 0.38, -1.0).Unit
	local mass = body.AssemblyMass
	body:ApplyImpulse(launchDir * (targetSpeed * mass))
	body:ApplyAngularImpulse(Vector3.new(-mass * 18, mass * 4, 0))

	-- Звук удара (обычный или мемный из Game Pass)
	local useMemeSounds = profile.OwnedPasses.MemeSoundPack == true
	play3DSound(
		body,
		useMemeSounds and GooberConfig.Sounds.MemeKick or GooberConfig.Sounds.StandardKick,
		1.0,
		isPerfect and 1.15 or 1.0
	)

	local flight: ActiveFlight = {
		Player = player,
		GooberData = gooberData,
		Model = gooberModel,
		Body = body,
		PerfectMultiplier = perfectMultiplier,
		ComboMultiplier = 1.0,
		StartTime = os.clock(),
		LastSteerTime = 0,
		Finished = false,
		TouchConnection = nil,
	}
	ActiveFlights[player] = flight

	-- Обработчик касаний батутов, колец-множителей и разрушаемых препятствий
	local hitCooldowns: { [Instance]: number } = {}

	flight.TouchConnection = body.Touched:Connect(function(hit: BasePart)
		if flight.Finished or not hit or not hit.Parent then
			return
		end

		local now = os.clock()
		if hitCooldowns[hit] and (now - hitCooldowns[hit]) < 0.85 then
			return
		end

		if hit:GetAttribute("IsTrampoline") then
			hitCooldowns[hit] = now
			flight.ComboMultiplier = math.min(flight.ComboMultiplier * 1.5, MAX_COMBO_MULTIPLIER)

			-- Подбрасываем вверх и вперёд вдоль склона
			local currentMass = body.AssemblyMass
			body:ApplyImpulse(Vector3.new(0, 78 * currentMass, -96 * currentMass))

			play3DSound(
				body,
				useMemeSounds and GooberConfig.Sounds.MemeBounce or GooberConfig.Sounds.StandardBounce,
				0.9,
				1.05
			)

			local dist = getDistanceStuds(body.Position)
			local liveReward = GooberConfig.CalculateFlightReward(
				flight.GooberData,
				dist,
				flight.PerfectMultiplier,
				flight.ComboMultiplier
			)

			spawnFloatingRewardPopup(
				body.Position,
				string.format("⚡ БАТУТ! КОМБО x%.2f", flight.ComboMultiplier),
				liveReward,
				Color3.fromRGB(255, 105, 235)
			)

			flightEvent:FireClient(player, "ComboUpdate", {
				ComboMultiplier = flight.ComboMultiplier,
				Distance = dist,
				LiveReward = liveReward,
				Source = "Trampoline",
			})
		elseif hit:GetAttribute("IsMultiplierRing") then
			hitCooldowns[hit] = now
			flight.ComboMultiplier = math.min(flight.ComboMultiplier * 1.5, MAX_COMBO_MULTIPLIER)

			local currentMass = body.AssemblyMass
			body:ApplyImpulse(Vector3.new(0, 24 * currentMass, -88 * currentMass))

			play3DSound(body, GooberConfig.Sounds.RingChime, 1.0, 1.1)

			local dist = getDistanceStuds(body.Position)
			local liveReward = GooberConfig.CalculateFlightReward(
				flight.GooberData,
				dist,
				flight.PerfectMultiplier,
				flight.ComboMultiplier
			)

			spawnFloatingRewardPopup(
				body.Position,
				string.format("⭕ КОЛЬЦО! КОМБО x%.2f", flight.ComboMultiplier),
				liveReward,
				Color3.fromRGB(255, 225, 65)
			)

			flightEvent:FireClient(player, "ComboUpdate", {
				ComboMultiplier = flight.ComboMultiplier,
				Distance = dist,
				LiveReward = liveReward,
				Source = "Ring",
			})
		elseif hit:GetAttribute("IsObstacle") and mutation.BreaksObstacles then
			hitCooldowns[hit] = now
			temporarilyBreakObstacle(hit)
			flight.ComboMultiplier = math.min(flight.ComboMultiplier * 1.25, MAX_COMBO_MULTIPLIER)

			-- Восстанавливаем пробивной импульс вперёд
			local currentMass = body.AssemblyMass
			body:ApplyImpulse(Vector3.new(0, 18 * currentMass, -65 * currentMass))

			local dist = getDistanceStuds(body.Position)
			local liveReward = GooberConfig.CalculateFlightReward(
				flight.GooberData,
				dist,
				flight.PerfectMultiplier,
				flight.ComboMultiplier
			)

			spawnFloatingRewardPopup(
				body.Position,
				string.format("💥 ПРОБИТО! x%.2f", flight.ComboMultiplier),
				liveReward,
				Color3.fromRGB(255, 140, 55)
			)

			flightEvent:FireClient(player, "ComboUpdate", {
				ComboMultiplier = flight.ComboMultiplier,
				Distance = dist,
				LiveReward = liveReward,
				Source = "Smash",
			})
		end
	end)

	-- Сообщаем клиенту о старте полёта для плавной камеры и HUD
	flightEvent:FireClient(player, "Started", {
		FlightId = flightId,
		Model = gooberModel,
		IsPerfect = isPerfect,
		PerfectMultiplier = perfectMultiplier,
		ChargePercent = chargePercent,
		GooberData = gooberData,
	})

	if isPerfect then
		DataManager.Notify(player, "🔥 PERFECT YEET! Множитель награды x3!", "rare")
	end

	-- Лёгкое отслеживание остановки Губера (проверка раз в 0.25 сек, без нагрузки на Heartbeat)
	task.spawn(function()
		local slowTicks = 0
		while not flight.Finished do
			task.wait(0.25)
			if flight.Finished then
				break
			end
			if not body or not body.Parent or not player:IsDescendantOf(Players) then
				finishFlight(flight, flightEvent)
				break
			end

			local elapsed = os.clock() - flight.StartTime
			local speed = body.AssemblyLinearVelocity.Magnitude
			local pos = body.Position

			-- Спасение, если каким-то чудом Губер провалился ниже карты
			if pos.Y < -25 then
				body.CFrame = CFrame.new(math.clamp(pos.X, -60, 60), 14, math.clamp(pos.Z, -2580, -1210))
				body.AssemblyLinearVelocity = Vector3.zero
				finishFlight(flight, flightEvent)
				break
			end

			if elapsed >= 1.8 then
				if speed < 3.8 then
					slowTicks += 1
				else
					slowTicks = 0
				end

				if slowTicks >= 3 or elapsed >= MAX_FLIGHT_DURATION or pos.Z <= -2585 then
					finishFlight(flight, flightEvent)
					break
				end
			end
		end
	end)
end

function LaunchService.HandleJetpackSteer(player: Player, direction: any)
	local flight = ActiveFlights[player]
	if not flight or flight.Finished then
		return
	end

	local profile = DataManager.GetProfile(player)
	if not profile or not profile.OwnedPasses.JetpackSteering then
		return
	end

	local now = os.clock()
	if (now - flight.LastSteerTime) < STEER_COOLDOWN then
		return
	end
	flight.LastSteerTime = now

	local body = flight.Body
	if not body or not body.Parent then
		return
	end

	local mass = body.AssemblyMass
	if direction == "Left" then
		body:ApplyImpulse(Vector3.new(-42 * mass, 8 * mass, -10 * mass))
	elseif direction == "Right" then
		body:ApplyImpulse(Vector3.new(42 * mass, 8 * mass, -10 * mass))
	elseif direction == "Boost" then
		body:ApplyImpulse(Vector3.new(0, 26 * mass, -58 * mass))
	end
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
			string.format("💰 Получено +%d монет за бросок на %d м!", pending.RewardCoins, pending.Distance),
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

	-- Телепорт к вершине горы (между инкубатором и обрывом)
	rootPart.CFrame = CFrame.new(0, 264, -18)
end

function LaunchService.Init()
	if initialized then
		return
	end
	initialized = true

	local remotes = ReplicatedStorage:WaitForChild(RemoteNames.FolderName)
	local launchRemote = remotes:WaitForChild(RemoteNames.LaunchGoober) :: RemoteEvent
	local steerRemote = remotes:WaitForChild(RemoteNames.JetpackSteer) :: RemoteEvent
	local decisionRemote = remotes:WaitForChild(RemoteNames.LandingDecision) :: RemoteEvent
	local teleportRemote = remotes:WaitForChild(RemoteNames.TeleportRequest) :: RemoteEvent
	local flightEvent = remotes:WaitForChild(RemoteNames.FlightEvent) :: RemoteEvent

	launchRemote.OnServerEvent:Connect(function(player: Player, chargePercent: any)
		LaunchService.HandleLaunch(player, chargePercent, flightEvent)
	end)

	steerRemote.OnServerEvent:Connect(function(player: Player, direction: any)
		LaunchService.HandleJetpackSteer(player, direction)
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
