--[[=====================================================================
    TbiGui Window - Beta   |   UI recreation (Roblox / Luau)
    ---------------------------------------------------------------------
    Что это:
        Окно "TbiGui Window - Beta" из скриншотов, перерисованное кодом
        (без картинок-ассетов): шапка с логотипом, строкой вкладок
        (Main / Autofarm + круглая кнопка "..."), светлая панель контента
        и чёрные строки внутри.
    Что убрано (как просили):
        * вкладка "Bucks transfer"
        * вкладка "Extras"
        * последняя кнопка в разделе "Pet Selection" (вкладка Autofarm)
    Что уже работает (это чистый интерфейс, игровой логики нет):
        * перетаскивание окна за шапку
        * переключение вкладок Main / Autofarm
        * слайдеры тянутся мышкой/пальцем и меняют только свой текст
        * переключатели (toggle) включаются/выключаются визуально
        * крестик скрывает окно, вернуть - кнопка "T" слева
          или клавиши RightControl / K
    Куда вставлять:
        LocalScript в StarterPlayer > StarterPlayerScripts
        (или выполнить через executor).
=======================================================================]]
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
--=====================================================================
-- ТЕМА (цвета подобраны по скриншотам)
--=====================================================================
local Theme = {
	WindowTop     = Color3.fromRGB(60, 60, 65),
	WindowBottom  = Color3.fromRGB(28, 28, 31),
	Panel         = Color3.fromRGB(46, 46, 50),
	Row           = Color3.fromRGB(10, 10, 12),
	RowStroke     = Color3.fromRGB(56, 56, 62),
	Text          = Color3.fromRGB(238, 238, 242),
	TextDim       = Color3.fromRGB(112, 112, 120),
	TextSection   = Color3.fromRGB(206, 206, 213),
	TabSelected   = Color3.fromRGB(226, 226, 231),
	TabSelectedTx = Color3.fromRGB(26, 26, 30),
	Icon          = Color3.fromRGB(226, 226, 231),
	Accent        = Color3.fromRGB(45, 126, 214),
	Track         = Color3.fromRGB(17, 27, 42),
	TrackStroke   = Color3.fromRGB(56, 68, 88),
	ToggleOff     = Color3.fromRGB(86, 86, 92),
	ToggleOn      = Color3.fromRGB(45, 126, 214),
	Knob          = Color3.fromRGB(240, 240, 244),
	Divider       = Color3.fromRGB(74, 74, 80),
	LogoTop       = Color3.fromRGB(236, 92, 92),
	LogoBottom    = Color3.fromRGB(168, 32, 32),
	Swatch        = Color3.fromRGB(74, 74, 56),
	ScrollBar     = Color3.fromRGB(96, 96, 104),
}
local FONT        = Enum.Font.Gotham
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_BOLD   = Enum.Font.GothamBold
--=====================================================================
-- ХЕЛПЕРЫ
--=====================================================================
local function new(className, props)
	local inst = Instance.new(className)
	if props then
		for key, value in pairs(props) do
			if value ~= nil then
				inst[key] = value
			end
		end
	end
	return inst
end
local function addCorner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end
local function addStroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end
local function addPadding(parent, top, right, bottom, left)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
		Parent = parent,
	})
end
local function addList(parent, padding, direction, halign, valign)
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end
local function label(parent, props)
	props = props or {}
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or Theme.Text
	props.TextSize = props.TextSize or 14
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	props.RichText = false
	if props.AutomaticSize == nil then
		props.AutomaticSize = Enum.AutomaticSize.None
	end
	return new("TextLabel", props)
end
local function transparent(parent, size, position, anchor)
	return new("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = size or UDim2.fromOffset(16, 16),
		Position = position,
		AnchorPoint = anchor or Vector2.new(0.5, 0.5),
		Parent = parent,
	})
end
--=====================================================================
-- ИКОНКИ (рисуются из Frame'ов, без rbxassetid)
--=====================================================================
local function iconInfo(parent)
	local box = transparent(parent, UDim2.fromOffset(18, 18), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	local circle = new("Frame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), Parent = box,
	})
	addCorner(circle, 9)
	addStroke(circle, Theme.Text, 1.4)
	label(circle, {
		Text = "i", Font = FONT_BOLD, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), Parent = circle,
	})
	return box
end
local function iconCoin(parent)
	local box = transparent(parent, UDim2.fromOffset(18, 18), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	local circle = new("Frame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), Parent = box,
	})
	addCorner(circle, 9)
	addStroke(circle, Theme.Text, 1.4)
	label(circle, {
		Text = "$", Font = FONT_BOLD, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), Parent = circle,
	})
	return box
end
local function iconBottle(parent)
	local box = transparent(parent, UDim2.fromOffset(18, 18), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	local body = new("Frame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(10, 12),
		Position = UDim2.new(0.5, 0, 0.5, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = box,
	})
	addCorner(body, 3)
	addStroke(body, Theme.Text, 1.3)
	new("Frame", {
		BackgroundColor3 = Theme.Text, BorderSizePixel = 0,
		Size = UDim2.fromOffset(5, 6),
		Position = UDim2.new(0.5, 0, 0.5, -6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = box,
	})
	return box
end
local function iconMonitor(parent, color)
	color = color or Theme.Icon
	local box = transparent(parent, UDim2.fromOffset(16, 16), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	local screen = new("Frame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(15, 11),
		Position = UDim2.new(0.5, 0, 0.5, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = box,
	})
	addCorner(screen, 2)
	addStroke(screen, color, 1.4)
	new("Frame", {
		BackgroundColor3 = color, BorderSizePixel = 0,
		Size = UDim2.fromOffset(7, 1.4),
		Position = UDim2.new(0.5, 0, 0.5, 6.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = box,
	})
	return box
end
-- ">" - стрелка-курсор для вкладки Autofarm
local function iconCursor(parent, color)
	color = color or Theme.Icon
	local box = transparent(parent, UDim2.fromOffset(16, 16), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	new("Frame", {
		BackgroundColor3 = color, BorderSizePixel = 0,
		Size = UDim2.fromOffset(8, 1.6),
		Position = UDim2.new(0.5, -2, 0.5, -2),
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
		Parent = box,
	})
	new("Frame", {
		BackgroundColor3 = color, BorderSizePixel = 0,
		Size = UDim2.fromOffset(8, 1.6),
		Position = UDim2.new(0.5, -2, 0.5, 2),
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -45,
		Parent = box,
	})
	return box
end
local function iconSearch(parent)
	local box = transparent(parent, UDim2.fromOffset(16, 16), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	local glass = new("Frame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.fromOffset(1, 1),
		Parent = box,
	})
	addCorner(glass, 6)
	addStroke(glass, Theme.Icon, 1.5)
	new("Frame", {
		BackgroundColor3 = Theme.Icon, BorderSizePixel = 0,
		Size = UDim2.fromOffset(6, 1.5),
		Position = UDim2.fromOffset(11, 11),
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
		Parent = box,
	})
	return box
end
local function iconNote(parent)
	local box = transparent(parent, UDim2.fromOffset(16, 16), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	new("Frame", {
		BackgroundColor3 = Theme.Icon, BorderSizePixel = 0,
		Size = UDim2.fromOffset(1.6, 9),
		Position = UDim2.new(0.5, 2, 0.5, -3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = box,
	})
	local head = new("Frame", {
		BackgroundColor3 = Theme.Icon, BorderSizePixel = 0,
		Size = UDim2.fromOffset(6, 5),
		Position = UDim2.new(0.5, -1, 0.5, 3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = box,
	})
	addCorner(head, 3)
	return box
end
local function iconCopy(parent)
	local box = transparent(parent, UDim2.fromOffset(16, 16), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	local back = new("Frame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(9, 9), Position = UDim2.fromOffset(1, 1),
		Parent = box,
	})
	addCorner(back, 2)
	addStroke(back, Theme.Icon, 1.3)
	local front = new("Frame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(9, 9), Position = UDim2.fromOffset(6, 6),
		Parent = box,
	})
	addCorner(front, 2)
	addStroke(front, Theme.Icon, 1.3)
	return box
end
local function iconClose(parent)
	local box = transparent(parent, UDim2.fromOffset(16, 16), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	new("Frame", {
		BackgroundColor3 = Theme.Icon, BorderSizePixel = 0,
		Size = UDim2.fromOffset(10, 1.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
		Parent = box,
	})
	new("Frame", {
		BackgroundColor3 = Theme.Icon, BorderSizePixel = 0,
		Size = UDim2.fromOffset(10, 1.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -45,
		Parent = box,
	})
	return box
end
local function iconDots(parent, color)
	color = color or Theme.Icon
	local box = transparent(parent, UDim2.fromOffset(14, 14), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	for i = -1, 1 do
		local dot = new("Frame", {
			BackgroundColor3 = color, BorderSizePixel = 0,
			Size = UDim2.fromOffset(3, 3),
			Position = UDim2.new(0.5, i * 4.5, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = box,
		})
		addCorner(dot, 2)
	end
	return box
end
local function iconChevron(parent, color)
	color = color or Theme.Text
	local box = transparent(parent, UDim2.fromOffset(12, 12), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
	new("Frame", {
		BackgroundColor3 = color, BorderSizePixel = 0,
		Size = UDim2.fromOffset(7, 1.5),
		Position = UDim2.new(0.5, -2, 0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
		Parent = box,
	})
	new("Frame", {
		BackgroundColor3 = color, BorderSizePixel = 0,
		Size = UDim2.fromOffset(7, 1.5),
		Position = UDim2.new(0.5, 2, 0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -45,
		Parent = box,
	})
	return box
end
local function recolorIcon(holder, color)
	for _, item in ipairs(holder:GetDescendants()) do
		if item:IsA("Frame") then
			local stroke = item:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = color
			end
			if item.BackgroundTransparency < 1 and not item:FindFirstChildOfClass("UIStroke") then
				item.BackgroundColor3 = color
			end
		end
	end
end
--=====================================================================
-- ПЕРЕТАСКИВАНИЕ
--=====================================================================
local function makeDraggable(frame, handle)
	handle = handle or frame
	local dragging = false
	local dragInput, dragStart, startPos
	handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if input.Target and input.Target:IsA("GuiObject") then
			local node = input.Target
			while node and node ~= frame do
				if node:IsA("GuiButton") then
					return
				end
				node = node.Parent
			end
		end
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end)
	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end
--=====================================================================
-- КОРЕНЬ
--=====================================================================
local screenGui = new("ScreenGui", {
	Name = "TbiGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 100,
	Parent = PlayerGui,
})
local WINDOW_W, WINDOW_H = 560, 532
local HEADER_H, TABS_H = 44, 44
local window = new("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = screenGui,
})
addCorner(window, 10)
addStroke(window, Color3.fromRGB(70, 70, 76), 1, 0.25)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Theme.WindowTop, Theme.WindowBottom),
	Parent = window,
})
local uiScale = new("UIScale", { Scale = 1, Parent = window })
local setOpen -- forward declaration (используется в кнопке-крестике)
--=====================================================================
-- ШАПКА
--=====================================================================
local header = new("Frame", {
	Name = "Header",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, HEADER_H),
	Parent = window,
})
local logo = new("Frame", {
	Name = "Logo",
	Size = UDim2.fromOffset(26, 26),
	Position = UDim2.new(0, 14, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = Theme.LogoTop,
	BorderSizePixel = 0,
	Parent = header,
})
addCorner(logo, 7)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Theme.LogoTop, Theme.LogoBottom),
	Parent = logo,
})
label(logo, {
	Text = "T", Font = FONT_BOLD, TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = logo,
})
label(header, {
	Name = "Title",
	Text = "TbiGui Window - Beta",
	Font = FONT_MEDIUM,
	TextSize = 15,
	Position = UDim2.new(0, 50, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.new(0, 240, 1, 0),
	Parent = header,
})
local headerIcons = {
	{ offset = -136, builder = iconSearch },
	{ offset = -104, builder = iconNote },
	{ offset = -72,  builder = iconCopy },
	{ offset = -34,  builder = iconClose, close = true },
}
for _, cfg in ipairs(headerIcons) do
	local btn = new("TextButton", {
		Name = "HeaderIcon",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, cfg.offset, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = header,
	})
	local holder = transparent(btn, UDim2.fromOffset(16, 16), UDim2.fromScale(0.5, 0.5))
	cfg.builder(holder)
	if cfg.close then
		btn.MouseButton1Click:Connect(function()
			if setOpen then setOpen(false) end
		end)
	end
end
makeDraggable(window, header)
--=====================================================================
-- СТРОКА ВКЛАДОК
--=====================================================================
local tabBar = new("Frame", {
	Name = "TabBar",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, HEADER_H),
	Size = UDim2.new(1, 0, 0, TABS_H),
	Parent = window,
})
addPadding(tabBar, 0, 12, 0, 14)
addList(tabBar, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
local contentPanel = new("Frame", {
	Name = "ContentPanel",
	BackgroundColor3 = Theme.Panel,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 0, HEADER_H + TABS_H),
	Size = UDim2.new(1, 0, 1, -(HEADER_H + TABS_H)),
	Parent = window,
})
local tabs = {}
local activeTab
local function selectTab(tab)
	activeTab = tab
	for _, item in ipairs(tabs) do
		local selected = (item == tab)
		item.text.TextColor3 = selected and Theme.TabSelectedTx or Theme.Text
		TweenService:Create(
			item.button,
			TweenInfo.new(0.15),
			{ BackgroundTransparency = selected and 0 or 1 }
		):Play()
		recolorIcon(item.iconHolder, selected and Theme.TabSelectedTx or Theme.Text)
		item.content.Visible = selected
	end
end
local function createTab(order, name, iconBuilder)
	local btn = new("TextButton", {
		Name = name .. "Tab",
		BackgroundColor3 = Theme.TabSelected,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.new(0, 0, 0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = tabBar,
	})
	addCorner(btn, 9)
	addPadding(btn, 0, 14, 0, 12)
	addList(btn, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local iconHolder = transparent(btn, UDim2.fromOffset(16, 16), nil, nil)
	iconHolder.LayoutOrder = 1
	iconBuilder(iconHolder, Theme.Text)
	local text = label(btn, {
		Text = name,
		Font = FONT_MEDIUM,
		TextSize = 14,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = btn,
	})
	local scroll = new("ScrollingFrame", {
		Name = name .. "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.ScrollBar,
		ScrollBarImageTransparency = 0.3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		Parent = contentPanel,
	})
	addPadding(scroll, 12, 14, 14, 14)
	addList(scroll, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	local tab = { button = btn, text = text, iconHolder = iconHolder, content = scroll, name = name }
	table.insert(tabs, tab)
	btn.MouseButton1Click:Connect(function()
		selectTab(tab)
	end)
	return tab
end
-- круглая кнопка "..." в конце строки вкладок
local dots = new("TextButton", {
	Name = "More",
	BackgroundColor3 = Theme.TabSelected,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Size = UDim2.fromOffset(26, 26),
	LayoutOrder = 99,
	Parent = tabBar,
})
addCorner(dots, 13)
iconDots(transparent(dots, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5)), Theme.TabSelectedTx)
--=====================================================================
-- СТРОКИ КОНТЕНТА
--=====================================================================
local function addSection(parent, order, text)
	return label(parent, {
		Name = "Section",
		Text = text,
		Font = FONT,
		TextSize = 13,
		TextColor3 = Theme.TextSection,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = order,
		Parent = parent,
	})
end
local function addDivider(parent, order)
	return new("Frame", {
		Name = "Divider",
		BackgroundColor3 = Theme.Divider,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = order,
		Parent = parent,
	})
end
local function addRow(parent, order, height)
	local row = new("Frame", {
		Name = "Row",
		BackgroundColor3 = Theme.Row,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height or 46),
		LayoutOrder = order,
		Parent = parent,
	})
	addCorner(row, 8)
	addStroke(row, Theme.RowStroke, 1, 0.5)
	return row
end
local function rowLabel(row, text, widthOffset, size, color)
	return label(row, {
		Name = "RowLabel",
		Text = text,
		TextSize = size or 15,
		TextColor3 = color or Theme.Text,
		Size = UDim2.new(1, widthOffset or -60, 1, -8),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextWrapped = true,
		Parent = row,
	})
end
local function addInfoRow(parent, order, iconBuilder, text, height)
	local row = addRow(parent, order, height or 46)
	local holder = transparent(row, UDim2.fromOffset(18, 18), UDim2.new(0, 16, 0.5, 0), Vector2.new(0, 0.5))
	iconBuilder(holder)
	label(row, {
		Name = "InfoText",
		Text = text,
		TextSize = 14,
		Size = UDim2.new(1, -60, 1, -10),
		Position = UDim2.new(0, 46, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextWrapped = true,
		Parent = row,
	})
	return row
end
local function makeSlider(parent, config)
	local track = new("TextButton", {
		Name = "Slider",
		BackgroundColor3 = Theme.Track,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(252, 24),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = parent,
	})
	addCorner(track, 12)
	addStroke(track, Theme.TrackStroke, 1, 0.3)
	local fill = new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = track,
	})
	addCorner(fill, 12)
	local valueText = label(track, {
		Name = "Value",
		Text = "",
		TextSize = 14,
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
		Parent = track,
	})
	local minValue = config.min or 0
	local maxValue = config.max or 100
	local value = config.value or minValue
	local step = config.step
	local format = config.format or function(v) return tostring(math.floor(v + 0.5)) end
	local onChange = config.onChanged
	local function render()
		local alpha = 0
		if maxValue > minValue then
			alpha = (value - minValue) / (maxValue - minValue)
		end
		alpha = math.clamp(alpha, 0, 1)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		valueText.Text = format(value)
	end
	local function setValueFromX(x)
		local width = math.max(track.AbsoluteSize.X, 1)
		local rel = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		local raw = minValue + (maxValue - minValue) * rel
		if step then
			raw = math.floor(raw / step + 0.5) * step
		end
		value = math.clamp(raw, minValue, maxValue)
		render()
		if onChange then
			onChange(value)
		end
	end
	local dragging = false
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setValueFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setValueFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	render()
	return track
end
local function addSliderRow(parent, order, text, config)
	local row = addRow(parent, order, 46)
	rowLabel(row, text, -300)
	makeSlider(row, config)
	return row
end
local function addToggleRow(parent, order, text, defaultState, height)
	local row = addRow(parent, order, height or 46)
	rowLabel(row, text, -70, 14)
	local state = defaultState and true or false
	local track = new("TextButton", {
		Name = "Toggle",
		BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(30, 17),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = row,
	})
	addCorner(track, 9)
	local knob = new("Frame", {
		Name = "Knob",
		BackgroundColor3 = Theme.Knob,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(13, 13),
		Position = UDim2.new(0, state and 15 or 2, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = track,
	})
	addCorner(knob, 7)
	track.MouseButton1Click:Connect(function()
		state = not state
		TweenService:Create(
			track, TweenInfo.new(0.15),
			{ BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff }
		):Play()
		TweenService:Create(
			knob, TweenInfo.new(0.15),
			{ Position = UDim2.new(0, state and 15 or 2, 0.5, 0) }
		):Play()
	end)
	return track
end
local function addColorRow(parent, order, text, color)
	local row = addRow(parent, order, 46)
	rowLabel(row, text, -70, 15)
	local swatch = new("Frame", {
		Name = "Swatch",
		BackgroundColor3 = color or Theme.Swatch,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(30, 22),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = row,
	})
	addCorner(swatch, 5)
	addStroke(swatch, Theme.RowStroke, 1, 0.2)
	return swatch
end
local function addActionRow(parent, order, text, actionText)
	local row = addRow(parent, order, 46)
	rowLabel(row, text, -200, 15)
	label(row, {
		Name = "Action",
		Text = actionText,
		TextSize = 14,
		TextColor3 = Theme.TextDim,
		Size = UDim2.new(0, 170, 1, 0),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	return row
end
local function addDropdownRow(parent, order, text, options, defaultIndex)
	local row = addRow(parent, order, 46)
	rowLabel(row, text, -170, 15)
	local holder = transparent(row, UDim2.new(0, 130, 1, 0), UDim2.new(1, -16, 0.5, 0), Vector2.new(1, 0.5))
	label(holder, {
		Name = "Value",
		Text = options[defaultIndex] or "None",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -18, 1, 0),
		Parent = holder,
	})
	iconChevron(transparent(holder, UDim2.fromOffset(12, 12), UDim2.new(1, -6, 0.5, 0), Vector2.new(1, 0.5)))
	return row
end
--=====================================================================
-- ВКЛАДКА "MAIN"
--=====================================================================
local mainTab = createTab(1, "Main", iconMonitor)
local main = mainTab.content
addSection(main, 1, "Main")
addInfoRow(main, 2, iconInfo, "This adopt me script is in beta and still under development! There may still be bugs", 50)
addDivider(main, 3)
addSliderRow(main, 4, "Player Walk Speed", {
	min = 1, max = 50, value = 16, step = 1,
	format = function(v) return string.format("%d WalkSpeed", v) end,
})
addSliderRow(main, 5, "Player Jump Power", {
	min = 1, max = 100, value = 50, step = 1,
	format = function(v) return string.format("%d JumpPower", v) end,
})
addSection(main, 6, "Performance")
addToggleRow(main, 7, "Disable Rendering (makes the screen white, helps to reduce lags during afk grinding)", false, 50)
addSliderRow(main, 8, "Tick Delay", {
	min = 0, max = 10, value = 2.2,
	format = function(v) return string.format("%.1f Seconds", v) end,
})
addSliderRow(main, 9, "Fps cap", {
	min = 10, max = 240, value = 60, step = 5,
	format = function(v) return string.format("%d fps", v) end,
})
--=====================================================================
-- ВКЛАДКА "AUTOFARM"
--=====================================================================
local farmTab = createTab(2, "Autofarm", iconCursor)
local farm = farmTab.content
addSection(farm, 1, "Info")
addInfoRow(farm, 2, iconCoin, "You earned: 10 Bucks")
addInfoRow(farm, 3, iconBottle, "You farmed: 0 Age Potions")
addToggleRow(farm, 4, "Disable Information (Might reduce lags)", false)
addSection(farm, 5, "Settings")
addColorRow(farm, 6, "Pick Color for Platform", Theme.Swatch)
addActionRow(farm, 7, "Destroy Platform", "button")
addDropdownRow(farm, 8, "Select allments to disable them", { "None", "All", "Selected" }, 1)
addSection(farm, 9, "Pet Selection")
-- последняя кнопка (Pet Selection) намеренно не создана
selectTab(mainTab)
--=====================================================================
-- СКРЫТИЕ / ВОЗВРАТ ОКНА
--=====================================================================
local reopen = new("TextButton", {
	Name = "Reopen",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = Theme.LogoTop,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	Parent = screenGui,
})
addCorner(reopen, 12)
addStroke(reopen, Color3.fromRGB(96, 96, 104), 1, 0.3)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Theme.LogoTop, Theme.LogoBottom),
	Parent = reopen,
})
label(reopen, {
	Text = "T", Font = FONT_BOLD, TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1), Parent = reopen,
})
local extraScale = new("UIScale", { Scale = 1, Parent = reopen })
function setOpen(open)
	window.Visible = open
	reopen.Visible = not open
end
reopen.MouseButton1Click:Connect(function()
	setOpen(true)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.K then
		setOpen(not window.Visible)
	end
end)
--=====================================================================
-- МАСШТАБ ПОД РАЗМЕР ЭКРАНА
--=====================================================================
local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 800)
	local scale = math.clamp(viewport.X / 700, 0.62, 1)
	uiScale.Scale = scale
	extraScale.Scale = scale
end
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
updateScale()
return screenGui
