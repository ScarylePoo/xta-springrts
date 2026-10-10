-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Core",
		desc    = "Shared theme, scaling, fonts and drawing helpers for the Slate panels. /slate opacity <0-1>, /slate blur, /slate wind, /slate tidal",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = -99998,   -- after Slate Draw (-100000) and Slate Layout (-99999), before every panel
		enabled = true,
		handler = true,
	}
end

--------------------------------------------------------------------------------
-- WHAT THIS IS
--
-- Every Slate panel is a small widget that asks this one for three things:
--
--   WG.Slate.theme   colours, opacity, sizes   (luaui/slate/configs/slate_theme.lua)
--   WG.Slate.game    what the game looks like  (luaui/slate/configs/slate_game.lua)
--   drawing helpers  Panel, Rect, Outline, Icon, Text, Box, ...
--
-- so no panel hardcodes a colour, loads its own font, or knows whether shapes
-- are being batched by Slate Draw or drawn the old way.
--
-- TO USE SLATE IN ANOTHER GAME
--
--   copy  the luaui/slate/ folder
--   add   luaui/slate/widgets/ to the widget handler's search (README.md)
--   edit  a copy of slate_game.lua (and slate_theme.lua to taste) placed in
--         the game's own luaui/configs/, which is read in preference
--
-- Nothing else in the game refers to these files.
--------------------------------------------------------------------------------

local SLATE_DIR  = LUAUI_DIRNAME .. "slate/"
-- A game's own copy in luaui/configs/ wins, so the slate folder can be
-- replaced with a newer one without losing the game's settings.
local CONFIG_DIRS = { LUAUI_DIRNAME .. "configs/", SLATE_DIR .. "configs/" }
local BASE_HEIGHT = 1080

local spGetViewGeometry = Spring.GetViewGeometry
local spEcho            = Spring.Echo
local glColor           = gl.Color
local glRect            = gl.Rect
local glTexture         = gl.Texture
local glTexRect         = gl.TexRect
local floor             = math.floor
local max               = math.max
local min               = math.min

local S = {}
local SG                 -- WG.SlateDraw when its shader came up, else nil
local rawFont, font
local fontPixels = 0
local vsx, vsy = spGetViewGeometry()

-- Player overrides, saved between games.
local saved = {}

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------

local function LoadTable(file, fallback)
	local path
	for i = 1, #CONFIG_DIRS do
		if VFS.FileExists(CONFIG_DIRS[i] .. file) then
			path = CONFIG_DIRS[i] .. file
			break
		end
	end
	if not path then
		spEcho("[Slate] missing " .. CONFIG_DIRS[#CONFIG_DIRS] .. file)
		return fallback
	end
	local ok, result = pcall(VFS.Include, path)
	if not ok or type(result) ~= "table" then
		spEcho("[Slate] could not load " .. path .. ": " .. tostring(result))
		return fallback
	end
	return result
end

-- Untinted copies of the colours a tint changes.
local base

local function TintColor(name)
	local tints = S.theme.tints or {}
	for i = 1, #tints do
		if tints[i].name == name then return tints[i].color end
	end
end

local function ApplyTint()
	local t = S.theme
	if not base then
		base = {
			panel  = { t.panel[1], t.panel[2], t.panel[3] },
			border = { t.border[1], t.border[2], t.border[3], t.border[4] },
			accent = { t.accent[1], t.accent[2], t.accent[3], t.accent[4] },
		}
	end
	local c = TintColor(t.tint)
	local s = c and min(1, max(0, t.tintStrength or 0)) or 0
	c = c or { 0, 0, 0 }
	for i = 1, 3 do
		local light = c[i] * 0.55 + 0.45
		-- the glass stays dark enough for text at any strength
		t.panel[i]  = base.panel[i] * (1 - s) + c[i] * 0.38 * s
		t.border[i] = base.border[i] * (1 - s) + light * s
		t.accent[i] = base.accent[i] * (1 - s) + light * s
	end
end

local function ApplySaved()
	local t = S.theme
	if type(saved.opacity) == "number" then t.opacity = min(1, max(0.1, saved.opacity)) end
	if type(saved.blur) == "boolean" then t.blur = saved.blur end
	if type(saved.scale) == "number" then t.scale = min(1.5, max(0.7, saved.scale)) end
	if type(saved.minimapSize) == "number" then t.minimapSize = min(2.5, max(0.5, saved.minimapSize)) end
	if type(saved.tint) == "string" then t.tint = saved.tint end
	if type(saved.tintStrength) == "number" then t.tintStrength = saved.tintStrength end
	ApplyTint()
	local addons = S.game.addons
	if addons then
		if type(saved.wind) == "boolean" then addons.wind = saved.wind end
		if type(saved.tidal) == "boolean" then addons.tidal = saved.tidal end
	end
end

--------------------------------------------------------------------------------
-- Scale and fonts
--------------------------------------------------------------------------------

local function LoadFont()
	local px = max(12, floor(26 * S.scale + 0.5))
	if font and px == fontPixels then return end
	if rawFont then gl.DeleteFont(rawFont) end
	fontPixels = px
	local file = SLATE_DIR .. "fonts/" .. (S.theme.font or "")
	if not VFS.FileExists(file) then file = LUAUI_DIRNAME .. "fonts/" .. (S.theme.font or "") end
	rawFont = VFS.FileExists(file) and gl.LoadFont(file, px, max(2, floor(px * 0.2)), 1.4) or nil
	if not rawFont then
		rawFont = gl.LoadFont("FreeSansBold.otf", px, max(2, floor(px * 0.2)), 1.4)
	end
	font = (SG and SG.WrapFont) and SG.WrapFont(rawFont) or rawFont
	S.font = font
end

local function RescaleNow()
	vsx, vsy = spGetViewGeometry()
	S.vsx, S.vsy = vsx, vsy
	S.scale = (vsy / BASE_HEIGHT) * (S.theme.scale or 1)
	LoadFont()
end

--------------------------------------------------------------------------------
-- Drawing helpers
--
-- All coordinates are final screen pixels, origin bottom-left.
--------------------------------------------------------------------------------

-- Scale a 1080p design size to this screen, rounded to a whole pixel.
function S.px(v)
	return floor(v * S.scale + 0.5)
end

function S.Rect(x1, y1, x2, y2, color, radius)
	if SG then
		SG.RoundedRect(x1, y1, x2, y2, radius or 0, color)
	else
		glColor(color[1], color[2], color[3], color[4] or 1)
		glRect(x1, y1, x2, y2)
	end
end

function S.Outline(x1, y1, x2, y2, color, radius, width)
	width = width or 1
	if SG then
		SG.RoundedOutline(x1, y1, x2, y2, radius or 0, color, width)
	else
		glColor(color[1], color[2], color[3], color[4] or 1)
		glRect(x1, y1, x2, y1 + width)
		glRect(x1, y2 - width, x2, y2)
		glRect(x1, y1, x1 + width, y2)
		glRect(x2 - width, y1, x2, y2)
	end
end

-- The standard panel body: translucent glass plus a hairline border.
function S.Panel(x1, y1, x2, y2)
	local t = S.theme
	local r = S.px(t.radius)
	local p = t.panel
	S.Rect(x1, y1, x2, y2, { p[1], p[2], p[3], t.opacity }, r)
	S.Outline(x1, y1, x2, y2, t.border, r, 1)
end

-- A clickable tile. state: nil, "hover", "active", "warn".
function S.Button(x1, y1, x2, y2, state)
	local t = S.theme
	local r = S.px(t.buttonRadius)
	local fill = t.button
	if state == "active" then fill = t.buttonActive
	elseif state == "hover" then fill = t.buttonHover end
	S.Rect(x1, y1, x2, y2, fill, r)
	if state == "warn" then
		S.Outline(x1, y1, x2, y2, t.warn, r, max(2, S.px(2)))
	elseif state == "active" then
		S.Outline(x1, y1, x2, y2, t.accent, r, 1)
	else
		S.Outline(x1, y1, x2, y2, t.buttonBorder, r, 1)
	end
end

-- A horizontal bar filled to `frac` (0-1).
function S.Bar(x1, y1, x2, y2, frac, color)
	local r = (y2 - y1) * 0.5
	S.Rect(x1, y1, x2, y2, S.theme.track, r)
	frac = min(1, max(0, frac or 0))
	local fx = x1 + (x2 - x1) * frac
	if fx - x1 >= 2 then
		S.Rect(x1, y1, fx, y2, color, min(r, (fx - x1) * 0.5))
	end
end

function S.Icon(x1, y1, x2, y2, texture, color)
	color = color or { 1, 1, 1, 1 }
	if SG then
		SG.Icon(x1, y1, x2, y2, texture, color)
	else
		glColor(color[1], color[2], color[3], color[4] or 1)
		glTexture(texture)
		glTexRect(x1, y1, x2, y2)
		glTexture(false)
	end
end

-- size is in 1080p design pixels. opts are the engine font flags: "c" centre,
-- "r" right, "o" outline, "v" vertical centre, "d" baseline at descender.
function S.Text(str, x, y, size, color, opts)
	if not font or not str then return end
	color = color or S.theme.text
	font:SetTextColor(color[1], color[2], color[3], color[4] or 1)
	-- an outline has its own colour; fade it with the text
	if opts and opts:find("o", 1, true) then font:SetOutlineColor(0, 0, 0, color[4] or 1) end
	font:Print(str, floor(x), floor(y), max(8, size * S.scale), opts or "")
end

function S.TextWidth(str, size)
	if not font or not str then return 0 end
	return font:GetTextWidth(str) * max(8, size * S.scale)
end

-- Shorten a string with an ellipsis until it fits `width` screen pixels.
function S.Fit(str, size, width)
	if not str then return "" end
	if S.TextWidth(str, size) <= width then return str end
	local n = #str
	while n > 1 and S.TextWidth(str:sub(1, n) .. "...", size) > width do
		n = n - 1
	end
	return str:sub(1, n) .. "..."
end

--------------------------------------------------------------------------------
-- Caching
--
-- Drawing a panel means laying it out, formatting numbers, measuring and
-- trimming text, and pushing every shape - a lot of Lua for something that
-- usually looks the same as last frame. Cached() records all of that once and
-- replays the recording until `key` changes:
--
--     cache = S.Cached(cache, key, function() ...draw the panel... end)
--
-- `key` is any value that is different whenever the panel should look
-- different (a string built from the numbers shown is typical). Include
-- S.version in it: that number goes up whenever the theme, scale or layout
-- changes. Without Slate Draw there is nothing to record into, so the function
-- simply runs every frame.
--------------------------------------------------------------------------------

S.version = 0

function S.Cached(cache, key, fn)
	if not SG then
		fn()
		return cache
	end
	cache = cache or { list = SG.NewList() }
	if cache.key ~= key then
		cache.key = key
		-- One text block per recording: the panel's shapes go out in a single
		-- batch and its text in another, instead of a draw call per label.
		-- (Everything a panel draws as text sits on top of its shapes.)
		SG.Record(cache.list, function()
			if font then font:Begin() end
			fn()
			if font then font:End() end
		end)
	end
	SG.Replay(cache.list)
	return cache
end

-- Call at the end of every panel's DrawScreen: hands batched shapes to the GPU.
function S.Flush()
	if SG then SG.Flush() end
	glColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- Placement
--
-- Box() turns "300x264 design pixels, 16 in from the bottom-left corner" into
-- a screen rectangle, and lets Slate Layout move it if the player has dragged
-- the panel in tweak mode (Ctrl+F11).
--
-- anchorX: "l", "c" or "r".  anchorY: "t" or "b".  offX/offY are design
-- pixels in from that edge (ignored for "c").
--------------------------------------------------------------------------------

function S.Box(id, anchorX, anchorY, offX, offY, w, h)
	local pw, ph = S.px(w), S.px(h)
	local x1, y1
	if anchorX == "l" then x1 = S.px(offX)
	elseif anchorX == "r" then x1 = vsx - S.px(offX) - pw
	else x1 = floor((vsx - pw) * 0.5) + S.px(offX) end
	if anchorY == "b" then y1 = S.px(offY)
	else y1 = vsy - S.px(offY) - ph end

	local L = WG.SlateLayout
	if L and id then x1, y1 = L.Place("slate_" .. id, x1, y1, pw, ph) end
	return x1, y1, x1 + pw, y1 + ph
end

-- onResize(width, height), optional, makes the panel resizable in tweak mode:
-- it is called with the size the player is dragging the corner grip to.
function S.Register(id, label, onMove, onResize)
	local L = WG.SlateLayout
	if L then L.Register("slate_" .. id, { label = label, onMove = onMove, onResize = onResize }) end
end

function S.Unregister(id)
	local L = WG.SlateLayout
	if L then L.Unregister("slate_" .. id) end
end

function S.Inside(x, y, x1, y1, x2, y2)
	return x1 and x >= x1 and x <= x2 and y >= y1 and y <= y2
end

--------------------------------------------------------------------------------
-- Blur behind panels (optional)
--------------------------------------------------------------------------------

local blurred = {}

function S.Blur(id, x1, y1, x2, y2)
	local api = WG["guishader_api"]
	if not (S.theme.blur and api and x1) then
		if blurred[id] and api then api.RemoveRect("slate_" .. id) end
		blurred[id] = nil
		return
	end
	local key = x1 .. ":" .. y1 .. ":" .. x2 .. ":" .. y2
	if blurred[id] ~= key then
		api.InsertRect(x1, y1, x2, y2, "slate_" .. id)
		blurred[id] = key
	end
end

function S.Unblur(id)
	local api = WG["guishader_api"]
	if blurred[id] and api then api.RemoveRect("slate_" .. id) end
	blurred[id] = nil
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

function S.Number(v)
	v = floor((v or 0) + 0.5)
	local s = tostring(math.abs(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (v < 0 and "-" or "") .. out
end

-- Whole-number cost for a small label: 145, 2484, 12k.
function S.Cost(v)
	v = v or 0
	if v >= 100000 then return string.format("%.0fk", v / 1000) end
	if v >= 10000 then return string.format("%.1fk", v / 1000) end
	return string.format("%d", floor(v + 0.5))
end

function S.Short(v)
	v = v or 0
	local a = math.abs(v)
	if a >= 100000 then return string.format("%.0fk", v / 1000) end
	if a >= 10000 then return string.format("%.1fk", v / 1000) end
	if a >= 100 then return string.format("%.0f", v) end
	return string.format("%.1f", v)
end

--------------------------------------------------------------------------------
-- Settings: what the settings screen (or any widget) reads and writes.
-- Keys: opacity, blur, scale, minimapSize, tint, tintStrength, wind, tidal.
--------------------------------------------------------------------------------

function S.Get(key)
	local t = S.theme
	if key == "wind" or key == "tidal" then
		return (S.game.addons or {})[key] and true or false
	end
	return t[key]
end

local NotifyAll, Rescale   -- defined below

function S.Set(key, value)
	saved[key] = value
	ApplySaved()
	if key == "blur" and value and not WG["guishader_api"] then
		widgetHandler:EnableWidget("GUI-Shader")
	end
	Rescale()
	NotifyAll()
end

--------------------------------------------------------------------------------
-- Windows: the frame shared by the settings screen, widget list and graphs.
-- Draws a centred panel with a title and a close button, and returns the
-- panel rectangle plus the close button rectangle.
--------------------------------------------------------------------------------

function S.Window(id, w, h, title, mx, my)
	local t = S.theme
	local pw, ph = min(S.px(w), vsx - 20), min(S.px(h), vsy - 20)
	local x1, y1 = floor((vsx - pw) * 0.5), floor((vsy - ph) * 0.5)
	local x2, y2 = x1 + pw, y1 + ph
	local r = S.px(t.radius)
	local p = t.panel
	-- windows hold a lot of text, so they are never more see-through than this
	S.Rect(x1, y1, x2, y2, { p[1], p[2], p[3], max(t.opacity, 0.88) }, r)
	S.Outline(x1, y1, x2, y2, t.border, r, 1)
	S.Blur(id, x1, y1, x2, y2)

	local bar = S.px(44)
	S.Text(title, x1 + S.px(18), y2 - bar * 0.5, 18, t.text, "v")
	S.Rect(x1 + S.px(12), y2 - bar, x2 - S.px(12), y2 - bar + 1, t.border, 0)
	local cs = S.px(28)
	local cx2, cy2 = x2 - S.px(10), y2 - S.px(8)
	local close = { cx2 - cs, cy2 - cs, cx2, cy2 }
	S.Button(close[1], close[2], close[3], close[4], S.Inside(mx, my, close[1], close[2], close[3], close[4]) and "hover" or nil)
	S.Text("X", (close[1] + close[3]) * 0.5, (close[2] + close[4]) * 0.5, 14, t.text, "cv")
	return x1, y1, x2, y2 - bar, close
end

--------------------------------------------------------------------------------
-- Line chart
--
-- series = { { label = "Income", color = {r,g,b,a}, points = { v1, v2, ... } }, ... }
-- All series share one y axis starting at zero and the same number of points.
-- opts.xLabel(i) -> string names point i (used for the axis ends and hover).
-- opts.title is drawn above the plot. opts.noLegend leaves the legend to the
-- caller. Hovering shows the values under the cursor; the index of the hovered
-- point is returned (nil when the mouse is elsewhere).
--------------------------------------------------------------------------------

local function Polyline(points, width, color)
	if #points < 4 then return end
	if SG then
		SG.LineStrip(points, width, color)
	else
		local verts = {}
		for i = 1, #points - 1, 2 do verts[#verts + 1] = { v = { points[i], points[i + 1] } } end
		glColor(color[1], color[2], color[3], color[4] or 1)
		gl.LineWidth(width)
		gl.Shape(GL.LINE_STRIP, verts)
		gl.LineWidth(1)
	end
end

function S.LineChart(x1, y1, x2, y2, series, opts, mx, my)
	local t = S.theme
	opts = opts or {}
	local n = 0
	local top = 0
	for s = 1, #series do
		local pts = series[s].points
		n = max(n, #pts)
		for i = 1, #pts do if pts[i] > top then top = pts[i] end end
	end
	if top <= 0 then top = 1 end

	-- title and legend share the strip above the plot
	local head = S.px(26)
	local lx = x1
	if opts.title then
		S.Text(opts.title:upper(), x1, y2 - head * 0.5, 12, t.accent, "v")
		lx = x1 + S.TextWidth(opts.title:upper(), 12) + S.px(18)
	end
	for s = 1, (opts.noLegend and 0 or #series) do
		local e = series[s]
		local sw = S.px(10)
		local mid = y2 - head * 0.5
		if lx + sw < x2 - S.px(40) then
			S.Rect(lx, mid - S.px(2), lx + sw, mid + S.px(2), e.color, S.px(2))
			local last = e.points[#e.points]
			local label = e.label .. (last and ("  " .. S.Short(last)) or "")
			S.Text(label, lx + sw + S.px(6), mid, 13, t.text, "v")
			lx = lx + sw + S.px(6) + S.TextWidth(label, 13) + S.px(18)
		end
	end

	local axisW = S.px(46)
	local px1, px2 = x1 + axisW, x2
	local py1, py2 = y1 + S.px(20), y2 - head - S.px(4)

	-- recessive grid: baseline, middle, top
	for g = 0, 2 do
		local gy = floor(py1 + (py2 - py1) * g / 2)
		S.Rect(px1, gy, px2, gy + 1, t.chartGrid, 0)
		S.Text(S.Short(top * g / 2), px1 - S.px(8), gy, 11, t.textDim, "rv")
	end
	if n >= 1 and opts.xLabel then
		S.Text(opts.xLabel(1), px1, y1 + S.px(6), 11, t.textDim, "v")
		S.Text(opts.xLabel(n), px2, y1 + S.px(6), 11, t.textDim, "rv")
	end
	if n < 2 then
		S.Text("Not enough data yet", (px1 + px2) * 0.5, (py1 + py2) * 0.5, 13, t.textDim, "cv")
		return
	end

	local lineW = max(2, S.px(2))
	for s = 1, #series do
		local pts = series[s].points
		local flat = {}
		for i = 1, #pts do
			flat[#flat + 1] = px1 + (px2 - px1) * (i - 1) / (n - 1)
			flat[#flat + 1] = py1 + (py2 - py1) * (pts[i] / top)
		end
		Polyline(flat, lineW, series[s].color)
	end

	-- hover: crosshair, a dot on each line, and the values at that point
	local hoverIndex
	if mx and S.Inside(mx, my, px1, py1, px2, py2) then
		local i = floor((mx - px1) / (px2 - px1) * (n - 1) + 0.5) + 1
		hoverIndex = i
		local hx = floor(px1 + (px2 - px1) * (i - 1) / (n - 1))
		S.Rect(hx, py1, hx + 1, py2, t.textDim, 0)
		local rows = {}
		local wide = opts.xLabel and S.TextWidth(opts.xLabel(i), 12) or 0
		for s = 1, #series do
			local v = series[s].points[i]
			if v then
				local hy = py1 + (py2 - py1) * (v / top)
				local r = S.px(4)
				S.Rect(hx - r, hy - r, hx + r, hy + r, series[s].color, r)
				local label = series[s].label .. "  " .. S.Short(v)
				rows[#rows + 1] = { color = series[s].color, label = label }
				wide = max(wide, S.TextWidth(label, 13) + S.px(16))
			end
		end
		local lh = S.px(18)
		local bw, bh = wide + S.px(20), (#rows + 1) * lh + S.px(12)
		local bx = (hx + S.px(26) + bw < px2) and (hx + S.px(26)) or (hx - S.px(14) - bw)
		local by = min(py2 - bh, max(py1, my - bh * 0.5))
		S.Rect(bx, by, bx + bw, by + bh, { 0.04, 0.045, 0.05, 0.95 }, S.px(5))
		S.Outline(bx, by, bx + bw, by + bh, t.border, S.px(5), 1)
		local ty = by + bh - S.px(6) - lh * 0.5
		if opts.xLabel then S.Text(opts.xLabel(i), bx + S.px(10), ty, 12, t.textDim, "v") end
		for r = 1, #rows do
			ty = ty - lh
			S.Rect(bx + S.px(10), ty - S.px(2), bx + S.px(20), ty + S.px(2), rows[r].color, S.px(2))
			S.Text(rows[r].label, bx + S.px(26), ty, 13, t.text, "v")
		end
	end
return hoverIndex
end

--------------------------------------------------------------------------------
-- Shared hover state: the build/order menu writes it, the selection panel
-- reads it. { unitDefID = n } or { title = "...", text = "..." } or nil.
--------------------------------------------------------------------------------

S.hover = nil

--------------------------------------------------------------------------------
-- Panel hints. A panel registers a function (mx, my) -> title, text that
-- answers only while the mouse is over it; the selection panel shows the
-- answer. (The engine tooltip is switched off, so hints have to travel here.)
--------------------------------------------------------------------------------

local tipProviders = {}
function S.SetTip(owner, fn) tipProviders[owner] = fn end

function S.TipAt(mx, my)
	for _, fn in pairs(tipProviders) do
		local ok, title, text = pcall(fn, mx, my)
		if ok and title then return title, text end
	end
end

-- Panels call this from ViewResize/Initialize handlers they register here, so
-- one resolution or theme change rebuilds every panel's geometry.
local listeners = {}
function S.OnChange(owner, fn) listeners[owner] = fn end
function S.OffChange(owner) listeners[owner] = nil end

NotifyAll = function()
	S.version = S.version + 1
	for owner, fn in pairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then spEcho("[Slate] " .. tostring(owner) .. ": " .. tostring(err)) end
	end
end

--------------------------------------------------------------------------------
-- Widget callins
--------------------------------------------------------------------------------

function widget:Initialize()
	SG = WG.SlateDraw
	if SG and not (SG.IsReady and SG.IsReady()) then SG = nil end

	S.theme = LoadTable("slate_theme.lua", nil)
	S.game  = LoadTable("slate_game.lua", nil)
	if not S.theme or not S.game then
		spEcho("[Slate] config missing - Slate is disabled")
		widgetHandler:RemoveWidget()
		return
	end
	ApplySaved()
	RescaleNow()

	if S.theme.blur and not WG["guishader_api"] then
		widgetHandler:EnableWidget("GUI-Shader")
	end

	-- Line-of-sight view on at the start of a game, if the game asks for it.
	-- Only before the game starts, so a player who turns it off keeps it off
	-- when the interface is reloaded.
	if S.game.losView and (Spring.GetGameFrame() or 0) <= 0 and Spring.GetMapDrawMode() ~= "los" then
		Spring.SendCommands("togglelos")
	end

	WG.Slate = S
end

function widget:Shutdown()
	if WG.Slate == S then WG.Slate = nil end
	local api = WG["guishader_api"]
	if api then
		for id in pairs(blurred) do api.RemoveRect("slate_" .. id) end
	end
	blurred = {}
	if rawFont then gl.DeleteFont(rawFont) ; rawFont = nil end
end

function widget:ViewResize()
	if not S.theme then return end
	RescaleNow()
	NotifyAll()
end

function widget:GetConfigData()
	return saved
end

function widget:SetConfigData(data)
	if type(data) == "table" then saved = data end
end

function widget:TextCommand(command)
	if command:sub(1, 5) ~= "slate" then return false end
	local arg1, arg2 = command:match("^slate%s+(%S+)%s*(%S*)")
	if arg1 == "opacity" then
		local v = tonumber(arg2)
		if v then
			saved.opacity = min(1, max(0.1, v))
			spEcho("[Slate] panel opacity " .. saved.opacity)
		else
			spEcho("[Slate] usage: /slate opacity 0.6")
		end
	elseif arg1 == "blur" then
		saved.blur = not S.theme.blur
		if saved.blur and not WG["guishader_api"] then widgetHandler:EnableWidget("GUI-Shader") end
		spEcho("[Slate] blur behind panels " .. (saved.blur and "on" or "off"))
	elseif arg1 == "wind" or arg1 == "tidal" then
		local addons = S.game.addons or {}
		S.game.addons = addons
		saved[arg1] = not addons[arg1]
		spEcho("[Slate] " .. arg1 .. " read-out " .. (saved[arg1] and "on" or "off"))
	else
		return false
	end
	ApplySaved()
	NotifyAll()
	return true
end

Rescale = RescaleNow
S.Notify = NotifyAll
