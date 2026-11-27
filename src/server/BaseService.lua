--!strict
--[[
	BaseService.lua
	База игрока (4 пьедестала) и пассивный доход монет в секунду:
	- Закрепляет за игроком свободную базу на вершине горы.
	- Отображает 3D-трофеи собранных Губеров со всеми деталями Мастерской.
	- Строго выдерживает компактный шрифт и MaxDistance = 45 для всех BillboardGui
	  над базами и слотами, чтобы надписи не накладывались друг на друга.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local IncubatorService = require(script.Parent:WaitForChild("IncubatorService"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))

export type GooberData = GooberConfig.GooberData

local BaseService = {}

local PlayerPlots: { [Player]: Model } = {}
local PlotOwners: { [Model]: Player } = {}
local initialized = false
local BASE_SIGN_MAX_DISTANCE = 45

local function updateSignLabels(
	guiOwner: Instance?,
	mainText: string,
	subText: string?,
	mainColor: Color3?,
	studsOffset: Vector3?
)
	if not guiOwner then
		return
	end
	local signGui = guiOwner:FindFirstChild("SignGui") :: BillboardGui?
	if not signGui then
		return
	end

	-- Гарантируем MaxDistance = 45, чтобы таблички баз не захламляли экран издалека
	signGui.MaxDistance = BASE_SIGN_MAX_DISTANCE
	if studsOffset then
		signGui.StudsOffset = studsOffset
	end

	local mainLabel = signGui:FindFirstChild("MainLabel") :: TextLabel?
	if mainLabel then
		mainLabel.Text = mainText
		if mainColor then
			mainLabel.TextColor3 = mainColor
		end
	end
	local subLabel = signGui:FindFirstChild("SubLabel") :: TextLabel?
	if subLabel and subText then
		subLabel.Text = subText
	end
end

local function refreshPedestalVisual(plotModel: Model, slot: number, gooberData: GooberData?)
	local pedestalsFolder = plotModel:FindFirstChild("Pedestals")
	if not pedestalsFolder then
		return
	end
	local pedModel = pedestalsFolder:FindFirstChild("Pedestal_" .. tostring(slot)) :: Model?
	if not pedModel then
		return
	end

	local existingTrophy = pedModel:FindFirstChild("TrophyGoober")
	if existingTrophy then
		existingTrophy:Destroy()
	end

	local topPlate = pedModel:FindFirstChild("TopPlate") :: BasePart?
	if not topPlate then
		return
	end

	if not gooberData then
		updateSignLabels(
			topPlate,
			"Слот #" .. tostring(slot),
			"Пусто",
			Color3.fromRGB(200, 210, 225),
			Vector3.new(0, 2.3, 0)
		)
		return
	end

	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local mutation = GooberConfig.Mutations[gooberData.MutationId] or GooberConfig.Mutations.Normal
	local income = GooberConfig.CalculatePassiveIncome(gooberData)

	local rawDiam = GooberConfig.GetDiameterFromWeight(gooberData.Weight)
	local trophyDiam = math.clamp(1.6 + rawDiam * 0.25, 2.0, 4.2)

	local trophy = GooberConfig.BuildGooberModel(gooberData, {
		ScaleOverride = trophyDiam,
		HideBillboard = true,
	})
	trophy.Name = "TrophyGoober"

	for _, desc in ipairs(trophy:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
		elseif desc:IsA("ParticleEmitter") then
			desc.Enabled = false
		end
	end

	local trophyPos = topPlate.Position + Vector3.new(0, 0.35 + trophyDiam * 0.5, 0)
	trophy:PivotTo(CFrame.new(trophyPos) * CFrame.Angles(0, math.rad(180), 0))
	trophy.Parent = pedModel

	updateSignLabels(
		topPlate,
		string.format("%s (+%d/с)", species.Name, income),
		string.format("%.1fкг • %s", gooberData.Weight, mutation.Name),
		Color3.fromRGB(255, 225, 80),
		Vector3.new(0, trophyDiam + 1.5, 0)
	)
end

function BaseService.RefreshAllPedestals(player: Player)
	local plot = PlayerPlots[player]
	local profile = DataManager.GetProfile(player)
	if not plot or not profile then
		return
	end

	local totalIncome = DataManager.CalculateTotalPassiveIncome(player)
	local pad = plot:FindFirstChild("PlotPad")
	updateSignLabels(
		pad,
		string.format("🏠 %s", player.DisplayName),
		string.format("+%d 🪙/сек", totalIncome),
		Color3.fromRGB(120, 255, 175),
		Vector3.new(0, 6.4, 0)
	)

	for slot = 1, GooberConfig.PEDESTAL_COUNT do
		local goober = profile.Pedestals[tostring(slot)]
		refreshPedestalVisual(plot, slot, goober)
	end
end

local function assignPlotToPlayer(player: Player)
	if PlayerPlots[player] then
		BaseService.RefreshAllPedestals(player)
		return
	end

	local map = MapGenerator.EnsureMap()
	local summit = map:FindFirstChild("Summit")
	local basesFolder = summit and summit:FindFirstChild("PlayerBases")
	if not basesFolder then
		return
	end

	for i = 1, 6 do
		local candidate = basesFolder:FindFirstChild("BasePlot_" .. tostring(i)) :: Model?
		if candidate and not PlotOwners[candidate] then
			PlotOwners[candidate] = player
			PlayerPlots[player] = candidate
			BaseService.RefreshAllPedestals(player)
			return
		end
	end
end

local function releasePlotForPlayer(player: Player)
	local plot = PlayerPlots[player]
	if not plot then
		return
	end
	PlayerPlots[player] = nil
	PlotOwners[plot] = nil

	local idx = plot:GetAttribute("PlotIndex") or 1
	local pad = plot:FindFirstChild("PlotPad")
	updateSignLabels(
		pad,
		"🏠 База #" .. tostring(idx),
		"Свободно",
		Color3.fromRGB(140, 220, 255),
		Vector3.new(0, 6.4, 0)
	)

	for slot = 1, GooberConfig.PEDESTAL_COUNT do
		refreshPedestalVisual(plot, slot, nil)
	end
end

function BaseService.GetPlayerPlotPosition(player: Player): Vector3?
	local plot = PlayerPlots[player]
	if plot and plot.PrimaryPart then
		return plot.PrimaryPart.Position + Vector3.new(0, 4.5, 0)
	end
	return nil
end

function BaseService.ChooseTargetSlot(player: Player, preferredSlot: number?): number
	local profile = DataManager.GetProfile(player)
	if not profile then
		return 1
	end

	if preferredSlot then
		local cleanSlot = math.floor(preferredSlot)
		if cleanSlot >= 1 and cleanSlot <= GooberConfig.PEDESTAL_COUNT then
			return cleanSlot
		end
	end

	for slot = 1, GooberConfig.PEDESTAL_COUNT do
		if not profile.Pedestals[tostring(slot)] then
			return slot
		end
	end

	local weakestSlot = 1
	local weakestIncome = math.huge
	for slot = 1, GooberConfig.PEDESTAL_COUNT do
		local existing = profile.Pedestals[tostring(slot)]
		local inc = existing and GooberConfig.CalculatePassiveIncome(existing) or 0
		if inc < weakestIncome then
			weakestIncome = inc
			weakestSlot = slot
		end
	end
	return weakestSlot
end

function BaseService.PlaceGooberOnPedestal(player: Player, gooberData: GooberData, preferredSlot: number?): boolean
	local profile = DataManager.GetProfile(player)
	local runtime = DataManager.GetRuntime(player)
	if not profile or not runtime then
		return false
	end

	local slot = BaseService.ChooseTargetSlot(player, preferredSlot)
	local slotKey = tostring(slot)
	local previous = profile.Pedestals[slotKey]

	if previous then
		DataManager.AddGooberToInventory(player, previous)
	end

	profile.Pedestals[slotKey] = gooberData
	runtime.Dirty = true

	BaseService.RefreshAllPedestals(player)
	DataManager.SyncToClient(player)

	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local income = GooberConfig.CalculatePassiveIncome(gooberData)
	DataManager.Notify(
		player,
		string.format("🏆 %s на пьедестале #%d (+%d 🪙/сек)!", species.Name, slot, income),
		"success"
	)
	return true
end

function BaseService.UnequipPedestalSlot(player: Player, slot: number): boolean
	local profile = DataManager.GetProfile(player)
	local runtime = DataManager.GetRuntime(player)
	if not profile or not runtime then
		return false
	end

	local cleanSlot = math.clamp(math.floor(slot), 1, GooberConfig.PEDESTAL_COUNT)
	local slotKey = tostring(cleanSlot)
	local existing = profile.Pedestals[slotKey]
	if not existing then
		return false
	end

	profile.Pedestals[slotKey] = nil
	runtime.Dirty = true

	if not runtime.HeldGoober then
		IncubatorService.EquipGooberDirect(player, existing)
	else
		DataManager.AddGooberToInventory(player, existing)
	end

	BaseService.RefreshAllPedestals(player)
	DataManager.SyncToClient(player)
	DataManager.Notify(player, string.format("Снят Губер со слота #%d!", cleanSlot), "info")
	return true
end

function BaseService.Init()
	if initialized then
		return
	end
	initialized = true

	MapGenerator.EnsureMap()

	DataManager.OnProfileLoaded(function(player: Player, _profile)
		assignPlotToPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		releasePlotForPlayer(player)
	end)

	local remotes = ReplicatedStorage:WaitForChild(RemoteNames.FolderName)
	local manageRemote = remotes:WaitForChild(RemoteNames.ManagePedestal) :: RemoteEvent

	manageRemote.OnServerEvent:Connect(function(player: Player, action: any, arg1: any, arg2: any)
		if type(action) ~= "string" then
			return
		end

		if action == "PlaceHeld" then
			local slot = tonumber(arg1)
			local held = IncubatorService.ConsumeHeldGoober(player)
			if held then
				BaseService.PlaceGooberOnPedestal(player, held, slot)
			else
				DataManager.Notify(player, "В руках нет Губера для установки!", "warn")
			end
		elseif action == "PlaceFromInventory" then
			local gooberId = tostring(arg1 or "")
			local slot = tonumber(arg2)
			local item = DataManager.RemoveGooberFromInventory(player, gooberId)
			if item then
				BaseService.PlaceGooberOnPedestal(player, item, slot)
			end
		elseif action == "UnequipSlot" then
			local slot = tonumber(arg1)
			if slot then
				BaseService.UnequipPedestalSlot(player, slot)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1.0)
			for _, player in ipairs(Players:GetPlayers()) do
				local income = DataManager.CalculateTotalPassiveIncome(player)
				if income > 0 then
					DataManager.AddCoins(player, income, false)
				end
			end
		end
	end)
end

return BaseService
