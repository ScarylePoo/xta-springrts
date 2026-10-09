-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Minimap",
		desc    = "Pins the engine minimap to the top-left corner at a size that follows the map's shape, and draws a frame around wherever the engine actually put it.",
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
-- may override that request during the first frames of a game. So this widget
-- does not treat the minimap as a panel:
--
--   * it is not registered with Slate Layout and cannot be dragged;
--   * it asks for the geometry repeatedly for the first frames, then stops;
--   * the frame is drawn around Spring.GetMiniMapGeometry() - what the engine
--     really did - never around what was asked for.
--
-- Height is fixed and width follows the map, so the map is never letterboxed.
-- Very wide maps are capped in width and lose height instead.
--
-- Other panels that need to sit beside the minimap read WG.Slate.minimap,
-- { x1, y1, x2, y2 } of the frame in screen pixels.
--------------------------------------------------------------------------------

-- design pixels (1080-high screen)
local MAP_HEIGHT    = 288
local MAX_MAP_WIDTH = 460
local FRAME         = 6             -- glass band around the map
local REAPPLY_FRAMES = 30

local spSendCommands       = Spring.SendCommands
local spGetMiniMapGeometry = Spring.GetMiniMapGeometry
local floor = math.floor

local S
local oldGeometry
local frames = 0
local lastRect = ""

--------------------------------------------------------------------------------

local function Apply()
	local aspect = (Game.mapSizeZ or 1) / (Game.mapSizeX or 1)   -- height / width
	local h = S.px(MAP_HEIGHT)
	local w = floor(h / aspect + 0.5)
	local maxW = S.px(MAX_MAP_WIDTH)
	if w > maxW then
		w = maxW
		h = floor(w * aspect + 0.5)
	end
	local inset = S.px(S.theme.margin) + S.px(FRAME)
	-- x and y are measured from the top-left corner of the screen
	spSendCommands("minimap geo " .. inset .. " " .. inset .. " " .. w .. " " .. h)
	spSendCommands("minimap border 0")
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
	S.OnChange("minimap", function() frames = 0 ; Apply() end)
	Apply()
end

function widget:Shutdown()
	if oldGeometry and oldGeometry ~= "" then
		spSendCommands("minimap geo " .. oldGeometry)
	end
	spSendCommands("minimap border 1")
	if S then
		S.OffChange("minimap")
		S.Unblur("minimap")
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
	local t = S.theme
	local p = t.panel
	local glass = { p[1], p[2], p[3], t.opacity }

	-- The engine has already drawn the map, so the glass goes around it as
	-- four bands, never over it.
	S.Rect(r.x1, y + h, r.x2, r.y2, glass, 0)     -- top
	S.Rect(r.x1, r.y1, r.x2, y, glass, 0)         -- bottom
	S.Rect(r.x1, y, x, y + h, glass, 0)           -- left
	S.Rect(x + w, y, r.x2, y + h, glass, 0)       -- right
	S.Outline(r.x1, r.y1, r.x2, r.y2, t.border, S.px(3), 1)
	S.Outline(x - 1, y - 1, x + w + 1, y + h + 1, t.buttonBorder, 0, 1)
	S.Flush()
end
