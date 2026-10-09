-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Resource Bar",
		desc    = "Metal and energy with storage, income, drain and a draggable share level. Optional wind and tidal read-outs.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = 1,
		enabled = true,
	}
end

local ID       = "resourcebar"
local ADDON_ID = "resourceaddons"

local WIDTH, HEIGHT = 760, 64       -- design pixels
local PAD_X, PAD_Y  = 16, 12
local COL_GAP       = 28
local BAR_H         = 8
local ADDON_H       = 30

local spGetMyTeamID      = Spring.GetMyTeamID
local spGetTeamResources = Spring.GetTeamResources
local spSetShareLevel    = Spring.SetShareLevel
local spGetWind          = Spring.GetWind
local floor = math.floor
local min, max = math.min, math.max

local S
local x1, y1, x2, y2
local ax1, ay1, ax2, ay2            -- addon strip, nil when hidden
local columns = {}                  -- per resource: { res, cx1, cx2, barY1, barY2 }
local dragging                      -- column being dragged, or nil
local hasWater = false

--------------------------------------------------------------------------------

local function AddonsWanted()
	local a = S.game.addons or {}
	return a.wind, (a.tidal and hasWater)
end

local function Layout()
	x1, y1, x2, y2 = S.Box(ID, "c", "t", 0, S.theme.margin, WIDTH, HEIGHT)

	local resources = S.game.resources or {}
	local n = max(1, #resources)
	local padX, gap = S.px(PAD_X), S.px(COL_GAP)
	local colW = ((x2 - x1) - padX * 2 - gap * (n - 1)) / n
	columns = {}
	for i = 1, #resources do
		local cx1 = floor(x1 + padX + (i - 1) * (colW + gap))
		columns[i] = {
			res   = resources[i],
			cx1   = cx1,
			cx2   = floor(cx1 + colW),
			barY1 = y1 + S.px(PAD_Y),
			barY2 = y1 + S.px(PAD_Y) + S.px(BAR_H),
		}
	end

	local wind, tidal = AddonsWanted()
	if wind or tidal then
		local w = (wind and 230 or 0) + (tidal and 130 or 0)
		ax1, ay1, ax2, ay2 = S.Box(ADDON_ID, "c", "t", 0, S.theme.margin + HEIGHT + 8, w, ADDON_H)
	else
		ax1 = nil
		S.Unblur(ADDON_ID)
	end
end

local function ShareX(col, level)
	return col.cx1 + (col.cx2 - col.cx1) * min(1, max(0, level or 0))
end

local function ColumnAt(mx, my)
	local slop = S.px(7)
	for i = 1, #columns do
		local c = columns[i]
		if mx >= c.cx1 - slop and mx <= c.cx2 + slop and my >= c.barY1 - slop and my <= c.barY2 + slop then
			return c
		end
	end
end

--------------------------------------------------------------------------------

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	local lowest = Spring.GetGroundExtremes()
	hasWater = (lowest or 0) < 0
	Spring.SendCommands("resbar 0")
	S.Register(ID, "Resources", Layout)
	S.Register(ADDON_ID, "Wind and tidal", Layout)
	S.OnChange(ID, Layout)
	Layout()
	S.SetTip(ID, function(mx, my)
		if not x1 then return nil end
		local col = ColumnAt(mx, my)
		if col then
			return col.res.label .. " share level",
				"Drag the marker along the bar. When your storage is fuller than the marker, the excess goes to your allies."
		elseif S.Inside(mx, my, x1, y1, x2, y2) then
			return "Resources", "Stored and storage on the left. On the right, income (+) and what your builders are asking for (-), per second."
		elseif ax1 and S.Inside(mx, my, ax1, ay1, ax2, ay2) then
			return "Wind and tide", "Wind changes constantly within the range shown for this map; wind generators produce in step with it. Tidal strength is fixed for the map."
		end
	end)
end

function widget:Shutdown()
	Spring.SendCommands("resbar 1")
	if S then
		S.SetTip(ID, nil)
		S.Unregister(ID) ; S.Unregister(ADDON_ID)
		S.OffChange(ID)
		S.Unblur(ID) ; S.Unblur(ADDON_ID)
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then Layout() end
end

--------------------------------------------------------------------------------

local function DrawColumn(col, teamID)
	local t = S.theme
	local res = col.res
	local cur, storage, pull, income, _, share = spGetTeamResources(teamID, res.key)
	cur, storage, pull, income = cur or 0, storage or 0, pull or 0, income or 0

	S.Bar(col.cx1, col.barY1, col.cx2, col.barY2, (storage > 0) and (cur / storage) or 0, res.color)

	-- share level marker: resources above this line are given to allies
	if share then
		local sx = ShareX(col, share)
		local w = max(1, S.px(1))
		local over = S.px(3)
		S.Rect(sx - w, col.barY1 - over, sx + w, col.barY2 + over, (dragging == col) and t.warn or t.text, 0)
	end

	local ty = col.barY2 + S.px(16)
	local x = col.cx1
	S.Text(res.label:upper(), x, ty, 12, res.color)
	x = x + S.TextWidth(res.label:upper(), 12) + S.px(10)
	local curStr = S.Number(cur)
	S.Text(curStr, x, ty, 17, t.text)
	x = x + S.TextWidth(curStr, 17) + S.px(8)
	S.Text("/ " .. S.Number(storage), x, ty, 13, t.textDim)

	local drain = "-" .. S.Short(pull)
	S.Text(drain, col.cx2, ty, 14, t.bad, "r")
	S.Text("+" .. S.Short(income), col.cx2 - S.TextWidth(drain, 14) - S.px(10), ty, 14, t.good, "r")
end

local function DrawAddons()
	local t = S.theme
	local wind, tidal = AddonsWanted()
	S.Panel(ax1, ay1, ax2, ay2)
	S.Blur(ADDON_ID, ax1, ay1, ax2, ay2)
	local ty = ay1 + S.px(10)
	local x = ax1 + S.px(12)
	if wind then
		local _, _, _, strength = spGetWind()
		local label = "WIND"
		S.Text(label, x, ty, 12, t.accent)
		x = x + S.TextWidth(label, 12) + S.px(8)
		local v = string.format("%.1f", strength or 0)
		S.Text(v, x, ty, 15, t.text)
		x = x + S.TextWidth(v, 15) + S.px(8)
		local range = string.format("(%d - %d)", Game.windMin or 0, Game.windMax or 0)
		S.Text(range, x, ty, 13, t.textDim)
		x = x + S.TextWidth(range, 13) + S.px(20)
	end
	if tidal then
		local label = "TIDAL"
		S.Text(label, x, ty, 12, t.accent)
		x = x + S.TextWidth(label, 12) + S.px(8)
		S.Text(string.format("%.1f", Game.tidal or 0), x, ty, 15, t.text)
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S or not x1 then return end
	local teamID = spGetMyTeamID()
	if not teamID then return end

	S.Panel(x1, y1, x2, y2)
	S.Blur(ID, x1, y1, x2, y2)
	for i = 1, #columns do
		DrawColumn(columns[i], teamID)
	end
	if ax1 then DrawAddons() end
	S.Flush()
end

--------------------------------------------------------------------------------
-- Share level drag
--------------------------------------------------------------------------------

local function SetShareFromMouse(col, mx)
	local level = min(1, max(0, (mx - col.cx1) / (col.cx2 - col.cx1)))
	spSetShareLevel(col.res.key, level)
end

function widget:IsAbove(mx, my)
	if WG.Slate ~= S or not x1 then return false end
	return S.Inside(mx, my, x1, y1, x2, y2)
end

function widget:GetTooltip(mx, my)
	if ColumnAt(mx, my) then
		return "Drag the marker to set how full storage gets before the excess is shared with allies"
	end
	return "Stored / storage, income (+) and demand (-) per second"
end

function widget:MousePress(mx, my, button)
	if WG.Slate ~= S or not x1 then return false end
	if button ~= 1 or Spring.GetSpectatingState() then return S.Inside(mx, my, x1, y1, x2, y2) or false end
	local col = ColumnAt(mx, my)
	if col then
		dragging = col
		SetShareFromMouse(col, mx)
		return true
	end
	-- swallow clicks on the panel so they do not reach the map underneath
	return S.Inside(mx, my, x1, y1, x2, y2) or false
end

function widget:MouseMove(mx, my)
	if dragging then
		SetShareFromMouse(dragging, mx)
		return true
	end
end

function widget:MouseRelease()
	if dragging then
		dragging = nil
		return true
	end
	return false
end
