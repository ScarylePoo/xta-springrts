-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Minimap",
		desc    = "Frames the engine minimap. Its shape follows the map; move it and resize it in tweak mode (Ctrl+F11), or set its size in the settings.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = 1000,
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- HOW THIS WORKS (same approach as Splinter Faction's "Minimap Top Left")
--
-- The engine owns the minimap: it draws it, takes its mouse input and decides
-- its final rectangle. A widget can only ask for a geometry, and the engine
-- may override that request during the first frames of a game. So the minimap
-- is not something inside a box this widget built; it is something this
-- widget keeps drawing a box around:
--
--   * it asks for the geometry repeatedly for the first frames, then stops;
--   * the frame is drawn around Spring.GetMiniMapGeometry() - what the engine
--     really did - never around what was asked for.
--
-- Where and how big to ask for is the player's choice. In tweak mode
-- (Ctrl+F11) the frame drags like any other panel and its bottom-right corner
-- resizes it; the settings screen has a size slider as well. The shape always
-- follows the map, so the map is never letterboxed: resizing scales it, and
-- very wide maps are capped in width and lose height instead.
--
-- Other panels that need to sit beside the minimap read WG.Slate.minimap,
-- { x1, y1, x2, y2 } of the frame in screen pixels.
--------------------------------------------------------------------------------

-- design pixels (1080-high screen), at size 1
local MAP_HEIGHT    = 288
local MAX_MAP_WIDTH = 460
local FRAME         = 6             -- glass band around the map
local REAPPLY_FRAMES = 30
local ID = "minimap"

local spSendCommands       = Spring.SendCommands
local spGetMiniMapGeometry = Spring.GetMiniMapGeometry
local floor = math.floor
local min, max = math.min, math.max

local S
local oldGeometry
local frames = 0
local lastRect = ""
local lastAsked = ""
local cache

--------------------------------------------------------------------------------

-- Map size in screen pixels for a size multiplier.
local function MapSize(size)
	local aspect = (Game.mapSizeZ or 1) / (Game.mapSizeX or 1)   -- height / width
	local h = S.px(MAP_HEIGHT) * size
	local w = h / aspect
	local maxW = min(S.px(MAX_MAP_WIDTH) * size, S.vsx * 0.6)
	if w > maxW then
		w = maxW
		h = w * aspect
	end
	local maxH = S.vsy * 0.7
	if h > maxH then
		h = maxH
		w = h / aspect
	end
	return floor(w + 0.5), floor(h + 0.5)
end

local function Apply()
	local w, h = MapSize(S.theme.minimapSize or 1)
	local pad = S.px(FRAME)
	local fw, fh = w + pad * 2, h + pad * 2
	-- the frame is the panel: top-left by default, wherever it was dragged
	-- to otherwise
	local m = S.theme.margin
	local fx1, fy1 = S.Box(ID, "l", "t", m, m, fw / S.scale, fh / S.scale)
	local x = fx1 + pad
	local top = S.vsy - (fy1 + fh) + pad      -- the engine measures from the top
	local asked = x .. " " .. top .. " " .. w .. " " .. h
	if asked ~= lastAsked or frames < REAPPLY_FRAMES then
		lastAsked = asked
		spSendCommands("minimap geo " .. asked)
		spSendCommands("minimap border 0")
	end
end

-- Tweak mode is dragging the corner grip to this frame size.
local function Resize(_, frameH)
	local _, baseH = MapSize(1)
	local size = (frameH - S.px(FRAME) * 2) / max(1, baseH)
	size = floor(min(2.5, max(0.5, size)) * 50 + 0.5) / 50
	if size ~= (S.theme.minimapSize or 1) then S.Set("minimapSize", size) end
end

-- Publish the frame rectangle and tell the other panels when it changes.
local function Publish(x, y, w, h)
	local pad = S.px(FRAME)
	local rect = { x1 = x - pad, y1 = y - pad, x2 = x + w + pad, y2 = y + h + pad }
	local key = rect.x1 .. ":" .. rect.y1 .. ":" .. rect.x2 .. ":" .. rect.y2
	S.minimap = rect
	if key ~= lastRect then
		lastRect = key
		if S.Notify then S.Notify() end
	end
	return rect
end

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	oldGeometry = Spring.GetConfigString("MiniMapGeometry", "2 2 200 200")
	spSendCommands("minimap minimize 0")
	S.Register(ID, "Minimap", Apply, Resize)
	S.OnChange(ID, Apply)
	Apply()
end

function widget:Shutdown()
	if oldGeometry and oldGeometry ~= "" then
		spSendCommands("minimap geo " .. oldGeometry)
	end
	spSendCommands("minimap border 1")
	if S then
		S.Unregister(ID)
		S.OffChange(ID)
		S.Unblur(ID)
		S.minimap = nil
		if S.Notify then S.Notify() end
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then
		frames = 0
		Apply()
	end
end

-- The engine can replace the geometry while a game is starting, so keep asking
-- for a short while and then leave it alone.
function widget:Update()
	if WG.Slate ~= S then return end
	if frames < REAPPLY_FRAMES then
		frames = frames + 1
		Apply()
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S then return end
	local x, y, w, h, minimized = spGetMiniMapGeometry()
	if not (x and y and w and h) or minimized then return end

	local r = Publish(x, y, w, h)
	cache = S.Cached(cache, S.version .. ":" .. lastRect, function()
		local t = S.theme
		local p = t.panel
		local glass = { p[1], p[2], p[3], t.opacity }
		-- The engine has already drawn the map, so the glass goes around it
		-- as four bands, never over it.
		S.Rect(r.x1, y + h, r.x2, r.y2, glass, 0)     -- top
		S.Rect(r.x1, r.y1, r.x2, y, glass, 0)         -- bottom
		S.Rect(r.x1, y, x, y + h, glass, 0)           -- left
		S.Rect(x + w, y, r.x2, y + h, glass, 0)       -- right
		S.Outline(r.x1, r.y1, r.x2, r.y2, t.border, S.px(3), 1)
		S.Outline(x - 1, y - 1, x + w + 1, y + h + 1, t.buttonBorder, 0, 1)
	end)
	S.Flush()
end
