--!strict
--[[
	ShopAndMonetization.lua
	Магазин прокачки Ботинка за монеты и монетизация Game Pass'ов через MarketplaceService:
	- Улучшение уровня Ботинка (растёт начальный импульс пинка с обрыва).
	- Game Pass «Meme Sound Pack» и «Turbo Jetpack VIP» (удвоенная тяга A/D и ускоренный Рывок).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))

local ShopAndMonetization = {}

local initialized = false

local function grantPassToPlayer(player: Player, passKey: string)
	local profile = DataManager.GetProfile(player)
	local runtime = DataManager.GetRuntime(player)
	if not profile or not runtime then
		return
	end

	if passKey == "MemeSoundPack" then
		profile.OwnedPasses.MemeSoundPack = true
	elseif passKey == "JetpackSteering" then
		profile.OwnedPasses.JetpackSteering = true
	else
		return
	end

	runtime.Dirty = true
	DataManager.SyncToClient(player)
end

local function checkExistingPasses(player: Player)
	local profile = DataManager.GetProfile(player)
	if not profile then
		return
	end

	local changed = false
	for key, passInfo in pairs(GooberConfig.GamePasses) do
		if passInfo.PassId > 0 and not (profile.OwnedPasses :: any)[key] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passInfo.PassId)
			end)
			if ok and owns then
				(profile.OwnedPasses :: any)[key] = true
				changed = true
			end
		end
	end

	if changed then
		DataManager.SyncToClient(player)
	end
end

function ShopAndMonetization.HandleUpgradeBoot(player: Player)
	local profile = DataManager.GetProfile(player)
	local runtime = DataManager.GetRuntime(player)
	if not profile or not runtime then
		return
	end

	local cost = GooberConfig.GetBootUpgradeCost(profile.BootLevel)
	if profile.Coins < cost then
		local missing = cost - profile.Coins
		DataManager.Notify(player, string.format("Не хватает %d 🪙 для прокачки Ботинка!", missing), "warn")
		return
	end

	if DataManager.SpendCoins(player, cost) then
		profile.BootLevel += 1
		runtime.Dirty = true
		DataManager.SyncToClient(player)

		local mult = GooberConfig.GetBootPowerMultiplier(profile.BootLevel)
		local title = GooberConfig.GetBootTitle(profile.BootLevel)
		DataManager.Notify(
			player,
			string.format("👟 Куплен «%s» (Ур. %d, Сила x%.2f)!", title, profile.BootLevel, mult),
			"success"
		)
	end
end

function ShopAndMonetization.HandlePromptGamePass(player: Player, passKey: any)
	if type(passKey) ~= "string" then
		return
	end

	local passInfo = GooberConfig.GamePasses[passKey]
	if not passInfo then
		return
	end

	local profile = DataManager.GetProfile(player)
	if not profile then
		return
	end

	if (profile.OwnedPasses :: any)[passKey] == true then
		DataManager.Notify(player, string.format("✅ «%s» уже активирован!", passInfo.Name), "info")
		return
	end

	if passInfo.PassId > 0 then
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, passInfo.PassId)
		end)
		if not ok then
			warn("[ShopAndMonetization] Ошибка PromptGamePassPurchase: " .. tostring(err))
			DataManager.Notify(player, "Не удалось открыть окно покупки Roblox.", "warn")
		end
	else
		if RunService:IsStudio() then
			grantPassToPlayer(player, passKey)
			DataManager.Notify(
				player,
				string.format("🧪 [Studio Тест] «%s» разблокирован!", passInfo.Name),
				"rare"
			)
		else
			DataManager.Notify(
				player,
				string.format("Game Pass «%s» скоро станет доступен! (PassId = 0)", passInfo.Name),
				"info"
			)
		end
	end
end

function ShopAndMonetization.Init()
	if initialized then
		return
	end
	initialized = true

	DataManager.OnProfileLoaded(function(player: Player, _profile)
		checkExistingPasses(player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, purchasedPassId: number, wasPurchased: boolean)
		if not wasPurchased or not player then
			return
		end

		for key, passInfo in pairs(GooberConfig.GamePasses) do
			if passInfo.PassId > 0 and passInfo.PassId == purchasedPassId then
				grantPassToPlayer(player, key)
				DataManager.Notify(player, string.format("🎉 Спасибо за покупку «%s»!", passInfo.Name), "rare")
				break
			end
		end
	end)

	local remotes = ReplicatedStorage:WaitForChild(RemoteNames.FolderName)
	local upgradeRemote = remotes:WaitForChild(RemoteNames.UpgradeBoot) :: RemoteEvent
	local passRemote = remotes:WaitForChild(RemoteNames.PromptGamePass) :: RemoteEvent

	upgradeRemote.OnServerEvent:Connect(function(player: Player)
		ShopAndMonetization.HandleUpgradeBoot(player)
	end)

	passRemote.OnServerEvent:Connect(function(player: Player, passKey: any)
		ShopAndMonetization.HandlePromptGamePass(player, passKey)
	end)
end

return ShopAndMonetization
