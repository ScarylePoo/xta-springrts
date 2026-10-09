-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Team Statistics",
		desc    = "One line per team for a chosen statistic over the game. Opens when the game ends, from the Menu, or with /slate stats.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = -13,
		enabled = true,
	}
end

local ID = "teamstats"
local WIDTH, HEIGHT = 860, 600      -- design pixels
local TAB_H = 34
local floor = math.floor
local max = math.max

local S
local open = false
local closeRect
local wx1, wy1, wx2, wy2
local hits = {}
local stat = 1
local series = {}
local sampleTimes = {}
local timer = 10
local hiddenTeams = 0

-- Fields of the engine's per-team statistics history.
local stats = {
	{ label = "Metal produced",  key = "metalProduced" },
	{ label = "Energy produced", key = "energyProduced" },
	{ label = "Damage dealt",    key = "damageDealt" },
	{ label = "Units produced",  key = "unitsProduced" },
	{ label = "Units killed",    key = "unitsKilled" },
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
end

function widget:Shutdown()
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

function widget:GameOver()
	if WG.Slate == S then
		open = true
		Rebuild()
	end
end

function widget:Update(dt)
	if not open then return end
	timer = timer + dt
	if timer > 4 then
		timer = 0
		Rebuild()
	end
end

function widget:DrawScreen()
	if not open or WG.Slate ~= S then return end
	local t = S.theme
	local mx, my = Spring.GetMouseState()
	hits = {}
	local top
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, HEIGHT, "Team statistics", mx, my)
	wy2 = top + S.px(44)

	local pad = S.px(20)
	local x1, x2 = wx1 + pad, wx2 - pad
	local y = top - S.px(12)

	local th = S.px(TAB_H)
	local gap = S.px(6)
	local tw = ((x2 - x1) - gap * (#stats - 1)) / #stats
	for i = 1, #stats do
		local tx1 = floor(x1 + (i - 1) * (tw + gap))
		local tx2 = floor(tx1 + tw)
		local over = S.Inside(mx, my, tx1, y - th, tx2, y)
		S.Button(tx1, y - th, tx2, y, (i == stat) and "active" or (over and "hover" or nil))
		S.Text(S.Fit(stats[i].label, 13, tw - S.px(6)), (tx1 + tx2) * 0.5, y - th * 0.5, 13, t.text, "cv")
		hits[#hits + 1] = { tx1, y - th, tx2, y, i }
	end
	y = y - th - S.px(16)

	local footer = S.px(34)
	S.LineChart(x1, wy1 + footer, x2, y, series,
		{ xLabel = function(i) return Clock(sampleTimes[i]) end }, mx, my)

	if hiddenTeams > 0 then
		S.Text("Other teams appear here once the game ends, or when you are spectating.",
			x1, wy1 + footer * 0.5 + S.px(4), 13, t.textDim, "v")
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
