--!strict
--[[
	ServerInit.server.lua
	Главная серверная точка входа «YEET A GOOBER! [MUTATIONS]».
	Создаёт RemoteEvents, авто-генерирует 3D-карту с препятствиями/бонусами и запускает сервисы.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))

local remotesFolder = ReplicatedStorage:FindFirstChild(RemoteNames.FolderName)
if not remotesFolder then
	local newFolder = Instance.new("Folder")
	newFolder.Name = RemoteNames.FolderName
	newFolder.Parent = ReplicatedStorage
	remotesFolder = newFolder
end

local eventKeys = {
	RemoteNames.RequestIncubate,
	RemoteNames.UpdateWorkshopPreset,
	RemoteNames.PickupIncubatedGoober,
	RemoteNames.EquipInventoryGoober,
	RemoteNames.LaunchGoober,
	RemoteNames.AirSteer,
	RemoteNames.AirDash,
	RemoteNames.LandingDecision,
	RemoteNames.ManagePedestal,
	RemoteNames.UpgradeBoot,
	RemoteNames.PromptGamePass,
	RemoteNames.TeleportRequest,
	RemoteNames.StateSync,
	RemoteNames.FlightEvent,
	RemoteNames.Notification,
}

for _, eventName in ipairs(eventKeys) do
	if not (remotesFolder :: Folder):FindFirstChild(eventName) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = eventName
		remote.Parent = remotesFolder
	end
end

local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))
MapGenerator.EnsureMap()

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local IncubatorService = require(script.Parent:WaitForChild("IncubatorService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local LaunchService = require(script.Parent:WaitForChild("LaunchService"))
local ShopAndMonetization = require(script.Parent:WaitForChild("ShopAndMonetization"))

DataManager.Init()
IncubatorService.Init()
BaseService.Init()
LaunchService.Init()
ShopAndMonetization.Init()

print("[YEET A GOOBER! MUTATIONS] Сервер запущен: Мастерская Губера, трасса трюков и базы готовы!")
