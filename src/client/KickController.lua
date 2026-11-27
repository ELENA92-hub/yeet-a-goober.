--!strict
--[[
	KickController.lua
	Механика пинка Губера с обрыва:
	- Шкала заряда 0→100% (зелёная зона 85–95% = PERFECT YEET множитель x3).
	- Плавная камера, преследующая Губера, с динамическим FOV (70 → 98) по ощущению скорости.
	- Тряска камеры при столкновениях и супер-трюках (через Humanoid.CameraOffset).
	- Управление в воздухе: A/D + ←/→ и мобильные кнопки «◀ / ▶», «Рывок [Space]».
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))

local KickController = {}

local player = Players.LocalPlayer

local remotes: Folder? = nil
local launchRemote: RemoteEvent? = nil
local steerRemote: RemoteEvent? = nil
local dashRemote: RemoteEvent? = nil
local flightEvent: RemoteEvent? = nil

local camera: Camera? = nil
local humanoid: Humanoid? = nil

-- Состояние пинка
local isCharging = false
local chargeValue = 0
local chargeDirection = 1
local chargeConnection: RBXScriptConnection? = nil
local inputBeganConn: RBXScriptConnection? = nil
local inputEndedConn: RBXScriptConnection? = nil
local inputChangedConn: RBXScriptConnection? = nil

-- Состояние полёта
local isFlying = false
local flightModel: Model? = nil
local flightBody: BasePart? = nil
local flightFollowConn: RBXScriptConnection? = nil
local steerHeld: { Left: boolean, Right: boolean } = { Left = false, Right = false }
local shakeUntil: number = 0
local shakePower: number = 0
local currentFOV: number = 70
local baseFOV: number = 70

-- UI элементы (создаются программно здесь и связываются с UIController)
local guiRoot: ScreenGui? = nil
local kickPanel: Frame? = nil
local chargeBar: Frame? = nil
local chargeFill: Frame? = nil
local chargeLabel: TextLabel? = nil
local kickButton: TextButton? = nil
local perfectZone: Frame? = nil
local flightHUD: Frame? = nil
local dashButton: TextButton? = nil
local skipCameraButton: TextButton? = nil
local steerLeftButton: TextButton? = nil
local steerRightButton: TextButton? = nil
local windLines: Frame? = nil
local dashCooldownBar: Frame? = nil

local dashAvailableAt: number = 0
local dashCooldown: number = 2.8

local DEFAULT_FOV = 70
local MAX_FOV = 98
local FOV_LERP_SPEED = 4.5

-- ============================================================================
-- ВСПОМОГАТЕЛЬНОЕ
-- ============================================================================

local function getRemotes(): (Folder?, RemoteEvent?, RemoteEvent?, RemoteEvent?, RemoteEvent?)
	if not remotes then
		remotes = ReplicatedStorage:FindFirstChild(RemoteNames.FolderName) :: Folder?
		if remotes then
			launchRemote = remotes:FindFirstChild(RemoteNames.LaunchGoober) :: RemoteEvent?
			steerRemote = remotes:FindFirstChild(RemoteNames.AirSteer) :: RemoteEvent?
			dashRemote = remotes:FindFirstChild(RemoteNames.AirDash) :: RemoteEvent?
			flightEvent = remotes:FindFirstChild(RemoteNames.FlightEvent) :: RemoteEvent?
		end
	end
	return remotes, launchRemote, steerRemote, dashRemote, flightEvent
end

local function refreshHumanoid()
	local char = player.Character
	if char then
		humanoid = char:FindFirstChildOfClass("Humanoid")
		camera = Workspace.CurrentCamera
	end
end

local function triggerShake(power: number, duration: number)
	shakePower = math.max(shakePower, power)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

local function sendSteerState()
	if not steerRemote then
		return
	end
	local dir = 0
	if steerHeld.Left and not steerHeld.Right then
		dir = -1
	elseif steerHeld.Right and not steerHeld.Left then
		dir = 1
	end
	steerRemote:FireServer(dir)
end

local function tryDash()
	if not isFlying then
		return
	end
	if os.clock() < dashAvailableAt then
		return
	end
	if dashRemote then
		dashRemote:FireServer()
	end
end

-- ============================================================================
-- UI КНОПКИ ПИНКА
-- ============================================================================

local function makeCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function ensureKickUI()
	if guiRoot and guiRoot.Parent then
		return
	end

	local existing = player:FindFirstChild("PlayerGui")
	if not existing then
		return
	end
	local pg = existing :: PlayerGui

	guiRoot = pg:FindFirstChild("YeetKickGui") :: ScreenGui?
	if not guiRoot then
		local sg = Instance.new("ScreenGui")
		sg.Name = "YeetKickGui"
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.Parent = pg
		guiRoot = sg
	end

	-- Панель заряда
	kickPanel = (guiRoot :: ScreenGui):FindFirstChild("KickPanel") :: Frame?
	if not kickPanel then
		local panel = Instance.new("Frame")
		panel.Name = "KickPanel"
		panel.Size = UDim2.new(0, 320, 0, 92)
		panel.Position = UDim2.new(0.5, -160, 1, -132)
		panel.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
		panel.BackgroundTransparency = 0.12
		panel.BorderSizePixel = 0
		panel.Visible = false
		panel.Parent = guiRoot
		makeCorner(panel, 18)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 220, 60)
		stroke.Thickness = 2.2
		stroke.Parent = panel
		kickPanel = panel

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 235, 80)
		title.Text = "🦵 СИЛА ПИНКА"
		title.Parent = panel
		local tc = Instance.new("UITextSizeConstraint")
		tc.MaxTextSize = 14
		tc.MinTextSize = 10
		tc.Parent = title

		chargeBar = Instance.new("Frame")
		chargeBar.Name = "ChargeBar"
		chargeBar.Size = UDim2.new(1, -24, 0, 26)
		chargeBar.Position = UDim2.new(0, 12, 0, 28)
		chargeBar.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
		chargeBar.BorderSizePixel = 0
		chargeBar.Parent = panel
		makeCorner(chargeBar, 13)

		perfectZone = Instance.new("Frame")
		perfectZone.Name = "PerfectZone"
		perfectZone.Size = UDim2.new(0.10, 0, 1, 0)
		perfectZone.Position = UDim2.new(0.85, 0, 0, 0)
		perfectZone.BackgroundColor3 = Color3.fromRGB(75, 255, 95)
		perfectZone.BackgroundTransparency = 0.15
		perfectZone.BorderSizePixel = 0
		perfectZone.Parent = chargeBar
		makeCorner(perfectZone, 4)
		local pzStroke = Instance.new("UIStroke")
		pzStroke.Color = Color3.fromRGB(65, 255, 110)
		pzStroke.Thickness = 1.5
		pzStroke.Parent = perfectZone
		local pzLabel = Instance.new("TextLabel")
		pzLabel.Size = UDim2.fromScale(1, 1)
		pzLabel.BackgroundTransparency = 1
		pzLabel.Font = Enum.Font.GothamBold
		pzLabel.TextScaled = true
		pzLabel.TextColor3 = Color3.fromRGB(75, 255, 95)
		pzLabel.Text = "★"
		pzLabel.Parent = perfectZone
		local pztc = Instance.new("UITextSizeConstraint")
		pztc.MaxTextSize = 10
		pztc.Parent = pzLabel

		chargeFill = Instance.new("Frame")
		chargeFill.Name = "ChargeFill"
		chargeFill.Size = UDim2.new(0, 0, 1, 0)
		chargeFill.BackgroundColor3 = Color3.fromRGB(255, 210, 45)
		chargeFill.BorderSizePixel = 0
		chargeFill.ZIndex = 2
		chargeFill.Parent = chargeBar
		makeCorner(chargeFill, 13)

		chargeLabel = Instance.new("TextLabel")
		chargeLabel.Name = "ChargeLabel"
		chargeLabel.Size = UDim2.new(1, 0, 0, 18)
		chargeLabel.Position = UDim2.new(0, 0, 0, 58)
		chargeLabel.BackgroundTransparency = 1
		chargeLabel.Font = Enum.Font.GothamBlack
		chargeLabel.TextScaled = true
		chargeLabel.TextColor3 = Color3.new(1, 1, 1)
		chargeLabel.Text = "Зажми ЛКМ / кнопку!"
		chargeLabel.Parent = panel
		local ctc = Instance.new("UITextSizeConstraint")
		ctc.MaxTextSize = 12
		ctc.MinTextSize = 9
		ctc.Parent = chargeLabel

		kickButton = Instance.new("TextButton")
		kickButton.Name = "KickButton"
		kickButton.Size = UDim2.new(0, 148, 0, 44)
		kickButton.Position = UDim2.new(0.5, -74, 0, 78)
		kickButton.BackgroundColor3 = Color3.fromRGB(255, 85, 65)
		kickButton.Font = Enum.Font.GothamBlack
		kickButton.TextScaled = true
		kickButton.TextColor3 = Color3.new(1, 1, 1)
		kickButton.Text = "🦵 ЗАЖМИ ПИНОК!"
		kickButton.AutoButtonColor = true
		kickButton.BorderSizePixel = 0
		kickButton.Visible = false
		kickButton.Parent = panel
		makeCorner(kickButton, 14)
		local kStroke = Instance.new("UIStroke")
		kStroke.Color = Color3.fromRGB(255, 165, 55)
		kStroke.Thickness = 1.8
		kStroke.Parent = kickButton
		local ktc = Instance.new("UITextSizeConstraint")
		ktc.MaxTextSize = 13
		ktc.MinTextSize = 9
		ktc.Parent = kickButton
	else
		chargeBar = kickPanel:FindFirstChild("ChargeBar") :: Frame?
		chargeFill = chargeBar and chargeBar:FindFirstChild("ChargeFill") :: Frame?
		chargeLabel = kickPanel:FindFirstChild("ChargeLabel") :: TextLabel?
		kickButton = kickPanel:FindFirstChild("KickButton") :: TextButton?
		perfectZone = chargeBar and chargeBar:FindFirstChild("PerfectZone") :: Frame?
	end

	-- HUD полёта
	flightHUD = (guiRoot :: ScreenGui):FindFirstChild("FlightHUD") :: Frame?
	if not flightHUD then
		local hud = Instance.new("Frame")
		hud.Name = "FlightHUD"
		hud.Size = UDim2.new(1, 0, 0, 96)
		hud.Position = UDim2.new(0, 0, 0, 0)
		hud.BackgroundColor3 = Color3.fromRGB(18, 20, 34)
		hud.BackgroundTransparency = 0.18
		hud.BorderSizePixel = 0
		hud.Visible = false
		hud.Parent = guiRoot
		flightHUD = hud

		local distLabel = Instance.new("TextLabel")
		distLabel.Name = "DistanceLabel"
		distLabel.Size = UDim2.new(0.34, 0, 1, 0)
		distLabel.BackgroundTransparency = 1
		distLabel.Font = Enum.Font.GothamBlack
		distLabel.TextScaled = true
		distLabel.TextColor3 = Color3.fromRGB(110, 255, 150)
		distLabel.Text = "🏁 0 м"
		distLabel.Parent = hud
		local dtc = Instance.new("UITextSizeConstraint")
		dtc.MaxTextSize = 20
		dtc.MinTextSize = 12
		dtc.Parent = distLabel

		local speedLabel = Instance.new("TextLabel")
		speedLabel.Name = "SpeedLabel"
		speedLabel.Size = UDim2.new(0.22, 0, 1, 0)
		speedLabel.Position = UDim2.new(0.34, 0, 0, 0)
		speedLabel.BackgroundTransparency = 1
		speedLabel.Font = Enum.Font.GothamBold
		speedLabel.TextScaled = true
		speedLabel.TextColor3 = Color3.fromRGB(130, 210, 255)
		speedLabel.Text = "💨 0"
		speedLabel.Parent = hud
		local stc = Instance.new("UITextSizeConstraint")
		stc.MaxTextSize = 16
		stc.MinTextSize = 10
		stc.Parent = speedLabel

		local comboLabel = Instance.new("TextLabel")
		comboLabel.Name = "ComboLabel"
		comboLabel.Size = UDim2.new(0.22, 0, 1, 0)
		comboLabel.Position = UDim2.new(0.56, 0, 0, 0)
		comboLabel.BackgroundTransparency = 1
		comboLabel.Font = Enum.Font.GothamBlack
		comboLabel.TextScaled = true
		comboLabel.TextColor3 = Color3.fromRGB(255, 225, 55)
		comboLabel.Text = "🔥 x1.00"
		comboLabel.Parent = hud
		local ctc2 = Instance.new("UITextSizeConstraint")
		ctc2.MaxTextSize = 16
		ctc2.MinTextSize = 10
		ctc2.Parent = comboLabel

		local shieldLabel = Instance.new("TextLabel")
		shieldLabel.Name = "ShieldLabel"
		shieldLabel.Size = UDim2.new(0.22, 0, 1, 0)
		shieldLabel.Position = UDim2.new(0.78, 0, 0, 0)
		shieldLabel.BackgroundTransparency = 1
		shieldLabel.Font = Enum.Font.GothamBold
		shieldLabel.TextScaled = true
		shieldLabel.TextColor3 = Color3.fromRGB(90, 235, 255)
		shieldLabel.Text = ""
		shieldLabel.Parent = hud
		local shtc = Instance.new("UITextSizeConstraint")
		shtc.MaxTextSize = 14
		shtc.MinTextSize = 9
		shtc.Parent = shieldLabel
	end

	-- Мобильные кнопки руления
	local steerContainer = (guiRoot :: ScreenGui):FindFirstChild("SteerContainer") :: Frame?
	if not steerContainer then
		local sc = Instance.new("Frame")
		sc.Name = "SteerContainer"
		sc.Size = UDim2.new(1, 0, 0, 64)
		sc.Position = UDim2.new(0, 0, 1, -92)
		sc.BackgroundTransparency = 1
		sc.Visible = false
		sc.Parent = guiRoot
		steerContainer = sc

		steerLeftButton = Instance.new("TextButton")
		steerLeftButton.Name = "SteerLeft"
		steerLeftButton.Size = UDim2.new(0, 72, 0, 64)
		steerLeftButton.Position = UDim2.new(0, 16, 0, 0)
		steerLeftButton.BackgroundColor3 = Color3.fromRGB(55, 135, 255)
		steerLeftButton.BackgroundTransparency = 0.18
		steerLeftButton.Font = Enum.Font.GothamBlack
		steerLeftButton.TextScaled = true
		steerLeftButton.TextColor3 = Color3.new(1, 1, 1)
		steerLeftButton.Text = "◀"
		steerLeftButton.BorderSizePixel = 0
		steerLeftButton.Parent = sc
		makeCorner(steerLeftButton, 18)
		local ltc = Instance.new("UITextSizeConstraint")
		ltc.MaxTextSize = 28
		ltc.Parent = steerLeftButton

		steerRightButton = Instance.new("TextButton")
		steerRightButton.Name = "SteerRight"
		steerRightButton.Size = UDim2.new(0, 72, 0, 64)
		steerRightButton.Position = UDim2.new(1, -88, 0, 0)
		steerRightButton.BackgroundColor3 = Color3.fromRGB(55, 135, 255)
		steerRightButton.BackgroundTransparency = 0.18
		steerRightButton.Font = Enum.Font.GothamBlack
		steerRightButton.TextScaled = true
		steerRightButton.TextColor3 = Color3.new(1, 1, 1)
		steerRightButton.Text = "▶"
		steerRightButton.BorderSizePixel = 0
		steerRightButton.Parent = sc
		makeCorner(steerRightButton, 18)
		local rtc = Instance.new("UITextSizeConstraint")
		rtc.MaxTextSize = 28
		rtc.Parent = steerRightButton
	else
		steerLeftButton = steerContainer:FindFirstChild("SteerLeft") :: TextButton?
		steerRightButton = steerContainer:FindFirstChild("SteerRight") :: TextButton?
	end

	-- Кнопка Рывка
	dashButton = (guiRoot :: ScreenGui):FindFirstChild("DashButton") :: TextButton?
	if not dashButton then
		local db = Instance.new("TextButton")
		db.Name = "DashButton"
		db.Size = UDim2.new(0, 176, 0, 52)
		db.Position = UDim2.new(0.5, -88, 1, -160)
		db.BackgroundColor3 = Color3.fromRGB(255, 125, 35)
		db.Font = Enum.Font.GothamBlack
		db.TextScaled = true
		db.TextColor3 = Color3.new(1, 1, 1)
		db.Text = "⚡ РЫВОК [SPACE]"
		db.BorderSizePixel = 0
		db.Visible = false
		db.Parent = guiRoot
		makeCorner(db, 16)
		local dbs = Instance.new("UIStroke")
		dbs.Color = Color3.fromRGB(255, 195, 55)
		dbs.Thickness = 2
		dbs.Parent = db
		local dtc2 = Instance.new("UITextSizeConstraint")
		dtc2.MaxTextSize = 14
		dtc2.MinTextSize = 9
		dtc2.Parent = db
		dashButton = db

		dashCooldownBar = Instance.new("Frame")
		dashCooldownBar.Name = "CooldownBar"
		dashCooldownBar.Size = UDim2.new(1, 0, 0, 6)
		dashCooldownBar.Position = UDim2.new(0, 0, 1, -6)
		dashCooldownBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		dashCooldownBar.BackgroundTransparency = 0.2
		dashCooldownBar.BorderSizePixel = 0
		dashCooldownBar.Visible = false
		dashCooldownBar.Parent = db
		makeCorner(dashCooldownBar, 3)
	end

	-- Кнопка пропуска камеры
	skipCameraButton = (guiRoot :: ScreenGui):FindFirstChild("SkipCameraButton") :: TextButton?
	if not skipCameraButton then
		local sb = Instance.new("TextButton")
		sb.Name = "SkipCameraButton"
		sb.Size = UDim2.new(0, 160, 0, 36)
		sb.Position = UDim2.new(1, -172, 0, 104)
		sb.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
		sb.BackgroundTransparency = 0.15
		sb.Font = Enum.Font.GothamBold
		sb.TextScaled = true
		sb.TextColor3 = Color3.fromRGB(200, 210, 225)
		sb.Text = "⏭ Пропустить камеру"
		sb.BorderSizePixel = 0
		sb.Visible = false
		sb.Parent = guiRoot
		makeCorner(sb, 10)
		local sbtc = Instance.new("UITextSizeConstraint")
		sbtc.MaxTextSize = 11
		sbtc.Parent = sb
		skipCameraButton = sb
	end

	-- Линии ветра по краям экрана
	windLines = (guiRoot :: ScreenGui):FindFirstChild("WindLines") :: Frame?
	if not windLines then
		local wl = Instance.new("Frame")
		wl.Name = "WindLines"
		wl.Size = UDim2.new(1, 0, 1, 0)
		wl.BackgroundTransparency = 1
		wl.Visible = false
		wl.Parent = guiRoot
		windLines = wl
		for i = 1, 6 do
			local line = Instance.new("Frame")
			line.Name = "WindLine_" .. tostring(i)
			line.Size = UDim2.new(0, 3, 0, 42 + i * 8)
			line.Position = UDim2.new(0, 8 + (i % 2) * 14, 0, 90 + i * 58)
			line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			line.BackgroundTransparency = 0.62
			line.BorderSizePixel = 0
			line.Parent = wl
			makeCorner(line, 2)
			local line2 = line:Clone()
			line2.Position = UDim2.new(1, -18 - (i % 2) * 14, 0, 90 + i * 58)
			line2.Parent = wl
		end
	end
end

-- ============================================================================
-- ЗАРЯД И ОТПРАВКА ПИНКА
-- ============================================================================

local function updateChargeVisual()
	if not chargeFill or not chargeLabel then
		return
	end
	chargeFill.Size = UDim2.new(chargeValue / 100, 0, 1, 0)
	local inPerfect = chargeValue >= 85 and chargeValue <= 95
	if inPerfect then
		chargeFill.BackgroundColor3 = Color3.fromRGB(65, 255, 110)
		chargeLabel.Text = string.format("★ PERFECT YEET! x3 ★  %d%%", math.floor(chargeValue + 0.5))
		chargeLabel.TextColor3 = Color3.fromRGB(65, 255, 110)
	else
		if chargeValue < 30 then
			chargeFill.BackgroundColor3 = Color3.fromRGB(255, 95, 75)
		elseif chargeValue < 70 then
			chargeFill.BackgroundColor3 = Color3.fromRGB(255, 210, 45)
		else
			chargeFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
		end
		chargeLabel.TextColor3 = Color3.new(1, 1, 1)
		chargeLabel.Text = string.format("Сила: %d%%", math.floor(chargeValue + 0.5))
	end
end

local function startCharging()
	if isCharging or isFlying then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local distToEdge = hrp.Position.Z - (-22)
	local heightOk = hrp.Position.Y >= 248
	local nearEdge = math.abs(distToEdge) < 52 and math.abs(hrp.Position.X) < 70
	if not (heightOk and nearEdge) then
		return
	end

	isCharging = true
	chargeValue = 0
	chargeDirection = 1
	ensureKickUI()
	if kickPanel then
		kickPanel.Visible = true
	end
	if chargeConnection then
		chargeConnection:Disconnect()
	end
	chargeConnection = RunService.Heartbeat:Connect(function(dt: number)
		-- Скорость заполнения ~ 68% в секунду
		chargeValue += chargeDirection * dt * 68
		if chargeValue >= 100 then
			chargeValue = 100
			chargeDirection = -1
		elseif chargeValue <= 0 then
			chargeValue = 0
			chargeDirection = 1
		end
		updateChargeVisual()
	end)
end

local function releaseKick()
	if not isCharging then
		return
	end
	isCharging = false
	if chargeConnection then
		chargeConnection:Disconnect()
		chargeConnection = nil
	end
	local finalCharge = math.clamp(math.floor(chargeValue + 0.5), 1, 100)
	if kickPanel then
		kickPanel.Visible = false
	end
	if launchRemote then
		launchRemote:FireServer(finalCharge)
	end
end

local function cancelCharging()
	if not isCharging then
		return
	end
	isCharging = false
	if chargeConnection then
		chargeConnection:Disconnect()
		chargeConnection = nil
	end
	if kickPanel then
		kickPanel.Visible = false
	end
end

-- ============================================================================
-- КАМЕРА ПОЛЁТА (ПЛАВНОЕ ПРЕСЛЕДОВАНИЕ + FOV + ТРЯСКА)
-- ============================================================================

local function startFlightCamera(model: Model, perfectMult: number?)
	flightModel = model
	flightBody = model.PrimaryPart :: BasePart?
	isFlying = true
	ensureKickUI()

	if flightHUD then
		flightHUD.Visible = true
	end
	local steerContainer = guiRoot and guiRoot:FindFirstChild("SteerContainer") :: Frame?
	if steerContainer then
		steerContainer.Visible = true
	end
	if dashButton then
		dashButton.Visible = true
	end
	if skipCameraButton then
		skipCameraButton.Visible = true
	end
	if windLines then
		windLines.Visible = true
	end
	if kickPanel then
		kickPanel.Visible = false
	end

	camera = Workspace.CurrentCamera
	refreshHumanoid()
	if camera then
		baseFOV = camera.FieldOfView
		currentFOV = baseFOV
	end

	if flightFollowConn then
		flightFollowConn:Disconnect()
	end

	local followOffset = Vector3.new(0, 18, 34)
	local lookAheadFactor = 0.35

	flightFollowConn = RunService.RenderStepped:Connect(function(dt: number)
		if not isFlying then
			return
		end
		local body = flightBody
		local mdl = flightModel
		if not mdl or not mdl.Parent or not body or not body.Parent then
			return
		end
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end

		local pos = body.Position
		local vel = body.AssemblyLinearVelocity
		local speed = vel.Magnitude
		local lookAhead = vel.Unit * math.clamp(speed * lookAheadFactor, 0, 18)
		if vel.Magnitude < 1 then
			lookAhead = Vector3.zero
		end

		local targetPos = pos + followOffset + lookAhead * 0.45
		local targetLook = pos + lookAhead

		-- Плавное следование (lerp)
		local alpha = math.clamp(dt * 5.5, 0, 1)
		cam.CFrame = cam.CFrame:Lerp(CFrame.new(targetPos, targetLook), alpha)

		-- Динамический FOV по скорости (70 → 98)
		local speedNorm = math.clamp(speed / 145, 0, 1)
		local targetFOV = DEFAULT_FOV + speedNorm * (MAX_FOV - DEFAULT_FOV)
		currentFOV = currentFOV + (targetFOV - currentFOV) * math.clamp(dt * FOV_LERP_SPEED, 0, 1)
		cam.FieldOfView = currentFOV

		-- Тряска камеры
		local now = os.clock()
		if now < shakeUntil and humanoid and humanoid.Parent then
			local t = 1 - (shakeUntil - now) / 0.45
			local decay = 1 - t
			local offX = (math.sin(now * 42) * 0.85 + math.cos(now * 31) * 0.5) * shakePower * decay
			local offY = (math.sin(now * 37) * 0.75 + math.cos(now * 28) * 0.45) * shakePower * decay
			humanoid.CameraOffset = Vector3.new(offX, offY, 0)
		else
			if humanoid and humanoid.Parent then
				humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, math.clamp(dt * 8, 0, 1))
			end
			if now >= shakeUntil then
				shakePower = 0
			end
		end

		-- Линии ветра: прозрачность по скорости
		if windLines then
			local alpha2 = math.clamp(speedNorm * 1.35, 0, 1)
			for _, child in ipairs(windLines:GetChildren()) do
				if child:IsA("Frame") then
					child.BackgroundTransparency = 1 - alpha2 * 0.55
				end
			end
		end

		-- HUD дистанции и скорости
		if flightHUD then
			local distLabel = flightHUD:FindFirstChild("DistanceLabel") :: TextLabel?
			if distLabel then
				local cliffZ = -6
				local d = math.max(1, math.floor((cliffZ - pos.Z) + 0.5))
				distLabel.Text = string.format("🏁 %d м", d)
			end
			local speedLabel = flightHUD:FindFirstChild("SpeedLabel") :: TextLabel?
			if speedLabel then
				speedLabel.Text = string.format("💨 %d", math.floor(speed + 0.5))
			end
		end

		-- Откат кнопки Рывка
		if dashButton then
			local remaining = dashAvailableAt - os.clock()
			if remaining > 0 then
				dashButton.AutoButtonColor = false
				dashButton.BackgroundTransparency = 0.35
				if dashCooldownBar then
					dashCooldownBar.Visible = true
					dashCooldownBar.Size = UDim2.new(math.clamp(remaining / dashCooldown, 0, 1), 0, 0, 6)
				end
			else
				dashButton.AutoButtonColor = true
				dashButton.BackgroundTransparency = 0
				if dashCooldownBar then
					dashCooldownBar.Visible = false
				end
			end
		end
	end)
end

local function stopFlightCamera(resetToCharacter: boolean?)
	isFlying = false
	flightModel = nil
	flightBody = nil

	if flightFollowConn then
		flightFollowConn:Disconnect()
		flightFollowConn = nil
	end

	if flightHUD then
		flightHUD.Visible = false
	end
	local steerContainer = guiRoot and guiRoot:FindFirstChild("SteerContainer") :: Frame?
	if steerContainer then
		steerContainer.Visible = false
	end
	if dashButton then
		dashButton.Visible = false
	end
	if skipCameraButton then
		skipCameraButton.Visible = false
	end
	if windLines then
		windLines.Visible = false
	end
	if dashCooldownBar then
		dashCooldownBar.Visible = false
	end

	steerHeld.Left = false
	steerHeld.Right = false
	shakeUntil = 0
	shakePower = 0

	camera = Workspace.CurrentCamera
	if camera then
		currentFOV = DEFAULT_FOV
		camera.FieldOfView = DEFAULT_FOV
		if resetToCharacter ~= false then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				camera.CameraSubject = (char:FindFirstChildOfClass("Humanoid") :: Instance?) :: CameraSubject? or hrp
				camera.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 18), hrp.Position)
			end
		end
	end
	if humanoid and humanoid.Parent then
		humanoid.CameraOffset = Vector3.zero
	end
end

-- ============================================================================
-- ОБРАБОТКА FLIGHTEVENT С СЕРВЕРА
-- ============================================================================

local function bindFlightEvents()
	getRemotes()
	if not flightEvent then
		task.delay(1, bindFlightEvents)
		return
	end

	flightEvent.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "Started" then
			local mdl = payload and payload.Model
			if mdl and typeof(mdl) == "Instance" and mdl:IsA("Model") then
				dashCooldown = tonumber(payload.DashCooldown) or 2.8
				dashAvailableAt = os.clock() + 0.35
				startFlightCamera(mdl, payload.PerfectMultiplier)
				if payload.IsPerfect then
					triggerShake(1.0, 0.45)
				end
			end
		elseif kind == "ComboUpdate" or kind == "SuperMutation" then
			if flightHUD then
				local comboLabel = flightHUD:FindFirstChild("ComboLabel") :: TextLabel?
				if comboLabel and payload then
					local cm = tonumber(payload.ComboMultiplier) or 1.0
					comboLabel.Text = string.format("🔥 x%.2f (трюк #%d)", cm, tonumber(payload.TrickStreak) or 0)
					if payload.HasShield then
						local shieldLabel = flightHUD:FindFirstChild("ShieldLabel") :: TextLabel?
						if shieldLabel then
							shieldLabel.Text = "🛡️ ЩИТ"
						end
					end
					-- Подсветка комбо при росте
					comboLabel.TextColor3 = Color3.fromRGB(255, 235, 65)
					TweenService:Create(comboLabel, TweenInfo.new(0.18), { TextColor3 = Color3.fromRGB(255, 225, 55) }):Play()
				end
			end
			if payload and payload.Shake then
				triggerShake(tonumber(payload.Shake) or 0.4, 0.35)
			end
		elseif kind == "Impact" or kind == "StreakReset" then
			if flightHUD and payload then
				local comboLabel = flightHUD:FindFirstChild("ComboLabel") :: TextLabel?
				if comboLabel then
					comboLabel.Text = string.format("🔥 x%.2f", tonumber(payload.ComboMultiplier) or 1.0)
				end
				if payload.HasShield ~= nil then
					local shieldLabel = flightHUD:FindFirstChild("ShieldLabel") :: TextLabel?
					if shieldLabel then
						shieldLabel.Text = payload.HasShield and "🛡️ ЩИТ" or ""
					end
				end
			end
			if payload and payload.Shake then
				triggerShake(tonumber(payload.Shake) or 0.6, 0.45)
			end
		elseif kind == "DashUsed" then
			if payload then
				dashCooldown = tonumber(payload.Cooldown) or dashCooldown
				dashAvailableAt = os.clock() + dashCooldown
				if payload.Shake then
					triggerShake(tonumber(payload.Shake) or 0.55, 0.3)
				end
			end
		elseif kind == "Landed" then
			stopFlightCamera(false)
		elseif kind == "ResetCamera" then
			stopFlightCamera(true)
		end
	end)
end

-- ============================================================================
-- ВВОД: КЛАВИАТУРА, МЫШЬ, СЕНСОР
-- ============================================================================

local function bindInput()
	if inputBeganConn then
		return
	end

	inputBeganConn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			-- Если во время полёта тап по экрану = Рывок
			if isFlying then
				tryDash()
			else
				startCharging()
			end
		elseif input.KeyCode == Enum.KeyCode.Space then
			if isFlying then
				tryDash()
			end
		elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			if isFlying then
				steerHeld.Left = true
				sendSteerState()
			end
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			if isFlying then
				steerHeld.Right = true
				sendSteerState()
			end
		end
	end)

	inputEndedConn = UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if isCharging then
				releaseKick()
			end
		elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			if steerHeld.Left then
				steerHeld.Left = false
				sendSteerState()
			end
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			if steerHeld.Right then
				steerHeld.Right = false
				sendSteerState()
			end
		end
	end)
end

-- ============================================================================
-- ПУБЛИЧНОЕ API
-- ============================================================================

function KickController.IsFlying(): boolean
	return isFlying
end

function KickController.IsCharging(): boolean
	return isCharging
end

function KickController.TriggerShake(power: number, duration: number)
	triggerShake(power, duration)
end

function KickController.Init()
	ensureKickUI()
	bindFlightEvents()
	bindInput()
	refreshHumanoid()

	player.CharacterAdded:Connect(function()
		task.wait(0.35)
		refreshHumanoid()
		ensureKickUI()
		bindInput()
	end)

	-- Подключаем созданные кнопки после постройки UI
	task.defer(function()
		local tries = 0
		while tries < 30 do
			tries += 1
			task.wait(0.2)
			ensureKickUI()
			if kickButton and not kickButton:GetAttribute("KickWired") then
				kickButton:SetAttribute("KickWired", true)
				kickButton.InputBegan:Connect(function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						startCharging()
					end
				end)
				kickButton.InputEnded:Connect(function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						if isCharging then
							releaseKick()
						end
					end
				end)
			end
			if steerLeftButton and not steerLeftButton:GetAttribute("SteerWired") then
				steerLeftButton:SetAttribute("SteerWired", true)
				steerLeftButton.InputBegan:Connect(function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						steerHeld.Left = true
						sendSteerState()
					end
				end)
				steerLeftButton.InputEnded:Connect(function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						steerHeld.Left = false
						sendSteerState()
					end
				end)
			end
			if steerRightButton and not steerRightButton:GetAttribute("SteerWired") then
				steerRightButton:SetAttribute("SteerWired", true)
				steerRightButton.InputBegan:Connect(function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						steerHeld.Right = true
						sendSteerState()
					end
				end)
				steerRightButton.InputEnded:Connect(function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						steerHeld.Right = false
						sendSteerState()
					end
				end)
			end
			if dashButton and not dashButton:GetAttribute("DashWired") then
				dashButton:SetAttribute("DashWired", true)
				dashButton.MouseButton1Click:Connect(tryDash)
				dashButton.TouchTap:Connect(tryDash)
			end
			if skipCameraButton and not skipCameraButton:GetAttribute("SkipWired") then
				skipCameraButton:SetAttribute("SkipWired", true)
				skipCameraButton.MouseButton1Click:Connect(function()
					stopFlightCamera(true)
				end)
			end
		end
	end)

	-- Сброс заряда при сворачивании окна Roblox
	UserInputService.WindowFocusReleased:Connect(cancelCharging)
end

return KickController
