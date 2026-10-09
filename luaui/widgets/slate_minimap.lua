-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Minimap",
		desc    = "Frames the engine minimap in a Slate panel and keeps it sized to the map's shape.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = 6,
		enabled = true,
	}
end

local ID = "minimap"
local SIZE  = 300                   -- design pixels, outer frame
local INSET = 6

local floor = math.floor

local S
local x1, y1, x2, y2
local oldGeometry
local lastGeometry = ""
local mapRect                       -- { x1, y1, x2, y2 } of the minimap itself

--------------------------------------------------------------------------------

local function Apply()
	if not x1 then return end
	local inset = S.px(INSET)
	local boxW, boxH = (x2 - x1) - inset * 2, (y2 - y1) - inset * 2
	local aspect = (Game.mapSizeX or 1) / (Game.mapSizeZ or 1)
	local w, h = boxW, boxH
	if aspect > 1 then h = floor(boxW / aspect) else w = floor(boxH * aspect) end
	local mx = floor(x1 + inset + (boxW - w) * 0.5)
	local topY = floor(y2 - inset - (boxH - h) * 0.5)
	-- the engine measures the minimap's y position from the top of the screen
	mapRect = { mx, topY - h, mx + w, topY }
	local geometry = string.format("%i %i %i %i", mx, S.vsy - topY, w, h)
	if geometry ~= lastGeometry then
		lastGeometry = geometry
		Spring.SendCommands("minimap geometry " .. geometry)
	end
end

local function Layout()
	x1, y1, x2, y2 = S.Box(ID, "l", "t", S.theme.margin, S.theme.margin, SIZE, SIZE)
	Apply()
end

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	oldGeometry = Spring.GetConfigString("MiniMapGeometry", "2 2 200 200")
	Spring.SendCommands("minimap minimize 0")
	S.Register(ID, "Minimap", Layout)
	S.OnChange(ID, Layout)
	Layout()
end

function widget:Shutdown()
	if oldGeometry and oldGeometry ~= "" then
		Spring.SendCommands("minimap geometry " .. oldGeometry)
	end
	if S then
		S.Unregister(ID)
		S.OffChange(ID)
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then
		lastGeometry = ""
		Layout()
	end
end

-- The engine draws its minimap before widgets draw, so a full panel here would
-- sit on top of it. Draw the frame as four bands around the map instead.
function widget:DrawScreen()
	if WG.Slate ~= S or not x1 or not mapRect then return end
	local t = S.theme
	local p = t.panel
	local glass = { p[1], p[2], p[3], t.opacity }
	local m = mapRect
	S.Rect(x1, m[4], x2, y2, glass, 0)          -- above the map
	S.Rect(x1, y1, x2, m[2], glass, 0)          -- below
	S.Rect(x1, m[2], m[1], m[4], glass, 0)      -- left
	S.Rect(m[3], m[2], x2, m[4], glass, 0)      -- right
	S.Outline(x1, y1, x2, y2, t.border, S.px(t.radius), 1)
	S.Outline(m[1] - 1, m[2] - 1, m[3] + 1, m[4] + 1, t.buttonBorder, 0, 1)
	S.Flush()
end
