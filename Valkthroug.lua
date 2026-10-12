--[[
	VALKTHROUG — Floating Coordinate & Teleport Toolbar
	Single LocalScript. Put it in StarterPlayerScripts (or StarterGui) and press Play.

	Features
	  • Draggable (mouse + touch), 3 size levels, minimize to a compact bar
	  • Live position tracker + Copy (setclipboard)
	  • "Cord" button: captures your position into the selected Source/Destination box
	  • Teleport trigger: reaching Source (<= 5 studs) teleports you to Destination,
	    then Source is cleared so it can never loop
	  • Thai / English UI toggle
	  • TweenService animations everywhere

	Notes
	  • setclipboard only exists in some environments. If it is missing, the coordinates
	    are printed to the Output window instead and the status bar tells you.
	  • Input boxes are committed when you finish editing (tap outside / press Enter),
	    so half-typed numbers can never trigger a teleport.
]]

----------------------------------------------------------------------
-- 1. SERVICES & CONFIG
----------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CONFIG = {
	GuiName = "ValkthrougGui",
	TriggerRadius = 5, -- studs
	UIRefreshInterval = 0.1, -- seconds between label refreshes (trigger check runs every frame)
	BaseWidth = 340,
	BodyHeight = 240,
	HeaderHeight = 40,
	MinimizedWidth = 256,
	Scales = { 0.82, 1, 1.2 }, -- Small / Medium / Large
	StartPosition = Vector2.new(24, 90),
}
local FULL_HEIGHT = CONFIG.HeaderHeight + 1 + CONFIG.BodyHeight

-- Remove an older copy if the script is re-run
local old = playerGui:FindFirstChild(CONFIG.GuiName)
if old then
	old:Destroy()
end

----------------------------------------------------------------------
-- 2. THEME, TEXT, HELPERS
----------------------------------------------------------------------
local THEME = {
	Black = Color3.fromRGB(10, 6, 18),
	DeepPurple = Color3.fromRGB(38, 16, 74),
	Purple = Color3.fromRGB(124, 58, 237),
	PurpleHover = Color3.fromRGB(146, 86, 255),
	SoftPurple = Color3.fromRGB(167, 119, 255),
	Gold = Color3.fromRGB(212, 175, 55),
	GoldHover = Color3.fromRGB(240, 205, 90),
	LightGold = Color3.fromRGB(255, 226, 125),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(176, 166, 200),
	Red = Color3.fromRGB(255, 95, 110),
	PanelButton = Color3.fromRGB(44, 22, 84),
	PanelButtonHover = Color3.fromRGB(70, 34, 130),
}

local STRINGS = {
	EN = {
		position = "POSITION",
		copy = "Copy",
		cord = "Cord",
		source = "Source",
		destination = "Destination",
		srcTag = "SRC",
		dstTag = "DST",
		placeholder = "x, y, z",
		trigOn = "Trigger: ON",
		trigOff = "Trigger: OFF",
		stIdle = "Add a source",
		stNoDest = "Add a destination",
		stArmed = "Armed • watching",
		stOff = "Trigger disabled",
		stInvalid = "Invalid coordinates",
		stCopied = "Copied!",
		stNoClip = "No clipboard (see Output)",
		stFilledSrc = "Source captured",
		stFilledDst = "Destination captured",
		stTeleported = "Teleported!",
		stNoChar = "No character found",
		stSize1 = "Size: Small",
		stSize2 = "Size: Medium",
		stSize3 = "Size: Large",
	},
	TH = {
		position = "ตำแหน่งปัจจุบัน",
		copy = "คัดลอก",
		cord = "ดึงพิกัด",
		source = "ต้นทาง",
		destination = "ปลายทาง",
		srcTag = "ต้นทาง",
		dstTag = "ปลายทาง",
		placeholder = "x, y, z",
		trigOn = "ทริกเกอร์: เปิด",
		trigOff = "ทริกเกอร์: ปิด",
		stIdle = "ใส่พิกัดต้นทาง",
		stNoDest = "ใส่พิกัดปลายทาง",
		stArmed = "พร้อม • กำลังตรวจจับ",
		stOff = "ปิดการทำงาน",
		stInvalid = "พิกัดไม่ถูกต้อง",
		stCopied = "คัดลอกแล้ว!",
		stNoClip = "ไม่รองรับคลิปบอร์ด",
		stFilledSrc = "ดึงต้นทางแล้ว",
		stFilledDst = "ดึงปลายทางแล้ว",
		stTeleported = "เทเลพอร์ตแล้ว!",
		stNoChar = "ไม่พบตัวละคร",
		stSize1 = "ขนาด: เล็ก",
		stSize2 = "ขนาด: กลาง",
		stSize3 = "ขนาด: ใหญ่",
	},
}

local TI_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_PRESS = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_MED = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_POP = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local currentLang = "EN"
local localized = {} -- { {inst, key, prop} } — every translatable element

local function tween(inst, info, props)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function t(key)
	return STRINGS[currentLang][key]
end

local function bindText(inst, key, prop)
	prop = prop or "Text"
	table.insert(localized, { inst = inst, key = key, prop = prop })
	inst[prop] = t(key)
end

-- Tiny instance factory (Parent is assigned last for performance)
local function new(className, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function colorSeq(...)
	local colors = { ... }
	local points = {}
	for i, c in ipairs(colors) do
		points[i] = ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c)
	end
	return ColorSequence.new(points)
end

-- Hover / press animation for any button. Returns a style table so base colors can change later.
local hoverEnabled = UserInputService.MouseEnabled
local function registerButton(btn, base, hover)
	local scale = Instance.new("UIScale")
	scale.Parent = btn
	local style = { button = btn, base = base, hover = hover, hovering = false }
	btn.BackgroundColor3 = base

	if hoverEnabled then
		btn.MouseEnter:Connect(function()
			style.hovering = true
			tween(btn, TI_FAST, { BackgroundColor3 = style.hover })
			tween(scale, TI_FAST, { Scale = 1.04 })
		end)
		btn.MouseLeave:Connect(function()
			style.hovering = false
			tween(btn, TI_FAST, { BackgroundColor3 = style.base })
			tween(scale, TI_FAST, { Scale = 1 })
		end)
	end

	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end
	btn.InputBegan:Connect(function(input)
		if isPress(input) then
			tween(scale, TI_PRESS, { Scale = 0.94 })
		end
	end)
	btn.InputEnded:Connect(function(input)
		if isPress(input) then
			tween(scale, TI_FAST, { Scale = style.hovering and 1.04 or 1 })
		end
	end)
	return style
end

local function setButtonColors(style, base, hover)
	style.base, style.hover = base, hover
	tween(style.button, TI_FAST, { BackgroundColor3 = style.hovering and hover or base })
end

----------------------------------------------------------------------
-- 3. BUILD THE UI
----------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = CONFIG.GuiName,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

-- Full-screen flash used for the teleport transition
local flash = new("Frame", {
	Name = "TeleportFlash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.SoftPurple,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
	Parent = gui,
})

-- Zero-size anchor that carries the draggable position (the UIScale lives on Main)
local anchor = new("Frame", {
	Name = "Anchor",
	Size = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(CONFIG.StartPosition.X, CONFIG.StartPosition.Y),
	BackgroundTransparency = 1,
	Parent = gui,
})

local uiScale = new("UIScale", { Scale = 0.6 }) -- pops up to the real size on start
local strokeGradient = new("UIGradient", {
	Color = colorSeq(THEME.Gold, THEME.Purple, THEME.Gold),
})
local mainStroke = new("UIStroke", {
	Color = THEME.White,
	Thickness = 1.5,
	Transparency = 0.2,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, { strokeGradient })

local main = new("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(CONFIG.BaseWidth, FULL_HEIGHT),
	BackgroundColor3 = THEME.White, -- tinted by the gradient below
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Active = true, -- sinks input so taps don't leak into the game
	ClipsDescendants = true,
	Parent = anchor,
}, {
	corner(14),
	mainStroke,
	uiScale,
	new("UIGradient", {
		Color = colorSeq(THEME.DeepPurple, THEME.Black, Color3.fromRGB(30, 12, 58)),
		Rotation = 125,
	}),
})

-- Glass sheen across the header
new("Frame", {
	Name = "Sheen",
	Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
	BackgroundColor3 = THEME.White,
	BorderSizePixel = 0,
	Parent = main,
}, {
	corner(14),
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.86),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

-- Header (drag handle, title, 3 control buttons)
local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
	BackgroundTransparency = 1,
	Parent = main,
})

local dragHandle = new("Frame", {
	Name = "DragHandle",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Active = true,
	Parent = header,
})

new("Frame", {
	Name = "Diamond",
	Size = UDim2.fromOffset(8, 8),
	Position = UDim2.fromOffset(15, 16),
	Rotation = 45,
	BackgroundColor3 = THEME.Gold,
	BorderSizePixel = 0,
	Parent = header,
})

new("TextLabel", {
	Name = "Title",
	Size = UDim2.new(0, 120, 1, 0),
	Position = UDim2.fromOffset(32, 0),
	BackgroundTransparency = 1,
	Text = "VALKTHROUG",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = THEME.White,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
}, {
	new("UIGradient", { Color = colorSeq(THEME.LightGold, THEME.Gold), Rotation = 90 }),
})

local buttonsHolder = new("Frame", {
	Name = "Controls",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(94, 28),
	BackgroundTransparency = 1,
	Parent = header,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}),
})

local function headerButton(order, text)
	local btn = new("TextButton", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(28, 28),
		AutoButtonColor = false,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = THEME.LightGold,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = buttonsHolder,
	}, { corner(8), stroke(THEME.Gold, 1, 0.6) })
	registerButton(btn, THEME.PanelButton, THEME.PanelButtonHover)
	return btn
end

local langBtn = headerButton(1, "EN")
local sizeBtn = headerButton(2, "M")
local minBtn = headerButton(3, "–")

-- Divider under header
new("Frame", {
	Name = "Divider",
	Position = UDim2.new(0, 12, 0, CONFIG.HeaderHeight),
	Size = UDim2.new(1, -24, 0, 1),
	BackgroundColor3 = THEME.White,
	BorderSizePixel = 0,
	Parent = main,
}, {
	new("UIGradient", {
		Color = colorSeq(THEME.Gold, THEME.SoftPurple, THEME.Gold),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

-- Body (fixed width so it clips cleanly while minimizing)
local body = new("Frame", {
	Name = "Body",
	Position = UDim2.fromOffset(0, CONFIG.HeaderHeight + 1),
	Size = UDim2.fromOffset(CONFIG.BaseWidth, CONFIG.BodyHeight),
	BackgroundTransparency = 1,
	Parent = main,
}, {
	new("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}),
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- 3a. Position card
local posCard = new("Frame", {
	Name = "PositionCard",
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 58),
	BackgroundColor3 = THEME.Black,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	Parent = body,
}, { corner(10), stroke(THEME.Purple, 1, 0.45) })

local posTitle = new("TextLabel", {
	Position = UDim2.fromOffset(12, 7),
	Size = UDim2.new(1, -96, 0, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = THEME.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = posCard,
})
bindText(posTitle, "position")

local coordRow = new("Frame", {
	Position = UDim2.fromOffset(12, 26),
	Size = UDim2.new(1, -96, 0, 24),
	BackgroundTransparency = 1,
	Parent = posCard,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local function coordLabel(order)
	return new("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1 / 3, -3, 1, 0),
		BackgroundTransparency = 1,
		RichText = true,
		TextScaled = true,
		Font = Enum.Font.Code,
		TextColor3 = THEME.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = coordRow,
	}, { new("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 7 }) })
end
local xLabel, yLabel, zLabel = coordLabel(1), coordLabel(2), coordLabel(3)

local copyBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(66, 34),
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = THEME.Black,
	BorderSizePixel = 0,
	Parent = posCard,
}, { corner(9) })
bindText(copyBtn, "copy")
registerButton(copyBtn, THEME.Gold, THEME.GoldHover)

-- 3b. Target selector (Source / Destination) + Cord button
local selectorRow = new("Frame", {
	Name = "SelectorRow",
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Parent = body,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local selectors = {} -- selectors[which] = { btn, style, stroke }
local function makeSelector(order, which, textKey)
	local selStroke = stroke(THEME.Gold, 1, 0.75)
	local btn = new("TextButton", {
		LayoutOrder = order,
		Size = UDim2.new(1 / 3, -4, 1, 0),
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = THEME.White,
		BorderSizePixel = 0,
		Parent = selectorRow,
	}, { corner(9), selStroke })
	bindText(btn, textKey)
	selectors[which] = {
		btn = btn,
		stroke = selStroke,
		style = registerButton(btn, THEME.PanelButton, THEME.PanelButtonHover),
	}
end
makeSelector(1, "src", "source")
makeSelector(2, "dst", "destination")

local cordBtn = new("TextButton", {
	LayoutOrder = 3,
	Size = UDim2.new(1 / 3, -4, 1, 0),
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = THEME.Black,
	BorderSizePixel = 0,
	Parent = selectorRow,
}, { corner(9) })
bindText(cordBtn, "cord")
registerButton(cordBtn, THEME.Gold, THEME.GoldHover)

-- 3c. Input rows
local function makeInputRow(order, tagKey)
	local rowStroke = stroke(THEME.Purple, 1, 0.5)
	local row = new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = THEME.Black,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = body,
	}, { corner(10), rowStroke })

	local tag = new("TextLabel", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromOffset(52, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	bindText(tag, tagKey)

	local box = new("TextBox", {
		Position = UDim2.fromOffset(68, 0),
		Size = UDim2.new(1, -78, 1, 0),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		MultiLine = false,
		Text = "",
		Font = Enum.Font.Code,
		TextSize = 13,
		TextColor3 = THEME.White,
		PlaceholderColor3 = Color3.fromRGB(120, 108, 150),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	bindText(box, "placeholder", "PlaceholderText")
	return box, rowStroke
end
local sourceBox, sourceStroke = makeInputRow(3, "srcTag")
local destBox, destStroke = makeInputRow(4, "dstTag")

local boxes = { src = sourceBox, dst = destBox }
local inputStrokes = { src = sourceStroke, dst = destStroke }

-- 3d. Status row + trigger toggle
local statusRow = new("Frame", {
	LayoutOrder = 5,
	Size = UDim2.new(1, 0, 0, 26),
	BackgroundTransparency = 1,
	Parent = body,
})

local statusDot = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 2, 0.5, 0),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = THEME.Muted,
	BorderSizePixel = 0,
	Parent = statusRow,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

local statusLabel = new("TextLabel", {
	Position = UDim2.fromOffset(16, 0),
	Size = UDim2.new(1, -142, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = THEME.White,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "",
	Parent = statusRow,
})

local trigBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(118, 26),
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	BorderSizePixel = 0,
	Parent = statusRow,
}, { corner(8), stroke(THEME.Gold, 1, 0.6) })
local trigStyle = registerButton(trigBtn, THEME.Purple, THEME.PurpleHover)

----------------------------------------------------------------------
-- 4. STATE & LOGIC
----------------------------------------------------------------------
local selectedTarget = "src"
local triggerEnabled = true
local minimized = false
local sizeIndex = 2
local sourcePos, destPos = nil, nil
local invalid = { src = false, dst = false }
local rootPart = nil
local statusKey, statusLockUntil = nil, 0
local anchorTween, flashTween = nil, nil
local connections = {} -- global connections we must release on destroy

local function track(conn)
	connections[#connections + 1] = conn
	return conn
end

-- 4a. Character handling (cached root part — no per-frame lookups)
local function bindCharacter(char)
	rootPart = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 10)
end
local function getRoot()
	if rootPart and rootPart.Parent then
		return rootPart
	end
	return nil
end
track(player.CharacterAdded:Connect(bindCharacter))
track(player.CharacterRemoving:Connect(function()
	rootPart = nil
end))
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

-- 4b. Coordinate parsing / formatting
local function formatVector(v)
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end

-- Accepts "1, 2, 3", "1 2 3", "Vector3.new(1,2,3)", "-12.5 , .5, 3" ...
local function parseVector3(text)
	local nums = {}
	for n in string.gmatch(text, "[-+]?%d*%.?%d+") do
		nums[#nums + 1] = tonumber(n)
		if #nums == 3 then
			break
		end
	end
	if #nums == 3 and nums[1] and nums[2] and nums[3] then
		return Vector3.new(nums[1], nums[2], nums[3])
	end
	return nil
end

-- 4c. Language
local function renderStatusText()
	if statusKey then
		statusLabel.Text = t(statusKey)
	end
end

local function updateTriggerButton()
	trigBtn.Text = triggerEnabled and t("trigOn") or t("trigOff")
	tween(trigBtn, TI_FAST, { TextColor3 = triggerEnabled and THEME.LightGold or THEME.Muted })
	if triggerEnabled then
		setButtonColors(trigStyle, THEME.Purple, THEME.PurpleHover)
	else
		setButtonColors(trigStyle, THEME.PanelButton, THEME.PanelButtonHover)
	end
end

local function applyLanguage()
	for _, entry in ipairs(localized) do
		entry.inst[entry.prop] = t(entry.key)
	end
	langBtn.Text = currentLang
	updateTriggerButton()
	renderStatusText()
end

-- 4d. Status bar
local function renderStatus(key, color)
	statusKey = key
	statusLabel.Text = t(key)
	tween(statusDot, TI_FAST, { BackgroundColor3 = color })
end

local function flashStatus(key, color, seconds)
	statusLockUntil = os.clock() + (seconds or 2)
	renderStatus(key, color or THEME.LightGold)
end

local function updateBaseStatus()
	if os.clock() < statusLockUntil then
		return
	end
	local key, color
	if not triggerEnabled then
		key, color = "stOff", THEME.Muted
	elseif invalid.src or invalid.dst then
		key, color = "stInvalid", THEME.Red
	elseif not sourcePos then
		key, color = "stIdle", THEME.Muted
	elseif not destPos then
		key, color = "stNoDest", THEME.SoftPurple
	else
		key, color = "stArmed", THEME.Gold
	end
	if key ~= statusKey then
		renderStatus(key, color)
	end
end

-- 4e. Input visuals & commit
local function updateInputVisuals()
	for which, s in pairs(inputStrokes) do
		local color, thickness, transparency
		if invalid[which] then
			color, thickness, transparency = THEME.Red, 1.5, 0.1
		elseif selectedTarget == which then
			color, thickness, transparency = THEME.Gold, 1.5, 0.1
		else
			color, thickness, transparency = THEME.Purple, 1, 0.5
		end
		tween(s, TI_FAST, { Color = color, Thickness = thickness, Transparency = transparency })
	end
end

local function setTarget(which)
	selectedTarget = which
	for key, info in pairs(selectors) do
		local on = key == which
		setButtonColors(
			info.style,
			on and THEME.Purple or THEME.PanelButton,
			on and THEME.PurpleHover or THEME.PanelButtonHover
		)
		tween(info.btn, TI_FAST, { TextColor3 = on and THEME.LightGold or THEME.White })
		tween(info.stroke, TI_FAST, { Transparency = on and 0 or 0.75 })
	end
	updateInputVisuals()
end

-- Parse the text of a box once and cache the Vector3 (the trigger loop never parses)
local function commitInput(which)
	local text = boxes[which].Text
	local hasText = text:match("%S") ~= nil
	local value = hasText and parseVector3(text) or nil
	invalid[which] = hasText and value == nil
	if which == "src" then
		sourcePos = value
	else
		destPos = value
	end
	updateInputVisuals()
	updateBaseStatus()
end

local function setBoxText(which, text)
	boxes[which].Text = text
	commitInput(which)
end

-- 4f. Actions
local function copyPosition()
	local root = getRoot()
	if not root then
		flashStatus("stNoChar", THEME.Red)
		return
	end
	local text = formatVector(root.Position)
	local clipFn = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set)
	if clipFn and pcall(clipFn, text) then
		flashStatus("stCopied", THEME.LightGold)
	else
		print("[Valkthroug] Position: " .. text)
		flashStatus("stNoClip", THEME.Red, 2.5)
	end
end

local function grabCoordinate()
	local root = getRoot()
	if not root then
		flashStatus("stNoChar", THEME.Red)
		return
	end
	setBoxText(selectedTarget, formatVector(root.Position))
	flashStatus(selectedTarget == "src" and "stFilledSrc" or "stFilledDst", THEME.LightGold)
end

local function playTeleportFlash()
	if flashTween then
		flashTween:Cancel()
	end
	flash.Visible = true
	flash.BackgroundTransparency = 0.5
	flashTween = tween(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	flashTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			flash.Visible = false
		end
	end)
end

local function doTeleport(root)
	local destination = destPos
	-- Clear the source FIRST so the trigger can never fire twice
	sourcePos = nil
	setBoxText("src", "")

	root.CFrame = CFrame.new(destination) * root.CFrame.Rotation -- keep facing direction
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	playTeleportFlash()
	flashStatus("stTeleported", THEME.LightGold)
end

-- 4g. Window state: clamping, minimize, resize
local function getVisualSize()
	local scale = CONFIG.Scales[sizeIndex]
	if minimized then
		return Vector2.new(CONFIG.MinimizedWidth * scale, CONFIG.HeaderHeight * scale)
	end
	return Vector2.new(CONFIG.BaseWidth * scale, FULL_HEIGHT * scale)
end

local function clampToScreen(pos, size)
	local screen = gui.AbsoluteSize
	local maxX = math.max(0, screen.X - size.X)
	local maxY = math.max(0, screen.Y - size.Y)
	return Vector2.new(math.clamp(pos.X, 0, maxX), math.clamp(pos.Y, 0, maxY))
end

-- Smoothly pull the window back on-screen after a resize / minimize / screen change
local function settleOnScreen()
	local current = Vector2.new(anchor.Position.X.Offset, anchor.Position.Y.Offset)
	local target = clampToScreen(current, getVisualSize())
	if target ~= current then
		anchorTween = tween(anchor, TI_MED, { Position = UDim2.fromOffset(target.X, target.Y) })
	end
end

local function setMinimized(state)
	minimized = state
	minBtn.Text = state and "+" or "–"
	if state then
		local tw = tween(main, TI_MED, {
			Size = UDim2.fromOffset(CONFIG.MinimizedWidth, CONFIG.HeaderHeight),
		})
		tw.Completed:Once(function()
			if minimized then
				body.Visible = false -- also removes the TextBoxes from focus
			end
		end)
	else
		body.Visible = true
		tween(main, TI_MED, { Size = UDim2.fromOffset(CONFIG.BaseWidth, FULL_HEIGHT) })
		updateBaseStatus()
	end
	settleOnScreen()
end

local SIZE_LABELS = { "S", "M", "L" }
local function setSizeLevel(index)
	sizeIndex = index
	sizeBtn.Text = SIZE_LABELS[index]
	tween(uiScale, TI_MED, { Scale = CONFIG.Scales[index] })
	settleOnScreen()
	flashStatus("stSize" .. index, THEME.SoftPurple, 1.2)
end

-- 4h. Dragging (mouse + touch)
local dragging, dragInput, dragStart, dragOrigin = false, nil, nil, nil
local moveConn, endConn = nil, nil

local function stopDrag()
	dragging = false
	dragInput = nil
	if moveConn then
		moveConn:Disconnect()
		moveConn = nil
	end
	if endConn then
		endConn:Disconnect()
		endConn = nil
	end
end

dragHandle.InputBegan:Connect(function(input)
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
		return
	end
	if dragging then
		return
	end

	dragging = true
	dragInput = input
	dragStart = input.Position
	dragOrigin = Vector2.new(anchor.Position.X.Offset, anchor.Position.Y.Offset)
	if anchorTween then
		anchorTween:Cancel()
	end

	endConn = input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			stopDrag()
		end
	end)

	-- Only connected while a drag is active → zero idle cost
	moveConn = UserInputService.InputChanged:Connect(function(changed)
		if changed.UserInputType == Enum.UserInputType.MouseMovement or changed == dragInput then
			local delta = changed.Position - dragStart
			local target = clampToScreen(dragOrigin + Vector2.new(delta.X, delta.Y), getVisualSize())
			anchor.Position = UDim2.fromOffset(target.X, target.Y)
		end
	end)
end)

----------------------------------------------------------------------
-- 5. EVENTS
----------------------------------------------------------------------
copyBtn.Activated:Connect(copyPosition)
cordBtn.Activated:Connect(grabCoordinate)

for which, info in pairs(selectors) do
	info.btn.Activated:Connect(function()
		setTarget(which)
	end)
end

for which, box in pairs(boxes) do
	box.Focused:Connect(function()
		setTarget(which)
	end)
	box.FocusLost:Connect(function()
		commitInput(which)
	end)
end

trigBtn.Activated:Connect(function()
	triggerEnabled = not triggerEnabled
	updateTriggerButton()
	statusLockUntil = 0
	updateBaseStatus()
end)

langBtn.Activated:Connect(function()
	currentLang = currentLang == "EN" and "TH" or "EN"
	applyLanguage()
end)

sizeBtn.Activated:Connect(function()
	setSizeLevel(sizeIndex % #CONFIG.Scales + 1)
end)

minBtn.Activated:Connect(function()
	setMinimized(not minimized)
end)

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(settleOnScreen)

-- Main loop: trigger check every frame (cheap), UI text at ~10 Hz
local accumulator = 0
local cellCache = {}
local function setCell(label, axis, text)
	if cellCache[label] ~= text then
		cellCache[label] = text
		label.Text = string.format('<font color="#D4AF37">%s</font> %s', axis, text)
	end
end

local function refreshUI(root)
	if minimized then
		return
	end
	if root then
		local p = root.Position
		setCell(xLabel, "X", string.format("%.1f", p.X))
		setCell(yLabel, "Y", string.format("%.1f", p.Y))
		setCell(zLabel, "Z", string.format("%.1f", p.Z))
	else
		setCell(xLabel, "X", "–")
		setCell(yLabel, "Y", "–")
		setCell(zLabel, "Z", "–")
	end
	updateBaseStatus()
end

track(RunService.Heartbeat:Connect(function(dt)
	local root = getRoot()

	if root and triggerEnabled and sourcePos and destPos then
		if (root.Position - sourcePos).Magnitude <= CONFIG.TriggerRadius then
			doTeleport(root)
		end
	end

	accumulator += dt
	if accumulator >= CONFIG.UIRefreshInterval then
		accumulator = 0
		refreshUI(root)
	end
end))

-- Cleanup: release everything that outlives the GUI
local borderLoop = tween(strokeGradient, TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
	Rotation = 360,
})

gui.Destroying:Connect(function()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	stopDrag()
	borderLoop:Cancel()
	if flashTween then
		flashTween:Cancel()
	end
end)

----------------------------------------------------------------------
-- 6. START
----------------------------------------------------------------------
applyLanguage()
setTarget("src")
updateBaseStatus()
gui.Parent = playerGui
tween(uiScale, TI_POP, { Scale = CONFIG.Scales[sizeIndex] })
