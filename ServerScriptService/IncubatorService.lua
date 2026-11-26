--!strict
--[[
	IncubatorService.lua
	Логика инкубатора:
	- Нажатие кнопки «Вырастить» (или ProximityPrompt у капсулы) запускает таймер 5 секунд.
	- Через 5 секунд появляется Губер со случайным видом, весом (0.5–1000 кг) и мутацией.
	- Игрок может взять его в руки (модель крепится к персонажу через WeldConstraint).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))

export type GooberData = GooberConfig.GooberData

local IncubatorService = {}

local HeldModels: { [Player]: Model } = {}
local PodPreviewModels: { [Player]: Model } = {}
local initialized = false

local function destroyModelSafe(tbl: { [Player]: Model }, player: Player)
	local existing = tbl[player]
	if existing then
		tbl[player] = nil
		if existing.Parent then
			existing:Destroy()
		end
	end
end

local function makeModelNonPhysicalForCarry(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
		end
	end
end

function IncubatorService.ClearHeldVisual(player: Player)
	destroyModelSafe(HeldModels, player)
end

function IncubatorService.AttachHeldVisual(player: Player, gooberData: GooberData)
	destroyModelSafe(HeldModels, player)

	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local model = GooberConfig.BuildGooberModel(gooberData)
	model.Name = "HeldGooberModel"
	makeModelNonPhysicalForCarry(model)

	local body = model.PrimaryPart
	if not body then
		model:Destroy()
		return
	end

	local radius = body.Size.X * 0.5
	-- Размещаем Губера перед руками и чуть выше головы при большом размере, чтобы не закрывал обзор
	local carryOffset = CFrame.new(0, math.max(1.2, radius * 0.65), -(radius * 0.65 + 2.0))
	model:PivotTo(rootPart.CFrame * carryOffset)
	model.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = rootPart
	weld.Part1 = body
	weld.Parent = body

	HeldModels[player] = model
end

local function spawnPodPreview(player: Player, gooberData: GooberData)
	destroyModelSafe(PodPreviewModels, player)

	local map = workspace:FindFirstChild(MapGenerator.MAP_NAME)
	local summit = map and map:FindFirstChild("Summit")
	local incZone = summit and summit:FindFirstChild("IncubatorZone")
	local incBase = incZone and incZone:FindFirstChild("IncubatorBase") :: BasePart?
	if not incBase then
		return
	end

	-- Компактное превью внутри капсулы инкубатора (ограничиваем визуальный диаметр в капсуле до 7 стадов)
	local rawDiameter = GooberConfig.GetDiameterFromWeight(gooberData.Weight)
	local podDiameter = math.min(rawDiameter, 7.2)
	local preview = GooberConfig.BuildGooberModel(gooberData, { ScaleOverride = podDiameter })
	preview.Name = "IncubatedPreview_" .. player.Name

	for _, desc in ipairs(preview:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
		end
	end

	local spawnPos = incBase.Position + Vector3.new(0, 2.2 + podDiameter * 0.5, 0)
	preview:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, math.rad(35), 0))
	preview.Parent = incZone

	if preview.PrimaryPart then
		local grabPrompt = Instance.new("ProximityPrompt")
		grabPrompt.Name = "PickupGooberPrompt"
		grabPrompt.ActionText = "Взять в руки"
		grabPrompt.ObjectText = string.format(
			"%s (%.1f кг)",
			(GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey).Name,
			gooberData.Weight
		)
		grabPrompt.MaxActivationDistance = 20
		grabPrompt.HoldDuration = 0
		grabPrompt.RequiresLineOfSight = false
		grabPrompt.Parent = preview.PrimaryPart

		grabPrompt.Triggered:Connect(function(triggerPlayer: Player)
			if triggerPlayer == player then
				IncubatorService.PickupReadyGoober(player)
			else
				DataManager.Notify(triggerPlayer, "Этот Губер выращен другим игроком! Нажми «Вырастить» для своего.", "warn")
			end
		end)
	end

	PodPreviewModels[player] = preview
end

function IncubatorService.PickupReadyGoober(player: Player): boolean
	local runtime = DataManager.GetRuntime(player)
	if not runtime then
		return false
	end

	local ready = runtime.ReadyGoober
	if not ready then
		DataManager.Notify(player, "В инкубаторе пока нет готового Губера! Нажми «Вырастить».", "warn")
		return false
	end

	-- Если в руках уже был другой Губер — убираем его в инвентарь
	if runtime.HeldGoober then
		DataManager.AddGooberToInventory(player, runtime.HeldGoober)
	end

	runtime.ReadyGoober = nil
	runtime.HeldGoober = ready
	destroyModelSafe(PodPreviewModels, player)

	IncubatorService.AttachHeldVisual(player, ready)
	DataManager.SyncToClient(player)

	local species = GooberConfig.Species[ready.SpeciesId] or GooberConfig.Species.Slimey
	local mutation = GooberConfig.Mutations[ready.MutationId] or GooberConfig.Mutations.Normal
	DataManager.Notify(
		player,
		string.format("🤲 В руках: %s (%.1f кг, %s)! Иди к краю обрыва!", species.Name, ready.Weight, mutation.Name),
		"success"
	)
	return true
end

function IncubatorService.EquipGooberDirect(player: Player, gooberData: GooberData)
	local runtime = DataManager.GetRuntime(player)
	if not runtime then
		return
	end
	if runtime.HeldGoober then
		DataManager.AddGooberToInventory(player, runtime.HeldGoober)
	end
	runtime.HeldGoober = gooberData
	IncubatorService.AttachHeldVisual(player, gooberData)
	DataManager.SyncToClient(player)
end

function IncubatorService.EquipFromInventory(player: Player, gooberId: string): boolean
	if type(gooberId) ~= "string" or gooberId == "" then
		return false
	end
	local runtime = DataManager.GetRuntime(player)
	if not runtime then
		return false
	end

	local extracted = DataManager.RemoveGooberFromInventory(player, gooberId)
	if not extracted then
		DataManager.Notify(player, "Губер не найден в инвентаре.", "warn")
		return false
	end

	if runtime.HeldGoober then
		DataManager.AddGooberToInventory(player, runtime.HeldGoober)
	end

	runtime.HeldGoober = extracted
	IncubatorService.AttachHeldVisual(player, extracted)
	DataManager.SyncToClient(player)

	local species = GooberConfig.Species[extracted.SpeciesId] or GooberConfig.Species.Slimey
	DataManager.Notify(player, string.format("🤲 Экипирован %s (%.1f кг)!", species.Name, extracted.Weight), "info")
	return true
end

function IncubatorService.StartIncubation(player: Player)
	local runtime = DataManager.GetRuntime(player)
	if not runtime then
		return
	end

	-- Если уже лежит готовый Губер в капсуле — сразу берём его в руки
	if runtime.ReadyGoober then
		IncubatorService.PickupReadyGoober(player)
		return
	end

	if runtime.IsIncubating then
		local left = math.max(0.1, runtime.IncubateEndTime - os.clock())
		DataManager.Notify(player, string.format("⏳ Инкубатор уже работает! Осталось %.1f сек.", left), "info")
		return
	end

	runtime.IsIncubating = true
	runtime.IncubateEndTime = os.clock() + GooberConfig.INCUBATION_TIME
	DataManager.SyncToClient(player)
	DataManager.Notify(player, "🥚 Выращиваем Губера... Подожди 5 секунд!", "info")

	task.delay(GooberConfig.INCUBATION_TIME, function()
		if not player:IsDescendantOf(Players) then
			return
		end
		local currentRuntime = DataManager.GetRuntime(player)
		if not currentRuntime or not currentRuntime.IsIncubating then
			return
		end

		local grown = GooberConfig.RollRandomGoober()
		currentRuntime.IsIncubating = false
		currentRuntime.IncubateEndTime = 0
		currentRuntime.ReadyGoober = grown

		spawnPodPreview(player, grown)
		DataManager.SyncToClient(player)

		local species = GooberConfig.Species[grown.SpeciesId] or GooberConfig.Species.Slimey
		local mutation = GooberConfig.Mutations[grown.MutationId] or GooberConfig.Mutations.Normal
		local prefix = species.IsRareGuest and "🌟 РЕДКИЙ ГОСТЬ! " or "✅ Готово! "
		DataManager.Notify(
			player,
			string.format("%s%s • %.1f кг • Мутация: %s! Возьми его в руки!", prefix, species.Name, grown.Weight, mutation.Name),
			species.IsRareGuest and "rare" or "success"
		)
	end)
end

-- Забирает Губера из рук игрока в момент пинка с обрыва
function IncubatorService.ConsumeHeldGoober(player: Player): GooberData?
	local runtime = DataManager.GetRuntime(player)
	if not runtime or not runtime.HeldGoober then
		return nil
	end
	local held = runtime.HeldGoober
	runtime.HeldGoober = nil
	IncubatorService.ClearHeldVisual(player)
	DataManager.SyncToClient(player)
	return held
end

local function setupPlayerCharacterHooks(player: Player)
	player.CharacterAdded:Connect(function(_character: Model)
		task.wait(0.25)
		if not player:IsDescendantOf(Players) then
			return
		end
		local runtime = DataManager.GetRuntime(player)
		if runtime and runtime.HeldGoober then
			IncubatorService.AttachHeldVisual(player, runtime.HeldGoober)
		end
	end)
end

function IncubatorService.Init()
	if initialized then
		return
	end
	initialized = true

	local remotes = ReplicatedStorage:WaitForChild(RemoteNames.FolderName)
	local reqIncubate = remotes:WaitForChild(RemoteNames.RequestIncubate) :: RemoteEvent
	local reqPickup = remotes:WaitForChild(RemoteNames.PickupIncubatedGoober) :: RemoteEvent
	local reqEquip = remotes:WaitForChild(RemoteNames.EquipInventoryGoober) :: RemoteEvent

	reqIncubate.OnServerEvent:Connect(function(player: Player)
		IncubatorService.StartIncubation(player)
	end)

	reqPickup.OnServerEvent:Connect(function(player: Player)
		IncubatorService.PickupReadyGoober(player)
	end)

	reqEquip.OnServerEvent:Connect(function(player: Player, gooberId: any)
		if type(gooberId) == "string" then
			IncubatorService.EquipFromInventory(player, gooberId)
		end
	end)

	-- Подключаем ProximityPrompt капсулы инкубатора на карте
	local map = MapGenerator.EnsureMap()
	local summit = map:FindFirstChild("Summit")
	local incZone = summit and summit:FindFirstChild("IncubatorZone")
	local incBase = incZone and incZone:FindFirstChild("IncubatorBase")
	local prompt = incBase and incBase:FindFirstChild("IncubatorPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Triggered:Connect(function(player: Player)
			local runtime = DataManager.GetRuntime(player)
			if runtime and runtime.ReadyGoober then
				IncubatorService.PickupReadyGoober(player)
			else
				IncubatorService.StartIncubation(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(setupPlayerCharacterHooks)
	for _, p in ipairs(Players:GetPlayers()) do
		setupPlayerCharacterHooks(p)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		destroyModelSafe(HeldModels, player)
		destroyModelSafe(PodPreviewModels, player)
	end)
end

return IncubatorService
