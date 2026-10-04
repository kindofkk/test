--[[
================================================================================
  Adopt Me · Pet Needs Autopilot
  Тёмный минималистичный интерфейс + автопилот потребностей питомца
--------------------------------------------------------------------------------
  ЧТО ДЕЛАЕТ
    • Читает потребности питомца (атрибуты / NumberValue / UI-полоски).
    • Ищет способ закрыть потребность по стратегиям, по порядку:
        1) кнопки интерфейса игры (панель питомца / потребностей),
        2) объекты мира (ProximityPrompt / ClickDetector),
        3) предметы в инвентаре (Tool),
        4) повтор remote-вызова, записанного режимом "Захват действий".
    • Сам идёт (или телепортируется) к цели и сам выполняет действие.
      Игрок не нажимает ничего.
    • Кнопка "Захват действий" записывает, что именно вызывает игра, когда
      ты руками кормишь/моешь питомца: путь кнопки и remote с аргументами.
      Это главный инструмент калибровки Config под текущую версию игры.
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

	-- Стратегия: сначала пробовать кнопки интерфейса, потом объекты в мире
	PreferGui = true,
	AutoOpenPanel = true,           -- искать и нажимать кнопку открытия панели питомца
	PanelOpenCooldown = 8,          -- не чаще раза в N секунд
	PanelButtons = { "pet needs", "pet care", "needs", "pets", "pet menu", "my pets", "потребности" },

	-- Слова, по которым узнаётся кнопка/объект для потребности (подстроки).
	-- ВАЖНО: именно эту таблицу правим, если игра называет действия иначе.
	Actions = {
		Hunger   = { "feed", "food", "eat", "hungry", "hunger", "корм" },
		Thirst   = { "water", "drink", "thirst", "thirsty", "напоить" },
		Sleep    = { "sleep", "rest", "bed", "tired", "energy", "сон" },
		Hygiene  = { "bath", "wash", "clean", "shower", "groom", "dirty", "купать" },
		Fun      = { "play", "toy", "fun", "happy", "играть" },
		Bathroom = { "toilet", "potty", "bathroom", "bladder", "walk" },
	},

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

-- Встроенный журнал: всё видно в окне, даже если консоль (F9) недоступна
local SESSION_START = os.clock()
local Log = { lines = {}, max = 500, view = nil }

local function joinArgs(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		local ok, s = pcall(tostring, v)
		parts[i] = ok and s or "?"
	end
	return table.concat(parts, " ")
end

function Log.add(text)
	local stamp = string.format("[%6.1f] ", os.clock() - SESSION_START)
	table.insert(Log.lines, stamp .. text)
	while #Log.lines > Log.max do table.remove(Log.lines, 1) end

	if Log.view then
		pcall(function()
			Log.view.Text = table.concat(Log.lines, "\n")
			local holder = Log.view.Parent
			if holder and holder:IsA("ScrollingFrame") then
				holder.CanvasPosition = Vector2.new(0, math.max(0, holder.AbsoluteCanvasSize.Y))
			end
		end)
	end
end

function Log.text()
	return table.concat(Log.lines, "\n")
end

-- Отдаёт отчёт наружу: буфер обмена, файл, либо вкладка "Журнал"
function Log.export()
	local text = Log.text()
	local where = {}

	if setclipboard then
		if pcall(setclipboard, text) then table.insert(where, "скопирован в буфер обмена") end
	end
	if writefile then
		if pcall(writefile, "PetAutopilot_report.txt", text) then
			table.insert(where, "файл PetAutopilot_report.txt")
		end
	end

	if #where == 0 then
		return "Смотри вкладку «Журнал»: нажми «Выделить» и Ctrl+C"
	end
	return "Отчёт: " .. table.concat(where, " · ")
end

local function log(...)
	local text = joinArgs(...)
	Log.add(text)
	if Config.Debug then
		pcall(print, "[PetAutopilot] " .. text)
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

-- Кнопка переключения на вкладку «Журнал»
local logBtn = create("TextButton", {
	Name = "LogToggle",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -72, 0, 16),
	Size = UDim2.new(0, 22, 0, 22),
	BackgroundColor3 = Theme.SurfaceAlt,
	AutoButtonColor = false,
	Text = "≡",
	Font = FONT_BOLD,
	TextSize = 15,
	TextColor3 = Theme.Accent,
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

-- Вкладка «Журнал»: показывает всё, что скрипт делает
local logView = create("ScrollingFrame", {
	Name = "LogView",
	Position = UDim2.new(0, 0, 0, 96),
	Size = UDim2.new(1, 0, 1, -184),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Theme.Stroke,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Visible = false,
	Parent = window,
}, {
	create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}),
	create("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = Log.text(),
		TextColor3 = Theme.Muted,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}),
})

Log.view = logView:FindFirstChild("Text")

-- Кнопки работы с отчётом
local logActions = create("Frame", {
	Name = "LogActions",
	Position = UDim2.new(0, 0, 0, 382),
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = window,
}, {
	create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}),
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- Поле с текстом отчёта: можно выделить и скопировать вручную (Ctrl+A, Ctrl+C)
local reportBox = create("TextBox", {
	Name = "ReportBox",
	Position = UDim2.new(0, 0, 0, 96),
	Size = UDim2.new(1, 0, 1, -184),
	BackgroundColor3 = Theme.Surface,
	BorderSizePixel = 0,
	Font = Enum.Font.Code,
	Text = "",
	TextColor3 = Theme.Text,
	TextSize = 10,
	TextWrapped = true,
	TextEditable = false,
	ClearTextOnFocus = false,
	MultiLine = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Visible = false,
	ZIndex = 5,
	Parent = window,
}, {
	corner(8),
	stroke(Theme.Stroke, 1, 0.3),
	create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}),
})

local function logActionButton(label, callback)
	local btn = create("TextButton", {
		Size = UDim2.new(0.25, -5, 1, 0),
		BackgroundColor3 = Theme.SurfaceAlt,
		AutoButtonColor = false,
		Font = FONT_BOLD,
		Text = label,
		TextColor3 = Theme.Text,
		TextSize = 11,
		Parent = logActions,
	}, { corner(7), stroke(Theme.Stroke, 1, 0.5) })

	btn.MouseButton1Click:Connect(function()
		local ok, err = pcall(callback)
		if not ok then UI.notify("Ошибка", tostring(err), "error") end
	end)
	return btn
end

logActionButton("Копир.", function()
	if not setclipboard then
		UI.notify("Нет доступа", "Исполнитель не даёт setclipboard — жми «Выделить»", "warn")
		return
	end
	pcall(setclipboard, Log.text())
	UI.notify("Скопировано", "Отчёт в буфере обмена", "success")
end)

logActionButton("Файл", function()
	if not writefile then
		UI.notify("Нет доступа", "Исполнитель не даёт writefile — жми «Выделить»", "warn")
		return
	end
	local ok = pcall(writefile, "PetAutopilot_report.txt", Log.text())
	if ok then
		UI.notify("Сохранено", "PetAutopilot_report.txt (папка исполнителя)", "success")
	else
		UI.notify("Не вышло", "Запись файла отклонена", "error")
	end
end)

logActionButton("Выделить", function()
	reportBox.Text = Log.text()
	reportBox.Visible = true
	UI.notify("Текст открыт", "Ctrl+A, затем Ctrl+C — и пришли мне отчёт", "success")
end)

logActionButton("Очистить", function()
	Log.lines = {}
	if Log.view then Log.view.Text = "" end
	reportBox.Visible = false
	UI.notify("Журнал очищен", "Записи удалены", "success")
end)

local logPage = false

function UI.showLog(show)
	logPage = (show == nil) and true or show

	content.Visible = not logPage
	logView.Visible = logPage
	logActions.Visible = logPage
	reportBox.Visible = false

	if logPage and Log.view then
		Log.view.Text = Log.text()
		logView.CanvasPosition = Vector2.new(0, math.max(0, logView.AbsoluteCanvasSize.Y))
	end
end

function UI.isLogShown()
	return logPage
end

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

-- Подсказки в именах элементов, которые являются полосками прогресса
local BAR_HINTS = { "fill", "bar", "progress", "need", "value", "meter", "level", "indicator" }

-- Пытается вытащить процент из найденного элемента интерфейса игры
local function readValueFromGuiNode(node)
	local layer = { node }
	local depth = 0

	while depth < 3 and #layer > 0 do
		local nextLayer = {}
		for _, item in ipairs(layer) do
			-- текст вида "45%" / "45 %"
			if (item:IsA("TextLabel") or item:IsA("TextButton")) then
				local ok, text = pcall(function() return item.Text end)
				if ok and type(text) == "string" and text:find("%%") then
					local num = tonumber(text:match("(%d+%.?%d*)"))
					if num and num >= 0 and num <= 100 then return num end
				end
			end

			-- полоска прогресса: нужен намёк в имени, иначе легко поймать контейнер
			if item:IsA("GuiObject") then
				local name = lower(item.Name)
				local hinted = false
				for _, hint in ipairs(BAR_HINTS) do
					if name:find(hint, 1, true) then hinted = true break end
				end
				if hinted then
					local ok, size = pcall(function() return item.Size.X.Scale end)
					if ok and type(size) == "number" and size >= 0 and size <= 1 then
						return size * 100
					end
				end
			end

			for _, sub in ipairs(item:GetChildren()) do
				if sub:IsA("GuiObject") then table.insert(nextLayer, sub) end
			end
		end
		layer = nextLayer
		depth = depth + 1
	end

	return nil
end

-- Фолбэк: читаем полоски потребностей прямо из интерфейса игры
local function readNeedFromUI(need)
	local keys = Config.NeedKeys[need] or { need }
	local stack = { PlayerGui }
	local visited = 0

	while #stack > 0 and visited < 1500 do
		local node = table.remove(stack)
		visited = visited + 1

		for _, child in ipairs(node:GetChildren()) do
			if child:IsDescendantOf(gui) then
				-- это наша собственная панель: её проценты не считаем
			else
				local name = lower(child.Name)
				local match = false
				for _, key in ipairs(keys) do
					if name:find(lower(key), 1, true) then match = true break end
				end

				if match then
					local value = readValueFromGuiNode(child)
					if value then return value end
				end

				if child:IsA("GuiObject") or child:IsA("Folder") then
					table.insert(stack, child)
				end
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

	-- последний шанс: любая модель с Humanoid в workspace, кроме персонажей игроков
	if #found == 0 then
		local chars = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then chars[plr.Character] = true end
		end
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") and not chars[child] then
				add(child)
			end
		end
	end

	-- отбрасываем чужих питомцев, если удалось отличить своих
	local mine = {}
	for _, pet in ipairs(found) do
		if Pets.isMine(pet) then table.insert(mine, pet) end
	end
	if #mine > 0 then found = mine end

	return found
end

-- Свой ли это питомец: по атрибутам владельца, Value-объектам или близости
function Pets.isMine(pet)
	local uid = LocalPlayer.UserId
	local names = { "Owner", "OwnerId", "OwnerUserId", "Player", "PlayerId", "UserId" }

	for _, key in ipairs(names) do
		local attr = pet:GetAttribute(key)
		if attr ~= nil then
			if typeof(attr) == "number" and attr == uid then return true end
			if typeof(attr) == "string" and attr == LocalPlayer.Name then return true end
			if typeof(attr) == "Instance" and attr == LocalPlayer then return true end
		end
	end

	for _, key in ipairs(names) do
		local child = pet:FindFirstChild(key, true)
		if child then
			local ok, v = pcall(function() return child.Value end)
			if ok and v ~= nil then
				if type(v) == "number" and v == uid then return true end
				if type(v) == "string" and v == LocalPlayer.Name then return true end
				if typeof(v) == "Instance" and v == LocalPlayer then return true end
			end
		end
	end

	-- признаков владельца нет — считаем своим того, кто стоит рядом с персонажем
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local root = pet:FindFirstChild("HumanoidRootPart") or pet:FindFirstChildWhichIsA("BasePart", true)
	if hrp and root then
		return (root.Position - hrp.Position).Magnitude < 70
	end
	return true
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
	local readable = 0

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
				readable = readable + 1
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

	return best, readable
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

-- Кнопка вообще доступна для нажатия?
local function isButtonUsable(btn)
	if not btn.Visible then return false end

	local node = btn
	while node and node ~= PlayerGui do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end

	if btn.Active == false then return false end

	local ok, size = pcall(function() return btn.AbsoluteSize end)
	if ok and size and (size.X < 4 or size.Y < 4) then return false end

	return true
end

-- Совпадает ли кнопка (имя, текст, родители) с паттернами
local function buttonMatches(btn, patterns)
	if not patterns then return false end

	local node = btn
	local level = 0
	while node and level <= 2 do
		local samples = { node.Name }
		if node:IsA("TextButton") or node:IsA("TextLabel") then
			table.insert(samples, node.Text)
		end
		for _, sample in ipairs(samples) do
			local s = lower(sample)
			for _, pattern in ipairs(patterns) do
				if s ~= "" and s:find(lower(pattern), 1, true) then return true end
			end
		end
		node = node.Parent
		level = level + 1
	end

	return false
end

local function collectButtons(filter)
	local out = {}
	local stack = { PlayerGui }
	local visited = 0

	while #stack > 0 and visited < 2500 do
		local node = table.remove(stack)
		visited = visited + 1
		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("GuiButton") then
				if not child:IsDescendantOf(gui) and isButtonUsable(child) and filter(child) then
					table.insert(out, child)
				end
			end
			if child:IsA("GuiObject") or child:IsA("Folder") then
				table.insert(stack, child)
			end
		end
	end

	return out
end

-- Кнопки интерфейса, закрывающие потребность
function World.findGuiForNeed(need)
	local patterns = Config.Actions[need] or Config.Locations[need]
	return collectButtons(function(btn) return buttonMatches(btn, patterns) end)
end

-- Кнопка открытия панели питомца
function World.findPanelButton()
	return collectButtons(function(btn) return buttonMatches(btn, Config.PanelButtons) end)
end

-- Кнопка, в имени/тексте которой встречается произвольная строка (например, имя питомца)
function World.findButtonByText(text)
	if not text or text == "" then return {} end
	return collectButtons(function(btn) return buttonMatches(btn, { tostring(text) }) end)
end

-- Дамп всех кнопок интерфейса (для калибровки)
function World.dumpButtons(limit)
	local list = collectButtons(function() return true end)
	log("видимых кнопок интерфейса (кроме наших):", #list)
	for i, btn in ipairs(list) do
		if i > (limit or 60) then break end
		local text = ""
		pcall(function() text = btn.Text end)
		log(string.format("   %-28s text=%-24s path=%s", btn.Name, tostring(text), btn:GetFullName()))
	end
	return list
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

	log("=== КНОПКИ ИНТЕРФЕЙСА (PlayerGui, кроме наших) ===")
	World.dumpButtons(60)

	log("=== ПИТОМЕЦ: СТРУКТУРА (первый найденный) ===")
	local pets0 = Pets.get(true)
	if pets0[1] then
		local count = 0
		for _, inst in ipairs(pets0[1]:GetDescendants()) do
			count = count + 1
			if count <= 60 then
				local val = ""
				pcall(function()
					if inst:IsA("ValueBase") then val = " = " .. tostring(inst.Value) end
				end)
				log(string.format("   %s [%s]%s", inst:GetFullName(), inst.ClassName, val))
			end
		end
		log("   всего потомков у питомца:", count)
		local attrs = pets0[1]:GetAttributes()
		local buf = {}
		for k, v in pairs(attrs) do table.insert(buf, k .. "=" .. tostring(v)) end
		if #buf > 0 then log("   атрибуты питомца: " .. table.concat(buf, ", ")) end
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
-- 8.5 ЗАХВАТ ДЕЙСТВИЙ: что игра реально вызывает при ручном уходе за питомцем
--==============================================================================
local Capture = { active = false, events = {}, replays = {}, seenButtons = {}, hooked = false }

local function describeValue(v)
	local t = typeof(v)
	if t == "Instance" then return v:GetFullName() end
	if t == "string" then
		if #v > 40 then return string.format("%q..", v:sub(1, 40)) end
		return string.format("%q", v)
	end
	if t == "table" then
		local parts = {}
		for i = 1, math.min(#v, 6) do parts[i] = describeValue(v[i]) end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

-- Какая потребность угадывается по тексту нажатой кнопки
local function needFromText(text)
	local s = lower(text)
	for _, need in ipairs(Config.Priority) do
		for _, pattern in ipairs(Config.Actions[need] or {}) do
			if s:find(lower(pattern), 1, true) then return need end
		end
	end
	return nil
end

function Capture.record(kind, name, extra)
	if not Capture.active then return end
	if #Capture.events >= 400 then return end
	table.insert(Capture.events, { at = os.clock(), kind = kind, name = name, extra = extra })
	log(string.format("[ЗАХВАТ] %s | %s | %s", kind, name, tostring(extra or "")))
end

function Capture.attachButtons()
	if Capture.buttonsAttached then return end
	Capture.buttonsAttached = true

	local function hookButton(btn)
		if Capture.seenButtons[btn] then return end
		Capture.seenButtons[btn] = true
		btn.Activated:Connect(function()
			if not Capture.active then return end
			local text = ""
			pcall(function() text = btn.Text end)
			Capture.record("GUI CLICK", btn:GetFullName(),
				string.format("text=%q vis=%s", tostring(text), tostring(btn.Visible)))

			local need = needFromText(btn.Name .. " " .. tostring(text))
			if need then
				Capture.pendingNeed = need
				Capture.pendingAt = os.clock()
				log("захват: нажатие отнесено к потребности", need)
			end
		end)
	end

	for _, inst in ipairs(PlayerGui:GetDescendants()) do
		if inst:IsA("GuiButton") then hookButton(inst) end
	end
	PlayerGui.DescendantAdded:Connect(function(inst)
		if inst:IsA("GuiButton") then hookButton(inst) end
	end)
end

function Capture.attachRemotes()
	if Capture.hooked then return end
	if not (hookmetamethod and getnamecallmethod and newcclosure) then
		log("захват remote недоступен: исполнитель не даёт hookmetamethod")
		return
	end

	local ok = pcall(function()
		local original
		original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if Capture.active and (method == "FireServer" or method == "InvokeServer") then
				local args = { ... }
				local parts = {}
				for i = 1, math.min(#args, 8) do parts[i] = describeValue(args[i]) end
				local path = (typeof(self) == "Instance") and self:GetFullName() or tostring(self)
				Capture.record("REMOTE " .. method, path, table.concat(parts, ", "))

				local fresh = Capture.pendingNeed and (os.clock() - (Capture.pendingAt or 0) < 2.5)
				if fresh and typeof(self) == "Instance"
					and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
					table.insert(Capture.replays, {
						need = Capture.pendingNeed,
						remote = self,
						args = args,
						at = os.clock(),
					})
					log("захват: remote привязан к потребности", Capture.pendingNeed, path)
				end
			end
			return original(self, ...)
		end))
		Capture.hooked = true
	end)

	if not ok then log("не удалось установить хук __namecall") end
end

function Capture.replaysFor(need)
	local out = {}
	for _, rec in ipairs(Capture.replays) do
		if rec.need == need and rec.remote and rec.remote.Parent then
			table.insert(out, rec)
		end
	end
	return out
end

function Capture.report()
	local lines = { "", "========== ОТЧЁТ ЗАХВАТА ДЕЙСТВИЙ ==========" }
	for _, e in ipairs(Capture.events) do
		table.insert(lines, string.format("[%.1f] %-16s | %s | %s",
			e.at, e.kind, e.name, tostring(e.extra or "")))
	end
	table.insert(lines, string.format("записано remote-повторов: %d", #Capture.replays))
	for _, rec in ipairs(Capture.replays) do
		table.insert(lines, string.format("   %s → %s", rec.need, rec.remote:GetFullName()))
	end
	table.insert(lines, "=============================================")
	local text = table.concat(lines, "\n")
	print(text)
	if setclipboard then pcall(function() setclipboard(text) end) end
	return text
end

function Capture.start(seconds)
	Capture.active = true
	Capture.events = {}
	Capture.replays = {}
	Capture.attachButtons()
	Capture.attachRemotes()
	UI.notify("Захват включён", "Покорми/напои питомца руками — запишу кнопку и remote", "warn")
	Capture.record("START", "ручной режим", "длительность " .. tostring(seconds) .. " сек")

	task.delay(seconds or 60, function()
		Capture.active = false
		Capture.report()
		UI.notify("Захват завершён", "Отчёт в консоли (F9). Повторы remote подключены к автопилоту", "success")
	end)
end

--==============================================================================
-- 9. ДЕЙСТВИЯ: КНОПКИ ИНТЕРФЕЙСА, ОБЪЕКТЫ МИРА, TOOLS, REMOTE
--==============================================================================
local Actions = {}

local VirtualInputManager = game:GetService("VirtualInputManager")
local unpackArgs = table.unpack or unpack

local function tryFireProximity(prompt)
	local hold = 0
	pcall(function() hold = prompt.HoldDuration end)

	if fireproximityprompt then
		local ok = pcall(function() fireproximityprompt(prompt, hold) end)
		if ok then return true end
	end

	return pcall(function()
		prompt:InputHoldBegin()
		if hold > 0 then task.wait(hold) else task.wait(0.08) end
		prompt:InputHoldEnd()
	end)
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
	return pcall(function()
		hum:EquipTool(tool)
		task.wait(0.35)
		tool:Activate()
		task.wait(0.35)
	end)
end

-- Клик по кнопке интерфейса: сигнал (firesignal) либо настоящий виртуальный клик
function Actions.clickGui(button, mode)
	if not button or not button.Parent then return false end

	if mode == "mb1" and firesignal then
		local ok = pcall(function() firesignal(button.MouseButton1Click) end)
		if ok then task.wait(0.15) return true end
		return false
	end

	if mode == "activated" and firesignal then
		local ok = pcall(function() firesignal(button.Activated) end)
		if ok then task.wait(0.15) return true end
		return false
	end

	if mode == "virtual" or not firesignal then
		local ok = pcall(function()
			local pos = button.AbsolutePosition + button.AbsoluteSize / 2
			VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
			task.wait(0.08)
			VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
		end)
		if ok then task.wait(0.15) end
		return ok
	end

	return false
end

function Actions.fireRemote(remote, args)
	if not remote or not remote.Parent then return false end
	return pcall(function()
		if remote:IsA("RemoteEvent") then
			remote:FireServer(unpackArgs(args or {}))
		elseif remote:IsA("RemoteFunction") then
			remote:InvokeServer(unpackArgs(args or {}))
		end
	end)
end

function Actions.use(entry)
	if not entry or not entry.instance then return false end

	if entry.kind == "gui" then
		return Actions.clickGui(entry.instance, entry.mode)
	elseif entry.kind == "prompt" then
		return tryFireProximity(entry.instance)
	elseif entry.kind == "click" then
		return tryFireClick(entry.instance)
	elseif entry.kind == "tool" then
		return tryUseTool(entry.instance)
	elseif entry.kind == "remote" then
		return Actions.fireRemote(entry.instance, entry.args)
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

local panelCooldownUntil = 0

local function panelCooldownActive()
	return os.clock() < panelCooldownUntil
end

local function tryOpenPanel()
	panelCooldownUntil = os.clock() + Config.PanelOpenCooldown

	-- Сначала карточка самого питомца, затем кнопки вида "Pets" / "Needs"
	local buttons = {}
	local pets = Pets.get()
	if pets[1] then
		buttons = World.findButtonByText(pets[1].Name)
	end
	if #buttons == 0 then
		buttons = World.findPanelButton()
	end

	if #buttons == 0 then
		log("кнопка открытия панели питомца не найдена (Config.PanelButtons)")
		return false
	end

	local btn = buttons[1]
	local label = btn.Name
	pcall(function() if btn.Text ~= "" then label = btn.Text end end)

	UI.setStatus("Открываю панель питомца: " .. tostring(label), Theme.Accent)
	log("нажимаю кнопку панели:", btn:GetFullName())

	-- один способ, чтобы панель не открылась и сразу не закрылась
	if not Actions.clickGui(btn, "mb1") then
		Actions.clickGui(btn, "virtual")
	end
	return true
end

-- Полный отчёт: питомцы, значения нужд, доступные способы
local function diagnose()
	log("============= ДИАГНОСТИКА =============")

	local pets = Pets.get(true)
	log("питомцев найдено:", #pets)
	for i, pet in ipairs(pets) do
		if i > 5 then break end
		local vals = {}
		for _, need in ipairs(Config.Priority) do
			local v = readNeedFromPet(pet, need)
			if v == nil then v = readNeedFromUI(need) end
			table.insert(vals, string.format("%s=%s", need, v and string.format("%.0f", v) or "?"))
		end
		log(string.format("   %s [%s]  %s", pet:GetFullName(), pet.ClassName, table.concat(vals, "  ")))
	end

	for _, need in ipairs(Config.Priority) do
		local guiCount = #World.findGuiForNeed(need)
		local world = World.findForNeed(need)
		log(string.format("   %-9s кнопок=%d  объект=%s  повторов=%d",
			need, guiCount,
			world and world.instance:GetFullName() or "нет",
			#Capture.replaysFor(need)))
	end

	log("кнопка панели питомца:", #World.findPanelButton() > 0 and "есть" or "не найдена")
	log("=========== КОНЕЦ ДИАГНОСТИКИ =========")

	UI.showLog(true)
	UI.notify("Диагностика готова", Log.export(), "success")
end

local function describeEntry(entry)
	if entry.kind == "gui" then
		local text = ""
		pcall(function() text = entry.instance.Text end)
		local name = tostring(text ~= "" and text or entry.instance.Name)
		return string.format("кнопка «%s» [%s]", name, entry.mode)
	end
	if entry.kind == "prompt" then return "ProximityPrompt " .. entry.instance.Name end
	if entry.kind == "click" then return "ClickDetector " .. entry.instance.Name end
	if entry.kind == "tool" then return "Tool " .. entry.instance.Name end
	if entry.kind == "remote" then return "remote " .. entry.instance:GetFullName() end
	return tostring(entry.kind)
end

-- Собирает способы закрыть потребность в порядке приоритета
local function buildPlan(need)
	local plan = {}
	local guiList = World.findGuiForNeed(need)
	local world = World.findForNeed(need)

	local function addGui()
		for _, btn in ipairs(guiList) do
			table.insert(plan, { kind = "gui", mode = "mb1", instance = btn })
			table.insert(plan, { kind = "gui", mode = "activated", instance = btn })
			table.insert(plan, { kind = "gui", mode = "virtual", instance = btn })
		end
	end

	if Config.PreferGui then
		addGui()
		if world then table.insert(plan, world) end
	else
		if world then table.insert(plan, world) end
		addGui()
	end

	for _, rec in ipairs(Capture.replaysFor(need)) do
		table.insert(plan, { kind = "remote", instance = rec.remote, args = rec.args })
	end

	while #plan > 8 do table.remove(plan) end
	return plan
end

local function runCycle()
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		UI.setStatus("Персонаж не найден — жду респавна", Theme.Warn)
		return
	end

	local taskInfo, readable = Pets.pickTask()
	if not taskInfo then
		if (readable or 0) == 0 then
			local petCount = #Pets.get()
			if petCount == 0 then
				UI.setStatus("Питомцы не найдены — нажми «Диагностика: 1 цикл»", Theme.Danger)
			else
				UI.setStatus(string.format("Питомцев: %d, но потребности не читаются — жми «Диагностика»", petCount), Theme.Danger)
			end
			if Config.AutoOpenPanel and not panelCooldownActive() then
				tryOpenPanel()
			end
		else
			UI.setStatus(string.format("Все потребности в норме (%d значений)", readable), Theme.Success)
			Autopilot.lastAction = "idle"
		end
		return
	end

	local need = taskInfo.need
	if onCooldown(need) then
		UI.setStatus(string.format("%s на паузе (недавно обрабатывали)", need), Theme.Muted)
		return
	end

	UI.setStatus(string.format("%s: %.0f%% — ищу место...", need, taskInfo.value),
		taskInfo.critical and Theme.Danger or Theme.Warn)

	local plan = buildPlan(need)

	-- Ничего не нашли: пробуем открыть панель питомца и поискать снова
	if #plan == 0 and Config.AutoOpenPanel and not panelCooldownActive() then
		if tryOpenPanel() then
			task.wait(0.8)
			plan = buildPlan(need)
		end
	end

	if #plan == 0 then
		UI.setStatus(string.format("%s: способ не найден — нажми «Debug: скан мира»", need), Theme.Danger)
		setCooldown(need, Config.CooldownAfterFail)
		log("нет способа закрыть", need, "— проверь Config.Actions / Config.Locations по дампу консоли")
		return
	end

	UI.setStatus(string.format("%s: %.0f%% — способов в плане: %d", need, taskInfo.value, #plan), Theme.Accent)

	for index, entry in ipairs(plan) do
		if not Alive or not Config.Enabled then return end

		if entry.part then
			UI.setStatus(string.format("%s: иду к %s", need, entry.part.Name), Theme.Warn)
			if not Movement.goTo(entry.part.Position, Config.ActionTimeout) then
				log("не добрался до", entry.instance:GetFullName())
			else
				task.wait(0.2)
			end
		end

		local label = describeEntry(entry)
		UI.setStatus(string.format("%s: попытка %d/%d — %s", need, index, #plan, label), Theme.Accent)
		log(string.format("попытка %d/%d для %s: %s", index, #plan, need, label))

		Actions.use(entry)
		task.wait(0.9)

		local after = readNeedFromPet(taskInfo.pet, need)
		if after == nil then after = readNeedFromUI(need) end

		if after ~= nil and after > taskInfo.value + 1 then
			Autopilot.success = Autopilot.success + 1
			Autopilot.lastAction = need
			failStreak[need] = 0
			setCooldown(need, Config.CooldownAfterSuccess)
			UI.notify("Готово", string.format("%s: %.0f%% → %.0f%% (%s)", need, taskInfo.value, after, label), "success")
			log(string.format("%s улучшена: %.0f -> %.0f через %s", need, taskInfo.value, after, label))
			return
		end
	end

	Autopilot.failed = Autopilot.failed + 1
	failStreak[need] = (failStreak[need] or 0) + 1
	local penalty = Config.CooldownAfterFail * math.min(failStreak[need], 4)
	setCooldown(need, penalty)
	UI.notify("Без результата",
		string.format("%s осталась %.0f%%: испробовано способов — %d", need, taskInfo.value, #plan), "warn")
	log(string.format("%s без изменений после %d попыток, пауза %ds", need, #plan, penalty))
end

local function loop()
	while Alive do
		if Config.Enabled and not Autopilot.busy and not Capture.active then
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

UI.section("Действия")

UI.toggle("Сначала кнопки интерфейса", Config.PreferGui, function(v) Config.PreferGui = v end)
UI.toggle("Авто-открытие панели питомца", Config.AutoOpenPanel, function(v) Config.AutoOpenPanel = v end)

UI.button("Захват действий (60 сек)", function()
	Capture.start(60)
end)

UI.button("Отчёт захвата в консоль", function()
	Capture.report()
end)

UI.button("Показать кнопки интерфейса", function()
	World.dumpButtons(60)
	UI.notify("Дамп готов", "Список кнопок в консоли (F9)", "success")
end)

UI.button("Диагностика: 1 цикл", function()
	diagnose()
end, true)

UI.button("Открыть журнал (отчёты и лог)", function()
	UI.showLog(true)
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
	content.Visible = (not minimized) and not logPage
	footer.Visible = not minimized
	toggleBar.Visible = not minimized
	logView.Visible = (not minimized) and logPage
	logActions.Visible = (not minimized) and logPage
	if minimized then reportBox.Visible = false end
	minBtn.Text = minimized and "+" or "—"
end)

logBtn.MouseButton1Click:Connect(function()
	UI.showLog(not logPage)
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

Log.add("Скрипт запущен. RightShift — окно, RightCtrl — вкл/выкл, End — выгрузить.")
Log.add("Кнопка ≡ в шапке или «Открыть журнал» — лог и отчёты (консоль не нужна).")

if Config.AutoStart then
	UI.notify("Автопилот активен", "Питомец обслуживается без твоего участия", "success")
end
