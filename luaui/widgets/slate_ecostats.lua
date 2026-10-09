-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Economy Comparison",
		desc    = "For spectators: every team's income side by side, with totals per alliance. Hidden while you are playing.",
		author  = "Scary le Poo",
		date    = "2026-10-09",
		license = "GNU GPL, v2 or later",
		layer   = 7,
		enabled = true,
	}
end

local ID = "ecostats"
local WIDTH    = 340                -- design pixels
local PAD_X, PAD_Y = 12, 10
local HEADER_H = 40                 -- alliance row: label, totals, comparison bars
local ROW_H    = 22
local TOP_OFFSET = 16 + 44 + 16     -- under the clock and menu bar
local MAX_H    = 620

local spGetTeamResources = Spring.GetTeamResources
local floor = math.floor
local min, max = math.min, math.max

local S
local x1, y1, x2, y2
local groups = {}                   -- { label, teams = { { teamID, name, color, dead, income = { [key] = n } } }, total = { [key] = n } }
local best = {}                     -- per resource key: highest alliance total and highest team income
local rowCount = 0
local rowH = ROW_H
local timer = 10
local active = false

--------------------------------------------------------------------------------

local function TeamName(teamID)
	local _, leader, _, isAI = Spring.GetTeamInfo(teamID, false)
	if isAI then
		local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
		return (aiName and aiName ~= "" and aiName ~= "UNKNOWN") and aiName or shortName or "AI"
	end
	return Spring.GetPlayerInfo(leader or -1, false) or ("Team " .. teamID)
end

local function Layout()
	local teams = max(1, rowCount)
	local fixed = PAD_Y * 2 + #groups * HEADER_H
	rowH = min(ROW_H, max(12, (MAX_H - fixed) / teams))
	x1, y1, x2, y2 = S.Box(ID, "r", "t", S.theme.margin, TOP_OFFSET, WIDTH, fixed + teams * rowH)
end

local function Rebuild()
	local spec = Spring.GetSpectatingState()
	active = spec and true or false
	if not active then
		S.Unblur(ID)
		return
	end

	local resources = S.game.resources or {}
	local gaia = Spring.GetGaiaTeamID()
	local list = {}
	local count = 0
	best = {}
	for k = 1, #resources do best[resources[k].key] = { alliance = 0, team = 0 } end

	local allies = Spring.GetAllyTeamList() or {}
	for i = 1, #allies do
		local group = { teams = {}, total = {} }
		local ids = Spring.GetTeamList(allies[i]) or {}
		for j = 1, #ids do
			local teamID = ids[j]
			if teamID ~= gaia then
				local _, _, isDead = Spring.GetTeamInfo(teamID, false)
				local r, g, b = Spring.GetTeamColor(teamID)
				local team = { teamID = teamID, name = TeamName(teamID), color = { r or 1, g or 1, b or 1, 1 }, dead = isDead, income = {} }
				for k = 1, #resources do
					local key = resources[k].key
					local _, _, _, income = spGetTeamResources(teamID, key)
					income = (not isDead and income) or 0
					team.income[key] = income
					group.total[key] = (group.total[key] or 0) + income
					if income > best[key].team then best[key].team = income end
				end
				group.teams[#group.teams + 1] = team
			end
		end
		if #group.teams > 0 then
			group.label = "Team " .. (#list + 1)
			for k = 1, #resources do
				local key = resources[k].key
				if (group.total[key] or 0) > best[key].alliance then best[key].alliance = group.total[key] end
			end
			list[#list + 1] = group
			count = count + #group.teams
		end
	end

	local changed = (count ~= rowCount) or (#list ~= #groups) or not x1
	groups, rowCount = list, count
	if changed then Layout() end
end

--------------------------------------------------------------------------------

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	S.Register(ID, "Economy comparison", Layout)
	S.OnChange(ID, Layout)
	S.SetTip(ID, function(mx, my)
		if active and x1 and S.Inside(mx, my, x1, y1, x2, y2) then
			return "Economy comparison", "Income per second for every team. The bars under each alliance compare its total with the strongest alliance; the bars beside each team compare it with the strongest team."
		end
	end)
	Rebuild()
end

function widget:Shutdown()
	if S then
		S.SetTip(ID, nil)
		S.Unregister(ID)
		S.OffChange(ID)
		S.Unblur(ID)
	end
end

function widget:ViewResize()
	if S and WG.Slate == S and x1 then Layout() end
end

function widget:Update(dt)
	timer = timer + dt
	if timer > 0.5 and S and WG.Slate == S then
		timer = 0
		Rebuild()
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S or not active or not x1 or #groups == 0 then return end
	if Spring.IsGUIHidden() then return end
	local t = S.theme
	local resources = S.game.resources or {}
	local nres = max(1, #resources)
	S.Panel(x1, y1, x2, y2)
	S.Blur(ID, x1, y1, x2, y2)

	local padX = S.px(PAD_X)
	local ix1, ix2 = x1 + padX, x2 - padX
	local hh, rh = S.px(HEADER_H), S.px(rowH)
	local nameW = S.px(118)
	local colW = ((ix2 - ix1) - nameW) / nres       -- one column per resource
	local size = min(13, rowH * 0.62)
	local y = y2 - S.px(PAD_Y)

	for g = 1, #groups do
		local group = groups[g]

		-- alliance: label, totals, and a bar per resource against the best alliance
		local labelY = y - S.px(12)
		S.Text(group.label:upper(), ix1, labelY, 11, t.accent, "v")
		for k = 1, #resources do
			local res = resources[k]
			local cx1 = ix1 + nameW + (k - 1) * colW
			local cx2 = cx1 + colW - S.px(8)
			local total = group.total[res.key] or 0
			S.Text("+" .. S.Short(total), cx2, labelY, 13, t.text, "rv")
			local bh = max(3, S.px(5))
			local by = y - S.px(30)
			local top = best[res.key].alliance
			S.Bar(cx1, by, cx2, by + bh, (top > 0) and (total / top) or 0, res.color)
		end
		y = y - hh

		for i = 1, #group.teams do
			local team = group.teams[i]
			local mid = y - rh * 0.5
			local sw = S.px(10)
			S.Rect(ix1, mid - sw * 0.5, ix1 + sw, mid + sw * 0.5, team.color, S.px(2))
			S.Text(S.Fit(team.name, size, nameW - sw - S.px(12)), ix1 + sw + S.px(7), mid, size, team.dead and t.textDim or t.text, "v")
			for k = 1, #resources do
				local res = resources[k]
				local cx1 = ix1 + nameW + (k - 1) * colW
				local cx2 = cx1 + colW - S.px(8)
				local income = team.income[res.key] or 0
				local textW = S.px(46)
				local bh = max(3, S.px(4))
				local top = best[res.key].team
				S.Bar(cx1, mid - bh * 0.5, cx2 - textW, mid + bh * 0.5, (top > 0) and (income / top) or 0, res.color)
				S.Text(S.Short(income), cx2, mid, size, team.dead and t.textDim or t.text, "rv")
			end
			y = y - rh
		end
	end
	S.Flush()
end

function widget:IsAbove(mx, my)
	return (WG.Slate == S and active and x1 and S.Inside(mx, my, x1, y1, x2, y2)) or false
end

function widget:GetTooltip()
	return ""
end

function widget:MousePress(mx, my)
	return (WG.Slate == S and active and x1 and S.Inside(mx, my, x1, y1, x2, y2)) or false
end
