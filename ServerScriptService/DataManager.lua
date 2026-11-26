--!strict
--[[
	DataManager.lua
	Управление данными игрока: монеты, уровень Ботинка, инвентарь Губеров,
	пьедесталы базы и купленные Game Pass'ы с сохранением в DataStoreService через pcall.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))

export type GooberData = GooberConfig.GooberData

export type PlayerProfile = {
	Coins: number,
	BootLevel: number,
	BestDistance: number,
	Inventory: { GooberData },
	Pedestals: { [string]: GooberData? },
	OwnedPasses: {
		MemeSoundPack: boolean,
		JetpackSteering: boolean,
	},
}

export type SessionRuntime = {
	HeldGoober: GooberData?,
	IsIncubating: boolean,
	IncubateEndTime: number,
	ReadyGoober: GooberData?,
	Dirty: boolean,
}

local DataManager = {}

local DATASTORE_NAME = "YeetAGoober_Mutations_v1"
local AUTOSAVE_INTERVAL = 120

local playerStore: DataStore? = nil
local Profiles: { [Player]: PlayerProfile } = {}
local RuntimeStates: { [Player]: SessionRuntime } = {}
local OnProfileLoadedCallbacks: { (Player, PlayerProfile) -> () } = {}
local initialized = false

local function getDefaultProfile(): PlayerProfile
	return {
		Coins = 0,
		BootLevel = 1,
		BestDistance = 0,
		Inventory = {},
		Pedestals = {},
		OwnedPasses = {
			MemeSoundPack = false,
			JetpackSteering = false,
		},
	}
end

local function sanitizeGoober(raw: any): GooberData?
	if type(raw) ~= "table" then
		return nil
	end
	local speciesId = tostring(raw.SpeciesId or "Slimey")
	if not GooberConfig.Species[speciesId] then
		speciesId = "Slimey"
	end
	local mutationId = tostring(raw.MutationId or "Normal")
	if not GooberConfig.Mutations[mutationId] then
		mutationId = "Normal"
	end
	local weight = math.clamp(tonumber(raw.Weight) or 1.0, GooberConfig.MIN_WEIGHT, GooberConfig.MAX_WEIGHT)
	return {
		Id = tostring(raw.Id or tostring(os.clock())),
		SpeciesId = speciesId,
		Weight = math.floor(weight * 10 + 0.5) / 10,
		MutationId = mutationId,
		CreatedAt = tonumber(raw.CreatedAt) or os.time(),
	}
end

local function reconcileProfile(raw: any): PlayerProfile
	local profile = getDefaultProfile()
	if type(raw) ~= "table" then
		return profile
	end

	profile.Coins = math.max(0, math.floor(tonumber(raw.Coins) or 0))
	profile.BootLevel = math.max(1, math.floor(tonumber(raw.BootLevel) or 1))
	profile.BestDistance = math.max(0, math.floor(tonumber(raw.BestDistance) or 0))

	if type(raw.Inventory) == "table" then
		for _, item in ipairs(raw.Inventory) do
			if #profile.Inventory >= GooberConfig.MAX_INVENTORY_SIZE then
				break
			end
			local clean = sanitizeGoober(item)
			if clean then
				table.insert(profile.Inventory, clean)
			end
		end
	end

	if type(raw.Pedestals) == "table" then
		for slot = 1, GooberConfig.PEDESTAL_COUNT do
			local key = tostring(slot)
			local slotData = raw.Pedestals[key] or raw.Pedestals[slot]
			local clean = sanitizeGoober(slotData)
			if clean then
				profile.Pedestals[key] = clean
			end
		end
	end

	if type(raw.OwnedPasses) == "table" then
		profile.OwnedPasses.MemeSoundPack = raw.OwnedPasses.MemeSoundPack == true
		profile.OwnedPasses.JetpackSteering = raw.OwnedPasses.JetpackSteering == true
	end

	return profile
end

local function getRemotesFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(RemoteNames.FolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function updateLeaderstats(player: Player, profile: PlayerProfile)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end

	local coinsVal = ls:FindFirstChild("Coins") :: IntValue?
	if not coinsVal then
		local newCoins = Instance.new("IntValue")
		newCoins.Name = "Coins"
		newCoins.Parent = ls
		coinsVal = newCoins
	end
	if coinsVal then
		coinsVal.Value = profile.Coins
	end

	local bootVal = ls:FindFirstChild("Boot Lvl") :: IntValue?
	if not bootVal then
		local newBoot = Instance.new("IntValue")
		newBoot.Name = "Boot Lvl"
		newBoot.Parent = ls
		bootVal = newBoot
	end
	if bootVal then
		bootVal.Value = profile.BootLevel
	end
end

function DataManager.GetProfile(player: Player): PlayerProfile?
	return Profiles[player]
end

function DataManager.GetRuntime(player: Player): SessionRuntime?
	return RuntimeStates[player]
end

function DataManager.OnProfileLoaded(callback: (Player, PlayerProfile) -> ())
	table.insert(OnProfileLoadedCallbacks, callback)
	for player, profile in pairs(Profiles) do
		task.spawn(callback, player, profile)
	end
end

function DataManager.CalculateTotalPassiveIncome(player: Player): number
	local profile = Profiles[player]
	if not profile then
		return 0
	end
	local total = 0
	for slot = 1, GooberConfig.PEDESTAL_COUNT do
		local goober = profile.Pedestals[tostring(slot)]
		if goober then
			total += GooberConfig.CalculatePassiveIncome(goober)
		end
	end
	return total
end

function DataManager.SyncToClient(player: Player)
	local profile = Profiles[player]
	local runtime = RuntimeStates[player]
	if not profile or not runtime then
		return
	end

	updateLeaderstats(player, profile)

	local remotes = getRemotesFolder()
	if not remotes then
		return
	end
	local syncEvent = remotes:FindFirstChild(RemoteNames.StateSync)
	if syncEvent and syncEvent:IsA("RemoteEvent") then
		syncEvent:FireClient(player, {
			Coins = profile.Coins,
			BootLevel = profile.BootLevel,
			BestDistance = profile.BestDistance,
			Inventory = profile.Inventory,
			Pedestals = profile.Pedestals,
			OwnedPasses = profile.OwnedPasses,
			HeldGoober = runtime.HeldGoober,
			IsIncubating = runtime.IsIncubating,
			IncubateRemaining = runtime.IsIncubating and math.max(0, runtime.IncubateEndTime - os.clock()) or 0,
			ReadyGoober = runtime.ReadyGoober,
			PassiveIncome = DataManager.CalculateTotalPassiveIncome(player),
		})
	end
end

function DataManager.Notify(player: Player, message: string, kind: string?)
	local remotes = getRemotesFolder()
	if not remotes then
		return
	end
	local notifyEvent = remotes:FindFirstChild(RemoteNames.Notification)
	if notifyEvent and notifyEvent:IsA("RemoteEvent") then
		notifyEvent:FireClient(player, message, kind or "info")
	end
end

function DataManager.AddCoins(player: Player, amount: number, silentSync: boolean?)
	local profile = Profiles[player]
	local runtime = RuntimeStates[player]
	if not profile or not runtime then
		return
	end
	local delta = math.max(0, math.floor(amount))
	if delta == 0 then
		return
	end
	profile.Coins += delta
	runtime.Dirty = true
	if silentSync then
		updateLeaderstats(player, profile)
	else
		DataManager.SyncToClient(player)
	end
end

function DataManager.SpendCoins(player: Player, cost: number): boolean
	local profile = Profiles[player]
	local runtime = RuntimeStates[player]
	if not profile or not runtime then
		return false
	end
	local cleanCost = math.max(0, math.floor(cost))
	if profile.Coins < cleanCost then
		return false
	end
	profile.Coins -= cleanCost
	runtime.Dirty = true
	DataManager.SyncToClient(player)
	return true
end

function DataManager.AddGooberToInventory(player: Player, goober: GooberData): boolean
	local profile = Profiles[player]
	local runtime = RuntimeStates[player]
	if not profile or not runtime then
		return false
	end
	if #profile.Inventory >= GooberConfig.MAX_INVENTORY_SIZE then
		-- Удаляем самого старого Губера, если инвентарь переполнен
		table.remove(profile.Inventory, 1)
	end
	table.insert(profile.Inventory, goober)
	runtime.Dirty = true
	DataManager.SyncToClient(player)
	return true
end

function DataManager.RemoveGooberFromInventory(player: Player, gooberId: string): GooberData?
	local profile = Profiles[player]
	local runtime = RuntimeStates[player]
	if not profile or not runtime then
		return nil
	end
	for index, item in ipairs(profile.Inventory) do
		if item.Id == gooberId then
			table.remove(profile.Inventory, index)
			runtime.Dirty = true
			return item
		end
	end
	return nil
end

function DataManager.SavePlayer(player: Player)
	local profile = Profiles[player]
	local runtime = RuntimeStates[player]
	if not profile then
		return
	end

	if not playerStore then
		return
	end

	-- Копируем данные для записи; если в руках был Губер при выходе, сохраняем его в инвентарь
	local saveCopy = {
		Coins = profile.Coins,
		BootLevel = profile.BootLevel,
		BestDistance = profile.BestDistance,
		Inventory = table.clone(profile.Inventory),
		Pedestals = table.clone(profile.Pedestals),
		OwnedPasses = table.clone(profile.OwnedPasses),
	}

	if runtime and runtime.HeldGoober and #saveCopy.Inventory < GooberConfig.MAX_INVENTORY_SIZE then
		table.insert(saveCopy.Inventory, runtime.HeldGoober)
	end

	local key = "Player_" .. tostring(player.UserId)
	local ok, err = pcall(function()
		(playerStore :: DataStore):SetAsync(key, saveCopy)
	end)

	if ok then
		if runtime then
			runtime.Dirty = false
		end
	else
		warn(string.format("[DataManager] Ошибка сохранения для %s (%d): %s", player.Name, player.UserId, tostring(err)))
	end
end

local function loadPlayer(player: Player)
	local loadedRaw: any = nil

	if playerStore then
		local key = "Player_" .. tostring(player.UserId)
		local ok, result = pcall(function()
			return (playerStore :: DataStore):GetAsync(key)
		end)
		if ok then
			loadedRaw = result
		else
			warn(string.format("[DataManager] Не удалось загрузить DataStore для %s (работа в сессии): %s", player.Name, tostring(result)))
		end
	end

	if not player:IsDescendantOf(Players) then
		return
	end

	local profile = reconcileProfile(loadedRaw)
	Profiles[player] = profile
	RuntimeStates[player] = {
		HeldGoober = nil,
		IsIncubating = false,
		IncubateEndTime = 0,
		ReadyGoober = nil,
		Dirty = false,
	}

	updateLeaderstats(player, profile)
	DataManager.SyncToClient(player)

	for _, callback in ipairs(OnProfileLoadedCallbacks) do
		task.spawn(callback, player, profile)
	end
end

function DataManager.Init()
	if initialized then
		return
	end
	initialized = true

	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		playerStore = storeOrErr
	else
		warn("[DataManager] DataStoreService недоступен (включите Studio Access to API Services): " .. tostring(storeOrErr))
	end

	Players.PlayerAdded:Connect(loadPlayer)
	for _, existingPlayer in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, existingPlayer)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		DataManager.SavePlayer(player)
		Profiles[player] = nil
		RuntimeStates[player] = nil
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataManager.SavePlayer(player)
		end
	end)

	-- Периодическое авто-сохранение без лишней нагрузки
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, runtime in pairs(RuntimeStates) do
				if runtime.Dirty and player:IsDescendantOf(Players) then
					DataManager.SavePlayer(player)
				end
			end
		end
	end)
end

return DataManager
