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
--   WG.Slate.theme   colours, opacity, sizes   (luaui/configs/slate_theme.lua)
--   WG.Slate.game    what the game looks like  (luaui/configs/slate_game.lua)
--   drawing helpers  Panel, Rect, Outline, Icon, Text, Box, ...
--
-- so no panel hardcodes a colour, loads its own font, or knows whether shapes
-- are being batched by Slate Draw or drawn the old way.
--
-- TO USE SLATE IN ANOTHER GAME
--
--   copy  luaui/widgets/slate_*.lua
--         luaui/configs/slate_theme.lua, slate_game.lua
--         luaui/fonts/<theme.font>
--   edit  slate_game.lua (and slate_theme.lua to taste)
--
-- Nothing else in the game refers to these files.
--------------------------------------------------------------------------------

local CONFIG_DIR = LUAUI_DIRNAME .. "configs/"
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
	local path = CONFIG_DIR .. file
	if not VFS.FileExists(path) then
		spEcho("[Slate] missing " .. path)
		return fallback
	end
	local ok, result = pcall(VFS.Include, path)
	if not ok or type(result) ~= "table" then
		spEcho("[Slate] could not load " .. path .. ": " .. tostring(result))
		return fallback
	end
	return result
end

local function ApplySaved()
	local t = S.theme
	if type(saved.opacity) == "number" then t.opacity = min(1, max(0.1, saved.opacity)) end
	if type(saved.blur) == "boolean" then t.blur = saved.blur end
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
	local file = LUAUI_DIRNAME .. "fonts/" .. (S.theme.font or "")
	rawFont = VFS.FileExists(file) and gl.LoadFont(file, px, max(2, floor(px * 0.2)), 1.4) or nil
	if not rawFont then
		rawFont = gl.LoadFont("FreeSansBold.otf", px, max(2, floor(px * 0.2)), 1.4)
	end
	font = (SG and SG.WrapFont) and SG.WrapFont(rawFont) or rawFont
	S.font = font
end

local function Rescale()
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

function S.Register(id, label, onMove)
	local L = WG.SlateLayout
	if L then L.Register("slate_" .. id, { label = label, onMove = onMove }) end
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
-- Shared hover state: the build/order menu writes it, the selection panel
-- reads it. { unitDefID = n } or { title = "...", text = "..." } or nil.
--------------------------------------------------------------------------------

S.hover = nil

-- Panels call this from ViewResize/Initialize handlers they register here, so
-- one resolution or theme change rebuilds every panel's geometry.
local listeners = {}
function S.OnChange(owner, fn) listeners[owner] = fn end
function S.OffChange(owner) listeners[owner] = nil end

local function NotifyAll()
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
	Rescale()

	if S.theme.blur and not WG["guishader_api"] then
		widgetHandler:EnableWidget("GUI-Shader")
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
	Rescale()
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
