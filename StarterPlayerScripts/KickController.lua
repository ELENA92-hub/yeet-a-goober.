--!strict
--[[
	KickController.lua
	Клиентский контроллер заряда пинка, камеры полёта и реактивного подруливания:
	- У края обрыва отслеживает удержание ЛКМ / касания экрана (и мобильной кнопки пинка).
	- Гоняет шкалу заряда 0–100%; отпускание в зелёной зоне (85–95%) даёт PERFECT YEET (x3).
	- Плавно ведёт камеру за летящим Губером (экспоненциальная интерполяция без рывков).
	- Оптимизировано для мобильных устройств: RenderStepped подключается ТОЛЬКО во время
	  активного заряда или полёта Губера и сразу отключается после завершения.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local KickController = {}

local LocalPlayer = Players.LocalPlayer
local CHARGE_SPEED = 115.0 -- % в секунду
local CLIFF_EDGE_Z = -48.0

local isCharging = false
local chargePercent = 0.0
local chargeDirection = 1.0
local activeTouchInput: InputObject? = nil

local isInFlight = false
local currentCombo = 1.0
local currentIsPerfect = false

local chargeRenderConn: RBXScriptConnection? = nil
local cameraRenderConn: RBXScriptConnection? = nil
local proximityWatcherRunning = false
local initialized = false

local function getCharacterRoot(): BasePart?
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Проверка нахождения персонажа у края обрыва на вершине горы
local function isNearCliffEdge(): boolean
	local root = getCharacterRoot()
	if not root then
		return false
	end
	local pos = root.Position
	return pos.Y >= 248 and pos.Z <= -25 and pos.Z >= -54 and math.abs(pos.X) <= 48
end

local function stopChargingConnection()
	if chargeRenderConn then
		chargeRenderConn:Disconnect()
		chargeRenderConn = nil
	end
	isCharging = false
	activeTouchInput = nil
end

local function restoreDefaultCamera()
	if cameraRenderConn then
		cameraRenderConn:Disconnect()
		cameraRenderConn = nil
	end

	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	cam.CameraType = Enum.CameraType.Custom
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		cam.CameraSubject = humanoid
	end
end

local function findFlightModel(payload: any): Model?
	if typeof(payload.Model) == "Instance" and payload.Model:IsA("Model") and payload.Model.Parent then
		return payload.Model
	end

	local flightId = tostring(payload.FlightId or "")
	if flightId == "" then
		return nil
	end

	local activeFolder = workspace:FindFirstChild("ActiveGoobers")
	if not activeFolder then
		return nil
	end

	-- На случай задержки репликации на мобильной сети ждём до 2 секунд
	local deadline = os.clock() + 2.0
	while os.clock() < deadline do
		local found = activeFolder:FindFirstChild(flightId)
		if found and found:IsA("Model") then
			return found
		end
		task.wait(0.05)
	end
	return nil
end

local function startCameraFollow(targetModel: Model, gooberData: GooberConfig.GooberData?)
	if cameraRenderConn then
		cameraRenderConn:Disconnect()
		cameraRenderConn = nil
	end

	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	local diameter = gooberData and GooberConfig.GetDiameterFromWeight(gooberData.Weight) or 4.0
	local backDist = 18.0 + diameter * 1.35
	local upHeight = 8.5 + diameter * 0.60

	local body = targetModel.PrimaryPart or targetModel:FindFirstChildWhichIsA("BasePart")
	if not body then
		return
	end

	cam.CameraType = Enum.CameraType.Scriptable
	local smoothCamPos = body.Position + Vector3.new(0, upHeight, backDist)
	local smoothLookPos = body.Position + Vector3.new(0, 1.5, -14)
	local lastHudTick = 0

	cameraRenderConn = RunService.RenderStepped:Connect(function(dt: number)
		local currentCam = workspace.CurrentCamera
		if not currentCam then
			return
		end

		if not targetModel or not targetModel.Parent then
			return
		end

		local primary = targetModel.PrimaryPart or targetModel:FindFirstChildWhichIsA("BasePart")
		if not primary or not primary.Parent then
			return
		end

		local targetPos = primary.Position
		local desiredCamPos = targetPos + Vector3.new(0, upHeight, backDist)
		local desiredLookPos = targetPos + Vector3.new(0, 1.2, -14)

		local alpha = 1.0 - math.exp(-9.0 * math.min(dt, 0.1))
		smoothCamPos = smoothCamPos:Lerp(desiredCamPos, alpha)
		smoothLookPos = smoothLookPos:Lerp(desiredLookPos, alpha)

		currentCam.CFrame = CFrame.lookAt(smoothCamPos, smoothLookPos)

		-- Обновляем текст дистанции в полёте не чаще 10 раз в секунду для экономии CPU на смартфонах
		local now = os.clock()
		if isInFlight and (now - lastHudTick) >= 0.1 then
			lastHudTick = now
			local dist = math.max(1, math.floor(CLIFF_EDGE_Z - targetPos.Z + 0.5))
			UIController.SetFlightHUD(true, dist, currentCombo, currentIsPerfect)
		end
	end)
end

-- Лёгкий фоновый наблюдатель близости к обрыву (работает ТОЛЬКО пока в руках есть Губер)
local function ensureProximityWatcher()
	if proximityWatcherRunning then
		return
	end
	proximityWatcherRunning = true

	task.spawn(function()
		while true do
			local state = UIController.GetState()
			if not state.HeldGoober or isInFlight then
				proximityWatcherRunning = false
				if not isCharging then
					UIController.UpdateChargeDisplay(0, false, false)
				end
				break
			end

			if not isCharging then
				UIController.UpdateChargeDisplay(0, isNearCliffEdge(), false)
			end
			task.wait(0.2)
		end
	end)
end

function KickController.Init()
	if initialized then
		return
	end
	initialized = true

	local remotes = ReplicatedStorage:WaitForChild(RemoteNames.FolderName)
	local launchRemote = remotes:WaitForChild(RemoteNames.LaunchGoober) :: RemoteEvent
	local steerRemote = remotes:WaitForChild(RemoteNames.JetpackSteer) :: RemoteEvent
	local flightEvent = remotes:WaitForChild(RemoteNames.FlightEvent) :: RemoteEvent

	local function beginCharge(inputObj: InputObject?)
		if isCharging or isInFlight then
			return
		end
		local state = UIController.GetState()
		if not state.HeldGoober then
			return
		end
		if not isNearCliffEdge() then
			return
		end

		isCharging = true
		chargePercent = 0.0
		chargeDirection = 1.0
		activeTouchInput = inputObj

		chargeRenderConn = RunService.RenderStepped:Connect(function(dt: number)
			if not isCharging then
				return
			end
			if not isNearCliffEdge() or not UIController.GetState().HeldGoober then
				stopChargingConnection()
				UIController.UpdateChargeDisplay(0, false, false)
				return
			end

			chargePercent += chargeDirection * CHARGE_SPEED * math.min(dt, 0.08)
			if chargePercent >= 100.0 then
				chargePercent = 100.0
				chargeDirection = -1.0
			elseif chargePercent <= 0.0 then
				chargePercent = 0.0
				chargeDirection = 1.0
			end

			UIController.UpdateChargeDisplay(chargePercent, true, true)
		end)
	end

	local function releaseChargeAndLaunch()
		if not isCharging then
			return
		end

		local finalCharge = math.clamp(math.floor(chargePercent * 10 + 0.5) / 10, 2, 100)
		stopChargingConnection()

		if finalCharge >= 85 and finalCharge <= 95 then
			UIController.FlashPerfectYeet()
		end

		UIController.UpdateChargeDisplay(0, isNearCliffEdge(), false)
		launchRemote:FireServer(finalCharge)
	end

	-- Привязка специальной мобильной кнопки удержания пинка
	UIController.BindKickHoldButton(
		function()
			beginCharge(nil)
		end,
		function()
			releaseChargeAndLaunch()
		end
	)

	-- Привязка подруливания в воздухе (Jetpack Steering)
	UIController.BindFlightControls(
		function(dir: string)
			if isInFlight then
				steerRemote:FireServer(dir)
			end
		end,
		function()
			restoreDefaultCamera()
		end
	)

	-- Ввод ЛКМ / Касания экрана в свободной зоне экрана + клавиши подруливания на ПК
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if isInFlight and not gameProcessed then
			if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
				steerRemote:FireServer("Left")
			elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
				steerRemote:FireServer("Right")
			elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.W then
				steerRemote:FireServer("Boost")
			end
			return
		end

		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginCharge(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		if not isCharging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			releaseChargeAndLaunch()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			if activeTouchInput == nil or input == activeTouchInput then
				releaseChargeAndLaunch()
			end
		end
	end)

	-- Реакция на смену состояния (взяли Губера в руки -> включаем проверку близости к обрыву)
	UIController.OnStateChanged(function(state)
		if state.HeldGoober and not isInFlight then
			ensureProximityWatcher()
		end
	end)

	-- События полёта и приземления с сервера
	flightEvent.OnClientEvent:Connect(function(eventType: any, payload: any)
		if type(payload) ~= "table" then
			payload = {}
		end

		if eventType == "Started" then
			isInFlight = true
			currentCombo = 1.0
			currentIsPerfect = payload.IsPerfect == true
			UIController.SetFlightHUD(true, 1, currentCombo, currentIsPerfect)

			task.spawn(function()
				local model = findFlightModel(payload)
				if model and isInFlight then
					startCameraFollow(model, payload.GooberData)
				end
			end)
		elseif eventType == "ComboUpdate" then
			currentCombo = tonumber(payload.ComboMultiplier) or currentCombo
			local dist = tonumber(payload.Distance) or 1
			UIController.SetFlightHUD(true, dist, currentCombo, currentIsPerfect)
		elseif eventType == "Landed" then
			isInFlight = false
			UIController.ShowLandingDecision(payload, remotes)
		elseif eventType == "ResetCamera" then
			isInFlight = false
			UIController.SetFlightHUD(false)
			restoreDefaultCamera()
			if UIController.GetState().HeldGoober then
				ensureProximityWatcher()
			end
		end
	end)

	LocalPlayer.CharacterAdded:Connect(function()
		if not isInFlight then
			restoreDefaultCamera()
		end
	end)
end

return KickController
