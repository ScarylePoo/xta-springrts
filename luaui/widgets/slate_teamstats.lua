-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate End Graph",
		desc    = "The end-of-game statistics graph: one line per team for a chosen statistic. Opens when the game ends; during play, from the Menu or with /slate stats (you then see only what the engine lets you see).",
		author  = "Scary le Poo",
		date    = "2026-10-09",
		license = "GNU GPL, v2 or later",
		layer   = -13,
		enabled = true,
	}
end

local ID = "teamstats"
local WIDTH, HEIGHT = 1100, 660     -- design pixels
local SIDEBAR_W = 210
local BUTTON_H  = 30
local LEGEND_H  = 24

local floor = math.floor
local min, max = math.min, math.max

local S
local open = false
local closeRect
local wx1, wy1, wx2, wy2
local hits = {}
local stat = 2
local series = {}
local sampleTimes = {}
local timer = 10
local hiddenTeams = 0
local gameOverSeen = false
local hoverIndex

-- Fields of the engine's per-team statistics history, in button order.
local stats = {
	{ key = "metalUsed",      label = "Metal used" },
	{ key = "metalProduced",  label = "Metal produced" },
	{ key = "energyUsed",     label = "Energy used" },
	{ key = "energyProduced", label = "Energy produced" },
	{ key = "damageDealt",    label = "Damage dealt" },
	{ key = "damageReceived", label = "Damage received" },
	{ key = "unitsProduced",  label = "Units built" },
	{ key = "unitsKilled",    label = "Units killed" },
}

--------------------------------------------------------------------------------

local function Clock(seconds)
	seconds = floor(seconds or 0)
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60)
	end
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

local function TeamName(teamID)
	local _, leader, _, isAI = Spring.GetTeamInfo(teamID, false)
	if isAI then
		local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
		return (aiName and aiName ~= "" and aiName ~= "UNKNOWN") and aiName or shortName or "AI"
	end
	return Spring.GetPlayerInfo(leader or -1, false) or ("Team " .. teamID)
end

local function Rebuild()
	series, sampleTimes, hiddenTeams = {}, {}, 0
	local gaia = Spring.GetGaiaTeamID()
	local key = stats[stat].key
	local teams = Spring.GetTeamList() or {}
	for i = 1, #teams do
		local teamID = teams[i]
		if teamID ~= gaia then
			local count = Spring.GetTeamStatsHistory(teamID)
			local rows = count and count > 0 and Spring.GetTeamStatsHistory(teamID, 1, count)
			if rows and #rows > 0 then
				local points = {}
				for j = 1, #rows do
					points[j] = rows[j][key] or 0
					if #sampleTimes < j then sampleTimes[j] = rows[j].time or 0 end
				end
				local r, g, b = Spring.GetTeamColor(teamID)
				series[#series + 1] = { label = TeamName(teamID), color = { r or 1, g or 1, b or 1, 1 }, points = points }
			else
				-- the engine only reveals other teams' history to spectators
				-- and once the game is over
				hiddenTeams = hiddenTeams + 1
			end
		end
	end
	-- every series must be the same length for a shared x axis
	local n = 0
	for i = 1, #series do n = max(n, #series[i].points) end
	for i = 1, #series do
		local p = series[i].points
		local last = p[#p] or 0
		for j = #p + 1, n do p[j] = last end
	end
	-- legend order: best final value first
	table.sort(series, function(a, b)
		local av, bv = a.points[#a.points] or 0, b.points[#b.points] or 0
		if av ~= bv then return av > bv end
		return a.label < b.label
	end)
end

local function Close()
	open = false
	if S then S.Unblur(ID) end
end

--------------------------------------------------------------------------------

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	Spring.SendCommands("endgraph 0")   -- this replaces the engine's own end-of-game graph
end

function widget:Shutdown()
	Spring.SendCommands("endgraph 1")
	if S then S.Unblur(ID) end
end

function widget:TextCommand(command)
	if command == "slate stats" then
		if WG.Slate ~= S then return false end
		if open then Close() else open = true ; Rebuild() end
		return true
	end
	return false
end

local function GameOverNow()
	if gameOverSeen or WG.Slate ~= S then return end
	gameOverSeen = true
	open = true
	pcall(Rebuild)
end

function widget:GameOver()
	GameOverNow()
end

function widget:Update(dt)
	-- the GameOver call is not always delivered to widgets, so also poll
	if not gameOverSeen and Spring.IsGameOver and Spring.IsGameOver() then GameOverNow() end
	if not open then return end
	timer = timer + dt
	if timer > 2 then
		timer = 0
		Rebuild()
	end
end

--------------------------------------------------------------------------------

function widget:DrawScreen()
	if not open or WG.Slate ~= S then return end
	local t = S.theme
	local mx, my = Spring.GetMouseState()
	hits = {}
	local top
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, HEIGHT, gameOverSeen and "Game over" or "Team statistics", mx, my)
	wy2 = top + S.px(44)

	local pad = S.px(18)
	local x1, x2 = wx1 + pad, wx2 - pad
	local y = top - S.px(14)
	local side = S.px(SIDEBAR_W)

	-- sidebar: which statistic
	local bh, gap = S.px(BUTTON_H), S.px(5)
	for i = 1, #stats do
		local by2 = y - (i - 1) * (bh + gap)
		local over = S.Inside(mx, my, x1, by2 - bh, x1 + side, by2)
		S.Button(x1, by2 - bh, x1 + side, by2, (i == stat) and "active" or (over and "hover" or nil))
		S.Text(stats[i].label, x1 + S.px(12), by2 - bh * 0.5, 13, t.text, "v")
		hits[#hits + 1] = { x1, by2 - bh, x1 + side, by2, i }
	end
	local ly = y - #stats * (bh + gap) - S.px(12)

	-- sidebar: teams, best first, with the value under the cursor (or the latest)
	local footer = S.px(34)
	local lh = S.px(LEGEND_H)
	local room = max(0, floor((ly - (wy1 + footer)) / lh))
	local shown = min(#series, room)
	for i = 1, shown do
		local e = series[i]
		local mid = ly - (i - 0.5) * lh
		local sw = S.px(12)
		S.Rect(x1, mid - S.px(2), x1 + sw, mid + S.px(2), e.color, S.px(2))
		local v = e.points[hoverIndex or #e.points] or 0
		local value = S.Short(v)
		S.Text(value, x1 + side, mid, 13, t.text, "rv")
		S.Text(S.Fit(e.label, 13, side - sw - S.px(14) - S.TextWidth(value, 13)), x1 + sw + S.px(8), mid, 13, t.text, "v")
	end
	if #series > shown and room > 0 then
		S.Text("+" .. (#series - shown) .. " more (hover the chart)", x1, ly - (shown + 0.5) * lh, 12, t.textDim, "v")
	end

	hoverIndex = S.LineChart(x1 + side + S.px(18), wy1 + footer, x2, y, series,
		{ xLabel = function(i) return Clock(sampleTimes[i]) end, title = stats[stat].label, noLegend = true }, mx, my)

	if hiddenTeams > 0 then
		S.Text("Other teams appear once the game ends, or when you are spectating.",
			x1 + side + S.px(18), wy1 + footer * 0.5 + S.px(2), 13, t.textDim, "v")
	end
	S.Flush()
end

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
	for i = 1, #hits do
		local h = hits[i]
		if S.Inside(mx, my, h[1], h[2], h[3], h[4]) then
			stat = h[5]
			Rebuild()
			break
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
