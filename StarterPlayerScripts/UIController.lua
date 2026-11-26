--!strict
--[[
	UIController.lua
	100% программная сборка адаптивного мобильного и ПК интерфейса (ScreenGui):
	- Верхний HUD: монеты, пассивный доход/сек, уровень Ботинка, вес и мутация Губера в руках.
	- Нижняя панель действий: Вырастить (таймер 5с / Взять), Рюкзак, База (4 пьедестала), Магазин, На гору.
	- Шкала заряда пинка (0–100%) с зелёной зоной PERFECT YEET (85–95%, x3) + мобильная кнопка удержания.
	- Панель полёта (дистанция, комбо, кнопки Jetpack Steering).
	- Окно выбора после приземления: «Забрать монеты» ИЛИ «Поставить на базу (1..4 пьедестал)».
	- Окно магазина: прокачка Ботинка за монеты + Game Pass'ы (Meme Sound Pack, Jetpack Steering).
	- Всплывающие уведомления.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))

local UIController = {}

local LocalPlayer = Players.LocalPlayer

export type ClientState = {
	Coins: number,
	BootLevel: number,
	BestDistance: number,
	Inventory: { GooberConfig.GooberData },
	Pedestals: { [string]: GooberConfig.GooberData? },
	OwnedPasses: {
		MemeSoundPack: boolean,
		JetpackSteering: boolean,
	},
	HeldGoober: GooberConfig.GooberData?,
	IsIncubating: boolean,
	IncubateRemaining: number,
	ReadyGoober: GooberConfig.GooberData?,
	PassiveIncome: number,
}

local CurrentState: ClientState = {
	Coins = 0,
	BootLevel = 1,
	BestDistance = 0,
	Inventory = {},
	Pedestals = {},
	OwnedPasses = {
		MemeSoundPack = false,
		JetpackSteering = false,
	},
	HeldGoober = nil,
	IsIncubating = false,
	IncubateRemaining = 0,
	ReadyGoober = nil,
	PassiveIncome = 0,
}

local StateListeners: { (ClientState) -> () } = {}
local KickButtonHoldCallbacks: {
	OnPress: (() -> ())?,
	OnRelease: (() -> ())?,
} = {}
local SteerCallback: ((string) -> ())? = nil
local SkipCameraCallback: (() -> ())? = nil

-- Ссылки на ключевые UI-элементы
local screenGui: ScreenGui
local coinsLabel: TextLabel
local incomeLabel: TextLabel
local bootBadgeLabel: TextLabel
local heldStatusLabel: TextLabel
local incubateBtn: TextButton
local inventoryBtn: TextButton
local toastContainer: Frame

-- Панель заряда пинка
local chargeContainer: Frame
local chargeFill: Frame
local chargeValueLabel: TextLabel
local cliffHintLabel: TextLabel
local mobileKickHoldBtn: TextButton
local perfectBannerLabel: TextLabel

-- Панель полёта
local flightPanel: Frame
local flightDistLabel: TextLabel
local flightComboLabel: TextLabel
local flightPerfectLabel: TextLabel
local jetpackControlsFrame: Frame

-- Модальные окна
local shopModal: Frame
local shopBootInfoLabel: TextLabel
local shopUpgradeBtn: TextButton
local memePassBtn: TextButton
local jetpackPassBtn: TextButton

local baseModal: Frame
local baseSlotsContainer: Frame

local inventoryModal: Frame
local inventoryScroll: ScrollingFrame

local landingModal: Frame
local landingTitleLabel: TextLabel
local landingDetailsLabel: TextLabel
local claimCoinsBtn: TextButton
local placeBestSlotBtn: TextButton
local landingSlotsRow: Frame

local incubateTimerToken = 0
local initialized = false

--============================================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ СОЗДАНИЯ UI
--============================================================================

local function formatNumber(n: number): string
	local str = tostring(math.floor(n + 0.5))
	local formatted = str:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	if formatted:sub(1, 1) == " " then
		formatted = formatted:sub(2)
	end
	return formatted
end

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

local function addTextConstraint(label: GuiObject, maxTextSize: number, minTextSize: number?)
	local tc = Instance.new("UITextSizeConstraint")
	tc.MaxTextSize = maxTextSize
	tc.MinTextSize = minTextSize or 9
	tc.Parent = label
end

local function makeButton(
	name: string,
	text: string,
	bgColor: Color3,
	size: UDim2,
	parent: Instance
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = size
	btn.BackgroundColor3 = bgColor
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextScaled = true
	btn.Text = text
	btn.Parent = parent
	addCorner(btn, 10)
	addStroke(btn, Color3.fromRGB(255, 255, 255), 1.5, 0.7)
	addTextConstraint(btn, 18, 10)
	return btn
end

local function makeModalFrame(name: string, title: string, size: UDim2, parent: Instance): (Frame, Frame)
	local modal = Instance.new("Frame")
	modal.Name = name
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = size
	modal.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
	modal.Visible = false
	modal.ZIndex = 20
	modal.Parent = parent
	addCorner(modal, 14)
	addStroke(modal, Color3.fromRGB(95, 165, 255), 2, 0.2)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(540, 400)
	sizeConstraint.MinSize = Vector2.new(280, 220)
	sizeConstraint.Parent = modal

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 42)
	header.BackgroundColor3 = Color3.fromRGB(36, 44, 62)
	header.ZIndex = 21
	header.Parent = modal
	addCorner(header, 14)

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -52, 1, 0)
	titleLbl.Position = UDim2.fromOffset(14, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextColor3 = Color3.new(1, 1, 1)
	titleLbl.TextScaled = true
	titleLbl.Text = title
	titleLbl.ZIndex = 22
	titleLbl.Parent = header
	addTextConstraint(titleLbl, 20, 12)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(30, 30)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 65, 75)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextSize = 16
	closeBtn.Text = "✕"
	closeBtn.ZIndex = 22
	closeBtn.Parent = header
	addCorner(closeBtn, 8)

	closeBtn.Activated:Connect(function()
		modal.Visible = false
	end)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(12, 48)
	content.Size = UDim2.new(1, -24, 1, -58)
	content.BackgroundTransparency = 1
	content.ZIndex = 21
	content.Parent = modal

	return modal, content
end

local function closeAllModalsExcept(keep: Frame?)
	for _, m in ipairs({ shopModal, baseModal, inventoryModal }) do
		if m and m ~= keep then
			m.Visible = false
		end
	end
end

--============================================================================
-- УВЕДОМЛЕНИЯ (TOASTS)
--============================================================================

function UIController.ShowToast(message: string, kind: string?)
	if not toastContainer then
		return
	end

	local colorMap: { [string]: Color3 } = {
		info = Color3.fromRGB(45, 130, 235),
		success = Color3.fromRGB(40, 185, 105),
		warn = Color3.fromRGB(230, 140, 40),
		rare = Color3.fromRGB(165, 65, 245),
	}
	local accent = colorMap[kind or "info"] or colorMap.info

	local item = Instance.new("Frame")
	item.Size = UDim2.new(1, 0, 0, 36)
	item.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
	item.BackgroundTransparency = 0.1
	item.ZIndex = 40
	item.Parent = toastContainer
	addCorner(item, 9)
	addStroke(item, accent, 2, 0.1)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, -6)
	lbl.Position = UDim2.fromOffset(8, 3)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextScaled = true
	lbl.Text = message
	lbl.ZIndex = 41
	lbl.Parent = item
	addTextConstraint(lbl, 16, 10)

	task.delay(3.2, function()
		if not item or not item.Parent then
			return
		end
		local fade = TweenService:Create(item, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
		local txtFade = TweenService:Create(lbl, TweenInfo.new(0.35), { TextTransparency = 1 })
		fade:Play()
		txtFade:Play()
		fade.Completed:Connect(function()
			if item and item.Parent then
				item:Destroy()
			end
		end)
	end)
end

--============================================================================
-- ОБНОВЛЕНИЕ СОДЕРЖИМОГО МОДАЛЬНЫХ ОКОН И HUD
--============================================================================

local function refreshShopUI(_remotes: Folder)
	if not shopBootInfoLabel then
		return
	end
	local lvl = CurrentState.BootLevel
	local curMult = GooberConfig.GetBootPowerMultiplier(lvl)
	local nextMult = GooberConfig.GetBootPowerMultiplier(lvl + 1)
	local cost = GooberConfig.GetBootUpgradeCost(lvl)
	local curTitle = GooberConfig.GetBootTitle(lvl)
	local nextTitle = GooberConfig.GetBootTitle(lvl + 1)

	shopBootInfoLabel.Text = string.format(
		"👟 Сейчас: %s (Ур. %d • Сила x%.2f)\n➡️ След.: %s (Ур. %d • Сила x%.2f)",
		curTitle,
		lvl,
		curMult,
		nextTitle,
		lvl + 1,
		nextMult
	)
	shopUpgradeBtn.Text = string.format("Улучшить за %s 🪙", formatNumber(cost))
	shopUpgradeBtn.BackgroundColor3 = if CurrentState.Coins >= cost
		then Color3.fromRGB(45, 195, 105)
		else Color3.fromRGB(110, 115, 130)

	if CurrentState.OwnedPasses.MemeSoundPack then
		memePassBtn.Text = "✅ КУПЛЕНО"
		memePassBtn.BackgroundColor3 = Color3.fromRGB(50, 165, 95)
	else
		memePassBtn.Text = "Купить Game Pass"
		memePassBtn.BackgroundColor3 = Color3.fromRGB(145, 70, 245)
	end

	if CurrentState.OwnedPasses.JetpackSteering then
		jetpackPassBtn.Text = "✅ КУПЛЕНО"
		jetpackPassBtn.BackgroundColor3 = Color3.fromRGB(50, 165, 95)
	else
		jetpackPassBtn.Text = "Купить Game Pass"
		jetpackPassBtn.BackgroundColor3 = Color3.fromRGB(55, 155, 245)
	end
end

local function refreshBaseModalUI(remotes: Folder)
	if not baseSlotsContainer then
		return
	end
	for _, child in ipairs(baseSlotsContainer:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local manageRemote = remotes:WaitForChild(RemoteNames.ManagePedestal) :: RemoteEvent

	for slot = 1, GooberConfig.PEDESTAL_COUNT do
		local goober = CurrentState.Pedestals[tostring(slot)]
		local card = Instance.new("Frame")
		card.Name = "SlotCard_" .. tostring(slot)
		card.BackgroundColor3 = Color3.fromRGB(34, 40, 56)
		card.ZIndex = 22
		card.Parent = baseSlotsContainer
		addCorner(card, 10)
		addStroke(card, Color3.fromRGB(85, 145, 220), 1.2, 0.4)

		local slotHeader = Instance.new("TextLabel")
		slotHeader.Position = UDim2.fromOffset(8, 6)
		slotHeader.Size = UDim2.new(1, -16, 0, 22)
		slotHeader.BackgroundTransparency = 1
		slotHeader.Font = Enum.Font.GothamBlack
		slotHeader.TextColor3 = Color3.fromRGB(130, 215, 255)
		slotHeader.TextScaled = true
		slotHeader.Text = "Пьедестал #" .. tostring(slot)
		slotHeader.ZIndex = 23
		slotHeader.Parent = card
		addTextConstraint(slotHeader, 15, 10)

		local infoLbl = Instance.new("TextLabel")
		infoLbl.Position = UDim2.fromOffset(8, 30)
		infoLbl.Size = UDim2.new(1, -16, 1, -72)
		infoLbl.BackgroundTransparency = 1
		infoLbl.Font = Enum.Font.GothamMedium
		infoLbl.TextColor3 = Color3.new(1, 1, 1)
		infoLbl.TextScaled = true
		infoLbl.ZIndex = 23
		infoLbl.Parent = card
		addTextConstraint(infoLbl, 14, 9)

		if goober then
			local sp = GooberConfig.Species[goober.SpeciesId] or GooberConfig.Species.Slimey
			local mut = GooberConfig.Mutations[goober.MutationId] or GooberConfig.Mutations.Normal
			local inc = GooberConfig.CalculatePassiveIncome(goober)
			infoLbl.Text = string.format("%s (%.1f кг)\n[%s]\n+%d 🪙/сек", sp.Name, goober.Weight, mut.Name, inc)

			local unequipBtn = makeButton(
				"UnequipBtn",
				"Снять в руки",
				Color3.fromRGB(215, 120, 50),
				UDim2.new(1, -16, 0, 30),
				card
			)
			unequipBtn.Position = UDim2.new(0, 8, 1, -36)
			unequipBtn.ZIndex = 23
			unequipBtn.Activated:Connect(function()
				manageRemote:FireServer("UnequipSlot", slot)
			end)
		else
			infoLbl.Text = "Пустой слот\n(0 🪙/сек)"
			local placeHeldBtn = makeButton(
				"PlaceHeldBtn",
				"Поставить из рук",
				Color3.fromRGB(45, 175, 105),
				UDim2.new(1, -16, 0, 30),
				card
			)
			placeHeldBtn.Position = UDim2.new(0, 8, 1, -36)
			placeHeldBtn.ZIndex = 23
			placeHeldBtn.Activated:Connect(function()
				manageRemote:FireServer("PlaceHeld", slot)
			end)
		end
	end
end

local function refreshInventoryModalUI(remotes: Folder)
	if not inventoryScroll then
		return
	end
	for _, child in ipairs(inventoryScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local equipRemote = remotes:WaitForChild(RemoteNames.EquipInventoryGoober) :: RemoteEvent
	local manageRemote = remotes:WaitForChild(RemoteNames.ManagePedestal) :: RemoteEvent

	for idx, goober in ipairs(CurrentState.Inventory) do
		local sp = GooberConfig.Species[goober.SpeciesId] or GooberConfig.Species.Slimey
		local mut = GooberConfig.Mutations[goober.MutationId] or GooberConfig.Mutations.Normal
		local inc = GooberConfig.CalculatePassiveIncome(goober)

		local row = Instance.new("Frame")
		row.Name = "InvItem_" .. tostring(idx)
		row.Size = UDim2.new(1, -8, 0, 52)
		row.BackgroundColor3 = Color3.fromRGB(34, 40, 56)
		row.ZIndex = 22
		row.Parent = inventoryScroll
		addCorner(row, 8)

		local lbl = Instance.new("TextLabel")
		lbl.Position = UDim2.fromOffset(10, 4)
		lbl.Size = UDim2.new(0.54, -12, 1, -8)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextColor3 = sp.IsRareGuest and Color3.fromRGB(255, 215, 75) or Color3.new(1, 1, 1)
		lbl.TextScaled = true
		lbl.Text = string.format("%s • %.1f кг\n[%s] (+%d 🪙/с)", sp.Name, goober.Weight, mut.Name, inc)
		lbl.ZIndex = 23
		lbl.Parent = row
		addTextConstraint(lbl, 14, 9)

		local takeBtn = makeButton("TakeBtn", "В руки", Color3.fromRGB(50, 155, 240), UDim2.new(0.21, -4, 0, 36), row)
		takeBtn.Position = UDim2.new(0.55, 0, 0.5, -18)
		takeBtn.ZIndex = 23
		takeBtn.Activated:Connect(function()
			equipRemote:FireServer(goober.Id)
			inventoryModal.Visible = false
		end)

		local baseBtn = makeButton("BaseBtn", "На базу", Color3.fromRGB(45, 185, 105), UDim2.new(0.22, -6, 0, 36), row)
		baseBtn.Position = UDim2.new(0.77, 2, 0.5, -18)
		baseBtn.ZIndex = 23
		baseBtn.Activated:Connect(function()
			manageRemote:FireServer("PlaceFromInventory", goober.Id)
		end)
	end

	local listLayout = inventoryScroll:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		inventoryScroll.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 12)
	end
end

local function refreshHUD(remotes: Folder)
	if not coinsLabel then
		return
	end

	coinsLabel.Text = string.format("🪙 %s", formatNumber(CurrentState.Coins))
	incomeLabel.Text = string.format("Пассив: +%s 🪙/сек", formatNumber(CurrentState.PassiveIncome))

	local mult = GooberConfig.GetBootPowerMultiplier(CurrentState.BootLevel)
	bootBadgeLabel.Text = string.format("👟 Ботинок Ур. %d (x%.2f)", CurrentState.BootLevel, mult)

	if CurrentState.HeldGoober then
		local held = CurrentState.HeldGoober
		local sp = GooberConfig.Species[held.SpeciesId] or GooberConfig.Species.Slimey
		local mut = GooberConfig.Mutations[held.MutationId] or GooberConfig.Mutations.Normal
		heldStatusLabel.Text = string.format("🤲 В руках: %s • ⚖️ %.1f кг • [%s]", sp.Name, held.Weight, mut.Name)
		heldStatusLabel.TextColor3 = mut.BadgeColor
	else
		heldStatusLabel.Text = "🤲 Руки пусты — нажми «Вырастить»!"
		heldStatusLabel.TextColor3 = Color3.fromRGB(200, 210, 225)
	end

	inventoryBtn.Text = string.format("🎒 Рюкзак (%d)", #CurrentState.Inventory)

	-- Кнопка инкубатора: Вырастить / Таймер 5с / Взять готового Губера
	incubateTimerToken += 1
	local myToken = incubateTimerToken

	if CurrentState.ReadyGoober then
		local readySp = GooberConfig.Species[CurrentState.ReadyGoober.SpeciesId] or GooberConfig.Species.Slimey
		incubateBtn.Text = string.format("🤲 Взять: %s!", readySp.Name)
		incubateBtn.BackgroundColor3 = Color3.fromRGB(40, 210, 105)
	elseif CurrentState.IsIncubating and CurrentState.IncubateRemaining > 0 then
		incubateBtn.BackgroundColor3 = Color3.fromRGB(220, 145, 40)
		local endClock = os.clock() + CurrentState.IncubateRemaining
		task.spawn(function()
			while myToken == incubateTimerToken do
				local rem = math.max(0, endClock - os.clock())
				if incubateBtn and incubateBtn.Parent then
					incubateBtn.Text = string.format("⏳ Растёт: %.1fс", rem)
				end
				if rem <= 0 then
					break
				end
				task.wait(0.1)
			end
		end)
	else
		incubateBtn.Text = "🥚 Вырастить (5с)"
		incubateBtn.BackgroundColor3 = Color3.fromRGB(55, 165, 250)
	end

	-- Обновляем видимость шкалы пинка (показываем, когда в руках есть Губер и не открыт полёт)
	if chargeContainer and not flightPanel.Visible and not landingModal.Visible then
		chargeContainer.Visible = (CurrentState.HeldGoober ~= nil)
	end

	refreshShopUI(remotes)
	refreshBaseModalUI(remotes)
	refreshInventoryModalUI(remotes)
end

--============================================================================
-- ПУБЛИЧНЫЕ МЕТОДЫ ДЛЯ KICKCONTROLLER
--============================================================================

function UIController.GetState(): ClientState
	return CurrentState
end

function UIController.OnStateChanged(callback: (ClientState) -> ())
	table.insert(StateListeners, callback)
end

function UIController.BindKickHoldButton(onPress: () -> (), onRelease: () -> ())
	KickButtonHoldCallbacks.OnPress = onPress
	KickButtonHoldCallbacks.OnRelease = onRelease
end

function UIController.BindFlightControls(onSteer: (string) -> (), onSkipCamera: () -> ())
	SteerCallback = onSteer
	SkipCameraCallback = onSkipCamera
end

function UIController.UpdateChargeDisplay(chargePercent: number, isNearCliff: boolean, isCharging: boolean)
	if not chargeContainer then
		return
	end

	local hasGoober = CurrentState.HeldGoober ~= nil
	if not hasGoober or flightPanel.Visible or landingModal.Visible then
		chargeContainer.Visible = false
		return
	end

	chargeContainer.Visible = true
	local clamped = math.clamp(chargePercent, 0, 100)
	chargeFill.Size = UDim2.fromScale(1, clamped / 100.0)

	if clamped >= 85 and clamped <= 95 then
		chargeFill.BackgroundColor3 = Color3.fromRGB(65, 255, 120)
	elseif clamped > 95 then
		chargeFill.BackgroundColor3 = Color3.fromRGB(255, 90, 75)
	else
		chargeFill.BackgroundColor3 = Color3.fromRGB(255, 200, 55)
	end

	if isCharging then
		chargeValueLabel.Text = string.format("%d%%", math.floor(clamped + 0.5))
	else
		chargeValueLabel.Text = "0%"
	end

	if isNearCliff then
		cliffHintLabel.Text = "🔥 ЗАЖМИ ЛКМ / ЭКРАН И ОТПУСТИ В ЗЕЛЁНОЙ ЗОНЕ!"
		cliffHintLabel.TextColor3 = Color3.fromRGB(100, 255, 145)
		mobileKickHoldBtn.Visible = true
	else
		cliffHintLabel.Text = "⬆️ Подойди к жёлтой полосе у края обрыва!"
		cliffHintLabel.TextColor3 = Color3.fromRGB(255, 220, 95)
		mobileKickHoldBtn.Visible = false
	end
end

function UIController.FlashPerfectYeet()
	if not perfectBannerLabel then
		return
	end
	perfectBannerLabel.Visible = true
	perfectBannerLabel.TextTransparency = 0
	task.delay(1.8, function()
		if perfectBannerLabel and perfectBannerLabel.Parent then
			perfectBannerLabel.Visible = false
		end
	end)
end

function UIController.SetFlightHUD(visible: boolean, distance: number?, combo: number?, isPerfect: boolean?)
	if not flightPanel then
		return
	end
	flightPanel.Visible = visible
	if visible then
		chargeContainer.Visible = false
		closeAllModalsExcept(nil)
		flightDistLabel.Text = string.format("📏 Дистанция: %d м", math.floor(distance or 0))
		flightComboLabel.Text = string.format("🔥 КОМБО: x%.2f", combo or 1.0)
		flightPerfectLabel.Visible = isPerfect == true
		jetpackControlsFrame.Visible = CurrentState.OwnedPasses.JetpackSteering == true
	end
end

function UIController.ShowLandingDecision(summary: any, remotes: Folder)
	if not landingModal then
		return
	end
	flightPanel.Visible = false
	chargeContainer.Visible = false
	closeAllModalsExcept(nil)

	local goober: GooberConfig.GooberData = summary.GooberData
	local sp = GooberConfig.Species[goober.SpeciesId] or GooberConfig.Species.Slimey
	local mut = GooberConfig.Mutations[goober.MutationId] or GooberConfig.Mutations.Normal
	local coins = tonumber(summary.RewardCoins) or 1
	local passive = tonumber(summary.PassiveIncome) or 1
	local dist = tonumber(summary.Distance) or 1
	local combo = tonumber(summary.ComboMultiplier) or 1
	local perf = tonumber(summary.PerfectMultiplier) or 1

	landingTitleLabel.Text = string.format("🏁 ПРИЗЕМЛЕНИЕ: %d м!", dist)
	landingDetailsLabel.Text = string.format(
		"%s • %.1f кг • Мутация: %s\nКомбо: x%.2f %s",
		sp.Name,
		goober.Weight,
		mut.Name,
		combo,
		perf > 1 and "• 🔥 PERFECT YEET (x3)!" or ""
	)

	claimCoinsBtn.Text = string.format("💰 Забрать +%s 🪙", formatNumber(coins))
	placeBestSlotBtn.Text = string.format("🏆 На лучший пьедестал (+%s 🪙/сек)", formatNumber(passive))

	-- Обновляем 4 кнопки быстрого выбора конкретного пьедестала
	for _, child in ipairs(landingSlotsRow:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local decisionRemote = remotes:WaitForChild(RemoteNames.LandingDecision) :: RemoteEvent
	for slot = 1, GooberConfig.PEDESTAL_COUNT do
		local cur = CurrentState.Pedestals[tostring(slot)]
		local curInc = cur and GooberConfig.CalculatePassiveIncome(cur) or 0
		local slotBtn = makeButton(
			"PickSlot_" .. tostring(slot),
			cur and string.format("Слот #%d (%d/с)", slot, curInc) or string.format("Слот #%d (Пусто)", slot),
			Color3.fromRGB(50, 95, 165),
			UDim2.new(0.25, -6, 1, 0),
			landingSlotsRow
		)
		slotBtn.ZIndex = 32
		slotBtn.Activated:Connect(function()
			landingModal.Visible = false
			decisionRemote:FireServer("PlaceOnBase", slot)
		end)
	end

	landingModal.Visible = true
end

--============================================================================
-- ИНИЦИАЛИЗАЦИЯ И СБОРКА ВСЕГО ИНТЕРФЕЙСА
--============================================================================

function UIController.Init()
	if initialized then
		return
	end
	initialized = true

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local remotes = ReplicatedStorage:WaitForChild(RemoteNames.FolderName)

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "YeetAGooberHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- 1. ВЕРХНИЙ HUD (Монеты, Ботинок, Текущий Губер в руках)
	local topBar = Instance.new("Frame")
	topBar.Name = "TopHUD"
	topBar.AnchorPoint = Vector2.new(0.5, 0)
	topBar.Position = UDim2.new(0.5, 0, 0, 8)
	topBar.Size = UDim2.new(0.94, 0, 0, 58)
	topBar.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
	topBar.BackgroundTransparency = 0.12
	topBar.Parent = screenGui
	addCorner(topBar, 12)
	addStroke(topBar, Color3.fromRGB(80, 145, 235), 1.5, 0.45)

	local topMax = Instance.new("UISizeConstraint")
	topMax.MaxSize = Vector2.new(760, 64)
	topMax.Parent = topBar

	coinsLabel = Instance.new("TextLabel")
	coinsLabel.Position = UDim2.fromOffset(12, 5)
	coinsLabel.Size = UDim2.new(0.30, -12, 0, 28)
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Font = Enum.Font.GothamBlack
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinsLabel.TextColor3 = Color3.fromRGB(255, 220, 65)
	coinsLabel.TextScaled = true
	coinsLabel.Text = "🪙 0"
	coinsLabel.Parent = topBar
	addTextConstraint(coinsLabel, 20, 11)

	incomeLabel = Instance.new("TextLabel")
	incomeLabel.Position = UDim2.fromOffset(12, 33)
	incomeLabel.Size = UDim2.new(0.30, -12, 0, 20)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Font = Enum.Font.GothamMedium
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	incomeLabel.TextColor3 = Color3.fromRGB(115, 240, 165)
	incomeLabel.TextScaled = true
	incomeLabel.Text = "Пассив: +0 🪙/сек"
	incomeLabel.Parent = topBar
	addTextConstraint(incomeLabel, 13, 9)

	bootBadgeLabel = Instance.new("TextLabel")
	bootBadgeLabel.Position = UDim2.new(0.31, 4, 0, 5)
	bootBadgeLabel.Size = UDim2.new(0.68, -16, 0, 22)
	bootBadgeLabel.BackgroundTransparency = 1
	bootBadgeLabel.Font = Enum.Font.GothamBold
	bootBadgeLabel.TextXAlignment = Enum.TextXAlignment.Right
	bootBadgeLabel.TextColor3 = Color3.fromRGB(135, 205, 255)
	bootBadgeLabel.TextScaled = true
	bootBadgeLabel.Text = "👟 Ботинок Ур. 1 (x1.00)"
	bootBadgeLabel.Parent = topBar
	addTextConstraint(bootBadgeLabel, 15, 9)

	heldStatusLabel = Instance.new("TextLabel")
	heldStatusLabel.Position = UDim2.new(0.31, 4, 0, 29)
	heldStatusLabel.Size = UDim2.new(0.68, -16, 0, 24)
	heldStatusLabel.BackgroundTransparency = 1
	heldStatusLabel.Font = Enum.Font.GothamBold
	heldStatusLabel.TextXAlignment = Enum.TextXAlignment.Right
	heldStatusLabel.TextColor3 = Color3.fromRGB(200, 210, 225)
	heldStatusLabel.TextScaled = true
	heldStatusLabel.Text = "🤲 Руки пусты — нажми «Вырастить»!"
	heldStatusLabel.Parent = topBar
	addTextConstraint(heldStatusLabel, 15, 9)

	-- 2. СТЕК УВЕДОМЛЕНИЙ
	toastContainer = Instance.new("Frame")
	toastContainer.Name = "ToastContainer"
	toastContainer.AnchorPoint = Vector2.new(0.5, 0)
	toastContainer.Position = UDim2.new(0.5, 0, 0, 74)
	toastContainer.Size = UDim2.new(0.86, 0, 0, 130)
	toastContainer.BackgroundTransparency = 1
	toastContainer.ZIndex = 40
	toastContainer.Parent = screenGui

	local toastMax = Instance.new("UISizeConstraint")
	toastMax.MaxSize = Vector2.new(500, 140)
	toastMax.Parent = toastContainer

	local toastLayout = Instance.new("UIListLayout")
	toastLayout.Padding = UDim.new(0, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Parent = toastContainer

	-- БАННЕР PERFECT YEET
	perfectBannerLabel = Instance.new("TextLabel")
	perfectBannerLabel.Name = "PerfectBanner"
	perfectBannerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	perfectBannerLabel.Position = UDim2.fromScale(0.5, 0.28)
	perfectBannerLabel.Size = UDim2.new(0.75, 0, 0, 56)
	perfectBannerLabel.BackgroundTransparency = 1
	perfectBannerLabel.Font = Enum.Font.GothamBlack
	perfectBannerLabel.TextColor3 = Color3.fromRGB(90, 255, 130)
	perfectBannerLabel.TextStrokeTransparency = 0
	perfectBannerLabel.TextScaled = true
	perfectBannerLabel.Text = "🔥 PERFECT YEET! (x3) 🔥"
	perfectBannerLabel.Visible = false
	perfectBannerLabel.ZIndex = 35
	perfectBannerLabel.Parent = screenGui
	addTextConstraint(perfectBannerLabel, 38, 16)

	-- 3. НИЖНЯЯ ЦЕНТРАЛЬНАЯ ПАНЕЛЬ КНОПОК (не перекрывает мобильный джойстик и прыжок!)
	local bottomDock = Instance.new("Frame")
	bottomDock.Name = "ActionDock"
	bottomDock.AnchorPoint = Vector2.new(0.5, 1)
	bottomDock.Position = UDim2.new(0.5, 0, 1, -10)
	bottomDock.Size = UDim2.new(0.58, 0, 0, 48)
	bottomDock.BackgroundTransparency = 1
	bottomDock.Parent = screenGui

	local dockMax = Instance.new("UISizeConstraint")
	dockMax.MaxSize = Vector2.new(560, 52)
	dockMax.MinSize = Vector2.new(290, 42)
	dockMax.Parent = bottomDock

	local dockLayout = Instance.new("UIListLayout")
	dockLayout.FillDirection = Enum.FillDirection.Horizontal
	dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dockLayout.Padding = UDim.new(0, 6)
	dockLayout.Parent = bottomDock

	incubateBtn = makeButton("IncubateBtn", "🥚 Вырастить (5с)", Color3.fromRGB(55, 165, 250), UDim2.new(0.28, -4, 1, 0), bottomDock)
	inventoryBtn = makeButton("InventoryBtn", "🎒 Рюкзак (0)", Color3.fromRGB(85, 95, 145), UDim2.new(0.20, -4, 1, 0), bottomDock)
	local baseBtn = makeButton("BaseBtn", "🏠 База", Color3.fromRGB(45, 170, 120), UDim2.new(0.17, -4, 1, 0), bottomDock)
	local shopBtn = makeButton("ShopBtn", "🛒 Магазин", Color3.fromRGB(220, 130, 40), UDim2.new(0.19, -4, 1, 0), bottomDock)
	local tpBtn = makeButton("SummitTpBtn", "⛰️ Обрыв", Color3.fromRGB(125, 85, 220), UDim2.new(0.16, -4, 1, 0), bottomDock)

	local reqIncubate = remotes:WaitForChild(RemoteNames.RequestIncubate) :: RemoteEvent
	local reqPickup = remotes:WaitForChild(RemoteNames.PickupIncubatedGoober) :: RemoteEvent
	local tpRemote = remotes:WaitForChild(RemoteNames.TeleportRequest) :: RemoteEvent

	incubateBtn.Activated:Connect(function()
		if CurrentState.ReadyGoober then
			reqPickup:FireServer()
		else
			reqIncubate:FireServer()
		end
	end)

	inventoryBtn.Activated:Connect(function()
		closeAllModalsExcept(inventoryModal)
		inventoryModal.Visible = not inventoryModal.Visible
		refreshInventoryModalUI(remotes)
	end)

	baseBtn.Activated:Connect(function()
		closeAllModalsExcept(baseModal)
		baseModal.Visible = not baseModal.Visible
		refreshBaseModalUI(remotes)
	end)

	shopBtn.Activated:Connect(function()
		closeAllModalsExcept(shopModal)
		shopModal.Visible = not shopModal.Visible
		refreshShopUI(remotes)
	end)

	tpBtn.Activated:Connect(function()
		tpRemote:FireServer("Summit")
	end)

	-- 4. ШКАЛА ЗАРЯДА ПИНКА (0–100%, зелёная зона 85–95%)
	chargeContainer = Instance.new("Frame")
	chargeContainer.Name = "ChargeContainer"
	chargeContainer.AnchorPoint = Vector2.new(1, 0.5)
	chargeContainer.Position = UDim2.new(1, -16, 0.44, 0)
	chargeContainer.Size = UDim2.fromOffset(142, 220)
	chargeContainer.BackgroundTransparency = 1
	chargeContainer.Visible = false
	chargeContainer.Parent = screenGui

	cliffHintLabel = Instance.new("TextLabel")
	cliffHintLabel.AnchorPoint = Vector2.new(0.5, 1)
	cliffHintLabel.Position = UDim2.new(0.5, -30, 0, -6)
	cliffHintLabel.Size = UDim2.fromOffset(220, 36)
	cliffHintLabel.BackgroundTransparency = 1
	cliffHintLabel.Font = Enum.Font.GothamBlack
	cliffHintLabel.TextColor3 = Color3.fromRGB(255, 220, 95)
	cliffHintLabel.TextStrokeTransparency = 0.15
	cliffHintLabel.TextScaled = true
	cliffHintLabel.Text = "⬆️ Подойди к краю обрыва!"
	cliffHintLabel.Parent = chargeContainer
	addTextConstraint(cliffHintLabel, 15, 10)

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.AnchorPoint = Vector2.new(1, 0)
	barBg.Position = UDim2.new(1, 0, 0, 0)
	barBg.Size = UDim2.fromOffset(38, 190)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
	barBg.ClipsDescendants = true
	barBg.Parent = chargeContainer
	addCorner(barBg, 10)
	addStroke(barBg, Color3.new(1, 1, 1), 2, 0.35)

	-- Заполнение шкалы снизу вверх (0..100%)
	chargeFill = Instance.new("Frame")
	chargeFill.Name = "Fill"
	chargeFill.AnchorPoint = Vector2.new(0, 1)
	chargeFill.Position = UDim2.fromScale(0, 1)
	chargeFill.Size = UDim2.fromScale(1, 0)
	chargeFill.BackgroundColor3 = Color3.fromRGB(255, 200, 55)
	chargeFill.BorderSizePixel = 0
	chargeFill.ZIndex = 2
	chargeFill.Parent = barBg

	-- Зелёная зона 85%–95% (Y от 0.05 до 0.15 сверху!)
	local greenZone = Instance.new("Frame")
	greenZone.Name = "PerfectGreenZone"
	greenZone.Position = UDim2.fromScale(0, 0.05)
	greenZone.Size = UDim2.fromScale(1, 0.10)
	greenZone.BackgroundColor3 = Color3.fromRGB(50, 255, 110)
	greenZone.BackgroundTransparency = 0.25
	greenZone.BorderSizePixel = 0
	greenZone.ZIndex = 3
	greenZone.Parent = barBg

	local greenTag = Instance.new("TextLabel")
	greenTag.Size = UDim2.fromScale(1, 1)
	greenTag.BackgroundTransparency = 1
	greenTag.Font = Enum.Font.GothamBlack
	greenTag.TextColor3 = Color3.new(1, 1, 1)
	greenTag.TextStrokeTransparency = 0.1
	greenTag.TextScaled = true
	greenTag.Text = "x3"
	greenTag.ZIndex = 4
	greenTag.Parent = greenZone

	chargeValueLabel = Instance.new("TextLabel")
	chargeValueLabel.AnchorPoint = Vector2.new(1, 0)
	chargeValueLabel.Position = UDim2.new(1, 0, 0, 194)
	chargeValueLabel.Size = UDim2.fromOffset(38, 22)
	chargeValueLabel.BackgroundTransparency = 1
	chargeValueLabel.Font = Enum.Font.GothamBlack
	chargeValueLabel.TextColor3 = Color3.new(1, 1, 1)
	chargeValueLabel.TextStrokeTransparency = 0.2
	chargeValueLabel.TextScaled = true
	chargeValueLabel.Text = "0%"
	chargeValueLabel.Parent = chargeContainer

	-- Удобная мобильная кнопка удержания пинка прямо рядом со шкалой
	mobileKickHoldBtn = makeButton(
		"MobileKickHoldBtn",
		"🦵 ЗАЖМИ\nПИНОК!",
		Color3.fromRGB(245, 85, 55),
		UDim2.fromOffset(94, 82),
		chargeContainer
	)
	mobileKickHoldBtn.Position = UDim2.fromOffset(0, 56)
	mobileKickHoldBtn.Visible = false

	mobileKickHoldBtn.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if KickButtonHoldCallbacks.OnPress then
				KickButtonHoldCallbacks.OnPress()
			end
		end
	end)
	mobileKickHoldBtn.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if KickButtonHoldCallbacks.OnRelease then
				KickButtonHoldCallbacks.OnRelease()
			end
		end
	end)

	-- 5. ПАНЕЛЬ ПОЛЁТА (Дистанция, Комбо, Jetpack Steering)
	flightPanel = Instance.new("Frame")
	flightPanel.Name = "FlightHUD"
	flightPanel.AnchorPoint = Vector2.new(0.5, 0)
	flightPanel.Position = UDim2.new(0.5, 0, 0, 74)
	flightPanel.Size = UDim2.new(0.84, 0, 0, 118)
	flightPanel.BackgroundTransparency = 1
	flightPanel.Visible = false
	flightPanel.Parent = screenGui

	local flightMax = Instance.new("UISizeConstraint")
	flightMax.MaxSize = Vector2.new(440, 130)
	flightMax.Parent = flightPanel

	flightDistLabel = Instance.new("TextLabel")
	flightDistLabel.Size = UDim2.new(1, 0, 0, 30)
	flightDistLabel.BackgroundTransparency = 1
	flightDistLabel.Font = Enum.Font.GothamBlack
	flightDistLabel.TextColor3 = Color3.new(1, 1, 1)
	flightDistLabel.TextStrokeTransparency = 0.1
	flightDistLabel.TextScaled = true
	flightDistLabel.Text = "📏 Дистанция: 0 м"
	flightDistLabel.Parent = flightPanel
	addTextConstraint(flightDistLabel, 24, 12)

	flightComboLabel = Instance.new("TextLabel")
	flightComboLabel.Position = UDim2.fromOffset(0, 30)
	flightComboLabel.Size = UDim2.new(1, 0, 0, 28)
	flightComboLabel.BackgroundTransparency = 1
	flightComboLabel.Font = Enum.Font.GothamBlack
	flightComboLabel.TextColor3 = Color3.fromRGB(255, 215, 65)
	flightComboLabel.TextStrokeTransparency = 0.1
	flightComboLabel.TextScaled = true
	flightComboLabel.Text = "🔥 КОМБО: x1.00"
	flightComboLabel.Parent = flightPanel
	addTextConstraint(flightComboLabel, 22, 12)

	flightPerfectLabel = Instance.new("TextLabel")
	flightPerfectLabel.Position = UDim2.fromOffset(0, 58)
	flightPerfectLabel.Size = UDim2.new(1, 0, 0, 20)
	flightPerfectLabel.BackgroundTransparency = 1
	flightPerfectLabel.Font = Enum.Font.GothamBold
	flightPerfectLabel.TextColor3 = Color3.fromRGB(85, 255, 135)
	flightPerfectLabel.TextStrokeTransparency = 0.15
	flightPerfectLabel.TextScaled = true
	flightPerfectLabel.Text = "⚡ PERFECT YEET АКТИВЕН (x3)"
	flightPerfectLabel.Visible = false
	flightPerfectLabel.Parent = flightPanel

	jetpackControlsFrame = Instance.new("Frame")
	jetpackControlsFrame.Position = UDim2.fromOffset(0, 82)
	jetpackControlsFrame.Size = UDim2.new(1, 0, 0, 36)
	jetpackControlsFrame.BackgroundTransparency = 1
	jetpackControlsFrame.Visible = false
	jetpackControlsFrame.Parent = flightPanel

	local jpLayout = Instance.new("UIListLayout")
	jpLayout.FillDirection = Enum.FillDirection.Horizontal
	jpLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	jpLayout.Padding = UDim.new(0, 8)
	jpLayout.Parent = jetpackControlsFrame

	local steerLeftBtn = makeButton("SteerLeft", "◀ Влево (A)", Color3.fromRGB(55, 150, 240), UDim2.new(0.30, 0, 1, 0), jetpackControlsFrame)
	local steerBoostBtn = makeButton("SteerBoost", "🚀 Рывок (Space)", Color3.fromRGB(245, 125, 45), UDim2.new(0.35, 0, 1, 0), jetpackControlsFrame)
	local steerRightBtn = makeButton("SteerRight", "Вправо (D) ▶", Color3.fromRGB(55, 150, 240), UDim2.new(0.30, 0, 1, 0), jetpackControlsFrame)

	steerLeftBtn.Activated:Connect(function()
		if SteerCallback then
			SteerCallback("Left")
		end
	end)
	steerBoostBtn.Activated:Connect(function()
		if SteerCallback then
			SteerCallback("Boost")
		end
	end)
	steerRightBtn.Activated:Connect(function()
		if SteerCallback then
			SteerCallback("Right")
		end
	end)

	local skipCamBtn = makeButton("SkipCamBtn", "🎥 К себе", Color3.fromRGB(70, 80, 105), UDim2.fromOffset(92, 28), flightPanel)
	skipCamBtn.AnchorPoint = Vector2.new(1, 0)
	skipCamBtn.Position = UDim2.new(1, 0, 0, 0)
	skipCamBtn.Activated:Connect(function()
		if SkipCameraCallback then
			SkipCameraCallback()
		end
	end)

	-- 6. ОКНО МАГАЗИНА (Прокачка Ботинка + Game Pass'ы)
	local shopContent: Frame
	shopModal, shopContent = makeModalFrame("ShopModal", "🛒 МАГАЗИН И ПРОКАЧКА", UDim2.new(0.88, 0, 0.72, 0), screenGui)

	local bootCard = Instance.new("Frame")
	bootCard.Size = UDim2.new(1, 0, 0.36, -6)
	bootCard.BackgroundColor3 = Color3.fromRGB(34, 40, 56)
	bootCard.ZIndex = 22
	bootCard.Parent = shopContent
	addCorner(bootCard, 10)

	shopBootInfoLabel = Instance.new("TextLabel")
	shopBootInfoLabel.Position = UDim2.fromOffset(10, 6)
	shopBootInfoLabel.Size = UDim2.new(0.62, -14, 1, -12)
	shopBootInfoLabel.BackgroundTransparency = 1
	shopBootInfoLabel.Font = Enum.Font.GothamBold
	shopBootInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
	shopBootInfoLabel.TextColor3 = Color3.new(1, 1, 1)
	shopBootInfoLabel.TextScaled = true
	shopBootInfoLabel.ZIndex = 23
	shopBootInfoLabel.Parent = bootCard
	addTextConstraint(shopBootInfoLabel, 15, 9)

	shopUpgradeBtn = makeButton("UpgradeBootBtn", "Улучшить", Color3.fromRGB(45, 195, 105), UDim2.new(0.36, -10, 0, 42), bootCard)
	shopUpgradeBtn.AnchorPoint = Vector2.new(1, 0.5)
	shopUpgradeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	shopUpgradeBtn.ZIndex = 23

	local upgradeRemote = remotes:WaitForChild(RemoteNames.UpgradeBoot) :: RemoteEvent
	local passRemote = remotes:WaitForChild(RemoteNames.PromptGamePass) :: RemoteEvent

	shopUpgradeBtn.Activated:Connect(function()
		upgradeRemote:FireServer()
	end)

	-- Карточка Game Pass 1: Meme Sound Pack
	local memeCard = Instance.new("Frame")
	memeCard.Position = UDim2.new(0, 0, 0.38, 2)
	memeCard.Size = UDim2.new(1, 0, 0.29, -4)
	memeCard.BackgroundColor3 = Color3.fromRGB(38, 34, 58)
	memeCard.ZIndex = 22
	memeCard.Parent = shopContent
	addCorner(memeCard, 10)

	local memeLbl = Instance.new("TextLabel")
	memeLbl.Position = UDim2.fromOffset(10, 6)
	memeLbl.Size = UDim2.new(0.62, -14, 1, -12)
	memeLbl.BackgroundTransparency = 1
	memeLbl.Font = Enum.Font.GothamBold
	memeLbl.TextXAlignment = Enum.TextXAlignment.Left
	memeLbl.TextColor3 = Color3.fromRGB(230, 195, 255)
	memeLbl.TextScaled = true
	memeLbl.Text = "📯 Meme Sound Pack [Game Pass]\nМемная озвучка пинков и батутов!"
	memeLbl.ZIndex = 23
	memeLbl.Parent = memeCard
	addTextConstraint(memeLbl, 14, 9)

	memePassBtn = makeButton("BuyMemePassBtn", "Купить Game Pass", Color3.fromRGB(145, 70, 245), UDim2.new(0.36, -10, 0, 38), memeCard)
	memePassBtn.AnchorPoint = Vector2.new(1, 0.5)
	memePassBtn.Position = UDim2.new(1, -10, 0.5, 0)
	memePassBtn.ZIndex = 23
	memePassBtn.Activated:Connect(function()
		passRemote:FireServer("MemeSoundPack")
	end)

	-- Карточка Game Pass 2: Jetpack Steering
	local jpCard = Instance.new("Frame")
	jpCard.Position = UDim2.new(0, 0, 0.69, 4)
	jpCard.Size = UDim2.new(1, 0, 0.29, -4)
	jpCard.BackgroundColor3 = Color3.fromRGB(30, 44, 62)
	jpCard.ZIndex = 22
	jpCard.Parent = shopContent
	addCorner(jpCard, 10)

	local jpLbl = Instance.new("TextLabel")
	jpLbl.Position = UDim2.fromOffset(10, 6)
	jpLbl.Size = UDim2.new(0.62, -14, 1, -12)
	jpLbl.BackgroundTransparency = 1
	jpLbl.Font = Enum.Font.GothamBold
	jpLbl.TextXAlignment = Enum.TextXAlignment.Left
	jpLbl.TextColor3 = Color3.fromRGB(165, 225, 255)
	jpLbl.TextScaled = true
	jpLbl.Text = "🚀 Jetpack Steering [Game Pass]\nУправляй полётом Губера к кольцам!"
	jpLbl.ZIndex = 23
	jpLbl.Parent = jpCard
	addTextConstraint(jpLbl, 14, 9)

	jetpackPassBtn = makeButton("BuyJetpackPassBtn", "Купить Game Pass", Color3.fromRGB(55, 155, 245), UDim2.new(0.36, -10, 0, 38), jpCard)
	jetpackPassBtn.AnchorPoint = Vector2.new(1, 0.5)
	jetpackPassBtn.Position = UDim2.new(1, -10, 0.5, 0)
	jetpackPassBtn.ZIndex = 23
	jetpackPassBtn.Activated:Connect(function()
		passRemote:FireServer("JetpackSteering")
	end)

	-- 7. ОКНО БАЗЫ (4 ПЬЕДЕСТАЛА ПАССИВНОГО ДОХОДА)
	local baseContent: Frame
	baseModal, baseContent = makeModalFrame("BaseModal", "🏠 МОЯ БАЗА (4 ПЬЕДЕСТАЛА)", UDim2.new(0.88, 0, 0.72, 0), screenGui)

	baseSlotsContainer = Instance.new("Frame")
	baseSlotsContainer.Size = UDim2.new(1, 0, 1, -38)
	baseSlotsContainer.BackgroundTransparency = 1
	baseSlotsContainer.ZIndex = 22
	baseSlotsContainer.Parent = baseContent

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0.5, -6)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.Parent = baseSlotsContainer

	local tpBaseBtn = makeButton("TpToBaseBtn", "📍 Телепорт к моей базе", Color3.fromRGB(55, 145, 225), UDim2.new(1, 0, 0, 32), baseContent)
	tpBaseBtn.Position = UDim2.new(0, 0, 1, -32)
	tpBaseBtn.ZIndex = 22
	tpBaseBtn.Activated:Connect(function()
		baseModal.Visible = false
		tpRemote:FireServer("Base")
	end)

	-- 8. ОКНО ИНВЕНТАРЯ ГУБЕРОВ
	local invContent: Frame
	inventoryModal, invContent = makeModalFrame("InventoryModal", "🎒 РЮКЗАК ГУБЕРОВ", UDim2.new(0.88, 0, 0.72, 0), screenGui)

	inventoryScroll = Instance.new("ScrollingFrame")
	inventoryScroll.Size = UDim2.fromScale(1, 1)
	inventoryScroll.BackgroundTransparency = 1
	inventoryScroll.ScrollBarThickness = 6
	inventoryScroll.CanvasSize = UDim2.fromOffset(0, 0)
	inventoryScroll.ZIndex = 22
	inventoryScroll.Parent = invContent

	local invList = Instance.new("UIListLayout")
	invList.Padding = UDim.new(0, 6)
	invList.Parent = inventoryScroll

	-- 9. ОКНО ВЫБОРА ПОСЛЕ ПРИЗЕМЛЕНИЯ
	landingModal = Instance.new("Frame")
	landingModal.Name = "LandingDecisionModal"
	landingModal.AnchorPoint = Vector2.new(0.5, 0.5)
	landingModal.Position = UDim2.fromScale(0.5, 0.52)
	landingModal.Size = UDim2.new(0.88, 0, 0, 250)
	landingModal.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
	landingModal.Visible = false
	landingModal.ZIndex = 30
	landingModal.Parent = screenGui
	addCorner(landingModal, 14)
	addStroke(landingModal, Color3.fromRGB(255, 210, 65), 2.5, 0.1)

	local landingMax = Instance.new("UISizeConstraint")
	landingMax.MaxSize = Vector2.new(500, 265)
	landingMax.Parent = landingModal

	landingTitleLabel = Instance.new("TextLabel")
	landingTitleLabel.Position = UDim2.fromOffset(14, 10)
	landingTitleLabel.Size = UDim2.new(1, -28, 0, 32)
	landingTitleLabel.BackgroundTransparency = 1
	landingTitleLabel.Font = Enum.Font.GothamBlack
	landingTitleLabel.TextColor3 = Color3.fromRGB(255, 225, 70)
	landingTitleLabel.TextScaled = true
	landingTitleLabel.Text = "🏁 ПРИЗЕМЛЕНИЕ!"
	landingTitleLabel.ZIndex = 31
	landingTitleLabel.Parent = landingModal
	addTextConstraint(landingTitleLabel, 24, 14)

	landingDetailsLabel = Instance.new("TextLabel")
	landingDetailsLabel.Position = UDim2.fromOffset(14, 44)
	landingDetailsLabel.Size = UDim2.new(1, -28, 0, 44)
	landingDetailsLabel.BackgroundTransparency = 1
	landingDetailsLabel.Font = Enum.Font.GothamBold
	landingDetailsLabel.TextColor3 = Color3.new(1, 1, 1)
	landingDetailsLabel.TextScaled = true
	landingDetailsLabel.ZIndex = 31
	landingDetailsLabel.Parent = landingModal
	addTextConstraint(landingDetailsLabel, 15, 10)

	local decisionRemote = remotes:WaitForChild(RemoteNames.LandingDecision) :: RemoteEvent

	claimCoinsBtn = makeButton("ClaimCoinsBtn", "💰 Забрать монеты", Color3.fromRGB(45, 195, 95), UDim2.new(0.48, -10, 0, 48), landingModal)
	claimCoinsBtn.Position = UDim2.fromOffset(14, 98)
	claimCoinsBtn.ZIndex = 31
	claimCoinsBtn.Activated:Connect(function()
		landingModal.Visible = false
		decisionRemote:FireServer("ClaimCoins")
	end)

	placeBestSlotBtn = makeButton("PlaceBestSlotBtn", "🏆 На пьедестал базы", Color3.fromRGB(55, 150, 245), UDim2.new(0.48, -10, 0, 48), landingModal)
	placeBestSlotBtn.AnchorPoint = Vector2.new(1, 0)
	placeBestSlotBtn.Position = UDim2.new(1, -14, 0, 98)
	placeBestSlotBtn.ZIndex = 31
	placeBestSlotBtn.Activated:Connect(function()
		landingModal.Visible = false
		decisionRemote:FireServer("PlaceOnBase")
	end)

	local pickSlotHint = Instance.new("TextLabel")
	pickSlotHint.Position = UDim2.fromOffset(14, 154)
	pickSlotHint.Size = UDim2.new(1, -28, 0, 20)
	pickSlotHint.BackgroundTransparency = 1
	pickSlotHint.Font = Enum.Font.GothamMedium
	pickSlotHint.TextColor3 = Color3.fromRGB(185, 200, 225)
	pickSlotHint.TextScaled = true
	pickSlotHint.Text = "Или выбери конкретный пьедестал базы (1–4):"
	pickSlotHint.ZIndex = 31
	pickSlotHint.Parent = landingModal
	addTextConstraint(pickSlotHint, 13, 9)

	landingSlotsRow = Instance.new("Frame")
	landingSlotsRow.Position = UDim2.fromOffset(14, 178)
	landingSlotsRow.Size = UDim2.new(1, -28, 0, 52)
	landingSlotsRow.BackgroundTransparency = 1
	landingSlotsRow.ZIndex = 31
	landingSlotsRow.Parent = landingModal

	local slotsRowLayout = Instance.new("UIListLayout")
	slotsRowLayout.FillDirection = Enum.FillDirection.Horizontal
	slotsRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotsRowLayout.Padding = UDim.new(0, 6)
	slotsRowLayout.Parent = landingSlotsRow

	-- 10. ПОДПИСКА НА СОБЫТИЯ СЕРВЕРА
	local stateSyncRemote = remotes:WaitForChild(RemoteNames.StateSync) :: RemoteEvent
	local notifyRemote = remotes:WaitForChild(RemoteNames.Notification) :: RemoteEvent

	stateSyncRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		CurrentState.Coins = tonumber(payload.Coins) or 0
		CurrentState.BootLevel = tonumber(payload.BootLevel) or 1
		CurrentState.BestDistance = tonumber(payload.BestDistance) or 0
		CurrentState.Inventory = type(payload.Inventory) == "table" and payload.Inventory or {}
		CurrentState.Pedestals = type(payload.Pedestals) == "table" and payload.Pedestals or {}
		if type(payload.OwnedPasses) == "table" then
			CurrentState.OwnedPasses.MemeSoundPack = payload.OwnedPasses.MemeSoundPack == true
			CurrentState.OwnedPasses.JetpackSteering = payload.OwnedPasses.JetpackSteering == true
		end
		CurrentState.HeldGoober = payload.HeldGoober
		CurrentState.IsIncubating = payload.IsIncubating == true
		CurrentState.IncubateRemaining = tonumber(payload.IncubateRemaining) or 0
		CurrentState.ReadyGoober = payload.ReadyGoober
		CurrentState.PassiveIncome = tonumber(payload.PassiveIncome) or 0

		refreshHUD(remotes)
		for _, listener in ipairs(StateListeners) do
			task.spawn(listener, CurrentState)
		end
	end)

	notifyRemote.OnClientEvent:Connect(function(msg: any, kind: any)
		UIController.ShowToast(tostring(msg or ""), tostring(kind or "info"))
	end)

	refreshHUD(remotes)
end

return UIController
