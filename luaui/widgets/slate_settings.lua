-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Settings",
		desc    = "Settings screen: interface look (opacity, blur, colour tint, size), graphics and sound. Open it from the Menu or with /slate settings.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = -10,      -- above the panels: it is a window
		enabled = true,
	}
end

local ID = "settings"
local WIDTH, HEIGHT = 640, 560      -- design pixels
local ROW_H     = 42
local TAB_H     = 34
local CONTROL_W = 300

local floor = math.floor
local min, max = math.min, math.max

local S
local open = false
local tab = 1
local hits = {}                     -- rebuilt each frame: { x1, y1, x2, y2, fn = function(mx) }
local closeRect
local wx1, wy1, wx2, wy2
local drag                          -- { row = , x1 = , x2 = } while a slider is held

--------------------------------------------------------------------------------
-- What is on each tab
--
-- slider:   get() -> number, set(v), lo, hi, step, format(v) -> string
-- toggle:   get() -> boolean, set(v)
-- choice:   options = { "a", "b" }, get() -> index, set(index)
-- swatches: the colour tints from the theme
-- button:   action()
--------------------------------------------------------------------------------

local function Percent(v) return floor(v * 100 + 0.5) .. "%" end
local function Whole(v) return tostring(floor(v + 0.5)) end

local function SlateSlider(label, key, lo, hi, step, live)
	return { kind = "slider", label = label, lo = lo, hi = hi, step = step, format = Percent, onRelease = not live,
		get = function() return S.Get(key) or lo end,
		set = function(v) S.Set(key, v) end }
end

local function SlateToggle(label, key)
	return { kind = "toggle", label = label,
		get = function() return S.Get(key) and true or false end,
		set = function(v) S.Set(key, v) end }
end

-- An engine setting stored as an integer and applied with a console command.
local function EngineToggle(label, config, command, default)
	return { kind = "toggle", label = label,
		get = function() return (Spring.GetConfigInt(config, default or 0) or 0) > 0 end,
		set = function(v) Spring.SendCommands(command .. " " .. (v and 1 or 0)) end }
end

local function EngineSlider(label, config, lo, hi, step, default, command)
	return { kind = "slider", label = label, lo = lo, hi = hi, step = step, format = Whole, onRelease = true,
		get = function() return Spring.GetConfigInt(config, default) or default end,
		set = function(v)
			v = floor(v + 0.5)
			if command then Spring.SendCommands(command .. " " .. v) end
			Spring.SetConfigInt(config, v)
		end }
end

local function Volume(label, config)
	return { kind = "slider", label = label, lo = 0, hi = 100, step = 5, format = Whole,
		get = function() return Spring.GetConfigInt(config, 60) or 60 end,
		set = function(v) Spring.SetConfigInt(config, floor(v + 0.5)) end }
end

local tabs

local function BuildTabs()
	tabs = {
		{ label = "Interface", rows = {
			SlateSlider("Panel opacity", "opacity", 0.2, 1.0, 0.05, true),
			SlateToggle("Blur behind panels", "blur"),
			{ kind = "swatches", label = "Colour tint" },
			SlateSlider("Tint strength", "tintStrength", 0, 1.0, 0.05, true),
			SlateSlider("Interface size", "scale", 0.7, 1.5, 0.05, false),
			SlateToggle("Wind read-out", "wind"),
			SlateToggle("Tidal read-out (maps with water)", "tidal"),
			{ kind = "button", label = "Panel positions", text = "Reset to default",
				action = function() if WG.SlateLayout then WG.SlateLayout.ResetAll() end end },
		} },
		{ label = "Graphics", rows = {
			EngineToggle("Fullscreen", "Fullscreen", "fullscreen", 1),
			EngineToggle("Shadows", "Shadows", "shadows", 0),
			{ kind = "choice", label = "Water", options = { "Basic", "Reflective", "Dynamic", "Refractive", "Bump" },
				get = function() return (Spring.GetConfigInt("Water", 1) or 1) + 1 end,
				set = function(i) Spring.SendCommands("water " .. (i - 1)) end },
			EngineToggle("Vertical sync", "VSync", "vsync", 0),
			EngineToggle("Hardware cursor", "HardwareCursor", "hardwarecursor", 0),
			EngineSlider("Particle limit", "MaxParticles", 1000, 30000, 1000, 10000, "maxparticles"),
			EngineSlider("Unit icon distance", "UnitIconDist", 50, 400, 10, 200, "disticon"),
		} },
		{ label = "Sound", rows = {
			Volume("Master volume", "snd_volMaster"),
			Volume("Battle", "snd_volBattle"),
			Volume("Unit replies", "snd_volUnitReply"),
			Volume("Interface", "snd_volUI"),
			Volume("Music", "snd_volMusic"),
		} },
	}
end

--------------------------------------------------------------------------------

local function Close()
	open = false
	drag = nil
	if S then S.Unblur(ID) end
end

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	BuildTabs()
end

function widget:Shutdown()
	if S then S.Unblur(ID) end
end

function widget:TextCommand(command)
	if command == "slate settings" then
		if WG.Slate ~= S then return false end
		if open then Close() else open = true end
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

local function AddHit(x1, y1, x2, y2, fn, row)
	hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn, row = row }
end

local function Snap(row, v)
	v = min(row.hi, max(row.lo, v))
	return floor((v - row.lo) / row.step + 0.5) * row.step + row.lo
end

local function SliderValueAt(row, x1, x2, mx)
	return Snap(row, row.lo + (row.hi - row.lo) * min(1, max(0, (mx - x1) / (x2 - x1))))
end

local function DrawSlider(row, x1, x2, mid, mx, my)
	local t = S.theme
	local valueW = S.px(54)
	local tx2 = x2 - valueW
	local v = (drag and drag.row == row and drag.value) or row.get()
	local frac = (v - row.lo) / (row.hi - row.lo)
	local h = S.px(6)
	S.Bar(x1, mid - h * 0.5, tx2, mid + h * 0.5, frac, t.accent)
	local kx = x1 + (tx2 - x1) * min(1, max(0, frac))
	local kr = S.px(8)
	S.Rect(kx - kr, mid - kr, kx + kr, mid + kr, t.text, kr)
	S.Text(row.format(v), x2, mid, 14, t.text, "rv")
	local slop = S.px(12)
	AddHit(x1 - slop, mid - slop, tx2 + slop, mid + slop, function(cx)
		drag = { row = row, x1 = x1, x2 = tx2, value = SliderValueAt(row, x1, tx2, cx) }
		if not row.onRelease then row.set(drag.value) end
	end, row)
end

local function DrawToggle(row, x1, x2, mid, mx, my)
	local t = S.theme
	local on = row.get()
	local w, h = S.px(46), S.px(24)
	local tx1 = x2 - w
	S.Rect(tx1, mid - h * 0.5, x2, mid + h * 0.5, on and t.accent or t.track, h * 0.5)
	local kr = h * 0.5 - S.px(3)
	local kx = on and (x2 - h * 0.5) or (tx1 + h * 0.5)
	S.Rect(kx - kr, mid - kr, kx + kr, mid + kr, on and { 0.08, 0.09, 0.10, 1 } or t.textDim, kr)
	S.Text(on and "On" or "Off", tx1 - S.px(10), mid, 14, t.textDim, "rv")
	AddHit(tx1 - S.px(40), mid - h * 0.5, x2, mid + h * 0.5, function() row.set(not on) end, row)
end

local function DrawChoice(row, x1, x2, mid, mx, my)
	local t = S.theme
	local n = #row.options
	local gap = S.px(5)
	local w = ((x2 - x1) - gap * (n - 1)) / n
	local h = S.px(28)
	local cur = row.get()
	for i = 1, n do
		local cx1 = floor(x1 + (i - 1) * (w + gap))
		local cx2 = floor(cx1 + w)
		local over = S.Inside(mx, my, cx1, mid - h * 0.5, cx2, mid + h * 0.5)
		S.Button(cx1, mid - h * 0.5, cx2, mid + h * 0.5, (i == cur) and "active" or (over and "hover" or nil))
		S.Text(S.Fit(row.options[i], 12, w - S.px(4)), (cx1 + cx2) * 0.5, mid, 12, t.text, "cv")
		AddHit(cx1, mid - h * 0.5, cx2, mid + h * 0.5, function() row.set(i) end, row)
	end
end

local function DrawSwatches(row, x1, x2, mid, mx, my)
	local t = S.theme
	local tints = t.tints or {}
	local n = max(1, #tints)
	local gap = S.px(6)
	local size = min(S.px(30), floor(((x2 - x1) - gap * (n - 1)) / n))
	local sx = x2 - (n * size + (n - 1) * gap)
	for i = 1, #tints do
		local tint = tints[i]
		local bx1, by1, bx2, by2 = sx, mid - size * 0.5, sx + size, mid + size * 0.5
		local c = tint.color
		S.Rect(bx1, by1, bx2, by2, c and { c[1], c[2], c[3], 1 } or { 0.10, 0.11, 0.12, 1 }, S.px(5))
		if not c then
			-- "None": a neutral tile with a dash
			S.Rect(bx1 + size * 0.28, mid - 1, bx2 - size * 0.28, mid + 1, t.textDim, 0)
		end
		if t.tint == tint.name then
			S.Outline(bx1 - 2, by1 - 2, bx2 + 2, by2 + 2, t.text, S.px(6), max(2, S.px(2)))
		elseif S.Inside(mx, my, bx1, by1, bx2, by2) then
			S.Outline(bx1 - 1, by1 - 1, bx2 + 1, by2 + 1, t.textDim, S.px(6), 1)
		end
		local name = tint.name
		AddHit(bx1, by1, bx2, by2, function() S.Set("tint", name) end, row)
		sx = sx + size + gap
	end
end

local function DrawButton(row, x1, x2, mid, mx, my)
	local t = S.theme
	local w, h = S.px(170), S.px(30)
	local bx1 = x2 - w
	local over = S.Inside(mx, my, bx1, mid - h * 0.5, x2, mid + h * 0.5)
	S.Button(bx1, mid - h * 0.5, x2, mid + h * 0.5, over and "hover" or nil)
	S.Text(row.text, (bx1 + x2) * 0.5, mid, 13, t.text, "cv")
	AddHit(bx1, mid - h * 0.5, x2, mid + h * 0.5, row.action, row)
end

local drawers = {
	slider = DrawSlider, toggle = DrawToggle, choice = DrawChoice,
	swatches = DrawSwatches, button = DrawButton,
}

--------------------------------------------------------------------------------

function widget:DrawScreen()
	if not open or WG.Slate ~= S then return end
	local t = S.theme
	local mx, my = Spring.GetMouseState()
	hits = {}

	local top
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, HEIGHT, "Settings", mx, my)
	wy2 = top + S.px(44)

	local pad = S.px(18)
	local x1, x2 = wx1 + pad, wx2 - pad
	local y = top - S.px(12)

	-- tabs
	local th = S.px(TAB_H)
	local tw = S.px(120)
	for i = 1, #tabs do
		local tx1 = x1 + (i - 1) * (tw + S.px(6))
		local over = S.Inside(mx, my, tx1, y - th, tx1 + tw, y)
		S.Button(tx1, y - th, tx1 + tw, y, (i == tab) and "active" or (over and "hover" or nil))
		S.Text(tabs[i].label, tx1 + tw * 0.5, y - th * 0.5, 14, t.text, "cv")
		AddHit(tx1, y - th, tx1 + tw, y, function() tab = i end)
	end
	y = y - th - S.px(14)

	local rows = tabs[tab].rows
	local rh = S.px(ROW_H)
	local cw = S.px(CONTROL_W)
	for i = 1, #rows do
		local row = rows[i]
		local mid = y - rh * 0.5
		S.Text(row.label, x1, mid, 15, t.text, "v")
		drawers[row.kind](row, x2 - cw, x2, mid, mx, my)
		y = y - rh
	end

	S.Text("Changes apply straight away and are saved.", x1, wy1 + S.px(18), 13, t.textDim, "v")
	S.Flush()
end

--------------------------------------------------------------------------------
-- Mouse and keys
--------------------------------------------------------------------------------

local function InWindow(mx, my)
	return open and wx1 and S.Inside(mx, my, wx1, wy1, wx2, wy2)
end

function widget:IsAbove(mx, my)
	return (WG.Slate == S and InWindow(mx, my)) or false
end

function widget:GetTooltip()
	return ""
end

function widget:MousePress(mx, my, button)
	if not open or WG.Slate ~= S or not wx1 then return false end
	if not InWindow(mx, my) then return false end
	if button ~= 1 then return true end
	if closeRect and S.Inside(mx, my, closeRect[1], closeRect[2], closeRect[3], closeRect[4]) then
		Close()
		return true
	end
	for i = #hits, 1, -1 do
		local h = hits[i]
		if mx >= h.x1 and mx <= h.x2 and my >= h.y1 and my <= h.y2 then
			h.fn(mx)
			break
		end
	end
	return true
end

function widget:MouseMove(mx, my)
	if drag then
		drag.value = SliderValueAt(drag.row, drag.x1, drag.x2, mx)
		if not drag.row.onRelease then drag.row.set(drag.value) end
		return true
	end
end

function widget:MouseRelease(mx, my)
	if drag then
		if drag.row.onRelease then drag.row.set(drag.value) end
		drag = nil
	end
	return true
end

function widget:KeyPress(key)
	if open and key == 27 then   -- Esc
		Close()
		return true
	end
	return false
end
