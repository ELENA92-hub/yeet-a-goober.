--!strict
--[[
	ClientInit.client.lua
	Главная клиентская точка входа «YEET A GOOBER! [MUTATIONS]».
	Программно собирает весь мобильно-адаптивный интерфейс и запускает контроллер пинка и камеры.
]]

local UIController = require(script.Parent:WaitForChild("UIController"))
local KickController = require(script.Parent:WaitForChild("KickController"))

UIController.Init()
KickController.Init()
