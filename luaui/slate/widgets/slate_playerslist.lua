-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Players List",
		desc    = "Every player by team: stored resources, CPU and ping, frame rate, disconnects, alliances, and a spectator list. Click an ally to share; as a spectator, click a player to follow their camera.",
		author  = "Scary le Poo",
		date    = "2026-10-10",
		license = "GNU GPL, v2 or later",
		layer   = 4,
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- A row per player (so several people sharing one team all show), grouped by
-- alliance with your own first. From the right of each row:
--
--   frame rate   - only for players whose Slate Broadcast is sending it
--   P, C         - ping and CPU use, green to red
--   bars         - the team's stored resources, for allies or when spectating
--
-- and from the left: an alliance button where the game allows alliances to
-- change, the team colour, the name, and "dc" / "rejoining" / "lagging".
--
-- Spectators are listed under a header that folds away.
--
-- Following a camera, frame rates and system details come from Slate
-- Broadcast (WG.SlateBroadcast); without it those parts are simply empty.
-- WG['advplayerlist_api'] is published for widgets written against the old
-- AdvPlayersList (Player TV and the like).
--------------------------------------------------------------------------------

local ID = "players"
local WIDTH    = 330                -- design pixels
local PAD_X, PAD_Y = 10, 8
local ROW_H    = 22
local MAX_H    = 560                -- rows shrink rather than grow past this
local BAR_W    = 44
local CELL_W   = 15
local FPS_W    = 30
local ALLY_W   = 18

-- a rejoining client's ping is how far behind it is while it catches up
local LAG_PING       = 2.0          -- seconds
local REJOIN_GRACE   = 120          -- seconds after reconnecting that lag is called "rejoining"
local CAMERA_TIME    = 0.6          -- seconds to glide to a followed camera

local LEVEL_COLORS = {
	{ 0.11, 0.82, 0.11, 1 }, { 0.40, 0.75, 0.20, 1 }, { 0.72, 0.72, 0.20, 1 },
	{ 0.82, 0.27, 0.18, 1 }, { 1.00, 0.15, 0.30, 1 },
}
local ALLY_MUTUAL  = { 0.25, 0.85, 0.35, 1 }   -- allied both ways
local ALLY_OFFERED = { 1.00, 0.60, 0.15, 1 }   -- we offered, they have not answered
local ALLY_INVITED = { 0.30, 0.66, 0.96, 1 }   -- they offered, click to accept
local ALLY_NONE    = { 0.90, 0.25, 0.22, 1 }
local ENEMY_TINT   = { 0.75, 0.12, 0.10, 0.10 }

local spGetTeamInfo      = Spring.GetTeamInfo
local spGetPlayerInfo    = Spring.GetPlayerInfo
local spGetTeamResources = Spring.GetTeamResources
local spAreTeamsAllied   = Spring.AreTeamsAllied
local spSendCommands     = Spring.SendCommands
local floor = math.floor
local min, max = math.min, math.max

local S
local x1, y1, x2, y2
local rows = {}
local rowH = ROW_H
local timer = 10
local rowsVersion = 0
local cache

local specsOpen = false
local specCount = 0
local canAlly = false               -- alliances can change and we are playing
local wasConnected, reconnectedAt = {}, {}
local seconds = 0

-- following a camera (spectators)
local lockPlayerID
local lockApplied = -1              -- time stamp of the camera state last applied
local myCamera                      -- our own camera, to return to
local hideEnemies, lockLos = true, true
local fullViewToggles = 0           -- "specfullview" toggles still to send
local losWanted, losUntil = nil, 0

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function CpuLevel(c)
	if c < 0.15 then return 1 elseif c < 0.30 then return 2
	elseif c < 0.45 then return 3 elseif c < 0.65 then return 4 else return 5 end
end

local function PingLevel(p)
	if p < 0.15 then return 1 elseif p < 0.30 then return 2
	elseif p < 0.70 then return 3 elseif p < 1.50 then return 4 else return 5 end
end

-- AreTeamsAllied(A, B) reports whether B has allied A, so:
local function WeAllied(teamID)   return spAreTeamsAllied(teamID, Spring.GetMyTeamID()) end
local function TheyAllied(teamID) return spAreTeamsAllied(Spring.GetMyTeamID(), teamID) end

local function AllyState(teamID)
	local we, they = WeAllied(teamID), TheyAllied(teamID)
	if we and they then return ALLY_MUTUAL, "Allied. Click to break the alliance." end
	if we then return ALLY_OFFERED, "You offered an alliance. Click to withdraw it." end
	if they then return ALLY_INVITED, "They offered an alliance. Click to accept." end
	return ALLY_NONE, "Not allied. Click to offer an alliance."
end

local function AIName(teamID)
	local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
	return (aiName and aiName ~= "" and aiName ~= "UNKNOWN") and aiName or shortName or "AI"
end

local function StatusTag(row)
	if row.kind ~= "player" then return nil end
	if not row.connected then return "dc", S.theme.bad end
	if (row.ping or 0) >= LAG_PING then
		local at = reconnectedAt[row.playerID]
		if at and seconds - at < REJOIN_GRACE then return "rejoining", S.theme.warn end
		return "lagging", S.theme.warn
	end
	return nil
end

--------------------------------------------------------------------------------
-- Following a camera
--------------------------------------------------------------------------------

local function Broadcast() return WG.SlateBroadcast end

local function LockCamera(playerID)
	local _, fullView = Spring.GetSpectatingState()
	if playerID and playerID ~= Spring.GetMyPlayerID() and playerID ~= lockPlayerID then
		local _, _, isSpec, teamID = spGetPlayerInfo(playerID, false)
		if hideEnemies and not isSpec then
			-- see what they see: their team, their line of sight
			spSendCommands("specteam " .. teamID)
			spSendCommands("specfullview")
			fullViewToggles = fullView and 2 or 1
			if lockLos and Spring.GetMapDrawMode() ~= "los" then
				losWanted, losUntil = "los", seconds + 1
			end
		end
		lockPlayerID = playerID
		lockApplied = -1
		myCamera = myCamera or Spring.GetCameraState()
	else
		if myCamera then
			Spring.SetCameraState(myCamera, CAMERA_TIME)
			myCamera = nil
		end
		if lockPlayerID and hideEnemies then
			if not fullView then spSendCommands("specfullview") end
			if lockLos and Spring.GetMapDrawMode() == "los" then
				losWanted, losUntil = "normal", seconds + 1
			end
		end
		lockPlayerID = nil
	end
	rowsVersion = rowsVersion + 1
end

local function UpdateLock()
	if fullViewToggles > 0 then
		spSendCommands("specfullview")
		fullViewToggles = fullViewToggles - 1
	end
	if losWanted and seconds < losUntil then
		local mode = Spring.GetMapDrawMode()
		if (losWanted == "los") ~= (mode == "los") then spSendCommands("togglelos") end
	else
		losWanted = nil
	end
	if not lockPlayerID then return end

	local _, active = spGetPlayerInfo(lockPlayerID, false)
	if not Spring.GetSpectatingState() or not active then
		LockCamera()
		return
	end
	local b = Broadcast()
	local cam = b and b.camera[lockPlayerID]
	if cam and cam.time ~= lockApplied then
		lockApplied = cam.time
		Spring.SetCameraState(cam.state, CAMERA_TIME)
	end
end

local function PublishApi()
	WG['advplayerlist_api'] = {
		-- { top, left, bottom, right, scale }: consumers stack themselves above
		GetPosition        = function() return { y2 or 0, x1 or 0, y1 or 0, x2 or 0, S.scale } end,
		GetLockPlayerID    = function() return lockPlayerID end,
		SetLockPlayerID    = function(playerID) LockCamera(playerID) end,
		GetLockHideEnemies = function() return hideEnemies end,
		SetLockHideEnemies = function(v) hideEnemies = v and true or false end,
		GetLockLos         = function() return lockLos end,
		SetLockLos         = function(v) lockLos = v and true or false end,
	}
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local function Layout()
	local n = max(1, #rows)
	rowH = min(ROW_H, (MAX_H - PAD_Y * 2) / n)
	x1, y1, x2, y2 = S.Box(ID, "r", "b", S.theme.margin, S.theme.margin, WIDTH, n * rowH + PAD_Y * 2)
end

local function Rebuild()
	local gaia = Spring.GetGaiaTeamID()
	local mySpec = Spring.GetSpectatingState()
	local myAlly = Spring.GetMyAllyTeamID()
	local fixed = true
	if Spring.FixedAllies then fixed = Spring.FixedAllies() and true or false end
	canAlly = (not fixed) and not mySpec

	-- people by team, and spectators
	local byTeam, specs = {}, {}
	local players = Spring.GetPlayerList() or {}
	for i = 1, #players do
		local pid = players[i]
		local name, active, isSpec, teamID, _, ping, cpu = spGetPlayerInfo(pid, false)
		if wasConnected[pid] == false and active then reconnectedAt[pid] = seconds end
		wasConnected[pid] = active or false
		if isSpec then
			if active then specs[#specs + 1] = { kind = "spec", playerID = pid, name = name or ("Player " .. pid) } end
		elseif teamID then
			byTeam[teamID] = byTeam[teamID] or {}
			table.insert(byTeam[teamID], {
				playerID = pid, name = name or ("Player " .. pid),
				ping = ping or 0, cpu = cpu or 0, connected = active or false,
			})
		end
	end

	-- alliances, own first
	local order, seen = {}, {}
	local function Add(a) if a and not seen[a] then seen[a] = true ; order[#order + 1] = a end end
	if not mySpec then Add(myAlly) end
	local allies = Spring.GetAllyTeamList() or {}
	for i = 1, #allies do Add(allies[i]) end

	local groups = {}
	for i = 1, #order do
		local allyTeam = order[i]
		local enemy = (not mySpec) and allyTeam ~= myAlly
		local group = {}
		local teams = Spring.GetTeamList(allyTeam) or {}
		for j = 1, #teams do
			local teamID = teams[j]
			if teamID ~= gaia then
				local _, _, isDead, isAI = spGetTeamInfo(teamID, false)
				local r, g, b = Spring.GetTeamColor(teamID)
				local color = { r or 1, g or 1, b or 1, 1 }
				local people = byTeam[teamID]
				local function Row(extra)
					extra.teamID, extra.allyTeam, extra.color = teamID, allyTeam, color
					extra.dead, extra.enemy, extra.first = isDead, enemy, (extra.first ~= false)
					group[#group + 1] = extra
				end
				if people and #people > 0 then
					for k = 1, #people do
						local p = people[k]
						Row({ kind = "player", playerID = p.playerID, name = p.name, ping = p.ping,
							cpu = p.cpu, connected = p.connected, first = (k == 1) })
					end
				elseif isAI then
					Row({ kind = "ai", name = AIName(teamID) })
				else
					Row({ kind = "empty", name = "(nobody)" })
				end
			end
		end
		if #group > 0 then groups[#groups + 1] = { rows = group, enemy = enemy } end
	end

	local list = {}
	for i = 1, #groups do
		if #groups > 1 then list[#list + 1] = { kind = "header", label = "Team " .. i, enemy = groups[i].enemy } end
		for j = 1, #groups[i].rows do list[#list + 1] = groups[i].rows[j] end
	end
	specCount = #specs
	if specCount > 0 then
		list[#list + 1] = { kind = "spechdr" }
		if specsOpen then
			for i = 1, #specs do list[#list + 1] = specs[i] end
		end
	end

	local changed = (#list ~= #rows)
	rows = list
	rowsVersion = rowsVersion + 1
	if changed or not x1 then Layout() end
end

--------------------------------------------------------------------------------
-- Geometry shared by drawing, hints and clicks
--------------------------------------------------------------------------------

local function Columns()
	local padX = S.px(PAD_X)
	local c = {}
	c.left     = x1 + padX
	c.right    = x2 - padX
	c.fpsX1    = c.right - S.px(FPS_W)
	c.pingX2   = c.fpsX1 - S.px(4)
	c.pingX1   = c.pingX2 - S.px(CELL_W)
	c.cpuX2    = c.pingX1 - S.px(2)
	c.cpuX1    = c.cpuX2 - S.px(CELL_W)
	c.barX2    = c.cpuX1 - S.px(8)
	c.barX1    = c.barX2 - S.px(BAR_W)
	c.allyX1   = c.left
	c.swatchX1 = c.left + (canAlly and S.px(ALLY_W) or 0)
	c.nameX1   = c.swatchX1 + S.px(12) + S.px(7)
	c.nameX2   = c.barX1 - S.px(8)
	return c
end

local function RowAt(my)
	if not x1 then return nil end
	local i = floor((y2 - S.px(PAD_Y) - my) / S.px(rowH)) + 1
	return rows[i], i
end

local function HasAllyButton(row)
	return canAlly and row and row.first and row.teamID and row.kind ~= "empty"
		and row.teamID ~= Spring.GetMyTeamID() and not row.dead
end

local function CanShareWith(row)
	if not row or not row.teamID or row.dead or row.kind == "empty" or Spring.GetSpectatingState() then return false end
	local myTeam = Spring.GetMyTeamID()
	return row.teamID ~= myTeam and spAreTeamsAllied(row.teamID, myTeam) and spAreTeamsAllied(myTeam, row.teamID)
end

local function CanFollow(row)
	return row and row.kind == "player" and row.connected and Spring.GetSpectatingState()
		and row.playerID ~= Spring.GetMyPlayerID()
end

-- What the mouse is on: "ally", "net", "row", or nil.
local function Zone(mx, my)
	if not x1 or #rows == 0 or not S.Inside(mx, my, x1, y1, x2, y2) then return nil end
	local row = RowAt(my)
	if not row then return nil end
	local c = Columns()
	if HasAllyButton(row) and mx >= c.allyX1 and mx < c.swatchX1 then return "ally", row end
	if row.kind == "player" and mx >= c.cpuX1 then return "net", row end
	return "row", row
end

--------------------------------------------------------------------------------
-- Hints, shown in the selection panel
--------------------------------------------------------------------------------

local function Tip(mx, my)
	local zone, row = Zone(mx, my)
	if not zone then
		if x1 and #rows > 0 and S.Inside(mx, my, x1, y1, x2, y2) then
			return "Players", "Bars show each team's stored resources, for your allies or for everyone when you are spectating. C and P are CPU use and ping."
		end
		return nil
	end
	if zone == "ally" then
		local _, text = AllyState(row.teamID)
		return row.name, text
	end
	if zone == "net" then
		local b = Broadcast()
		local fps = b and b.fps[row.playerID]
		local lines = { string.format("%sCPU %d%%   Ping %d ms", fps and ("FPS " .. fps .. "   ") or "",
			floor((row.cpu or 0) * 100 + 0.5), floor((row.ping or 0) * 1000 + 0.5)) }
		local system = b and b.system[row.playerID]
		if system then
			for i = 1, #system do lines[#lines + 1] = system[i] end
		end
		return row.name, table.concat(lines, "\n")
	end
	if row.kind == "spechdr" then
		return "Spectators", specsOpen and "Click to hide the list." or "Click to list them."
	end
	if CanFollow(row) then
		if row.playerID == lockPlayerID then return row.name, "Following this player's camera. Click to stop." end
		local b = Broadcast()
		if b and b.camera[row.playerID] then return row.name, "Click to follow this player's camera and see what they see." end
		return row.name, "Click to see what this player's team sees. Their camera can only be followed if they are running Slate."
	end
	if CanShareWith(row) then
		return row.name, "Click to give this ally resources or your selected units."
	end
	return "Players", "Bars show each team's stored resources, for your allies or for everyone when you are spectating. C and P are CPU use and ping."
end

--------------------------------------------------------------------------------

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	spSendCommands("info 0")
	S.Register(ID, "Players", Layout)
	S.OnChange(ID, Layout)
	S.SetTip(ID, Tip)
	PublishApi()
	Rebuild()
end

function widget:Shutdown()
	if lockPlayerID then LockCamera() end
	spSendCommands("info 1")
	WG['advplayerlist_api'] = nil
	if S then
		S.SetTip(ID, nil)
		S.Unregister(ID)
		S.OffChange(ID)
		S.Unblur(ID)
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then Layout() end
end

function widget:PlayerChanged() timer = 10 end
function widget:PlayerAdded() timer = 10 end
function widget:PlayerRemoved() timer = 10 end

function widget:Update(dt)
	seconds = seconds + dt
	if not S or WG.Slate ~= S then return end
	UpdateLock()
	timer = timer + dt
	if timer > 1 then
		timer = 0
		Rebuild()
	end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Cell(cx1, cx2, mid, level, letter, size)
	local h = S.px(7)
	local t = S.theme
	S.Rect(cx1, mid - h, cx2, mid + h, level and LEVEL_COLORS[level] or t.track, S.px(3))
	S.Text(letter, (cx1 + cx2) * 0.5, mid, size, level and { 0, 0, 0, 0.85 } or t.textDim, "cv")
end

local function DrawPanel()
	local t = S.theme
	local res = S.game.resources or {}
	local mx, my = Spring.GetMouseState()
	local hotZone, hotRow = Zone(mx, my)
	local b = Broadcast()
	S.Panel(x1, y1, x2, y2)
	S.Blur(ID, x1, y1, x2, y2)

	local c = Columns()
	local rh = S.px(rowH)
	local size = min(14, rowH * 0.62)
	local small = min(11, size)
	local mySpec = Spring.GetSpectatingState()
	local myTeam = Spring.GetMyTeamID()
	local y = y2 - S.px(PAD_Y)

	for i = 1, #rows do
		local row = rows[i]
		local mid = y - rh * 0.5
		local inset = S.px(4)

		if row.kind == "header" then
			S.Text(row.label:upper(), c.left, mid, small, t.textDim, "v")

		elseif row.kind == "spechdr" then
			if hotRow == row then S.Rect(x1 + inset, y - rh, x2 - inset, y, t.buttonHover, S.px(3)) end
			S.Text((specsOpen and "-" or "+") .. "  SPECTATORS (" .. specCount .. ")", c.left, mid, small, t.textDim, "v")

		elseif row.kind == "spec" then
			S.Text(S.Fit(row.name, small + 1, c.right - c.nameX1), c.nameX1, mid, small + 1, t.textDim, "v")

		else
			if row.enemy then S.Rect(x1 + inset, y - rh, x2 - inset, y, ENEMY_TINT, 0) end
			if row.playerID and row.playerID == lockPlayerID then
				S.Rect(x1 + inset, y - rh, x2 - inset, y, t.buttonActive, S.px(3))
			elseif hotRow == row and hotZone == "row" and (CanFollow(row) or CanShareWith(row)) then
				S.Rect(x1 + inset, y - rh, x2 - inset, y, t.buttonHover, S.px(3))
			end

			if HasAllyButton(row) then
				local color = AllyState(row.teamID)
				local r = S.px(5)
				local cx = c.allyX1 + S.px(6)
				if hotRow == row and hotZone == "ally" then
					S.Rect(cx - r - 2, mid - r - 2, cx + r + 2, mid + r + 2, t.buttonHover, r + 2)
				end
				S.Rect(cx - r, mid - r, cx + r, mid + r, color, r)
			end

			if row.first then
				local sw = S.px(12)
				S.Rect(c.swatchX1, mid - sw * 0.5, c.swatchX1 + sw, mid + sw * 0.5, row.color, S.px(2))
			end

			-- name, then a status tag if there is room
			local tag, tagColor = StatusTag(row)
			local gone = row.dead or row.kind == "empty" or tag == "dc"
			local nameW = c.nameX2 - c.nameX1
			local tagW = tag and (S.TextWidth(tag, small) + S.px(6)) or 0
			local name = S.Fit(row.name, size, nameW - tagW)
			S.Text(name, c.nameX1, mid, size, gone and t.textDim or t.text, "v")
			if tag then
				S.Text(tag, c.nameX1 + S.TextWidth(name, size) + S.px(6), mid, small, tagColor, "v")
			end

			-- the team's stored resources, stacked; only readable for allies
			-- (or when spectating)
			if row.first and row.kind ~= "empty" and not row.dead and (mySpec or spAreTeamsAllied(myTeam, row.teamID)) then
				local n = #res
				local gap = max(1, S.px(2))
				local bh = max(2, floor((S.px(12) - gap * (n - 1)) / max(1, n)))
				local by = mid + (bh * n + gap * (n - 1)) * 0.5
				for k = 1, n do
					local cur, storage = spGetTeamResources(row.teamID, res[k].key)
					if cur and storage and storage > 0 then
						S.Bar(c.barX1, by - bh, c.barX2, by, cur / storage, res[k].color)
					end
					by = by - bh - gap
				end
			end

			if row.kind == "player" then
				Cell(c.cpuX1, c.cpuX2, mid, row.connected and CpuLevel(row.cpu) or nil, "C", small - 1)
				Cell(c.pingX1, c.pingX2, mid, row.connected and PingLevel(row.ping) or nil, "P", small - 1)
				local fps = row.connected and b and b.fps[row.playerID]
				if fps then
					S.Text(tostring(min(fps, 999)), c.right, mid, small, t.textDim, "rv")
				end
			end
		end
		y = y - rh
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S or not x1 or #rows == 0 then return end
	if Spring.IsGUIHidden() then return end
	local mx, my = Spring.GetMouseState()
	local zone, row = Zone(mx, my)
	local _, index = RowAt(my)
	local key = table.concat({ S.version, rowsVersion, floor(Spring.GetGameFrame() / 10),
		zone or "", zone and index or 0, lockPlayerID or -1 }, ":")
	cache = S.Cached(cache, key, DrawPanel)
	S.Flush()
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

function widget:IsAbove(mx, my)
	return WG.Slate == S and #rows > 0 and x1 and S.Inside(mx, my, x1, y1, x2, y2) or false
end

function widget:GetTooltip()
	return ""
end

function widget:MousePress(mx, my, button)
	if WG.Slate ~= S or #rows == 0 or not x1 or not S.Inside(mx, my, x1, y1, x2, y2) then return false end
	if button ~= 1 then return true end
	local zone, row = Zone(mx, my)
	if not zone then return true end

	if row.kind == "spechdr" then
		specsOpen = not specsOpen
		Rebuild()
	elseif zone == "ally" then
		spSendCommands("ally " .. row.allyTeam .. " " .. (WeAllied(row.teamID) and 0 or 1))
		rowsVersion = rowsVersion + 1
	elseif CanFollow(row) then
		if row.playerID == lockPlayerID then LockCamera() else LockCamera(row.playerID) end
	elseif CanShareWith(row) then
		spSendCommands("slate share " .. row.teamID)
	end
	return true
end
