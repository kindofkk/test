--[[
================================================================================
  Adopt Me · Pet Needs Autopilot
  Тёмный минималистичный интерфейс + автопилот потребностей питомца
--------------------------------------------------------------------------------
  ЧТО ДЕЛАЕТ
    • Читает потребности питомца (атрибуты / NumberValue / UI-полоски).
    • Находит в мире место или предмет, который закрывает нужную потребность.
    • Сам идёт (или телепортируется) туда и сам выполняет действие
      (ProximityPrompt / ClickDetector / Tool). Игрок не нажимает ничего.
    • Автоматически переключается на ходьбу, если античит откатывает телепорт.

  КАК ЗАПУСКАТЬ
    1. Вставь в executor (Delta / Xeno / Solara / Synapse и т.п.).
    2. Execute. Скрипт стартует сразу (Config.AutoStart = true).
    3. Если питомец не найден — нажми в окне "Debug: скан мира"
       и посмотри вывод в консоли (F9), затем поправь таблицу Config,
       она в самом верху файла и подписана.

  ВАЖНО (честно)
    • Я не вижу текущие внутренности Adopt Me. Имена мест/потребностей в игре
      меняются с обновлениями, поэтому поиск сделан эвристическим, а таблица
      ниже — главное, что нужно подстроить под свою версию игры.
    • Серверная часть Adopt Me валидирует действия. Клиентский скрипт может
      не пройти проверку на некоторых действиях — тогда потребность просто
      не закроется, скрипт отметит это и перейдёт к следующей.
    • Автоматизация нарушает правила Roblox/Adopt Me. Риск блокировки —
      на тебе. Используй только в личных целях и на свой страх и риск.
================================================================================
]]

--==============================================================================
-- 1. CONFIG — ГЛАВНАЯ ТАБЛИЦА ДЛЯ НАСТРОЙКИ
--==============================================================================
local Config = {
	AutoStart = true,            -- запускать автопилот сразу после Execute
	Threshold = 55,              -- закрывать потребность, если значение ниже этого (0-100)
	CriticalThreshold = 25,      -- такие потребности имеют приоритет
	ScanInterval = 0.75,         -- пауза между циклами, сек
	ActionTimeout = 14,          -- максимум секунд на одну потребность
	CooldownAfterSuccess = 6,    -- пауза для потребности после успеха, сек
	CooldownAfterFail = 20,      -- пауза после неудачи, сек
	Teleport = true,             -- true = телепорт, false = только ходьба
	AutoFallbackToWalk = true,   -- если телепорт откатывает античит — идти пешком
	UsePathfinding = true,       -- обход препятствий при ходьбе
	AntiAfk = true,              -- не выкидывать за неактивность
	Debug = true,                -- подробный лог в консоль (F9)

	-- Приоритет обработки потребностей (сверху вниз)
	Priority = { "Hunger", "Thirst", "Sleep", "Hygiene", "Fun", "Bathroom" },

	-- ПАТТЕРНЫ ПОИСКА МЕСТА/ПРЕДМЕТА ДЛЯ КАЖДОЙ ПОТРЕБНОСТИ.
	-- Сравнение по подстроке без учёта регистра: имя объекта, имя родителя
	-- и имена предков до 3 уровней. Дописывай свои варианты через запятую.
	-- Полезно: нажми "Debug: скан мира" и посмотри реальные имена в консоли.
	Locations = {
		Hunger   = { "pet food", "food bowl", "pet bowl", "feeder", "food", "kibble", "treat" },
		Thirst   = { "water bowl", "pet water", "water", "drink", "fountain", "bottle" },
		Sleep    = { "pet bed", "bed", "sleep", "pillow", "crib", "basket" },
		Hygiene  = { "bath", "shower", "soap", "wash", "tub", "spa", "groom" },
		Fun      = { "toy", "ball", "play", "chew", "rope", "frisbee", "stick" },
		Bathroom = { "toilet", "litter", "potty", "bathroom", "diaper" },
	},

	-- Дополнительные теги CollectionService, которыми помечены питомцы/нужды.
	PetTags = { "Pet", "Pets", "PetNeeds" },

	-- Имена Value-объектов и атрибутов, из которых читаются потребности.
	NeedKeys = {
		Hunger   = { "Hunger", "Food", "Satiety" },
		Thirst   = { "Thirst", "Water", "Hydration" },
		Sleep    = { "Sleep", "Energy", "Rest" },
		Hygiene  = { "Hygiene", "Clean", "Cleanliness" },
		Fun      = { "Fun", "Happiness", "Play" },
		Bathroom = { "Bathroom", "Bladder", "Potty" },
	},
}

--==============================================================================
-- 2. СЕРВИСЫ И ЗАЩИТА ОТ ДВОЙНОГО ЗАПУСКА
--==============================================================================
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local CollectionService  = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualUser        = game:GetService("VirtualUser")

if not game:IsLoaded() then game.Loaded:Wait() end

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("[Autopilot] Нет LocalPlayer, скрипт не может работать здесь.")
	return
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 20)
if not PlayerGui then
	warn("[Autopilot] PlayerGui не найден.")
	return
end

if _G.__AM_PET_AUTOPILOT then
	pcall(function() _G.__AM_PET_AUTOPILOT:Destroy() end)
end

local Alive = true

local function log(...)
	if Config.Debug then
		print("[PetAutopilot]", ...)
	end
end

--==============================================================================
-- 3. ТЕМА (тёмный минимализм)
--==============================================================================
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local Theme = {
	Bg           = Color3.fromRGB(15, 16, 20),
	Surface      = Color3.fromRGB(22, 24, 30),
	SurfaceAlt   = Color3.fromRGB(29, 32, 39),
	Stroke       = Color3.fromRGB(44, 48, 58),
	Text         = Color3.fromRGB(236, 239, 245),
	Muted        = Color3.fromRGB(136, 144, 160),
	Accent       = Color3.fromRGB(92, 142, 255),
	AccentSoft   = Color3.fromRGB(56, 84, 156),
	Success      = Color3.fromRGB(78, 214, 152),
	Warn         = Color3.fromRGB(255, 187, 86),
	Danger       = Color3.fromRGB(255, 96, 110),
	Track        = Color3.fromRGB(38, 41, 50),
}

--==============================================================================
-- 4. УТИЛИТЫ
--==============================================================================
local function create(class, props, children)
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then inst[k] = v end
		end
	end
	if children then
		for _, child in ipairs(children) do child.Parent = inst end
	end
	if props and props.Parent then inst.Parent = props.Parent end
	return inst
end

local function corner(radius) return create("UICorner", { CornerRadius = UDim.new(0, radius) }) end
local function stroke(color, thickness, transparency)
	return create("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end
local function pad(top, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or top or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
		PaddingLeft = UDim.new(0, left or right or top or 0),
	})
end

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
	return nil
end

local function tween(inst, time, props, style)
	local info = TweenInfo.new(time or 0.18, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function round(v, step)
	if not step or step <= 0 then return v end
	return math.floor(v / step + 0.5) * step
end

local function lower(s)
	return string.lower(tostring(s or ""))
end

--==============================================================================
-- 5. UI-БИБЛИОТЕКА
--==============================================================================
local UI = {}

local gui = create("ScreenGui", {
	Name = "PetAutopilotUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 9999,
	Parent = (gethui and gethui()) or PlayerGui,
})

_G.__AM_PET_AUTOPILOT = gui

-- Контейнер уведомлений
local toastHolder = create("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.new(0, 300, 0, 400),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}),
})

function UI.notify(title, text, kind)
	local color = Theme.Accent
	if kind == "success" then color = Theme.Success
	elseif kind == "warn" then color = Theme.Warn
	elseif kind == "error" then color = Theme.Danger end

	local card = create("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.04,
		Parent = toastHolder,
	}, {
		corner(10),
		stroke(Theme.Stroke, 1, 0.2),
		create("Frame", { -- акцентная полоса
			Size = UDim2.new(0, 3, 1, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = nil,
		}),
		create("Frame", {
			Name = "Body",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = nil,
		}, {
			pad(10, 12, 10, 14),
			create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
			create("TextLabel", {
				Name = "Title",
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Font = FONT_BOLD,
				Text = title,
				TextColor3 = Theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			create("TextLabel", {
				Name = "Text",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Font = FONT,
				Text = text,
				TextColor3 = Theme.Muted,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),
	})

	card.Position = UDim2.new(0, 40, 0, 0)
	tween(card, 0.22, { Position = UDim2.new(0, 0, 0, 0) })

	task.delay(4, function()
		if not card.Parent then return end
		tween(card, 0.25, { Position = UDim2.new(0, 40, 0, 0), BackgroundTransparency = 1 })
		task.wait(0.28)
		card:Destroy()
	end)
end

-- Окно ------------------------------------------------------------------------
local window = create("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 24, 0.5, 0),
	Size = UDim2.new(0, 360, 0, 470),
	BackgroundColor3 = Theme.Bg,
	BorderSizePixel = 0,
	Parent = gui,
}, {
	corner(14),
	stroke(Theme.Stroke, 1, 0.1),
})

-- Тень
create("ImageLabel", {
	Name = "Shadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 6),
	Size = UDim2.new(1, 40, 1, 40),
	BackgroundTransparency = 1,
	Image = "rbxassetid://5554236805",
	ImageColor3 = Color3.new(0, 0, 0),
	ImageTransparency = 0.55,
	ScaleType = Enum.ScaleType.Slice,
	SliceCenter = Rect.new(23, 23, 277, 277),
	ZIndex = -1,
	Parent = window,
})

-- Заголовок
local header = create("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 52),
	BackgroundTransparency = 1,
	Parent = window,
}, {
	create("Frame", {
		Name = "Dot",
		Position = UDim2.new(0, 18, 0, 21),
		Size = UDim2.new(0, 10, 0, 10),
		BackgroundColor3 = Theme.Muted,
		BorderSizePixel = 0,
		Parent = nil,
	}, { corner(5), stroke(Theme.Bg, 2, 0) }),
	create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 38, 0, 13),
		Size = UDim2.new(1, -80, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = "PET AUTOPILOT",
		TextColor3 = Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}),
	create("TextLabel", {
		Name = "Sub",
		Position = UDim2.new(0, 38, 0, 29),
		Size = UDim2.new(1, -80, 0, 14),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "Adopt Me · auto needs",
		TextColor3 = Theme.Muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}),
	create("Frame", {
		Name = "Sep",
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}),
})

local headerDot = header:FindFirstChild("Dot")
if headerDot then headerDot.Parent = header end

-- Кнопка свернуть
local minBtn = create("TextButton", {
	Name = "Min",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -44, 0, 16),
	Size = UDim2.new(0, 22, 0, 22),
	BackgroundColor3 = Theme.SurfaceAlt,
	AutoButtonColor = false,
	Text = "—",
	Font = FONT_BOLD,
	TextSize = 13,
	TextColor3 = Theme.Muted,
	Parent = header,
}, { corner(6) })

-- Кнопка скрыть полностью
local closeBtn = create("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.new(0, 22, 0, 22),
	BackgroundColor3 = Theme.SurfaceAlt,
	AutoButtonColor = false,
	Text = "×",
	Font = FONT_BOLD,
	TextSize = 15,
	TextColor3 = Theme.Muted,
	Parent = header,
}, { corner(6) })

-- Панель управления
local toggleBar = create("Frame", {
	Name = "ToggleBar",
	Position = UDim2.new(0, 0, 0, 52),
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = Theme.Surface,
	BorderSizePixel = 0,
	Parent = window,
}, {
	create("Frame", {
		Name = "SepBottom",
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}),
})

-- Контент
local content = create("ScrollingFrame", {
	Name = "Content",
	Size = UDim2.new(1, 0, 1, -140),
	Position = UDim2.new(0, 0, 0, 96),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Theme.Stroke,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = window,
}, {
	pad(4, 14, 10, 14),
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})

-- Футер со статусом
local footer = create("Frame", {
	Name = "Footer",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = Theme.Surface,
	BorderSizePixel = 0,
	Parent = window,
}, {
	corner(14),
	create("Frame", {
		Name = "Mask",
		Position = UDim2.new(0, 0, 0, -1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
	}),
})

local statusLabel = create("TextLabel", {
	Name = "Status",
	Position = UDim2.new(0, 16, 0, 8),
	Size = UDim2.new(1, -32, 0, 14),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "Ожидание...",
	TextColor3 = Theme.Muted,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = footer,
})

local statsLabel = create("TextLabel", {
	Name = "Stats",
	Position = UDim2.new(0, 16, 0, 23),
	Size = UDim2.new(1, -32, 0, 13),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "выполнено: 0   ·   ошибок: 0",
	TextColor3 = Theme.Muted,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = footer,
})

function UI.setStatus(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color or Theme.Muted
end

-- Перетаскивание окна
do
	local dragging, dragStart, startPos = false, nil, nil
	local function begin(input)
		dragging = true
		dragStart = input.Position
		startPos = window.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then dragging = false end
		end)
	end
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			begin(input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			window.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

-- Компоненты ------------------------------------------------------------------
local order = 0
local function nextOrder()
	order = order + 1
	return order
end

function UI.section(text)
	return create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = string.upper(text),
		TextColor3 = Theme.Muted,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = nextOrder(),
		Parent = content,
	})
end

function UI.toggle(labelText, default, callback)
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
		Parent = content,
	}, { corner(8) })

	create("TextLabel", {
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -66, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = labelText,
		TextColor3 = Theme.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local track = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 36, 0, 20),
		BackgroundColor3 = default and Theme.Accent or Theme.Track,
		BorderSizePixel = 0,
		Parent = row,
	}, { corner(10) })

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, default and 19 or 3, 0.5, 0),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(7) })

	local button = create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})

	local state = default and true or false
	local function apply(value, fire)
		state = value
		tween(track, 0.16, { BackgroundColor3 = state and Theme.Accent or Theme.Track })
		tween(knob, 0.16, { Position = UDim2.new(0, state and 19 or 3, 0.5, 0) })
		if fire and callback then callback(state) end
	end

	button.MouseButton1Click:Connect(function() apply(not state, true) end)

	return {
		Set = function(v) apply(v, true) end,
		Get = function() return state end,
		Row = row,
	}
end

function UI.slider(labelText, min, max, default, step, callback)
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
		Parent = content,
	}, { corner(8) })

	create("TextLabel", {
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -70, 0, 14),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = labelText,
		TextColor3 = Theme.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.new(0, 60, 0, 14),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = tostring(default),
		TextColor3 = Theme.Accent,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local track = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 10),
		Size = UDim2.new(1, -24, 0, 5),
		BackgroundColor3 = Theme.Track,
		BorderSizePixel = 0,
		Parent = row,
	}, { corner(3) })

	local fill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(3) })

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 13, 0, 13),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	}, { corner(7) })

	local value = default
	local dragging = false

	local function render()
		local alpha = (value - min) / (max - min)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueLabel.Text = tostring(value)
	end

	local function setFromX(x)
		local rel = clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		value = round(min + (max - min) * rel, step)
		if value < min then value = min end
		if value > max then value = max end
		render()
		if callback then callback(value) end
	end

	local hit = create("TextButton", {
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Parent = track,
	})

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	render()
	return {
		Set = function(v) value = clamp(v, min, max); render() end,
		Get = function() return value end,
		Row = row,
	}
end

function UI.button(labelText, callback, accent)
	local btn = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = accent and Theme.AccentSoft or Theme.SurfaceAlt,
		AutoButtonColor = false,
		Font = FONT_BOLD,
		Text = labelText,
		TextColor3 = accent and Theme.Text or Theme.Muted,
		TextSize = 12,
		LayoutOrder = nextOrder(),
		Parent = content,
	}, { corner(8), stroke(accent and Theme.Accent or Theme.Stroke, 1, 0.5) })

	btn.MouseEnter:Connect(function()
		tween(btn, 0.14, { BackgroundColor3 = accent and Theme.Accent or Theme.Track })
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, 0.14, { BackgroundColor3 = accent and Theme.AccentSoft or Theme.SurfaceAlt })
	end)
	btn.MouseButton1Click:Connect(function()
		local ok, err = pcall(callback)
		if not ok then
			UI.notify("Ошибка", tostring(err), "error")
			warn("[PetAutopilot]", err)
		end
	end)
	return btn
end

--==============================================================================
-- 6. ЧТЕНИЕ ПОТРЕБНОСТЕЙ ПИТОМЦА
--==============================================================================
local Pets = {}

local function readNumber(obj)
	if obj:IsA("NumberValue") or obj:IsA("IntValue") or obj:IsA("ValueBase") then
		local ok, v = pcall(function() return obj.Value end)
		if ok and type(v) == "number" then return v end
	end
	local attr = obj:GetAttribute("Value")
	if type(attr) == "number" then return attr end
	return nil
end

-- Ищет значение потребности у конкретного питомца
local function readNeedFromPet(pet, need)
	local keys = Config.NeedKeys[need] or { need }

	-- 1) атрибуты на модели питомца
	for _, key in ipairs(keys) do
		local v = pet:GetAttribute(key)
		if type(v) == "number" then return v end
	end

	-- 2) Value-объекты внутри питомца (любая глубина, разумный лимит)
	local stack = { pet }
	local visited = 0
	while #stack > 0 and visited < 400 do
		local node = table.remove(stack)
		visited = visited + 1
		for _, child in ipairs(node:GetChildren()) do
			local name = lower(child.Name)
			for _, key in ipairs(keys) do
				if name == lower(key) or name:find(lower(key), 1, true) then
					local v = readNumber(child)
					if v then
						if v > 0 and v < 1 then v = v * 100 end -- доля вместо процентов
						return v
					end
				end
			end
			if child:IsA("Model") or child:IsA("Folder") or child:IsA("BillboardGui") then
				table.insert(stack, child)
			end
		end
	end

	-- 3) атрибут с другим регистром имени
	for attrName, v in pairs(pet:GetAttributes()) do
		if lower(attrName) == lower(need) and type(v) == "number" then
			return v
		end
	end

	return nil
end

-- Фолбэк: читаем полоски потребностей прямо из интерфейса игры
local function readNeedFromUI(need)
	local keys = Config.NeedKeys[need] or { need }
	local root = PlayerGui
	local stack = { root }
	local visited = 0
	while #stack > 0 and visited < 1500 do
		local node = table.remove(stack)
		visited = visited + 1
		for _, child in ipairs(node:GetChildren()) do
			local name = lower(child.Name)
			local match = false
			for _, key in ipairs(keys) do
				if name:find(lower(key), 1, true) then match = true break end
			end
			if match then
				local bar = child:FindFirstChildWhichIsA("Frame", true)
				if bar then
					local ok, size = pcall(function() return bar.Size.X.Scale end)
					if ok and type(size) == "number" and size > 0 then
						return size * 100
					end
				end
			end
			if child:IsA("GuiObject") or child:IsA("Folder") then
				table.insert(stack, child)
			end
		end
	end
	return nil
end

local petCache = { list = {}, at = 0 }

function Pets.find()
	local found = {}
	local seen = {}

	local function add(inst)
		if not inst or seen[inst] then return end
		if not (inst:IsA("Model") or inst:IsA("Folder")) then return end
		if inst:IsDescendantOf(LocalPlayer.Character) and inst == LocalPlayer.Character then return end
		seen[inst] = true
		table.insert(found, inst)
	end

	-- по тегам
	for _, tag in ipairs(Config.PetTags) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do add(inst) end
	end

	-- типовые контейнеры
	for _, name in ipairs({ "Pets", "PetsFolder", "PetFolder", "PetStorage" }) do
		local container = workspace:FindFirstChild(name)
		if container then
			for _, child in ipairs(container:GetChildren()) do add(child) end
		end
	end

	-- питомцы рядом с игроком и на участке игрока
	local char = LocalPlayer.Character
	if char then
		local home = char.Parent
		if home then
			for _, child in ipairs(home:GetChildren()) do
				if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then add(child) end
			end
			-- глубокий скан участка дорогой: только если по тегам и прямым детям пусто
			if #found == 0 then
				for _, child in ipairs(home:GetDescendants()) do
					if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid")
						and (child:FindFirstChild("Needs") or child:GetAttribute("Hunger") or child:GetAttribute("Thirst")) then
						add(child)
					end
				end
			end
		end
	end

	-- последний шанс: любая модель, у которой есть признаки нужд
	if #found == 0 then
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Model") and (child:FindFirstChild("Needs") or child:GetAttribute("Hunger")) then
				add(child)
			end
		end
	end

	return found
end

function Pets.get(force)
	local now = os.clock()
	if not force and now - petCache.at < 1.5 then return petCache.list end
	petCache.list = Pets.find()
	petCache.at = now
	if #petCache.list > 0 then
		log("найдено питомцев:", #petCache.list)
	end
	return petCache.list
end

-- Возвращает самую срочную задачу: {pet=, need=, value=, critical=}
function Pets.pickTask()
	local list = Pets.get()
	local best = nil

	-- UI читается один раз на потребность за цикл (это дорогая операция)
	local uiMemo = {}
	local function uiValue(need)
		if uiMemo[need] == nil then
			local v = readNeedFromUI(need)
			uiMemo[need] = (v == nil) and false or v
		end
		local v = uiMemo[need]
		if v == false then return nil end
		return v
	end

	for _, pet in ipairs(list) do
		for _, need in ipairs(Config.Priority) do
			local value = readNeedFromPet(pet, need)
			if value == nil then value = uiValue(need) end
			if value ~= nil then
				local low = value <= Config.Threshold
				if low then
					local priority = indexOf(Config.Priority, need) or 99
					local critical = value <= Config.CriticalThreshold
					local score = (critical and -1000 or 0) + priority * 10 + value
					if not best or score < best.score then
						best = { pet = pet, need = need, value = value, critical = critical, score = score }
					end
				end
			end
		end
		if best and best.critical then break end
	end

	return best
end

--==============================================================================
-- 7. ПОИСК ОБЪЕКТОВ ВЗАИМОДЕЙСТВИЯ В МИРЕ
--==============================================================================
local World = {}

local function matchesNeed(inst, need, depth)
	local patterns = Config.Locations[need]
	if not patterns then return false end

	local node = inst
	local level = 0
	while node and level <= (depth or 3) do
		local name = lower(node.Name)
		for _, pattern in ipairs(patterns) do
			if name:find(lower(pattern), 1, true) then return true end
		end
		-- теги как дополнительный признак
		for _, tag in ipairs(CollectionService:GetTags(node)) do
			for _, pattern in ipairs(patterns) do
				if lower(tag):find(lower(pattern), 1, true) then return true end
			end
		end
		node = node.Parent
		level = level + 1
	end

	return false
end

local interactCache = { at = 0, data = nil }

local function scanInteractables()
	local out = { prompts = {}, clickDetectors = {}, tools = {} }

	for _, inst in ipairs(CollectionService:GetTagged("Interactable")) do
		if inst:IsA("ProximityPrompt") then table.insert(out.prompts, inst) end
		if inst:IsA("ClickDetector") then table.insert(out.clickDetectors, inst) end
	end

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			table.insert(out.prompts, inst)
		elseif inst:IsA("ClickDetector") then
			table.insert(out.clickDetectors, inst)
		end
	end

	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then table.insert(out.tools, item) end
		end
	end

	return out
end

-- Обновляем список не чаще раза в 6 секунд (скан всего workspace дорогой)
local function getInteractables(force)
	local now = os.clock()
	if not force and interactCache.data and (now - interactCache.at) < 6 then
		return interactCache.data
	end
	interactCache.data = scanInteractables()
	interactCache.at = now
	return interactCache.data
end

local function getPromptPart(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then return parent end
	if parent and parent:IsA("Attachment") then
		local p = parent.Parent
		if p and p:IsA("BasePart") then return p end
	end
	return nil
end

local function getClickPart(detector)
	local parent = detector.Parent
	if parent and parent:IsA("BasePart") then return parent end
	return nil
end

-- Ищет ближайший подходящий объект под потребность
function World.findForNeed(need)
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origin = hrp and hrp.Position or Vector3.new(0, 0, 0)

	local interactables = getInteractables()
	local best = nil

	local function consider(inst, part, kind)
		if not part or not matchesNeed(inst, need, 3) then return end
		local dist = (part.Position - origin).Magnitude
		if not best or dist < best.dist then
			best = { instance = inst, part = part, kind = kind, dist = dist }
		end
	end

	for _, prompt in ipairs(interactables.prompts) do
		if prompt.Enabled then
			consider(prompt, getPromptPart(prompt), "prompt")
		end
	end
	for _, detector in ipairs(interactables.clickDetectors) do
		consider(detector, getClickPart(detector), "click")
	end
	for _, tool in ipairs(interactables.tools) do
		if matchesNeed(tool, need, 2) then
			local kind = "tool"
			if not best then
				best = { instance = tool, part = nil, kind = kind, dist = 0 }
			end
		end
	end

	return best
end

-- Дамп мира для калибровки Config
function World.debugScan()
	log("=== ПИТОМЦЫ ===")
	local pets = Pets.get(true)
	if #pets == 0 then
		log("питомцы не найдены — расширь Config.PetTags или проверь структуру workspace")
	end
	for _, pet in ipairs(pets) do
		local parts = { pet.Name, pet.ClassName }
		for _, need in ipairs(Config.Priority) do
			local v = readNeedFromPet(pet, need)
			if v == nil then v = readNeedFromUI(need) end
			table.insert(parts, string.format("%s=%s", need, v and string.format("%.0f", v) or "?"))
		end
		log(table.concat(parts, "  "))
		local attrs = pet:GetAttributes()
		if next(attrs) then
			local buf = {}
			for k, v in pairs(attrs) do table.insert(buf, k .. "=" .. tostring(v)) end
			log("   атрибуты:", table.concat(buf, ", "))
		end
	end

	log("=== ИНТЕРАКТИВНЫЕ ОБЪЕКТЫ (ProximityPrompt) ===")
	local n = 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			n = n + 1
			if n <= 40 then
				local parent = inst.Parent and (inst.Parent.Name .. " [" .. inst.Parent.ClassName .. "]") or "?"
				log(string.format("   %s  →  родитель: %s  (ObjectText=%s)", inst.Name, parent, tostring(inst.ObjectText)))
			end
		end
	end
	log("   всего ProximityPrompt:", n)

	log("=== CLICKDETECTOR ===")
	local c = 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ClickDetector") then
			c = c + 1
			if c <= 25 then
				log(string.format("   %s  →  родитель: %s", inst.Name, inst.Parent and inst.Parent.Name or "?"))
			end
		end
	end
	log("   всего ClickDetector:", c)

	log("=== TOOLS В ИНВЕНТАРЕ ===")
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then log("   " .. item.Name) end
		end
	end

	log("=== REPLICATEDSTORAGE: подозрительные RemoteEvent ===")
	local rs = game:GetService("ReplicatedStorage")
	local count = 0
	for _, inst in ipairs(rs:GetDescendants()) do
		if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
			count = count + 1
			if count <= 40 then log("   " .. inst:GetFullName()) end
		end
	end
	log("   всего remote:", count)
	log("=== КОНЕЦ СКАНА ===")
end

--==============================================================================
-- 8. ПЕРЕМЕЩЕНИЕ
--==============================================================================
local Movement = {}
local teleportBlocked = false

local function getHumanoid()
	local char = LocalPlayer.Character
	if not char then return nil, nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return nil, nil, nil end
	return hum, hrp, char
end

local function walkTo(pos, timeout)
	local hum, hrp = getHumanoid()
	if not hum then return false end

	local start = os.clock()
	local lastPos = hrp.Position
	local stuckSince = os.clock()

	while os.clock() - start < timeout and Alive do
		local hum2, hrp2 = getHumanoid()
		if not hum2 or not hrp2 then return false end

		local dist = (Vector3.new(pos.X, hrp2.Position.Y, pos.Z) - Vector3.new(hrp2.Position.X, hrp2.Position.Y, hrp2.Position.Z)).Magnitude
		if dist <= 4.5 then return true end

		hum2:MoveTo(pos)

		task.wait(0.2)

		local _, hrp3 = getHumanoid()
		if hrp3 then
			if (hrp3.Position - lastPos).Magnitude > 0.6 then
				stuckSince = os.clock()
				lastPos = hrp3.Position
			elseif os.clock() - stuckSince > 1.2 then
				hum2.Jump = true
				stuckSince = os.clock()
			end
		end
	end

	return false
end

local function walkWithPathfinding(pos, timeout)
	local hum, hrp = getHumanoid()
	if not hum or not hrp then return false end

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentMaxSlope = 45,
	})

	local ok = pcall(function() path:ComputeAsync(hrp.Position, pos) end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return walkTo(pos, timeout)
	end

	local start = os.clock()
	for _, waypoint in ipairs(path:GetWaypoints()) do
		if os.clock() - start > timeout or not Alive then return false end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			local h = select(1, getHumanoid())
			if h then h.Jump = true end
		end
		if not walkTo(waypoint.Position, math.min(6, timeout)) then return false end
	end

	local _, hrp2 = getHumanoid()
	if hrp2 and (hrp2.Position - pos).Magnitude < 6 then return true end
	return walkTo(pos, 4)
end

function Movement.goTo(pos, timeout)
	local hum, hrp = getHumanoid()
	if not hrp then return false end

	local dist = (hrp.Position - pos).Magnitude
	if dist <= 5 then return true end

	if Config.Teleport and not teleportBlocked then
		local before = hrp.Position
		local look = CFrame.new(pos + Vector3.new(0, 3, 0), Vector3.new(pos.X, pos.Y + 2, pos.Z))
		pcall(function() hrp.CFrame = look end)
		task.wait(0.25)

		local _, hrp2 = getHumanoid()
		if hrp2 then
			local moved = (hrp2.Position - before).Magnitude
			local close = (hrp2.Position - pos).Magnitude <= 8
			if moved > 3 and close then
				log("телепорт ок, дистанция:", math.floor((hrp2.Position - pos).Magnitude))
				return true
			end
		end

		if Config.AutoFallbackToWalk then
			teleportBlocked = true
			UI.notify("Античит", "Телепорт откатывается — перехожу на ходьбу", "warn")
			log("телепорт откатан античитом, включён режим ходьбы")
		else
			return false
		end
	end

	if Config.UsePathfinding then
		return walkWithPathfinding(pos, timeout)
	end
	return walkTo(pos, timeout)
end

function Movement.resetTeleport()
	teleportBlocked = false
end

function Movement.isTeleportBlocked()
	return teleportBlocked
end

--==============================================================================
-- 9. ВЗАИМОДЕЙСТВИЕ
--==============================================================================
local Interact = {}

local function tryFireProximity(prompt)
	local hold = 0
	pcall(function() hold = prompt.HoldDuration end)

	if fireproximityprompt then
		local ok = pcall(function() fireproximityprompt(prompt, hold) end)
		if ok then return true end
	end

	local ok = pcall(function()
		prompt:InputHoldBegin()
		if hold > 0 then task.wait(hold) else task.wait(0.08) end
		prompt:InputHoldEnd()
	end)
	return ok
end

local function tryFireClick(detector)
	if fireclickdetector then
		local ok = pcall(function() fireclickdetector(detector) end)
		if ok then return true end
	end
	return pcall(function() detector.MouseClick:Fire() end)
end

local function tryUseTool(tool)
	local hum = getHumanoid()
	if not hum then return false end
	local ok = pcall(function()
		hum:EquipTool(tool)
		task.wait(0.35)
		tool:Activate()
		task.wait(0.35)
	end)
	return ok
end

function Interact.use(target, timeout)
	if not target then return false end

	if target.kind == "prompt" then
		return tryFireProximity(target.instance)
	elseif target.kind == "click" then
		return tryFireClick(target.instance)
	elseif target.kind == "tool" then
		return tryUseTool(target.instance)
	end

	return false
end

--==============================================================================
-- 10. АВТОПИЛОТ
--==============================================================================
local Autopilot = {
	busy = false,
	success = 0,
	failed = 0,
	lastAction = "",
}

local cooldowns = {}   -- need -> os.clock() время, до которого не трогаем
local failStreak = {}  -- need -> счётчик подряд неудач

local function onCooldown(need)
	local until_ = cooldowns[need]
	return until_ ~= nil and os.clock() < until_
end

local function setCooldown(need, seconds)
	cooldowns[need] = os.clock() + seconds
end

local function runCycle()
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		UI.setStatus("Персонаж не найден — жду респавна", Theme.Warn)
		return
	end

	local taskInfo = Pets.pickTask()
	if not taskInfo then
		UI.setStatus("Все потребности в норме", Theme.Success)
		Autopilot.lastAction = "idle"
		return
	end

	local need = taskInfo.need
	if onCooldown(need) then
		UI.setStatus(string.format("%s на паузе (недавно обрабатывали)", need), Theme.Muted)
		return
	end

	UI.setStatus(string.format("%s: %.0f%% — ищу место...", need, taskInfo.value),
		taskInfo.critical and Theme.Danger or Theme.Warn)

	local target = World.findForNeed(need)
	if not target then
		UI.setStatus(string.format("%s: место не найдено (см. Config.Locations)", need), Theme.Danger)
		setCooldown(need, Config.CooldownAfterFail)
		log("не найдено место для", need)
		return
	end

	log(string.format("задача %s (%.0f%%), цель: %s [%s]",
		need, taskInfo.value, target.instance:GetFullName(), target.kind))

	-- Путь до цели
	if target.part then
		local pos = target.part.Position
		UI.setStatus(string.format("%s: %.0f%% — иду к %s", need, taskInfo.value, target.part.Name), Theme.Warn)
		local arrived = Movement.goTo(pos, Config.ActionTimeout)
		if not arrived then
			UI.setStatus(string.format("%s: не добрался до цели", need), Theme.Danger)
			setCooldown(need, Config.CooldownAfterFail)
			Autopilot.failed = Autopilot.failed + 1
			return
		end
	end

	-- Действие
	UI.setStatus(string.format("%s: выполняю %s", need, target.kind), Theme.Accent)
	Interact.use(target, Config.ActionTimeout)

	-- Проверка результата
	task.wait(0.8)
	local after = readNeedFromPet(taskInfo.pet, need)
	if after == nil then after = readNeedFromUI(need) end

	local improved = after ~= nil and after > taskInfo.value + 1
	if improved then
		Autopilot.success = Autopilot.success + 1
		Autopilot.lastAction = need
		failStreak[need] = 0
		setCooldown(need, Config.CooldownAfterSuccess)
		UI.notify("Готово", string.format("%s закрыта: %.0f%% → %.0f%%", need, taskInfo.value, after), "success")
		log(string.format("%s улучшена: %.0f -> %.0f", need, taskInfo.value, after))
	else
		Autopilot.failed = Autopilot.failed + 1
		failStreak[need] = (failStreak[need] or 0) + 1
		local penalty = Config.CooldownAfterFail * math.min(failStreak[need], 4)
		setCooldown(need, penalty)
		if failStreak[need] == 1 then
			UI.notify("Не сработало", string.format("%s: сервер не принял действие (цель: %s)", need, target.instance.Name), "warn")
		end
		log(string.format("%s без изменений (было %.0f, стало %s), пауза %ds",
			need, taskInfo.value, after and string.format("%.0f", after) or "?", penalty))
	end
end

local function loop()
	while Alive do
		if Config.Enabled and not Autopilot.busy then
			Autopilot.busy = true
			local ok, err = pcall(runCycle)
			Autopilot.busy = false
			if not ok then
				UI.setStatus("Ошибка цикла: " .. tostring(err), Theme.Danger)
				warn("[PetAutopilot] цикл упал:", err)
				task.wait(1)
			end
		end
		if Alive and statsLabel.Parent then
			statsLabel.Text = string.format("выполнено: %d   ·   ошибок: %d", Autopilot.success, Autopilot.failed)
		end
		task.wait(Config.ScanInterval)
	end
end

--==============================================================================
-- 11. ANTI-AFK
--==============================================================================
-- Подписка создаётся всегда, флаг проверяется на месте, чтобы тумблер в UI работал
LocalPlayer.Idled:Connect(function()
	if not Alive or not Config.AntiAfk then return end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
	log("anti-afk: сброс неактивности")
end)

--==============================================================================
-- 12. СБОРКА ИНТЕРФЕЙСА
--==============================================================================
-- Главный переключатель в шапке панели управления
local masterRow = create("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Parent = toggleBar,
})

create("TextLabel", {
	Position = UDim2.new(0, 18, 0, 12),
	Size = UDim2.new(1, -90, 0, 20),
	BackgroundTransparency = 1,
	Font = FONT_BOLD,
	Text = "АВТОПИЛОТ",
	TextColor3 = Theme.Text,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = masterRow,
})

local masterTrack = create("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.new(0, 44, 0, 24),
	BackgroundColor3 = Config.AutoStart and Theme.Accent or Theme.Track,
	BorderSizePixel = 0,
	Parent = masterRow,
}, { corner(12) })

local masterKnob = create("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, Config.AutoStart and 23 or 3, 0.5, 0),
	Size = UDim2.new(0, 18, 0, 18),
	BackgroundColor3 = Theme.Text,
	BorderSizePixel = 0,
	Parent = masterTrack,
}, { corner(9) })

local function setMaster(on, notify)
	Config.Enabled = on
	tween(masterTrack, 0.16, { BackgroundColor3 = on and Theme.Accent or Theme.Track })
	tween(masterKnob, 0.16, { Position = UDim2.new(0, on and 23 or 3, 0.5, 0) })
	tween(headerDot, 0.2, { BackgroundColor3 = on and Theme.Success or Theme.Muted })
	if on then
		Movement.resetTeleport()
		UI.setStatus("Автопилот запущен", Theme.Success)
	else
		UI.setStatus("Автопилот выключен", Theme.Muted)
	end
	if notify then
		UI.notify(on and "Автопилот включён" or "Автопилот выключен",
			on and "Питомец обслуживается автоматически" or "Скрипт ждёт включения",
			on and "success" or "warn")
	end
end

local masterHit = create("TextButton", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = "",
	Parent = masterRow,
})
masterHit.MouseButton1Click:Connect(function() setMaster(not Config.Enabled, true) end)

-- Секции контента
UI.section("Питомец")

UI.slider("Порог срабатывания (%)", 10, 90, Config.Threshold, 5, function(v)
	Config.Threshold = v
	Config.CriticalThreshold = math.min(Config.CriticalThreshold, v - 5)
end)

UI.slider("Критический порог (%)", 0, 80, Config.CriticalThreshold, 5, function(v)
	Config.CriticalThreshold = v
end)

UI.slider("Интервал сканирования (сек × 0.25)", 1, 12, Config.ScanInterval / 0.25, 1, function(v)
	Config.ScanInterval = v * 0.25
end)

UI.section("Перемещение")

UI.toggle("Телепорт к цели", Config.Teleport, function(v) Config.Teleport = v end)
UI.toggle("Авто-переход на ходьбу", Config.AutoFallbackToWalk, function(v) Config.AutoFallbackToWalk = v end)
UI.toggle("Обход препятствий (Pathfinding)", Config.UsePathfinding, function(v) Config.UsePathfinding = v end)

UI.button("Сбросить блокировку телепорта", function()
	Movement.resetTeleport()
	UI.notify("Готово", "Телепорт снова разрешён", "success")
end)

UI.section("Прочее")

UI.toggle("Anti-AFK", Config.AntiAfk, function(v) Config.AntiAfk = v end)
UI.toggle("Отладочный лог", Config.Debug, function(v) Config.Debug = v end)

UI.button("Debug: скан мира", function()
	World.debugScan()
	UI.notify("Скан готов", "Результат в консоли (F9) → Logs", "success")
end)

UI.button("Обработать всё немедленно", function()
	for need, _ in pairs(cooldowns) do cooldowns[need] = nil end
	UI.notify("Сброшено", "Все паузы сняты", "success")
end, true)

-- Минимизация / скрытие
local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	local target = minimized and UDim2.new(0, 360, 0, 52) or UDim2.new(0, 360, 0, 470)
	tween(window, 0.24, { Size = target })
	content.Visible = not minimized
	footer.Visible = not minimized
	toggleBar.Visible = not minimized
	minBtn.Text = minimized and "+" or "—"
end)

local hidden = false
closeBtn.MouseButton1Click:Connect(function()
	hidden = not hidden
	window.Visible = not hidden
	if hidden then
		UI.notify("UI скрыт", "Автопилот продолжает работать · вернуть: клавиша RightShift", "warn")
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not Alive or not UI then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		hidden = false
		window.Visible = true
	elseif input.KeyCode == Enum.KeyCode.RightControl then
		setMaster(not Config.Enabled, true)
	elseif input.KeyCode == Enum.KeyCode.End then
		Alive = false
		task.wait(0.1)
		gui:Destroy()
		UI = nil
		print("[PetAutopilot] выгружен")
	end
end)

--==============================================================================
-- 13. СТАРТ
--==============================================================================
setMaster(Config.AutoStart, false)
task.spawn(loop)

print([[
[PetAutopilot] запущен.
  RightShift  — показать UI
  RightCtrl   — вкл/выкл автопилот
  End         — выгрузить скрипт
Питомец не найден? Нажми "Debug: скан мира" и посмотри консоль (F9).
]])

if Config.AutoStart then
	UI.notify("Автопилот активен", "Питомец обслуживается без твоего участия", "success")
end
