--!strict
--[[
	RemoteNames.lua
	Единый реестр имён RemoteEvent для синхронизации клиента и сервера.
]]

local RemoteNames = {
	FolderName = "Remotes",

	-- Client -> Server
	RequestIncubate = "RequestIncubate",
	PickupIncubatedGoober = "PickupIncubatedGoober",
	EquipInventoryGoober = "EquipInventoryGoober",
	LaunchGoober = "LaunchGoober",
	JetpackSteer = "JetpackSteer",
	LandingDecision = "LandingDecision",
	ManagePedestal = "ManagePedestal",
	UpgradeBoot = "UpgradeBoot",
	PromptGamePass = "PromptGamePass",
	TeleportRequest = "TeleportRequest",

	-- Server -> Client
	StateSync = "StateSync",
	FlightEvent = "FlightEvent",
	Notification = "Notification",
}

return RemoteNames
