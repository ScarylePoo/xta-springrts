-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Players List",
		desc    = "Players grouped by team, with team colour, metal and energy levels (where visible) and ping.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = 3,
		enabled = true,
	}
end

local ID = "players"
local WIDTH    = 300                -- design pixels
local PAD_X, PAD_Y = 12, 10
local ROW_H    = 24
local MAX_H    = 520                -- rows shrink rather than grow past this
local BAR_W    = 44

local spGetTeamInfo      = Spring.GetTeamInfo
local spGetPlayerInfo    = Spring.GetPlayerInfo
local spGetTeamResources = Spring.GetTeamResources
local floor = math.floor
local min, max = math.min, math.max

local S
local x1, y1, x2, y2
local rows = {}                     -- { header = "Team 1" } or { teamID, name, color, dead, ping }
local rowH = ROW_H
local timer = 10

--------------------------------------------------------------------------------

local function Layout()
	local n = max(1, #rows)
	rowH = min(ROW_H, (MAX_H - PAD_Y * 2) / n)
	x1, y1, x2, y2 = S.Box(ID, "r", "b", S.theme.margin, S.theme.margin, WIDTH, n * rowH + PAD_Y * 2)
end

local function TeamRow(teamID)
	local _, leader, isDead, isAI = spGetTeamInfo(teamID, false)
	local name, ping, active
	if isAI then
		local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
		name = (aiName and aiName ~= "" and aiName ~= "UNKNOWN") and aiName or shortName or "AI"
		active = true
	else
		local pname, pactive, _, _, _, pingTime = spGetPlayerInfo(leader or -1, false)
		name = pname or "(nobody)"
		active = pactive
		if pingTime then ping = floor(pingTime * 1000 + 0.5) .. " ms" end
	end
	local r, g, b = Spring.GetTeamColor(teamID)
	return {
		teamID = teamID, name = name, ping = ping,
		color = { r or 1, g or 1, b or 1, 1 },
		dead = isDead or not active,
	}
end

local function Rebuild()
	local gaia = Spring.GetGaiaTeamID()
	local list = {}
	local allies = Spring.GetAllyTeamList() or {}
	local groups = {}
	for i = 1, #allies do
		local teams = Spring.GetTeamList(allies[i]) or {}
		local group = {}
		for j = 1, #teams do
			if teams[j] ~= gaia then group[#group + 1] = TeamRow(teams[j]) end
		end
		if #group > 0 then groups[#groups + 1] = group end
	end
	for i = 1, #groups do
		if #groups > 1 then list[#list + 1] = { header = "Team " .. i } end
		for j = 1, #groups[i] do list[#list + 1] = groups[i][j] end
	end
	local changed = (#list ~= #rows)
	rows = list
	if changed or not x1 then Layout() end
end

--------------------------------------------------------------------------------

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	Spring.SendCommands("info 0")
	S.Register(ID, "Players", Layout)
	S.OnChange(ID, Layout)
	S.SetTip(ID, Tip)
	Rebuild()
end

function widget:Shutdown()
	Spring.SendCommands("info 1")
	if S then
		S.Unregister(ID)
		S.OffChange(ID)
		S.Unblur(ID)
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then Layout() end
end

function widget:Update(dt)
	timer = timer + dt
	if timer > 1 and S and WG.Slate == S then
		timer = 0
		Rebuild()
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S or not x1 or #rows == 0 then return end
	local t = S.theme
	local res = S.game.resources or {}
	S.Panel(x1, y1, x2, y2)
	S.Blur(ID, x1, y1, x2, y2)

	local padX = S.px(PAD_X)
	local rh = S.px(rowH)
	local size = min(14, rowH * 0.62)
	local barW, barH = S.px(BAR_W), max(3, S.px(5))
	local y = y2 - S.px(PAD_Y)

	for i = 1, #rows do
		local row = rows[i]
		local mid = y - rh * 0.5
		if row.header then
			S.Text(row.header:upper(), x1 + padX, mid, min(11, size), t.textDim, "v")
		else
			local sw = S.px(12)
			S.Rect(x1 + padX, mid - sw * 0.5, x1 + padX + sw, mid + sw * 0.5, row.color, S.px(2))

			local right = x2 - padX
			S.Text(row.ping or "", right, mid, min(12, size), t.textDim, "rv")
			right = right - S.px(46)

			-- resource levels are only readable for allies (or when spectating)
			for k = #res, 1, -1 do
				local cur, storage = spGetTeamResources(row.teamID, res[k].key)
				if cur and storage and storage > 0 and not row.dead then
					S.Bar(right - barW, mid - barH * 0.5, right, mid + barH * 0.5, cur / storage, res[k].color)
				end
				right = right - barW - S.px(8)
			end

			local nameX = x1 + padX + sw + S.px(8)
			S.Text(S.Fit(row.name, size, right - nameX), nameX, mid, size, row.dead and t.textDim or t.text, "v")
		end
		y = y - rh
	end
	S.Flush()
end

function widget:IsAbove(mx, my)
	return WG.Slate == S and #rows > 0 and S.Inside(mx, my, x1, y1, x2, y2) or false
end

local function RowAt(my)
	local i = floor((y2 - S.px(PAD_Y) - my) / S.px(rowH)) + 1
	return rows[i]
end

local function CanShareWith(row)
	if not row or not row.teamID or row.dead or Spring.GetSpectatingState() then return false end
	local myTeam = Spring.GetMyTeamID()
	return row.teamID ~= myTeam and Spring.AreTeamsAllied(row.teamID, myTeam)
end

local function Tip(mx, my)
	if not x1 or #rows == 0 or not S.Inside(mx, my, x1, y1, x2, y2) then return nil end
	local row = RowAt(my)
	if CanShareWith(row) then
		return row.name, "Click to give this ally resources or your selected units."
	end
	return "Players", "The bars show stored metal and energy. They are only visible for your allies, or for everyone when you are spectating."
end

function widget:GetTooltip(mx, my)
	if CanShareWith(RowAt(my)) then return "Click to share resources or units with this ally" end
	return "Bars show each ally's stored metal and energy"
end

function widget:MousePress(mx, my, button)
	if WG.Slate ~= S or #rows == 0 or not S.Inside(mx, my, x1, y1, x2, y2) then return false end
	local row = RowAt(my)
	if button == 1 and CanShareWith(row) then
		Spring.SendCommands("slate share " .. row.teamID)
	end
	return true
end
