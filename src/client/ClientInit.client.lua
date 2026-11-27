--!strict
--[[
	ClientInit.client.lua
	Главная клиентская точка входа «YEET A GOOBER! [MUTATIONS]».
	Запускает UIController и KickController, добавляет лёгкую клиентскую анимацию
	монет/кристаллов/пропеллеров без нагрузки на сервер.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UIController = require(script.Parent:WaitForChild("UIController"))
local KickController = require(script.Parent:WaitForChild("KickController"))

UIController.Init()
KickController.Init()

-- Клиентская анимация парящих монет, кристаллов, пропеллеров и облаков (чисто визуальная)
task.defer(function()
	local map = Workspace:WaitForChild("YeetMap", 12) :: Folder?
	if not map then
		map = Workspace:FindFirstChild("YeetMap") :: Folder?
	end
	if not map then
		return
	end
	local track = map:FindFirstChild("BoostersAndRings") :: Folder?
	if not track then
		return
	end

	type BobbingPart = {
		Part: BasePart,
		BaseY: number,
		Phase: number,
		Speed: number,
		Amp: number,
		Kind: string,
	}

	local bobbers: { BobbingPart } = {}

	-- Собираем монеты, кристаллы и облака для покачивания/вращения
	for _, child in ipairs(track:GetChildren()) do
		if child:IsA("BasePart") then
			if child:GetAttribute("IsFloatingCoin") or child:GetAttribute("IsMutationCrystal") then
				table.insert(bobbers, {
					Part = child,
					BaseY = child.Position.Y,
					Phase = math.random() * math.pi * 2,
					Speed = 1.2 + math.random() * 0.6,
					Amp = 1.8 + math.random() * 0.6,
					Kind = "BobSpin",
				})
			elseif child:GetAttribute("IsCloudTrampoline") then
				table.insert(bobbers, {
					Part = child,
					BaseY = child.Position.Y,
					Phase = math.random() * math.pi * 2,
					Speed = 0.7 + math.random() * 0.3,
					Amp = 0.9,
					Kind = "CloudDrift",
				})
			end
		end
	end

	-- Также собираем кольца (лёгкое вращение кольца)
	local ringSpins: { BasePart } = {}
	for _, child in ipairs(track:GetDescendants()) do
		if child:IsA("BasePart") and child.Name == "GoldenRingTorus" then
			table.insert(ringSpins, child)
		end
	end

	-- Пропеллеры на Губерах (вращаются прямо на модели; анимируем через поиск в Workspace)
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function(dt: number)
		local t = os.clock()

		for _, b in ipairs(bobbers) do
			if b.Part.Parent then
				if b.Kind == "BobSpin" then
					local bob = math.sin(t * b.Speed + b.Phase) * b.Amp
					b.Part.Position = Vector3.new(b.Part.Position.X, b.BaseY + bob, b.Part.Position.Z)
					b.Part.Orientation += Vector3.new(0, dt * 28, 0)
				elseif b.Kind == "CloudDrift" then
					b.Part.Position = Vector3.new(
						b.Part.Position.X,
						b.BaseY + math.sin(t * b.Speed + b.Phase) * b.Amp,
						b.Part.Position.Z
					)
				end
			end
		end

		for _, torus in ipairs(ringSpins) do
			if torus.Parent then
				torus.Orientation += Vector3.new(0, dt * 52, 0)
			end
		end

		-- Вращение лопастей пропеллера на всех активных Губерах
		for _, model in ipairs(Workspace:GetDescendants()) do
			if model:IsA("BasePart") and (model.Name == "PropellerBladeA" or model.Name == "PropellerBladeB") then
				-- Лопасти — WeldConstraint к телу, поворачиваем через CFrame
				-- Находим тело Губера (родительская модель, а лопасть — в модели)
				local parentModel = model.Parent
				if parentModel and parentModel:IsA("Model") and parentModel.PrimaryPart then
					local body = parentModel.PrimaryPart :: BasePart
					local isA = model.Name == "PropellerBladeA"
					local spin = t * 18
					local yOff = isA and 0.21 or 0.21
					local d = math.max(body.Size.X, body.Size.Y, body.Size.Z)
					-- Перезаписываем CFrame лопасти относительно тела
					model.CFrame = body.CFrame * CFrame.new(0, d * yOff, 0) * CFrame.Angles(0, spin + (isA and 0 or math.pi * 0.5), 0)
				end
			end
		end
	end)
end)

print("[YEET A GOOBER! MUTATIONS] Клиент запущен: Мастерская, камера и управление готовы!")
