-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Share",
		desc    = "Share resources and units with another player. Press H, use the Menu, click an ally in the players list, or /slate share.",
		author  = "Scary le Poo",
		date    = "2026-10-09",
		license = "GNU GPL, v2 or later",
		layer   = -13,              -- after Slate Key Bindings, so the player's own keys are loaded first
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Same arrangement as the Static GUI share menu:
--
--   left column  = who  : Allies, Enemies
--   right column = what : Selected units + "share selected units", one slider
--                         per resource
--   footer       = Cancel | Apply
--
-- Pick one player, set what to send, press Apply. The window stays open so
-- several gifts can be made in a row; H or Esc closes it.
--------------------------------------------------------------------------------

local ID = "share"
local ACTION = "luaui slate share"

-- design pixels
local WIDTH        = 640
local PAD          = 16
local HEADER_H     = 22
local ROW_H        = 28
local ENEMY_ROWS   = 3              -- allies get the rest of the left column
local UNIT_LINE_H  = 21
local UNIT_LINES   = 4
local CHECK_H      = 28
local SLIDER_H     = 52
local BUTTON_H     = 34
local GAP          = 8
local GROUP_GAP    = 12
local FOOTER_GAP   = 30             -- also holds the status line
local BAR_W        = 6

local floor = math.floor
local min, max = math.min, math.max

local S
local open = false
local closeRect
local wx1, wy1, wx2, wy2
local g = nil                       -- rectangles from the last draw, for hit tests

local allies, enemies = {}, {}      -- { teamID, name, color }
local target                        -- teamID
local units = {}                    -- { name, count }
local scroll = { ally = 0, enemy = 0, unit = 0 }   -- first row shown, counted from 0
local amount = {}                   -- per resource key
local shareUnits = false
local drag                          -- { slider = key } or { list = name, grab = px }
local notice = ""
local boundKey = false
local ENEMY_COLOR = { 0.90, 0.30, 0.28, 1 }

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local function TeamName(teamID)
	local _, leader, _, isAI = Spring.GetTeamInfo(teamID, false)
	if isAI then
		local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
		return (aiName and aiName ~= "" and aiName ~= "UNKNOWN") and aiName or shortName or "AI"
	end
	return Spring.GetPlayerInfo(leader or -1, false) or ("Team " .. teamID)
end

local function RefreshPlayers()
	allies, enemies = {}, {}
	local myTeam, myAlly = Spring.GetMyTeamID(), Spring.GetMyAllyTeamID()
	local gaia = Spring.GetGaiaTeamID()
	local found = false
	local teams = Spring.GetTeamList() or {}
	for i = 1, #teams do
		local teamID = teams[i]
		if teamID ~= myTeam and teamID ~= gaia then
			local _, _, isDead, _, _, allyTeam = Spring.GetTeamInfo(teamID, false)
			if not isDead then
				local r, gg, b = Spring.GetTeamColor(teamID)
				local entry = { teamID = teamID, name = TeamName(teamID), color = { r or 1, gg or 1, b or 1, 1 } }
				local list = (allyTeam == myAlly) and allies or enemies
				list[#list + 1] = entry
				if teamID == target then found = true end
			end
		end
	end
	if not found then target = nil end
end

local function RefreshUnits()
	units = {}
	local index = {}
	local sel = Spring.GetSelectedUnits() or {}
	for i = 1, #sel do
		local defID = Spring.GetUnitDefID(sel[i])
		local ud = defID and UnitDefs[defID]
		if ud then
			local name = ud.translatedHumanName or ud.humanName or ud.name
			local at = index[name]
			if not at then
				at = #units + 1
				index[name] = at
				units[at] = { name = name, count = 0 }
			end
			units[at].count = units[at].count + 1
		end
	end
end

local function Storage(key)
	local _, storage = Spring.GetTeamResources(Spring.GetMyTeamID(), key)
	return floor(storage or 0)
end

local function TargetName()
	for _, list in ipairs({ allies, enemies }) do
		for i = 1, #list do
			if list[i].teamID == target then return list[i].name end
		end
	end
	return "?"
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

local function Close()
	open = false
	drag = nil
	if S then S.Unblur(ID) end
end

local function Open(wanted)
	open = true
	notice = ""
	amount = {}
	shareUnits = false
	scroll.ally, scroll.enemy, scroll.unit = 0, 0, 0
	target = wanted
	RefreshPlayers()
	RefreshUnits()
end

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	-- H opens this instead of the engine's share dialog, unless the player has
	-- already put the window on a key of their own.
	local keys = Spring.GetActionHotKeys(ACTION)
	if not keys or #keys == 0 then
		Spring.SendCommands("unbind Any+h sharedialog", "bind Any+h " .. ACTION)
		boundKey = true
	end
end

function widget:Shutdown()
	if boundKey then
		Spring.SendCommands("unbind Any+h " .. ACTION, "bind Any+h sharedialog")
	end
	if S then S.Unblur(ID) end
end

function widget:TextCommand(command)
	if command:sub(1, 11) ~= "slate share" then return false end
	if WG.Slate ~= S then return false end
	local wanted = tonumber(command:match("^slate share%s+(%d+)"))
	if open and not wanted then
		Close()
	elseif open then
		target = wanted
		RefreshPlayers()
	else
		Open(wanted)
	end
	return true
end

function widget:Update()
	if open then RefreshUnits() end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Header(r, label, color)
	local t = S.theme
	S.Rect(r.x1, r.y1, r.x2, r.y2, t.button, S.px(4))
	S.Rect(r.x1, r.y2 - max(2, S.px(3)), r.x2, r.y2, color or t.accent, 0)
	S.Text(label, r.x1 + S.px(10), (r.y1 + r.y2) * 0.5 - S.px(1), 12, t.text, "v")
end

-- Rows that fit in a list box, and the furthest it can scroll.
local function ListRows(r, rowH, count)
	local rows = max(1, floor((r.y2 - r.y1) / rowH + 0.01))
	return rows, max(0, count - rows)
end

local function Scrollbar(r, rowH, count, first, mx, my)
	local rows, maxFirst = ListRows(r, rowH, count)
	if maxFirst == 0 then return end
	local t = S.theme
	local bx1 = r.x2 - S.px(BAR_W)
	local trackH = r.y2 - r.y1
	local thumbH = max(S.px(16), trackH * rows / count)
	local ty2 = r.y2 - (trackH - thumbH) * (first / maxFirst)
	S.Rect(bx1, r.y1, r.x2, r.y2, t.track, 0)
	local over = S.Inside(mx, my, bx1, r.y1, r.x2, r.y2)
	S.Rect(bx1, ty2 - thumbH, r.x2, ty2, over and t.buttonActive or t.buttonHover, 0)
end

local function PlayerList(r, list, first, mx, my)
	local t = S.theme
	local rowH = S.px(ROW_H)
	S.Rect(r.x1, r.y1, r.x2, r.y2, t.track, S.px(4))
	local rows = ListRows(r, rowH, #list)
	local rx2 = r.x2 - S.px(BAR_W) - 2
	for i = 1, rows do
		local e = list[first + i]
		if not e then break end
		local y2 = r.y2 - (i - 1) * rowH
		local y1 = y2 - rowH
		local on = (e.teamID == target)
		if on then
			local c = e.color
			S.Rect(r.x1, y1, rx2, y2, { c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 0.55 }, 0)
			S.Rect(r.x1, y1, r.x1 + S.px(3), y2, c, 0)
		elseif S.Inside(mx, my, r.x1, y1, rx2, y2) then
			S.Rect(r.x1, y1, rx2, y2, t.buttonHover, 0)
		end
		local sw = S.px(12)
		local mid = (y1 + y2) * 0.5
		S.Rect(r.x1 + S.px(8), mid - sw * 0.5, r.x1 + S.px(8) + sw, mid + sw * 0.5, e.color, S.px(2))
		S.Text(S.Fit(e.name, 13, rx2 - r.x1 - S.px(36)), r.x1 + S.px(28), mid, 13, on and t.text or t.textDim, "v")
	end
	Scrollbar(r, rowH, #list, first, mx, my)
end

local function SliderTrack(r)
	local pad = S.px(12)
	local mid = r.y2 - S.px(18)
	local h = S.px(8)
	return r.x1 + pad, mid - h * 0.5, r.x2 - pad, mid + h * 0.5
end

function widget:DrawScreen()
	if not open or WG.Slate ~= S then return end
	if Spring.IsGUIHidden() then return end
	local t = S.theme
	local mx, my = Spring.GetMouseState()
	local resources = S.game.resources or {}

	-- column heights, in design pixels
	local rightH = HEADER_H + GAP + UNIT_LINE_H * UNIT_LINES + GAP + CHECK_H
	             + #resources * (GROUP_GAP + HEADER_H + GAP + SLIDER_H)
	local enemyH = ROW_H * ENEMY_ROWS
	local allyH  = max(ROW_H * 2, rightH - (HEADER_H + GAP) - GROUP_GAP - (HEADER_H + GAP + enemyH))
	local colH   = max(rightH, (HEADER_H + GAP + allyH) + GROUP_GAP + (HEADER_H + GAP + enemyH))
	local height = 44 + PAD + colH + FOOTER_GAP + BUTTON_H + PAD

	local top
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, height, "Share", mx, my)
	wy2 = top + S.px(44)

	if Spring.GetSpectatingState() then
		S.Text("Spectators cannot share.", wx1 + S.px(PAD), top - S.px(30), 14, t.textDim, "v")
		g = nil
		S.Flush()
		return
	end

	local pad = S.px(PAD)
	local colW = floor((wx2 - wx1 - pad * 3) * 0.5)
	local lx1, lx2 = wx1 + pad, wx1 + pad + colW
	local rx1, rx2 = wx2 - pad - colW, wx2 - pad
	local cursor
	local function Next(x1, x2, h, gapAfter)
		local r = { x1 = x1, x2 = x2, y2 = cursor, y1 = cursor - S.px(h) }
		cursor = r.y1 - S.px(gapAfter or GAP)
		return r
	end

	g = { sliders = {} }

	-- left: who
	cursor = top - pad
	local allyHdr  = Next(lx1, lx2, HEADER_H)
	g.ally         = Next(lx1, lx2, allyH, GROUP_GAP)
	local enemyHdr = Next(lx1, lx2, HEADER_H)
	g.enemy        = Next(lx1, lx2, enemyH)
	Header(allyHdr, "Allies  (click to select)", t.good)
	PlayerList(g.ally, allies, scroll.ally, mx, my)
	if #allies == 0 then
		S.Text("(no allies)", g.ally.x1 + S.px(10), g.ally.y2 - S.px(ROW_H) * 0.5, 13, t.textDim, "v")
	end
	Header(enemyHdr, "Enemies  (sharing to enemies is unusual!)", ENEMY_COLOR)
	PlayerList(g.enemy, enemies, scroll.enemy, mx, my)

	-- right: what
	cursor = top - pad
	local unitHdr = Next(rx1, rx2, HEADER_H)
	g.unit        = Next(rx1, rx2, UNIT_LINE_H * UNIT_LINES)
	g.check       = Next(rx1, rx2, CHECK_H, GROUP_GAP)
	Header(unitHdr, "Selected units")
	S.Rect(g.unit.x1, g.unit.y1, g.unit.x2, g.unit.y2, t.track, S.px(4))
	if #units == 0 then
		S.Text("(no units selected)", g.unit.x1 + S.px(10), (g.unit.y1 + g.unit.y2) * 0.5, 13, t.textDim, "v")
	else
		local lh = S.px(UNIT_LINE_H)
		local rows = ListRows(g.unit, lh, #units)
		local ux2 = g.unit.x2 - S.px(BAR_W) - S.px(8)
		for i = 1, rows do
			local u = units[scroll.unit + i]
			if not u then break end
			local mid = g.unit.y2 - (i - 0.5) * lh
			S.Text(S.Fit(u.name, 13, ux2 - g.unit.x1 - S.px(60)), g.unit.x1 + S.px(10), mid, 13, t.text, "v")
			if u.count > 1 then S.Text("x" .. u.count, ux2, mid, 13, t.good, "rv") end
		end
		Scrollbar(g.unit, lh, #units, scroll.unit, mx, my)
	end

	-- checkbox
	do
		local r = g.check
		local cs = S.px(16)
		local mid = (r.y1 + r.y2) * 0.5
		local over = S.Inside(mx, my, r.x1, r.y1, r.x2, r.y2)
		S.Button(r.x1, mid - cs * 0.5, r.x1 + cs, mid + cs * 0.5, over and "hover" or nil)
		if shareUnits then
			local m = S.px(4)
			S.Rect(r.x1 + m, mid - cs * 0.5 + m, r.x1 + cs - m, mid + cs * 0.5 - m, t.good, S.px(2))
		end
		S.Text("Share selected units", r.x1 + cs + S.px(8), mid, 13, t.text, "v")
	end

	-- one slider per resource: how much to send, out of what storage can hold
	for i = 1, #resources do
		local res = resources[i]
		local hdr = Next(rx1, rx2, HEADER_H)
		local box = Next(rx1, rx2, SLIDER_H, GROUP_GAP)
		Header(hdr, res.label .. "  to send", res.color)
		S.Rect(box.x1, box.y1, box.x2, box.y2, t.track, S.px(4))
		local storage = Storage(res.key)
		local amt = min(amount[res.key] or 0, storage)
		amount[res.key] = amt
		local tx1, ty1, tx2, ty2 = SliderTrack(box)
		local frac = (storage > 0) and (amt / storage) or 0
		S.Bar(tx1, ty1, tx2, ty2, frac, res.color)
		local kx = tx1 + (tx2 - tx1) * frac
		local hw = S.px(4)
		local active = drag and drag.slider == res.key
		S.Rect(kx - hw, ty1 - S.px(4), kx + hw, ty2 + S.px(4), active and t.warn or t.text, S.px(2))
		S.Text(S.Number(amt) .. " / " .. S.Number(storage), (tx1 + tx2) * 0.5, box.y1 + S.px(12), 12, t.textDim, "cv")
		g.sliders[#g.sliders + 1] = { key = res.key, box = box, x1 = tx1, x2 = tx2, y1 = ty1, y2 = ty2, max = storage }
	end

	-- footer: Cancel under the left column, Apply under the right
	local by2 = top - pad - S.px(colH) - S.px(FOOTER_GAP)
	local by1 = by2 - S.px(BUTTON_H)
	if notice ~= "" then
		S.Text(S.Fit(notice, 13, wx2 - wx1 - pad * 2), wx1 + pad, by2 + S.px(FOOTER_GAP) * 0.5, 13, t.textDim, "v")
	end
	g.cancel = { x1 = lx1, y1 = by1, x2 = lx2, y2 = by2 }
	g.apply  = { x1 = rx1, y1 = by1, x2 = rx2, y2 = by2 }
	local function Footer(r, label, color)
		local over = S.Inside(mx, my, r.x1, r.y1, r.x2, r.y2)
		S.Button(r.x1, r.y1, r.x2, r.y2, over and "hover" or nil)
		S.Rect(r.x1 + S.px(2), r.y2 - max(2, S.px(3)), r.x2 - S.px(2), r.y2, color, 0)
		S.Text(label, (r.x1 + r.x2) * 0.5, (r.y1 + r.y2) * 0.5 - S.px(1), 14, t.text, "cv")
	end
	Footer(g.cancel, "Cancel", ENEMY_COLOR)
	Footer(g.apply, "Apply", t.chartA)

	S.Flush()
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local function Apply()
	if not target then
		notice = "Pick a player first."
		return
	end
	local resources = S.game.resources or {}
	local done = {}
	for i = 1, #resources do
		local res = resources[i]
		local amt = floor(amount[res.key] or 0)
		if amt > 0 then
			Spring.ShareResources(target, res.key, amt)
			done[#done + 1] = S.Number(amt) .. " " .. res.label:lower()
			amount[res.key] = 0
		end
	end
	if shareUnits then
		local count = Spring.GetSelectedUnitsCount() or 0
		if count > 0 then
			Spring.ShareResources(target, "units")
			done[#done + 1] = count .. " unit" .. (count == 1 and "" or "s")
		end
	end
	if #done == 0 then
		notice = "Nothing to send: move a slider or tick the units box."
	else
		notice = "Sent " .. table.concat(done, ", ") .. " to " .. TargetName() .. "."
	end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local function InWindow(mx, my)
	return open and wx1 and S.Inside(mx, my, wx1, wy1, wx2, wy2)
end

local function In(r, mx, my)
	return r and S.Inside(mx, my, r.x1, r.y1, r.x2, r.y2)
end

local function SliderAmount(s, mx)
	return floor(min(1, max(0, (mx - s.x1) / (s.x2 - s.x1))) * s.max + 0.5)
end

-- name -> list box, row height in screen pixels, number of entries
local function ListInfo(name)
	if name == "ally" then return g.ally, S.px(ROW_H), #allies end
	if name == "enemy" then return g.enemy, S.px(ROW_H), #enemies end
	return g.unit, S.px(UNIT_LINE_H), #units
end

local function ScrollTo(name, my, grab)
	local r, rowH, count = ListInfo(name)
	local rows, maxFirst = ListRows(r, rowH, count)
	if maxFirst == 0 then return end
	local trackH = r.y2 - r.y1
	local thumbH = max(S.px(16), trackH * rows / count)
	local frac = (r.y2 - (my + grab)) / max(1, trackH - thumbH)
	scroll[name] = floor(min(1, max(0, frac)) * maxFirst + 0.5)
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
	if not g then return true end

	for i = 1, #g.sliders do
		local s = g.sliders[i]
		local slop = S.px(8)
		if S.Inside(mx, my, s.x1 - slop, s.y1 - slop, s.x2 + slop, s.y2 + slop) then
			drag = { slider = s.key }
			amount[s.key] = SliderAmount(s, mx)
			return true
		end
	end

	-- scrollbars, then rows
	for _, name in ipairs({ "ally", "enemy", "unit" }) do
		local r, rowH, count = ListInfo(name)
		if In(r, mx, my) then
			local rows, maxFirst = ListRows(r, rowH, count)
			if maxFirst > 0 and mx >= r.x2 - S.px(BAR_W) - 2 then
				local trackH = r.y2 - r.y1
				local thumbH = max(S.px(16), trackH * rows / count)
				local ty2 = r.y2 - (trackH - thumbH) * (scroll[name] / maxFirst)
				local grab = (my <= ty2 and my >= ty2 - thumbH) and (ty2 - my) or thumbH * 0.5
				drag = { list = name, grab = grab }
				ScrollTo(name, my, grab)
			elseif name ~= "unit" then
				local list = (name == "ally") and allies or enemies
				local e = list[scroll[name] + floor((r.y2 - my) / rowH) + 1]
				if e then
					target = (target ~= e.teamID) and e.teamID or nil
					notice = ""
				end
			end
			return true
		end
	end

	if In(g.check, mx, my) then
		shareUnits = not shareUnits
	elseif In(g.apply, mx, my) then
		Apply()
	elseif In(g.cancel, mx, my) then
		Close()
	end
	return true
end

function widget:MouseMove(mx, my)
	if not drag or not g then return false end
	if drag.slider then
		for i = 1, #g.sliders do
			local s = g.sliders[i]
			if s.key == drag.slider then amount[s.key] = SliderAmount(s, mx) end
		end
	else
		ScrollTo(drag.list, my, drag.grab)
	end
	return true
end

function widget:MouseRelease()
	drag = nil
	return true
end

function widget:MouseWheel(up)
	if not open or not g or WG.Slate ~= S then return false end
	local mx, my = Spring.GetMouseState()
	if not InWindow(mx, my) then return false end
	for _, name in ipairs({ "ally", "enemy", "unit" }) do
		local r, rowH, count = ListInfo(name)
		if In(r, mx, my) then
			local _, maxFirst = ListRows(r, rowH, count)
			scroll[name] = min(maxFirst, max(0, scroll[name] + (up and -1 or 1)))
		end
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
