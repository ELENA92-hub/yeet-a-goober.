--!strict
--[[
	IncubatorService.lua
	Мастерская и Инкубатор Губеров:
	- Принимает выбранные игроком части из «Мастерской Губера» (форма тела, глаза, рот, аксессуар).
	- Выращивает уникального 3D-чудика со случайным видом, весом (0.5–1000 кг) и мутацией.
	- Позволяет взять собранного Губера в руки со всеми прикреплёнными 3D-деталями.
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

	local radius = math.max(body.Size.X, body.Size.Y, body.Size.Z) * 0.5
	local carryOffset = CFrame.new(0, math.max(1.2, radius * 0.65), -(radius * 0.65 + 2.2))
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

	local rawDiameter = GooberConfig.GetDiameterFromWeight(gooberData.Weight)
	local podDiameter = math.min(rawDiameter, 6.8)
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
	preview:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, math.rad(25), 0))
	preview.Parent = incZone

	if preview.PrimaryPart then
		local grabPrompt = Instance.new("ProximityPrompt")
		grabPrompt.Name = "PickupGooberPrompt"
		grabPrompt.ActionText = "Взять чудика в руки"
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
				DataManager.Notify(triggerPlayer, "Этот чудик собран другим игроком! Собери своего в Мастерской.", "warn")
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
		DataManager.Notify(player, "В капсуле нет готового Губера! Открой Мастерскую и нажми «Вырастить».", "warn")
		return false
	end

	if runtime.HeldGoober then
		DataManager.AddGooberToInventory(player, runtime.HeldGoober)
	end

	runtime.ReadyGoober = nil
	runtime.HeldGoober = ready
	destroyModelSafe(PodPreviewModels, player)

	IncubatorService.AttachHeldVisual(player, ready)
	DataManager.SyncToClient(player)

	local species = GooberConfig.Species[ready.SpeciesId] or GooberConfig.Species.Slimey
	local shape = GooberConfig.BodyShapes[ready.BodyShapeId] or GooberConfig.BodyShapes.Jelly
	local acc = GooberConfig.Accessories[ready.AccessoryId] or GooberConfig.Accessories.Propeller
	DataManager.Notify(
		player,
		string.format("🤲 В руках: %s [%s + %s] (%.1f кг)! Беги к обрыву!", species.Name, shape.Name, acc.Name, ready.Weight),
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
		DataManager.Notify(player, "Чудик не найден в рюкзаке.", "warn")
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

function IncubatorService.StartIncubation(player: Player, rawCustomBuild: any)
	local profile = DataManager.GetProfile(player)
	local runtime = DataManager.GetRuntime(player)
	if not profile or not runtime then
		return
	end

	if type(rawCustomBuild) == "table" then
		profile.WorkshopBuild = GooberConfig.SanitizeWorkshopBuild(rawCustomBuild)
		runtime.Dirty = true
	end

	if runtime.ReadyGoober then
		IncubatorService.PickupReadyGoober(player)
		return
	end

	if runtime.IsIncubating then
		local left = math.max(0.1, runtime.IncubateEndTime - os.clock())
		DataManager.Notify(player, string.format("⏳ Чудик уже собирается! Осталось %.1f сек.", left), "info")
		return
	end

	local chosenBuild = table.clone(profile.WorkshopBuild)
	runtime.IsIncubating = true
	runtime.IncubateEndTime = os.clock() + GooberConfig.INCUBATION_TIME
	DataManager.SyncToClient(player)

	local shapeInfo = GooberConfig.BodyShapes[chosenBuild.BodyShapeId] or GooberConfig.BodyShapes.Jelly
	local accInfo = GooberConfig.Accessories[chosenBuild.AccessoryId] or GooberConfig.Accessories.Propeller
	DataManager.Notify(
		player,
		string.format("🧬 Сборка чудика (%s + %s)... %.1f сек!", shapeInfo.Name, accInfo.Name, GooberConfig.INCUBATION_TIME),
		"info"
	)

	task.delay(GooberConfig.INCUBATION_TIME, function()
		if not player:IsDescendantOf(Players) then
			return
		end
		local currentRuntime = DataManager.GetRuntime(player)
		if not currentRuntime or not currentRuntime.IsIncubating then
			return
		end

		local grown = GooberConfig.RollRandomGoober(chosenBuild)
		currentRuntime.IsIncubating = false
		currentRuntime.IncubateEndTime = 0
		currentRuntime.ReadyGoober = grown

		spawnPodPreview(player, grown)
		DataManager.SyncToClient(player)

		local species = GooberConfig.Species[grown.SpeciesId] or GooberConfig.Species.Slimey
		local mutation = GooberConfig.Mutations[grown.MutationId] or GooberConfig.Mutations.Normal
		local prefix = species.IsRareGuest and "🌟 РЕДКИЙ ЧУДИК! " or "✅ СОБРАН! "
		DataManager.Notify(
			player,
			string.format("%s%s • %.1f кг • [%s]! Жми «Взять в руки»!", prefix, species.Name, grown.Weight, mutation.Name),
			species.IsRareGuest and "rare" or "success"
		)
	end)
end

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
	local reqPreset = remotes:WaitForChild(RemoteNames.UpdateWorkshopPreset) :: RemoteEvent
	local reqPickup = remotes:WaitForChild(RemoteNames.PickupIncubatedGoober) :: RemoteEvent
	local reqEquip = remotes:WaitForChild(RemoteNames.EquipInventoryGoober) :: RemoteEvent

	reqIncubate.OnServerEvent:Connect(function(player: Player, customBuild: any)
		IncubatorService.StartIncubation(player, customBuild)
	end)

	reqPreset.OnServerEvent:Connect(function(player: Player, customBuild: any)
		DataManager.SetWorkshopBuild(player, customBuild)
	end)

	reqPickup.OnServerEvent:Connect(function(player: Player)
		IncubatorService.PickupReadyGoober(player)
	end)

	reqEquip.OnServerEvent:Connect(function(player: Player, gooberId: any)
		if type(gooberId) == "string" then
			IncubatorService.EquipFromInventory(player, gooberId)
		end
	end)

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
				IncubatorService.StartIncubation(player, nil)
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
