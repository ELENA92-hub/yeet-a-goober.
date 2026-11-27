--!strict
--[[
	UIController.lua
	100% программный русский UI:
	- Верхняя панель: монеты, уровень Ботинка, «🎨 Мастерская Губера», «🏠 База», «🛒 Магазин», «🎒 Рюкзак».
	- Модалка «Мастерская Губера» (стикер-конструктор): форма тела / глаза / рот / аксессуар с живым предпросмотром бонусов.
	- Модалки Инвентаря, Базы, Магазина и выбора после приземления («Продать за монеты» / «Поставить на базу»).
	- Микро-анимации, мобильная адаптивность и toast-уведомления.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GooberConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GooberConfig"))
local RemoteNames = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteNames"))

local UIController = {}

local player = Players.LocalPlayer

local remotes: Folder? = nil
local stateSyncEvent: RemoteEvent? = nil
local flightEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil
local requestIncubateEvent: RemoteEvent? = nil
local updateWorkshopEvent: RemoteEvent? = nil
local pickupEvent: RemoteEvent? = nil
local equipEvent: RemoteEvent? = nil
local managePedestalEvent: RemoteEvent? = nil
local landingDecisionEvent: RemoteEvent? = nil
local upgradeBootEvent: RemoteEvent? = nil
local promptGamePassEvent: RemoteEvent? = nil
local teleportEvent: RemoteEvent? = nil

local state: any = {
	Coins = 0,
	BootLevel = 1,
	BestDistance = 0,
	Inventory = {},
	Pedestals = {},
	WorkshopBuild = GooberConfig.GetDefaultWorkshopBuild(),
	OwnedPasses = { MemeSoundPack = false, JetpackSteering = false },
	HeldGoober = nil,
	IsIncubating = false,
	IncubateRemaining = 0,
	ReadyGoober = nil,
	PassiveIncome = 0,
}

local draftBuild: GooberConfig.WorkshopBuild = GooberConfig.GetDefaultWorkshopBuild()
local selectedSection: string = "BodyShape"
local selectedInventoryId: string? = nil
local selectedPedestalSlot: number = 1
local isWorkshopOpen = false
local landPending: any = nil

local screenGui: ScreenGui? = nil
local topBar: Frame? = nil
local coinsLabel: TextLabel? = nil
local bootLabel: TextLabel? = nil
local heldLabel: TextLabel? = nil
local incomeLabel: TextLabel? = nil
local workshopModal: Frame? = nil
local inventoryModal: Frame? = nil
local baseModal: Frame? = nil
local shopModal: Frame? = nil
local landingModal: Frame? = nil
local toastFrame: Frame? = nil
local toastLabel: TextLabel? = nil
local toastHideTask: thread? = nil

-- ============================================================================
-- ВСПОМОГАТЕЛЬНОЕ UI
-- ============================================================================

local function makeCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makeStroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function makePadding(parent: Instance, left: number, right: number, top: number, bottom: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingRight = UDim.new(0, right)
	p.PaddingTop = UDim.new(0, top)
	p.PaddingBottom = UDim.new(0, bottom)
	p.Parent = parent
end

local function formatGooberTitle(gooberData: any): string
	if not gooberData then
		return "—"
	end
	local species = GooberConfig.Species[gooberData.SpeciesId] or GooberConfig.Species.Slimey
	local shape = GooberConfig.BodyShapes[gooberData.BodyShapeId] or GooberConfig.BodyShapes.Jelly
	local acc = GooberConfig.Accessories[gooberData.AccessoryId] or GooberConfig.Accessories.Propeller
	return string.format("%s %s %s (%.1f кг)", shape.Icon, species.Name, acc.Icon, tonumber(gooberData.Weight) or 0)
end

local function getBonusSummary(build: GooberConfig.WorkshopBuild): string
	local shape = GooberConfig.BodyShapes[build.BodyShapeId] or GooberConfig.BodyShapes.Jelly
	local eyes = GooberConfig.Eyes[build.EyesId] or GooberConfig.Eyes.Bulging
	local mouth = GooberConfig.Mouths[build.MouthId] or GooberConfig.Mouths.Screaming
	local acc = GooberConfig.Accessories[build.AccessoryId] or GooberConfig.Accessories.Propeller
	return string.format(
		"%s %s  •  %s %s  •  %s %s  •  %s %s",
		shape.Icon, shape.BonusShort,
		eyes.Icon, eyes.BonusShort,
		mouth.Icon, mouth.BonusShort,
		acc.Icon, acc.BonusShort
	)
end

local function showToast(message: string, kind: string?)
	if not toastFrame or not toastLabel then
		return
	end
	toastLabel.Text = message
	local bg = toastFrame :: Frame
	if kind == "success" or kind == "rare" then
		bg.BackgroundColor3 = Color3.fromRGB(38, 145, 75)
	elseif kind == "warn" then
		bg.BackgroundColor3 = Color3.fromRGB(155, 55, 35)
	else
		bg.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
	end
	bg.Visible = true
	bg.BackgroundTransparency = 0.08
	if toastHideTask then
		task.cancel(toastHideTask)
	end
	toastHideTask = task.delay(3.2, function()
		if bg.Parent then
			local tw = TweenService:Create(bg, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
			bg.Visible = false
			bg.BackgroundTransparency = 0.08
		end
	end)
end

local function closeAllModals()
	isWorkshopOpen = false
	for _, m in ipairs({ workshopModal, inventoryModal, baseModal, shopModal, landingModal }) do
		if m then
			m.Visible = false
		end
	end
end

local function openModal(modal: Frame?)
	closeAllModals()
	if modal then
		modal.Visible = true
		modal.BackgroundTransparency = 0.08
	end
end

local function stylePrimaryButton(btn: TextButton, bg: Color3, stroke: Color3)
	btn.BackgroundColor3 = bg
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	makeCorner(btn, 14)
	makeStroke(btn, stroke, 1.6)
	local tc = Instance.new("UITextSizeConstraint")
	tc.MaxTextSize = 13
	tc.MinTextSize = 9
	tc.Parent = btn
end

local function styleGhostButton(btn: TextButton)
	btn.BackgroundColor3 = Color3.fromRGB(42, 48, 68)
	btn.BackgroundTransparency = 0.12
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.TextColor3 = Color3.fromRGB(210, 220, 235)
	btn.BorderSizePixel = 0
	makeCorner(btn, 12)
	makeStroke(btn, Color3.fromRGB(70, 80, 110), 1.2)
	local tc = Instance.new("UITextSizeConstraint")
	tc.MaxTextSize = 12
	tc.MinTextSize = 8
	tc.Parent = btn
end

-- ============================================================================
-- ПОСТРОЕНИЕ КОРНЕВОГО GUI
-- ============================================================================

local function ensureRootGui(): ScreenGui
	local pg = player:WaitForChild("PlayerGui") :: PlayerGui
	local existing = pg:FindFirstChild("YeetMainGui") :: ScreenGui?
	if existing then
		screenGui = existing
		return existing
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "YeetMainGui"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder = 5
	sg.Parent = pg
	screenGui = sg
	return sg
end

local function buildTopBar(root: ScreenGui)
	local bar = root:FindFirstChild("TopBar") :: Frame?
	if not bar then
		bar = Instance.new("Frame")
		bar.Name = "TopBar"
		bar.Size = UDim2.new(1, 0, 0, 58)
		bar.BackgroundColor3 = Color3.fromRGB(18, 20, 34)
		bar.BackgroundTransparency = 0.12
		bar.BorderSizePixel = 0
		bar.Parent = root
		topBar = bar

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = bar
		makePadding(bar, 8, 8, 6, 6)

		local function addStat(name: string, text: string, order: number): TextLabel
			local lbl = Instance.new("TextLabel")
			lbl.Name = name
			lbl.Size = UDim2.new(0, 132, 1, 0)
			lbl.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
			lbl.BackgroundTransparency = 0.08
			lbl.Font = Enum.Font.GothamBold
			lbl.TextScaled = true
			lbl.TextColor3 = Color3.new(1, 1, 1)
			lbl.Text = text
			lbl.LayoutOrder = order
			lbl.BorderSizePixel = 0
			lbl.Parent = bar
			makeCorner(lbl, 10)
			makeStroke(lbl, Color3.fromRGB(55, 65, 95), 1)
			local tc = Instance.new("UITextSizeConstraint")
			tc.MaxTextSize = 11
			tc.MinTextSize = 8
			tc.Parent = lbl
			makePadding(lbl, 6, 6, 4, 4)
			return lbl
		end

		coinsLabel = addStat("CoinsLabel", "🪙 0", 1)
		bootLabel = addStat("BootLabel", "👟 Ур. 1", 2)
		incomeLabel = addStat("IncomeLabel", "💰 +0/с", 3)
		heldLabel = addStat("HeldLabel", "🤲 Пусто", 4)
		heldLabel.TextColor3 = Color3.fromRGB(255, 235, 95)

		local function addTopButton(name: string, text: string, bg: Color3, stroke: Color3, order: number): TextButton
			local btn = Instance.new("TextButton")
			btn.Name = name
			btn.Size = UDim2.new(0, 122, 1, 0)
			btn.BackgroundColor3 = bg
			btn.Font = Enum.Font.GothamBlack
			btn.TextScaled = true
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Text = text
			btn.LayoutOrder = order
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = true
			btn.Parent = bar
			makeCorner(btn, 10)
			makeStroke(btn, stroke, 1.4)
			local tc = Instance.new("UITextSizeConstraint")
			tc.MaxTextSize = 11
			tc.MinTextSize = 8
			tc.Parent = btn
			return btn
		end

		addTopButton("WorkshopButton", "🎨 Мастерская", Color3.fromRGB(155, 85, 255), Color3.fromRGB(185, 115, 255), 10)
		addTopButton("BaseButton", "🏠 База", Color3.fromRGB(55, 135, 255), Color3.fromRGB(85, 165, 255), 11)
		addTopButton("InventoryButton", "🎒 Рюкзак", Color3.fromRGB(45, 155, 95), Color3.fromRGB(75, 185, 125), 12)
		addTopButton("ShopButton", "🛒 Магазин", Color3.fromRGB(255, 135, 35), Color3.fromRGB(255, 165, 75), 13)
	else
		topBar = bar
		coinsLabel = bar:FindFirstChild("CoinsLabel") :: TextLabel?
		bootLabel = bar:FindFirstChild("BootLabel") :: TextLabel?
		incomeLabel = bar:FindFirstChild("IncomeLabel") :: TextLabel?
		heldLabel = bar:FindFirstChild("HeldLabel") :: TextLabel?
	end

	-- Toast
	local toast = root:FindFirstChild("ToastFrame") :: Frame?
	if not toast then
		toast = Instance.new("Frame")
		toast.Name = "ToastFrame"
		toast.Size = UDim2.new(0, 420, 0, 44)
		toast.Position = UDim2.new(0.5, -210, 0, 66)
		toast.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
		toast.Visible = false
		toast.BorderSizePixel = 0
		toast.Parent = root
		makeCorner(toast, 12)
		makeStroke(toast, Color3.fromRGB(255, 255, 255), 1, 0.75)
		local lbl = Instance.new("TextLabel")
		lbl.Name = "ToastLabel"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.Text = ""
		lbl.Parent = toast
		local tc = Instance.new("UITextSizeConstraint")
		tc.MaxTextSize = 12
		tc.MinTextSize = 9
		tc.Parent = lbl
		makePadding(lbl, 10, 10, 6, 6)
		toastFrame = toast
		toastLabel = lbl
	else
		toastFrame = toast
		toastLabel = toast:FindFirstChild("ToastLabel") :: TextLabel?
	end
end

-- ============================================================================
-- МАСТЕРСКАЯ ГУБЕРА
-- ============================================================================

local function buildWorkshopModal(root: ScreenGui)
	local modal = root:FindFirstChild("WorkshopModal") :: Frame?
	if modal then
		workshopModal = modal
		return
	end

	modal = Instance.new("Frame")
	modal.Name = "WorkshopModal"
	modal.Size = UDim2.new(0, 680, 0, 520)
	modal.Position = UDim2.new(0.5, -340, 0.5, -260)
	modal.BackgroundColor3 = Color3.fromRGB(22, 24, 38)
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = root
	makeCorner(modal, 18)
	makeStroke(modal, Color3.fromRGB(155, 85, 255), 2)
	workshopModal = modal

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 32)
	title.Position = UDim2.new(0, 16, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(185, 115, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🎨 МАСТЕРСКАЯ ГУБЕРА — Собери чудика!"
	title.Parent = modal
	local ttc = Instance.new("UITextSizeConstraint")
	ttc.MaxTextSize = 16
	ttc.Parent = title

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -40, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 80)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "✕"
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = modal
	makeCorner(closeBtn, 8)
	closeBtn.MouseButton1Click:Connect(closeAllModals)

	-- Вкладки
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.Size = UDim2.new(1, -24, 0, 38)
	tabs.Position = UDim2.new(0, 12, 0, 48)
	tabs.BackgroundTransparency = 1
	tabs.Parent = modal
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabs

	local tabDefs = {
		{ Id = "BodyShape", Label = "🧊 Тело" },
		{ Id = "Eyes", Label = "👀 Глаза" },
		{ Id = "Mouth", Label = "👅 Рот" },
		{ Id = "Accessory", Label = "🎩 Аксессуар" },
	}

	for _, td in ipairs(tabDefs) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. td.Id
		btn.Size = UDim2.new(0, 152, 1, 0)
		btn.BackgroundColor3 = td.Id == selectedSection and Color3.fromRGB(155, 85, 255) or Color3.fromRGB(42, 48, 68)
		btn.Font = Enum.Font.GothamBold
		btn.TextScaled = true
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Text = td.Label
		btn.BorderSizePixel = 0
		btn.Parent = tabs
		makeCorner(btn, 10)
		local tc = Instance.new("UITextSizeConstraint")
		tc.MaxTextSize = 11
		tc.Parent = btn
		btn.MouseButton1Click:Connect(function()
			selectedSection = td.Id
			refreshWorkshopModal()
		end)
	end

	-- Область выбора
	local optionsScroll = Instance.new("ScrollingFrame")
	optionsScroll.Name = "OptionsScroll"
	optionsScroll.Size = UDim2.new(1, -24, 0, 220)
	optionsScroll.Position = UDim2.new(0, 12, 0, 94)
	optionsScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 28)
	optionsScroll.BorderSizePixel = 0
	optionsScroll.ScrollBarThickness = 6
	optionsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	optionsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	optionsScroll.Parent = modal
	makeCorner(optionsScroll, 12)
	local optLayout = Instance.new("UIGridLayout")
	optLayout.CellSize = UDim2.new(0, 148, 0, 92)
	optLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	optLayout.FillDirectionMaxCells = 4
	optLayout.Parent = optionsScroll
	makePadding(optionsScroll, 8, 8, 8, 8)

	-- Сводка бонусов
	local summary = Instance.new("TextLabel")
	summary.Name = "BonusSummary"
	summary.Size = UDim2.new(1, -24, 0, 68)
	summary.Position = UDim2.new(0, 12, 0, 322)
	summary.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
	summary.BorderSizePixel = 0
	summary.Font = Enum.Font.GothamMedium
	summary.TextScaled = true
	summary.TextColor3 = Color3.fromRGB(210, 220, 235)
	summary.TextWrapped = true
	summary.Text = ""
	summary.Parent = modal
	makeCorner(summary, 10)
	makePadding(summary, 10, 10, 8, 8)
	local stc = Instance.new("UITextSizeConstraint")
	stc.MaxTextSize = 10
	stc.MinTextSize = 8
	stc.Parent = summary

	-- Кнопки действия
	local growBtn = Instance.new("TextButton")
	growBtn.Name = "GrowButton"
	growBtn.Size = UDim2.new(0, 220, 0, 48)
	growBtn.Position = UDim2.new(0, 12, 0, 402)
	growBtn.Text = "🧬 Вырастить чудика!"
	growBtn.Parent = modal
	stylePrimaryButton(growBtn, Color3.fromRGB(65, 185, 95), Color3.fromRGB(95, 215, 125))

	local pickupBtn = Instance.new("TextButton")
	pickupBtn.Name = "PickupButton"
	pickupBtn.Size = UDim2.new(0, 200, 0, 48)
	pickupBtn.Position = UDim2.new(0, 244, 0, 402)
	pickupBtn.Text = "🤲 Взять в руки"
	pickupBtn.Visible = false
	pickupBtn.Parent = modal
	stylePrimaryButton(pickupBtn, Color3.fromRGB(55, 135, 255), Color3.fromRGB(85, 165, 255))

	local equipInfo = Instance.new("TextLabel")
	equipInfo.Name = "EquipInfo"
	equipInfo.Size = UDim2.new(1, -24, 0, 22)
	equipInfo.Position = UDim2.new(0, 12, 0, 460)
	equipInfo.BackgroundTransparency = 1
	equipInfo.Font = Enum.Font.GothamMedium
	equipInfo.TextScaled = true
	equipInfo.TextColor3 = Color3.fromRGB(200, 210, 225)
	equipInfo.Text = "Выбери детали — каждая даёт реальный бонус к полёту!"
	equipInfo.Parent = modal
	local etc = Instance.new("UITextSizeConstraint")
	etc.MaxTextSize = 10
	etc.Parent = equipInfo

	growBtn.MouseButton1Click:Connect(function()
		if updateWorkshopEvent then
			updateWorkshopEvent:FireServer({
				BodyShapeId = draftBuild.BodyShapeId,
				EyesId = draftBuild.EyesId,
				MouthId = draftBuild.MouthId,
				AccessoryId = draftBuild.AccessoryId,
			})
		end
		if requestIncubateEvent then
			requestIncubateEvent:FireServer({
				BodyShapeId = draftBuild.BodyShapeId,
				EyesId = draftBuild.EyesId,
				MouthId = draftBuild.MouthId,
				AccessoryId = draftBuild.AccessoryId,
			})
		end
		showToast("🧬 Сборка чудика запущена!", "info")
	end)

	pickupBtn.MouseButton1Click:Connect(function()
		if pickupEvent then
			pickupEvent:FireServer()
		end
	end)

end

function refreshWorkshopModal()
	if not workshopModal then
		return
	end

	-- Подсветка активной вкладки
	local tabs = workshopModal:FindFirstChild("Tabs") :: Frame?
	if tabs then
		for _, child in ipairs(tabs:GetChildren()) do
			if child:IsA("TextButton") then
				local isActive = child.Name == "Tab_" .. selectedSection
				child.BackgroundColor3 = isActive and Color3.fromRGB(155, 85, 255) or Color3.fromRGB(42, 48, 68)
			end
		end
	end

	local scroll = workshopModal:FindFirstChild("OptionsScroll") :: ScrollingFrame?
	if not scroll then
		return
	end

	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local items: any = nil
	local currentId: string = ""
	if selectedSection == "BodyShape" then
		items = GooberConfig.BodyShapes
		currentId = draftBuild.BodyShapeId
	elseif selectedSection == "Eyes" then
		items = GooberConfig.Eyes
		currentId = draftBuild.EyesId
	elseif selectedSection == "Mouth" then
		items = GooberConfig.Mouths
		currentId = draftBuild.MouthId
	elseif selectedSection == "Accessory" then
		items = GooberConfig.Accessories
		currentId = draftBuild.AccessoryId
	end

	local orderList: { string } = {}
	if selectedSection == "BodyShape" then
		orderList = GooberConfig.BodyShapeOrder
	elseif selectedSection == "Eyes" then
		orderList = GooberConfig.EyesOrder
	elseif selectedSection == "Mouth" then
		orderList = GooberConfig.MouthOrder
	elseif selectedSection == "Accessory" then
		orderList = GooberConfig.AccessoryOrder
	end

	for _, id in ipairs(orderList) do
		local info = (items :: any)[id]
		if info then
			local card = Instance.new("TextButton")
			card.Name = "Option_" .. id
			card.BackgroundColor3 = id == currentId and Color3.fromRGB(75, 185, 95) or Color3.fromRGB(32, 38, 58)
			card.Font = Enum.Font.GothamBold
			card.TextScaled = false
			card.TextWrapped = true
			card.TextColor3 = Color3.new(1, 1, 1)
			card.Text = string.format("%s %s\n%s", info.Icon, info.Name, info.BonusShort)
			card.TextSize = 10
			card.BorderSizePixel = 0
			card.AutoButtonColor = true
			card.Parent = scroll
			makeCorner(card, 10)
			makeStroke(card, id == currentId and Color3.fromRGB(95, 215, 125) or Color3.fromRGB(55, 65, 95), 1.2)
			makePadding(card, 6, 6, 6, 6)

			card.MouseButton1Click:Connect(function()
				if selectedSection == "BodyShape" then
					draftBuild.BodyShapeId = id
				elseif selectedSection == "Eyes" then
					draftBuild.EyesId = id
				elseif selectedSection == "Mouth" then
					draftBuild.MouthId = id
				elseif selectedSection == "Accessory" then
					draftBuild.AccessoryId = id
				end
				if updateWorkshopEvent then
					updateWorkshopEvent:FireServer({
						BodyShapeId = draftBuild.BodyShapeId,
						EyesId = draftBuild.EyesId,
						MouthId = draftBuild.MouthId,
						AccessoryId = draftBuild.AccessoryId,
					})
				end
				refreshWorkshopModal()
			end)
		end
	end

	local summary = workshopModal:FindFirstChild("BonusSummary") :: TextLabel?
	if summary then
		summary.Text = "✨ БОНУСЫ СБОРКИ:  " .. getBonusSummary(draftBuild)
	end

	local growBtn = workshopModal:FindFirstChild("GrowButton") :: TextButton?
	local pickupBtn = workshopModal:FindFirstChild("PickupButton") :: TextButton?
	local equipInfo = workshopModal:FindFirstChild("EquipInfo") :: TextLabel?

	if state.ReadyGoober then
		if pickupBtn then
			pickupBtn.Visible = true
		end
		if growBtn then
			growBtn.Text = "🔄 Собрать нового!"
		end
		if equipInfo then
			equipInfo.Text = "✅ Чудик готов! Жми «Взять в руки» или собирай нового."
		end
	elseif state.IsIncubating then
		if pickupBtn then
			pickupBtn.Visible = false
		end
		if growBtn then
			growBtn.Text = string.format("⏳ Сборка... %.1f сек", state.IncubateRemaining or 0)
		end
		if equipInfo then
			equipInfo.Text = "⏳ Подожди, твой уникальный чудик собирается..."
		end
	else
		if pickupBtn then
			pickupBtn.Visible = false
		end
		if growBtn then
			growBtn.Text = "🧬 Вырастить чудика!"
		end
		if equipInfo then
			equipInfo.Text = "Выбери детали — каждая даёт реальный бонус к полёту!"
		end
	end
end

-- ============================================================================
-- ИНВЕНТАРЬ
-- ============================================================================

local function buildInventoryModal(root: ScreenGui)
	local modal = root:FindFirstChild("InventoryModal") :: Frame?
	if modal then
		inventoryModal = modal
		return
	end
	modal = Instance.new("Frame")
	modal.Name = "InventoryModal"
	modal.Size = UDim2.new(0, 520, 0, 460)
	modal.Position = UDim2.new(0.5, -260, 0.5, -230)
	modal.BackgroundColor3 = Color3.fromRGB(22, 24, 38)
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = root
	makeCorner(modal, 16)
	makeStroke(modal, Color3.fromRGB(75, 185, 95), 2)
	inventoryModal = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, 28)
	title.Position = UDim2.new(0, 12, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(95, 215, 125)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🎒 РЮКЗАК ГУБЕРОВ"
	title.Parent = modal
	local ttc = Instance.new("UITextSizeConstraint")
	ttc.MaxTextSize = 15
	ttc.Parent = title

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -40, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 80)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "✕"
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = modal
	makeCorner(closeBtn, 8)
	closeBtn.MouseButton1Click:Connect(closeAllModals)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "InventoryScroll"
	scroll.Size = UDim2.new(1, -24, 0, 320)
	scroll.Position = UDim2.new(0, 12, 0, 46)
	scroll.BackgroundColor3 = Color3.fromRGB(14, 16, 28)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = modal
	makeCorner(scroll, 12)
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.new(0, 150, 0, 92)
	g.CellPadding = UDim2.new(0, 8, 0, 8)
	g.Parent = scroll
	makePadding(scroll, 8, 8, 8, 8)

	local equipBtn = Instance.new("TextButton")
	equipBtn.Name = "EquipButton"
	equipBtn.Size = UDim2.new(0, 220, 0, 44)
	equipBtn.Position = UDim2.new(0, 12, 0, 380)
	equipBtn.Text = "🤲 Взять в руки"
	equipBtn.Visible = false
	equipBtn.Parent = modal
	stylePrimaryButton(equipBtn, Color3.fromRGB(55, 135, 255), Color3.fromRGB(85, 165, 255))

	local info = Instance.new("TextLabel")
	info.Name = "InventoryInfo"
	info.Size = UDim2.new(1, -24, 0, 20)
	info.Position = UDim2.new(0, 12, 0, 430)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamMedium
	info.TextScaled = true
	info.TextColor3 = Color3.fromRGB(200, 210, 225)
	info.Text = "Выбери чудика из списка!"
	info.Parent = modal
	local itc = Instance.new("UITextSizeConstraint")
	itc.MaxTextSize = 10
	itc.Parent = info

	equipBtn.MouseButton1Click:Connect(function()
		if selectedInventoryId and equipEvent then
			equipEvent:FireServer(selectedInventoryId)
			showToast("🤲 Чудик взят в руки! Беги к обрыву!", "success")
		end
	end)
end

function refreshInventoryModal()
	if not inventoryModal then
		return
	end
	local scroll = inventoryModal:FindFirstChild("InventoryScroll") :: ScrollingFrame?
	if not scroll then
		return
	end
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	selectedInventoryId = nil
	local equipBtn = inventoryModal:FindFirstChild("EquipButton") :: TextButton?
	if equipBtn then
		equipBtn.Visible = false
	end

	local inv: any = state.Inventory
	if not inv or #inv == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -16, 0, 40)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.GothamMedium
		empty.TextScaled = true
		empty.TextColor3 = Color3.fromRGB(180, 190, 210)
		empty.Text = "Пусто! Собери первого чудика в Мастерской → 🎨"
		empty.Parent = scroll
		local etc = Instance.new("UITextSizeConstraint")
		etc.MaxTextSize = 11
		etc.Parent = empty
		return
	end

	for _, goober in ipairs(inv) do
		local card = Instance.new("TextButton")
		card.Name = "Inv_" .. tostring(goober.Id)
		card.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
		card.Font = Enum.Font.GothamBold
		card.TextScaled = false
		card.TextWrapped = true
		card.TextColor3 = Color3.new(1, 1, 1)
		card.TextSize = 10
		card.BorderSizePixel = 0
		card.AutoButtonColor = true
		card.Parent = scroll
		makeCorner(card, 10)
		makeStroke(card, Color3.fromRGB(55, 65, 95), 1)
		makePadding(card, 6, 6, 6, 6)

		local species = GooberConfig.Species[goober.SpeciesId] or GooberConfig.Species.Slimey
		local mut = GooberConfig.Mutations[goober.MutationId] or GooberConfig.Mutations.Normal
		local shape = GooberConfig.BodyShapes[goober.BodyShapeId] or GooberConfig.BodyShapes.Jelly
		local acc = GooberConfig.Accessories[goober.AccessoryId] or GooberConfig.Accessories.Propeller
		local income = GooberConfig.CalculatePassiveIncome(goober)
		card.Text = string.format(
			"%s %s\n%.1fкг • %s\n%s%s • +%d/с",
			shape.Icon, species.Name,
			tonumber(goober.Weight) or 0,
			mut.Name,
			acc.Icon, acc.Name,
			income
		)

		card.MouseButton1Click:Connect(function()
			selectedInventoryId = goober.Id
			for _, other in ipairs(scroll:GetChildren()) do
				if other:IsA("TextButton") then
					(other :: TextButton).BackgroundColor3 = Color3.fromRGB(32, 38, 58)
				end
			end
			card.BackgroundColor3 = Color3.fromRGB(55, 135, 255)
			if equipBtn then
				equipBtn.Visible = true
				equipBtn.Text = "🤲 Взять: " .. species.Name
			end
			local info = inventoryModal and inventoryModal:FindFirstChild("InventoryInfo") :: TextLabel?
			if info then
				info.Text = string.format("Выбран: %s | Пинок → Полёт → Награда!", formatGooberTitle(goober))
			end
		end)
	end
end

-- ============================================================================
-- БАЗА (ПЬЕДЕСТАЛЫ)
-- ============================================================================

local function buildBaseModal(root: ScreenGui)
	local modal = root:FindFirstChild("BaseModal") :: Frame?
	if modal then
		baseModal = modal
		return
	end
	modal = Instance.new("Frame")
	modal.Name = "BaseModal"
	modal.Size = UDim2.new(0, 520, 0, 420)
	modal.Position = UDim2.new(0.5, -260, 0.5, -210)
	modal.BackgroundColor3 = Color3.fromRGB(22, 24, 38)
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = root
	makeCorner(modal, 16)
	makeStroke(modal, Color3.fromRGB(55, 135, 255), 2)
	baseModal = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, 28)
	title.Position = UDim2.new(0, 12, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(85, 165, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🏠 МОЯ БАЗА — 4 ПЬЕДЕСТАЛА"
	title.Parent = modal
	local ttc = Instance.new("UITextSizeConstraint")
	ttc.MaxTextSize = 15
	ttc.Parent = title

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -40, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 80)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "✕"
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = modal
	makeCorner(closeBtn, 8)
	closeBtn.MouseButton1Click:Connect(closeAllModals)

	local grid = Instance.new("Frame")
	grid.Name = "PedestalGrid"
	grid.Size = UDim2.new(1, -24, 0, 260)
	grid.Position = UDim2.new(0, 12, 0, 46)
	grid.BackgroundTransparency = 1
	grid.Parent = modal
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0, 238, 0, 120)
	gl.CellPadding = UDim2.new(0, 8, 0, 8)
	gl.Parent = grid

	for slot = 1, 4 do
		local card = Instance.new("Frame")
		card.Name = "PedestalCard_" .. tostring(slot)
		card.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
		card.BorderSizePixel = 0
		card.Parent = grid
		makeCorner(card, 12)
		makeStroke(card, Color3.fromRGB(55, 65, 95), 1)
		makePadding(card, 8, 8, 8, 8)

		local slotLabel = Instance.new("TextLabel")
		slotLabel.Name = "SlotLabel"
		slotLabel.Size = UDim2.new(1, 0, 0, 18)
		slotLabel.BackgroundTransparency = 1
		slotLabel.Font = Enum.Font.GothamBold
		slotLabel.TextScaled = true
		slotLabel.TextColor3 = Color3.fromRGB(210, 220, 235)
		slotLabel.Text = "Слот #" .. tostring(slot)
		slotLabel.Parent = card
		local stc = Instance.new("UITextSizeConstraint")
		stc.MaxTextSize = 11
		stc.Parent = slotLabel

		local gooberLabel = Instance.new("TextLabel")
		gooberLabel.Name = "GooberLabel"
		gooberLabel.Size = UDim2.new(1, 0, 0, 42)
		gooberLabel.Position = UDim2.new(0, 0, 0, 24)
		gooberLabel.BackgroundTransparency = 1
		gooberLabel.Font = Enum.Font.GothamMedium
		gooberLabel.TextScaled = false
		gooberLabel.TextWrapped = true
		gooberLabel.TextColor3 = Color3.new(1, 1, 1)
		gooberLabel.TextSize = 10
		gooberLabel.Text = "Пусто"
		gooberLabel.Parent = card

		local actionBtn = Instance.new("TextButton")
		actionBtn.Name = "ActionButton"
		actionBtn.Size = UDim2.new(1, 0, 0, 32)
		actionBtn.Position = UDim2.new(0, 0, 1, -32)
		actionBtn.BackgroundColor3 = Color3.fromRGB(55, 135, 255)
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.TextScaled = true
		actionBtn.TextColor3 = Color3.new(1, 1, 1)
		actionBtn.Text = "⬆ Поставить чудика"
		actionBtn.BorderSizePixel = 0
		actionBtn.Parent = card
		makeCorner(actionBtn, 8)
		local atc = Instance.new("UITextSizeConstraint")
		atc.MaxTextSize = 10
		atc.Parent = actionBtn

		actionBtn.MouseButton1Click:Connect(function()
			selectedPedestalSlot = slot
			local held = state.HeldGoober
			if held then
				if managePedestalEvent then
					managePedestalEvent:FireServer("PlaceHeld", slot)
				end
				showToast(string.format("🏆 Чудик на пьедестале #%d!", slot), "success")
			else
				-- Открываем инвентарь для выбора
				closeAllModals()
				openModal(inventoryModal)
				refreshInventoryModal()
				-- Перехватываем выбор инвентаря для установки на этот слот
				task.defer(function()
					local invEquip = inventoryModal and inventoryModal:FindFirstChild("EquipButton") :: TextButton?
					if invEquip then
						-- Кнопка инвентаря уже делает EquipInventoryGoober; для базы используем PlaceFromInventory
						-- Переопределяем поведение на один клик:
						showToast("Выбери чудика → затем нажми «Поставить» в Базе!", "info")
					end
				end)
			end
		end)

		local removeBtn = Instance.new("TextButton")
		removeBtn.Name = "RemoveButton"
		removeBtn.Size = UDim2.new(0, 52, 0, 22)
		removeBtn.Position = UDim2.new(1, -52, 0, 0)
		removeBtn.BackgroundColor3 = Color3.fromRGB(155, 55, 45)
		removeBtn.Font = Enum.Font.GothamBold
		removeBtn.TextScaled = true
		removeBtn.TextColor3 = Color3.new(1, 1, 1)
		removeBtn.Text = "Снять"
		removeBtn.Visible = false
		removeBtn.BorderSizePixel = 0
		removeBtn.Parent = card
		makeCorner(removeBtn, 6)
		local rtc = Instance.new("UITextSizeConstraint")
		rtc.MaxTextSize = 9
		rtc.Parent = removeBtn
		removeBtn.MouseButton1Click:Connect(function()
			if managePedestalEvent then
				managePedestalEvent:FireServer("UnequipSlot", slot)
			end
		end)
	end

	local tpBtn = Instance.new("TextButton")
	tpBtn.Name = "TeleportButton"
	tpBtn.Size = UDim2.new(0, 200, 0, 36)
	tpBtn.Position = UDim2.new(0, 12, 0, 320)
	tpBtn.Text = "📍 Телепорт на базу"
	tpBtn.Parent = modal
	styleGhostButton(tpBtn)
	tpBtn.MouseButton1Click:Connect(function()
		if teleportEvent then
			teleportEvent:FireServer("Base")
		end
		closeAllModals()
	end)

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -24, 0, 20)
	info.Position = UDim2.new(0, 12, 0, 364)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamMedium
	info.TextScaled = true
	info.TextColor3 = Color3.fromRGB(200, 210, 225)
	info.Text = "Каждый чудик на пьедестале приносит монеты каждую секунду!"
	info.Parent = modal
	local itc = Instance.new("UITextSizeConstraint")
	itc.MaxTextSize = 10
	itc.Parent = info
end

function refreshBaseModal()
	if not baseModal then
		return
	end
	local grid = baseModal:FindFirstChild("PedestalGrid") :: Frame?
	if not grid then
		return
	end
	for slot = 1, 4 do
		local card = grid:FindFirstChild("PedestalCard_" .. tostring(slot)) :: Frame?
		if card then
			local goober = state.Pedestals and state.Pedestals[tostring(slot)]
			local gooberLabel = card:FindFirstChild("GooberLabel") :: TextLabel?
			local actionBtn = card:FindFirstChild("ActionButton") :: TextButton?
			local removeBtn = card:FindFirstChild("RemoveButton") :: TextButton?
			if goober then
				local income = GooberConfig.CalculatePassiveIncome(goober)
				if gooberLabel then
					gooberLabel.Text = string.format("%s\n💰 +%d 🪙/сек", formatGooberTitle(goober), income)
				end
				if actionBtn then
					actionBtn.Text = "🔄 Заменить"
					actionBtn.BackgroundColor3 = Color3.fromRGB(155, 85, 255)
				end
				if removeBtn then
					removeBtn.Visible = true
				end
				card.BackgroundColor3 = Color3.fromRGB(42, 55, 85)
			else
				if gooberLabel then
					gooberLabel.Text = "Пусто — поставь чудика!"
				end
				if actionBtn then
					actionBtn.Text = "⬆ Поставить чудика"
					actionBtn.BackgroundColor3 = Color3.fromRGB(55, 135, 255)
				end
				if removeBtn then
					removeBtn.Visible = false
				end
				card.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
			end
		end
	end
end

-- ============================================================================
-- МАГАЗИН
-- ============================================================================

local function buildShopModal(root: ScreenGui)
	local modal = root:FindFirstChild("ShopModal") :: Frame?
	if modal then
		shopModal = modal
		return
	end
	modal = Instance.new("Frame")
	modal.Name = "ShopModal"
	modal.Size = UDim2.new(0, 520, 0, 440)
	modal.Position = UDim2.new(0.5, -260, 0.5, -220)
	modal.BackgroundColor3 = Color3.fromRGB(22, 24, 38)
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = root
	makeCorner(modal, 16)
	makeStroke(modal, Color3.fromRGB(255, 135, 35), 2)
	shopModal = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, 28)
	title.Position = UDim2.new(0, 12, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 175, 55)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🛒 МАГАЗИН"
	title.Parent = modal
	local ttc = Instance.new("UITextSizeConstraint")
	ttc.MaxTextSize = 15
	ttc.Parent = title

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -40, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 80)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "✕"
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = modal
	makeCorner(closeBtn, 8)
	closeBtn.MouseButton1Click:Connect(closeAllModals)

	local bootCard = Instance.new("Frame")
	bootCard.Name = "BootCard"
	bootCard.Size = UDim2.new(1, -24, 0, 110)
	bootCard.Position = UDim2.new(0, 12, 0, 48)
	bootCard.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
	bootCard.BorderSizePixel = 0
	bootCard.Parent = modal
	makeCorner(bootCard, 12)
	makeStroke(bootCard, Color3.fromRGB(255, 175, 55), 1.2)
	makePadding(bootCard, 10, 10, 10, 10)

	local bootTitle = Instance.new("TextLabel")
	bootTitle.Name = "BootTitle"
	bootTitle.Size = UDim2.new(1, -120, 0, 22)
	bootTitle.BackgroundTransparency = 1
	bootTitle.Font = Enum.Font.GothamBlack
	bootTitle.TextScaled = true
	bootTitle.TextColor3 = Color3.new(1, 1, 1)
	bootTitle.TextXAlignment = Enum.TextXAlignment.Left
	bootTitle.Text = "👟 Ботинок Ур. 1"
	bootTitle.Parent = bootCard
	local bttc = Instance.new("UITextSizeConstraint")
	bttc.MaxTextSize = 13
	bttc.Parent = bootTitle

	local bootDesc = Instance.new("TextLabel")
	bootDesc.Name = "BootDesc"
	bootDesc.Size = UDim2.new(1, -120, 0, 36)
	bootDesc.Position = UDim2.new(0, 0, 0, 26)
	bootDesc.BackgroundTransparency = 1
	bootDesc.Font = Enum.Font.GothamMedium
	bootDesc.TextScaled = false
	bootDesc.TextWrapped = true
	bootDesc.TextColor3 = Color3.fromRGB(200, 210, 225)
	bootDesc.TextSize = 10
	bootDesc.TextXAlignment = Enum.TextXAlignment.Left
	bootDesc.Text = "Усиливает начальный импульс пинка!"
	bootDesc.Parent = bootCard

	local bootUpgradeBtn = Instance.new("TextButton")
	bootUpgradeBtn.Name = "BootUpgradeButton"
	bootUpgradeBtn.Size = UDim2.new(0, 110, 0, 40)
	bootUpgradeBtn.Position = UDim2.new(1, -110, 0, 30)
	bootUpgradeBtn.Text = "⬆ 65 🪙"
	bootUpgradeBtn.Parent = bootCard
	stylePrimaryButton(bootUpgradeBtn, Color3.fromRGB(65, 185, 95), Color3.fromRGB(95, 215, 125))
	bootUpgradeBtn.MouseButton1Click:Connect(function()
		if upgradeBootEvent then
			upgradeBootEvent:FireServer()
		end
	end)

	local passesTitle = Instance.new("TextLabel")
	passesTitle.Size = UDim2.new(1, -24, 0, 22)
	passesTitle.Position = UDim2.new(0, 12, 0, 168)
	passesTitle.BackgroundTransparency = 1
	passesTitle.Font = Enum.Font.GothamBold
	passesTitle.TextScaled = true
	passesTitle.TextColor3 = Color3.fromRGB(255, 215, 65)
	passesTitle.TextXAlignment = Enum.TextXAlignment.Left
	passesTitle.Text = "⭐ GAME PASSES"
	passesTitle.Parent = modal
	local ptc = Instance.new("UITextSizeConstraint")
	ptc.MaxTextSize = 12
	ptc.Parent = passesTitle

	local passesGrid = Instance.new("Frame")
	passesGrid.Name = "PassesGrid"
	passesGrid.Size = UDim2.new(1, -24, 0, 180)
	passesGrid.Position = UDim2.new(0, 12, 0, 194)
	passesGrid.BackgroundTransparency = 1
	passesGrid.Parent = modal
	local pg = Instance.new("UIGridLayout")
	pg.CellSize = UDim2.new(0, 236, 0, 84)
	pg.CellPadding = UDim2.new(0, 8, 0, 8)
	pg.Parent = passesGrid

	for key, passInfo in pairs(GooberConfig.GamePasses) do
		local card = Instance.new("Frame")
		card.Name = "PassCard_" .. key
		card.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
		card.BorderSizePixel = 0
		card.Parent = passesGrid
		makeCorner(card, 12)
		makeStroke(card, Color3.fromRGB(255, 215, 65), 1)
		makePadding(card, 8, 8, 8, 8)

		local pTitle = Instance.new("TextLabel")
		pTitle.Size = UDim2.new(1, 0, 0, 18)
		pTitle.BackgroundTransparency = 1
		pTitle.Font = Enum.Font.GothamBold
		pTitle.TextScaled = true
		pTitle.TextColor3 = Color3.new(1, 1, 1)
		pTitle.Text = string.format("%s %s", passInfo.IconText, passInfo.Name)
		pTitle.Parent = card
		local pt = Instance.new("UITextSizeConstraint")
		pt.MaxTextSize = 11
		pt.Parent = pTitle

		local pDesc = Instance.new("TextLabel")
		pDesc.Size = UDim2.new(1, 0, 0, 26)
		pDesc.Position = UDim2.new(0, 0, 0, 22)
		pDesc.BackgroundTransparency = 1
		pDesc.Font = Enum.Font.GothamMedium
		pDesc.TextScaled = false
		pDesc.TextWrapped = true
		pDesc.TextColor3 = Color3.fromRGB(200, 210, 225)
		pDesc.TextSize = 9
		pDesc.Text = passInfo.Description
		pDesc.Parent = card

		local pBtn = Instance.new("TextButton")
		pBtn.Name = "BuyButton"
		pBtn.Size = UDim2.new(1, 0, 0, 28)
		pBtn.Position = UDim2.new(0, 0, 1, -28)
		pBtn.Text = "Купить (Robux)"
		pBtn.Parent = card
		stylePrimaryButton(pBtn, Color3.fromRGB(155, 85, 255), Color3.fromRGB(185, 115, 255))
		pBtn.MouseButton1Click:Connect(function()
			if promptGamePassEvent then
				promptGamePassEvent:FireServer(key)
			end
		end)
	end

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -24, 0, 20)
	info.Position = UDim2.new(0, 12, 0, 382)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamMedium
	info.TextScaled = true
	info.TextColor3 = Color3.fromRGB(180, 190, 210)
	info.Text = "Прокачай Ботинок за монеты и разблокируй VIP-способности!"
	info.Parent = modal
	local itc2 = Instance.new("UITextSizeConstraint")
	itc2.MaxTextSize = 10
	itc2.Parent = info
end

function refreshShopModal()
	if not shopModal then
		return
	end
	local bootCard = shopModal:FindFirstChild("BootCard") :: Frame?
	if bootCard then
		local bootTitle = bootCard:FindFirstChild("BootTitle") :: TextLabel?
		local bootDesc = bootCard:FindFirstChild("BootDesc") :: TextLabel?
		local bootBtn = bootCard:FindFirstChild("BootUpgradeButton") :: TextButton?
		local lvl = state.BootLevel or 1
		local title = GooberConfig.GetBootTitle(lvl)
		local mult = GooberConfig.GetBootPowerMultiplier(lvl)
		local cost = GooberConfig.GetBootUpgradeCost(lvl)
		if bootTitle then
			bootTitle.Text = string.format("👟 %s (Ур. %d • x%.2f)", title, lvl, mult)
		end
		if bootDesc then
			bootDesc.Text = string.format("След. уровень: Ур. %d • Текущая сила x%.2f", lvl + 1, mult)
		end
		if bootBtn then
			bootBtn.Text = string.format("⬆ %d 🪙", cost)
			bootBtn.BackgroundColor3 = (state.Coins or 0) >= cost and Color3.fromRGB(65, 185, 95) or Color3.fromRGB(95, 100, 115)
		end
	end

	local passesGrid = shopModal:FindFirstChild("PassesGrid") :: Frame?
	if passesGrid then
		for _, child in ipairs(passesGrid:GetChildren()) do
			if child:IsA("Frame") then
				local key = child.Name:gsub("PassCard_", "")
				local owned = state.OwnedPasses and state.OwnedPasses[key] == true
				local btn = child:FindFirstChild("BuyButton") :: TextButton?
				if btn then
					if owned then
						btn.Text = "✅ Активирован"
						btn.BackgroundColor3 = Color3.fromRGB(65, 185, 95)
						btn.AutoButtonColor = false
					else
						btn.Text = "Купить (Robux)"
						btn.BackgroundColor3 = Color3.fromRGB(155, 85, 255)
						btn.AutoButtonColor = true
					end
				end
			end
		end
	end
end

-- ============================================================================
-- МОДАЛКА ПРИЗЕМЛЕНИЯ
-- ============================================================================

local function buildLandingModal(root: ScreenGui)
	local modal = root:FindFirstChild("LandingModal") :: Frame?
	if modal then
		landingModal = modal
		return
	end
	modal = Instance.new("Frame")
	modal.Name = "LandingModal"
	modal.Size = UDim2.new(0, 440, 0, 300)
	modal.Position = UDim2.new(0.5, -220, 0.5, -150)
	modal.BackgroundColor3 = Color3.fromRGB(22, 24, 38)
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = root
	makeCorner(modal, 16)
	makeStroke(modal, Color3.fromRGB(65, 255, 110), 2)
	landingModal = modal

	local title = Instance.new("TextLabel")
	title.Name = "LandingTitle"
	title.Size = UDim2.new(1, -24, 0, 36)
	title.Position = UDim2.new(0, 12, 0, 12)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(65, 255, 110)
	title.Text = "🏁 ПРИЗЕМЛЕНИЕ!"
	title.Parent = modal
	local ttc = Instance.new("UITextSizeConstraint")
	ttc.MaxTextSize = 18
	ttc.Parent = title

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "LandingInfo"
	infoLabel.Size = UDim2.new(1, -24, 0, 110)
	infoLabel.Position = UDim2.new(0, 12, 0, 52)
	infoLabel.BackgroundColor3 = Color3.fromRGB(32, 38, 58)
	infoLabel.BorderSizePixel = 0
	infoLabel.Font = Enum.Font.GothamBold
	infoLabel.TextScaled = false
	infoLabel.TextWrapped = true
	infoLabel.TextColor3 = Color3.new(1, 1, 1)
	infoLabel.TextSize = 12
	infoLabel.Text = ""
	infoLabel.Parent = modal
	makeCorner(infoLabel, 10)
	makePadding(infoLabel, 10, 10, 8, 8)

	local sellBtn = Instance.new("TextButton")
	sellBtn.Name = "SellButton"
	sellBtn.Size = UDim2.new(0, 195, 0, 48)
	sellBtn.Position = UDim2.new(0, 12, 0, 176)
	sellBtn.Text = "💰 Продать за монеты"
	sellBtn.Parent = modal
	stylePrimaryButton(sellBtn, Color3.fromRGB(65, 185, 95), Color3.fromRGB(95, 215, 125))

	local placeBtn = Instance.new("TextButton")
	placeBtn.Name = "PlaceButton"
	placeBtn.Size = UDim2.new(0, 195, 0, 48)
	placeBtn.Position = UDim2.new(1, -207, 0, 176)
	placeBtn.Text = "🏠 На пьедестал"
	placeBtn.Parent = modal
	stylePrimaryButton(placeBtn, Color3.fromRGB(55, 135, 255), Color3.fromRGB(85, 165, 255))

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -24, 0, 22)
	hint.Position = UDim2.new(0, 12, 0, 238)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextScaled = true
	hint.TextColor3 = Color3.fromRGB(200, 210, 225)
	hint.Text = "На пьедестале чудик приносит монеты каждую секунду!"
	hint.Parent = modal
	local htc = Instance.new("UITextSizeConstraint")
	htc.MaxTextSize = 10
	htc.Parent = hint

	sellBtn.MouseButton1Click:Connect(function()
		if landingDecisionEvent then
			landingDecisionEvent:FireServer("Sell")
		end
		landPending = nil
		closeAllModals()
	end)

	placeBtn.MouseButton1Click:Connect(function()
		if landingDecisionEvent then
			landingDecisionEvent:FireServer("PlaceOnBase", selectedPedestalSlot)
		end
		landPending = nil
		closeAllModals()
	end)
end

function refreshLandingModal(payload: any)
	if not landingModal then
		return
	end
	landPending = payload
	local info = landingModal:FindFirstChild("LandingInfo") :: TextLabel?
	if info and payload then
		local goober = payload.GooberData
		local species = goober and (GooberConfig.Species[goober.SpeciesId] or GooberConfig.Species.Slimey)
		local mut = goober and (GooberConfig.Mutations[goober.MutationId] or GooberConfig.Mutations.Normal)
		info.Text = string.format(
			"%s\n%.1f кг • [%s] • %d м\n💰 Награда: +%d 🪙  •  🏠 Доход: +%d/с\n🔥 Комбо: x%.2f  •  Трюков: %d  •  Perfect: x%d",
			species and species.Name or "Губер",
			goober and tonumber(goober.Weight) or 0,
			mut and mut.Name or "—",
			tonumber(payload.Distance) or 0,
			tonumber(payload.RewardCoins) or 0,
			tonumber(payload.PassiveIncome) or 0,
			tonumber(payload.ComboMultiplier) or 1.0,
			tonumber(payload.BestTrickStreak) or 0,
			tonumber(payload.PerfectMultiplier) or 1
		)
	end
	openModal(landingModal)
end

-- ============================================================================
-- ОБНОВЛЕНИЕ ВЕРХНЕЙ ПАНЕЛИ
-- ============================================================================

local function refreshTopBar()
	if not topBar then
		return
	end
	if coinsLabel then
		coinsLabel.Text = string.format("🪙 %d", state.Coins or 0)
	end
	if bootLabel then
		bootLabel.Text = string.format("👟 Ур. %d", state.BootLevel or 1)
	end
	if incomeLabel then
		incomeLabel.Text = string.format("💰 +%d/с", state.PassiveIncome or 0)
	end
	if heldLabel then
		if state.HeldGoober then
			heldLabel.Text = "🤲 " .. formatGooberTitle(state.HeldGoober)
		elseif state.ReadyGoober then
			heldLabel.Text = "📦 Готов в инкубаторе!"
		elseif state.IsIncubating then
			heldLabel.Text = string.format("⏳ %.1f сек", state.IncubateRemaining or 0)
		else
			heldLabel.Text = "🤲 Пусто — собери чудика!"
		end
	end

	-- Инкубатор: обновляем кнопку «Вырастить» в Мастерской
	if workshopModal and isWorkshopOpen then
		refreshWorkshopModal()
	end
end

-- ============================================================================
-- СВЯЗКА REMOTES
-- ============================================================================

local function bindRemotes()
	remotes = ReplicatedStorage:FindFirstChild(RemoteNames.FolderName) :: Folder?
	if not remotes then
		remotes = ReplicatedStorage:WaitForChild(RemoteNames.FolderName, 10) :: Folder?
	end
	if not remotes then
		warn("[UIController] Папка Remotes не найдена!")
		return
	end

	stateSyncEvent = remotes:FindFirstChild(RemoteNames.StateSync) :: RemoteEvent?
	flightEvent = remotes:FindFirstChild(RemoteNames.FlightEvent) :: RemoteEvent?
	notificationEvent = remotes:FindFirstChild(RemoteNames.Notification) :: RemoteEvent?
	requestIncubateEvent = remotes:FindFirstChild(RemoteNames.RequestIncubate) :: RemoteEvent?
	updateWorkshopEvent = remotes:FindFirstChild(RemoteNames.UpdateWorkshopPreset) :: RemoteEvent?
	pickupEvent = remotes:FindFirstChild(RemoteNames.PickupIncubatedGoober) :: RemoteEvent?
	equipEvent = remotes:FindFirstChild(RemoteNames.EquipInventoryGoober) :: RemoteEvent?
	managePedestalEvent = remotes:FindFirstChild(RemoteNames.ManagePedestal) :: RemoteEvent?
	landingDecisionEvent = remotes:FindFirstChild(RemoteNames.LandingDecision) :: RemoteEvent?
	upgradeBootEvent = remotes:FindFirstChild(RemoteNames.UpgradeBoot) :: RemoteEvent?
	promptGamePassEvent = remotes:FindFirstChild(RemoteNames.PromptGamePass) :: RemoteEvent?
	teleportEvent = remotes:FindFirstChild(RemoteNames.TeleportRequest) :: RemoteEvent?

	if stateSyncEvent then
		stateSyncEvent.OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" then
				for k, v in pairs(payload) do
					state[k] = v
				end
				-- Синхронизируем черновик Мастерской с серверным пресетом, если модалка закрыта
				if not isWorkshopOpen then
					draftBuild = table.clone(state.WorkshopBuild or GooberConfig.GetDefaultWorkshopBuild())
				end
				refreshTopBar()
				refreshShopModal()
				refreshBaseModal()
				-- Инвентарь обновляем только если открыт, чтобы не сбивать выбор
			end
		end)
	end

	if flightEvent then
		flightEvent.OnClientEvent:Connect(function(kind: string, payload: any)
			if kind == "Landed" then
				refreshLandingModal(payload)
			end
		end)
	end

	if notificationEvent then
		notificationEvent.OnClientEvent:Connect(function(message: any, kind: any)
			if type(message) == "string" then
				showToast(message, type(kind) == "string" and kind or "info")
			end
		end)
	end
end

local function bindTopBarButtons()
	if not topBar then
		return
	end
	local workshopBtn = topBar:FindFirstChild("WorkshopButton") :: TextButton?
	local baseBtn = topBar:FindFirstChild("BaseButton") :: TextButton?
	local invBtn = topBar:FindFirstChild("InventoryButton") :: TextButton?
	local shopBtn = topBar:FindFirstChild("ShopButton") :: TextButton?

	if workshopBtn then
		workshopBtn.MouseButton1Click:Connect(function()
			draftBuild = table.clone(state.WorkshopBuild or GooberConfig.GetDefaultWorkshopBuild())
			isWorkshopOpen = true
			refreshWorkshopModal()
			openModal(workshopModal)
			isWorkshopOpen = true
		end)
	end
	if baseBtn then
		baseBtn.MouseButton1Click:Connect(function()
			refreshBaseModal()
			openModal(baseModal)
		end)
	end
	if invBtn then
		invBtn.MouseButton1Click:Connect(function()
			refreshInventoryModal()
			openModal(inventoryModal)
		end)
	end
	if shopBtn then
		shopBtn.MouseButton1Click:Connect(function()
			refreshShopModal()
			openModal(shopModal)
		end)
	end
end

-- Горячие клавиши
local function bindHotkeys()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			closeAllModals()
		elseif input.KeyCode == Enum.KeyCode.Tab then
			draftBuild = table.clone(state.WorkshopBuild or GooberConfig.GetDefaultWorkshopBuild())
			isWorkshopOpen = true
			refreshWorkshopModal()
			openModal(workshopModal)
			isWorkshopOpen = true
		end
	end)
end

-- ============================================================================
-- ПУБЛИЧНОЕ API
-- ============================================================================

function UIController.GetState(): any
	return state
end

function UIController.GetDraftBuild(): GooberConfig.WorkshopBuild
	return table.clone(draftBuild)
end

function UIController.ShowToast(message: string, kind: string?)
	showToast(message, kind)
end

function UIController.CloseModals()
	closeAllModals()
end

function UIController.Init()
	local root = ensureRootGui()
	buildTopBar(root)
	buildWorkshopModal(root)
	buildInventoryModal(root)
	buildBaseModal(root)
	buildShopModal(root)
	buildLandingModal(root)
	bindRemotes()
	bindTopBarButtons()
	bindHotkeys()
	refreshTopBar()
	refreshShopModal()
	refreshBaseModal()

	-- Клик по затемнению = закрыть модалки
	root.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			-- Закрываем только если клик не по модалке: проверяем GUIAtPosition
			-- Упрощённо: Escape уже закрывает; клик по пустой зоне не трогаем
		end
	end)

	-- Обновляем таймер инкубации каждую секунду (если открыт Workshop)
	task.spawn(function()
		while true do
			task.wait(0.4)
			if state.IsIncubating and state.IncubateRemaining then
				state.IncubateRemaining = math.max(0, (state.IncubateRemaining :: number) - 0.4)
				refreshTopBar()
			end
		end
	end)
end

return UIController
