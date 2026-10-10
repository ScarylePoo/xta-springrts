-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Chat",
		desc    = "Shows chat on screen with team-coloured names and a colour per channel, and keeps the full history for the Slate Chat Log. Engine console output stays out of the way. Replaces the engine console.",
		author  = "Scary le Poo",
		date    = "2026-10-09",
		license = "GNU GPL, v2 or later",
		layer   = 4,
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- HOW THIS WORKS (the same model as ChatterboxChat in Splinter Faction)
--
-- Every console line is parsed into an entry with a channel:
--
--   public, ally, spectator, whisper   what players typed
--   marker                             "<player> added point: ..."
--   event                              speed changes, pause and unpause
--   system                             everything else the engine prints
--
-- All entries go into one history (WG.SlateChat.GetLog), which the Slate Chat
-- Log window shows with Chat / Console / All tabs. Only chat - everything that
-- is not "system" - appears in the on-screen overlay, where it fades out.
--------------------------------------------------------------------------------

local ID = "chat"
local WIDTH, HEIGHT = 500, 190      -- design pixels
local TOP_OFFSET    = 96            -- below the resource bar
local LEFT_OFFSET   = 332           -- right of the minimap frame, until its real size is known
local LINE_H        = 22
local TEXT_SIZE     = 16
local MAX_LINES     = 8             -- wrapped lines on screen at once
local LINE_LIFETIME = 10            -- seconds before a line starts to fade
local FADE_TIME     = 6
local MAX_LOG       = 1000
local LOG_SLACK     = 64
local SPEED_DEBOUNCE = 0.6          -- collapse a burst of speed changes into one line

local floor = math.floor
local min, max = math.min, math.max

-- Seconds of real time since the widget loaded (os.clock counts CPU time,
-- which runs slow when the game is idle).
local startTimer = Spring.GetTimer()
local function Clock() return Spring.DiffTimers(Spring.GetTimer(), startTimer) end

local S
local x1, y1, x2, y2
local overlay = {}                  -- entries currently on screen, oldest first
local fullLog = {}                  -- every entry, capped at MAX_LOG
local players = {}                  -- lowercase name -> { name, color }
local playerTimer = 10
local pendingSpeed, pendingSpeedTime

--------------------------------------------------------------------------------
-- Players and colours
--------------------------------------------------------------------------------

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function RefreshPlayers()
	players = {}
	local list = Spring.GetPlayerList() or {}
	for i = 1, #list do
		local name, _, spectator, teamID = Spring.GetPlayerInfo(list[i], false)
		if name then
			local color
			if not spectator and teamID then
				local r, g, b = Spring.GetTeamColor(teamID)
				if r then
					-- lift very dark team colours so the name stays readable
					local lum = 0.3 * r + 0.59 * g + 0.11 * b
					if lum < 0.35 then
						local k = 0.35 - lum
						r, g, b = min(1, r + k), min(1, g + k), min(1, b + k)
					end
					color = { r, g, b, 1 }
				end
			end
			players[name:lower()] = { name = name, color = color }
		end
	end
end

local function NameColor(name)
	local p = players[Trim(name):lower()]
	return (p and p.color) or S.theme.chat.spectatorName
end

local function Code(c)
	local function b(v) return string.char(max(1, min(255, floor(v * 255 + 0.5)))) end
	return "\255" .. b(c[1]) .. b(c[2]) .. b(c[3])
end

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------

local function Parse(line)
	if not line or line == "" then return nil end
	local text = Trim(line)
	local c = S.theme.chat
	local player, body

	player, body = text:match("^<([^>]+)>%s*Spectators:%s*(.*)$")
	if player then return { channel = "spectator", player = player, body = body, color = c.spectator } end

	player, body = text:match("^<([^>]+)>%s*Allies:%s*(.*)$")
	if player then return { channel = "ally", player = player, body = body, color = c.ally } end

	player, body = text:match("^<([^>]+)>%s*Whispers:%s*(.*)$")
	if not player then player, body = text:match("^Whisper from ([^:]+):%s*(.*)$") end
	if not player then player, body = text:match("^To ([^:]+):%s*(.*)$") end
	if player then return { channel = "whisper", player = Trim(player), body = body, color = c.whisper } end

	-- Public chat is "<Name> message". Widgets and gadgets print lines of the
	-- same shape ("<DefenseRange> ..."), so the name has to be a player's.
	player, body = text:match("^<([^>]+)>%s*(.*)$")
	if player and not players[Trim(player):lower()] then RefreshPlayers() end
	if player and players[Trim(player):lower()] then
		return { channel = "public", player = player, body = body, color = c.public }
	end

	player, body = text:match("^(.+) added point:%s*(.*)$")
	if player then
		return { channel = "marker", player = player, color = c.ally,
			body = (body ~= "") and ("added point: " .. body) or "added a point", joined = true }
	end

	-- "Speed set to N [player]" - the trailing [player] is optional
	local n, who = text:match("^Speed set to%s+([%d%.]+)%s+%[([^%]]+)%]%s*$")
	if not n then n = text:match("^Speed set to%s+([%d%.]+)%s*$") end
	if n then
		if who and who ~= "" then
			return { channel = "event", kind = "speed", player = Trim(who), body = "set speed to " .. n .. "x", color = c.event, joined = true }
		end
		return { channel = "event", kind = "speed", body = "Speed set to " .. n .. "x", color = c.event }
	end

	-- check "unpaused" first so it is never read as "paused"
	who = text:match("^(.-)%s+unpaused the game%s*$")
	if who and who ~= "" then
		return { channel = "event", kind = "pause", player = Trim(who), body = "unpaused the game", color = c.event, joined = true }
	end
	who = text:match("^(.-)%s+paused the game%s*$")
	if who and who ~= "" then
		return { channel = "event", kind = "pause", player = Trim(who), body = "paused the game", color = c.event, joined = true }
	end

	-- Spectator chat arrives as "[Name] message". The engine also prints
	-- bracketed tags that are not chat ("[GiveUnits] ..."), so only accept the
	-- form when the name is a known player.
	player, body = text:match("^%[([^%]]+)%]%s*(.*)$")
	if player and players[Trim(player):lower()] then
		return { channel = "spectator", player = Trim(player), body = body, color = c.spectator }
	end

	return { channel = "system", body = line, color = c.system }
end

local function IsChat(entry)
	return entry ~= nil and entry.channel ~= "system"
end

--------------------------------------------------------------------------------
-- Wrapping and storage
--------------------------------------------------------------------------------

-- Lines for the overlay: the name (in its own colour) leads the first line and
-- the body wraps underneath, indented. Each line is a list of segments
-- { text, color, x } so every segment can be faded; the engine's inline colour
-- codes cannot be used here because they reset transparency to solid.
local function Wrap(entry, width)
	local lines = {}
	local segs, offset = {}, 0
	if entry.player then
		local lead = entry.player .. (entry.joined and " " or ":  ")
		segs[1] = { text = lead, color = NameColor(entry.player), x = 0 }
		offset = S.TextWidth(lead, TEXT_SIZE)
	end
	local indent = S.TextWidth("    ", TEXT_SIZE)
	local line, words = "", 0
	for word in (entry.body or ""):gmatch("%S+") do
		local try = (words > 0) and (line .. " " .. word) or word
		if words > 0 and offset + S.TextWidth(try, TEXT_SIZE) > width then
			segs[#segs + 1] = { text = line, color = entry.color, x = offset }
			lines[#lines + 1] = segs
			segs, offset = {}, indent
			line, words = word, 1
		else
			line, words = try, words + 1
		end
	end
	if words > 0 then segs[#segs + 1] = { text = line, color = entry.color, x = offset } end
	if #segs > 0 then lines[#lines + 1] = segs end
	return lines
end

local function Emit(entry)
	entry.gameTime = floor(Spring.GetGameSeconds() or 0)
	fullLog[#fullLog + 1] = entry
	local n = #fullLog
	if n >= MAX_LOG + LOG_SLACK then
		local drop = n - MAX_LOG
		for i = 1, n - drop do fullLog[i] = fullLog[i + drop] end
		for i = n - drop + 1, n do fullLog[i] = nil end
	end

	if not IsChat(entry) then return end
	entry.born = Clock()
	entry.lines = Wrap(entry, (x2 or 600) - (x1 or 0))
	overlay[#overlay + 1] = entry

	local sounds = S.game.chatSounds
	local sound = sounds and entry.player and sounds[entry.channel]
	if sound then Spring.PlaySoundFile(sound, 1.0, "ui") end
end

--------------------------------------------------------------------------------

local function Layout()
	-- start to the right of the minimap frame, which varies with the map
	local left = LEFT_OFFSET
	if S.minimap then
		-- only step aside while the minimap is actually in this corner
		local m = S.minimap
		local inCorner = m.x1 < S.px(LEFT_OFFSET) and m.y2 > S.vsy - S.px(TOP_OFFSET + 60)
		left = inCorner and (m.x2 / S.scale + S.theme.gap) or S.theme.margin
	end
	x1, y1, x2, y2 = S.Box(ID, "l", "t", left, TOP_OFFSET, WIDTH, HEIGHT)
	-- keep the engine's chat entry line just under the messages
	Spring.SendCommands(string.format("inputtextgeo %.3f %.3f 0.02 0.028",
		x1 / S.vsx, max(0.05, (y1 - S.px(34)) / S.vsy)))
	for i = 1, #overlay do
		overlay[i].lines = Wrap(overlay[i], x2 - x1)
	end
end

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	Spring.SendCommands("console 0")
	RefreshPlayers()
	S.Register(ID, "Chat", Layout)
	S.OnChange(ID, Layout)
	Layout()
	WG.SlateChat = {
		GetLog = function() return fullLog end,
		IsChat = IsChat,
		NameColor = NameColor,
	}
end

function widget:Shutdown()
	Spring.SendCommands("console 1")
	WG.SlateChat = nil
	if S then
		S.Unregister(ID)
		S.OffChange(ID)
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then Layout() end
end

function widget:PlayerChanged()
	if S and WG.Slate == S then RefreshPlayers() end
end

function widget:AddConsoleLine(text)
	if WG.Slate ~= S or not text or text == "" then return end
	for part in (text .. "\n"):gmatch("(.-)\r?\n") do
		local entry = Parse(part)
		if entry then
			if entry.kind == "speed" then
				-- dragging the speed slider prints dozens of these; keep the last
				pendingSpeed, pendingSpeedTime = entry, Clock()
			else
				Emit(entry)
			end
		end
	end
end

function widget:Update(dt)
	if WG.Slate ~= S then return end
	if pendingSpeed and (Clock() - pendingSpeedTime) >= SPEED_DEBOUNCE then
		local entry = pendingSpeed
		pendingSpeed = nil
		Emit(entry)
	end
	playerTimer = playerTimer + dt
	if playerTimer > 5 then
		playerTimer = 0
		RefreshPlayers()
	end
	-- drop entries that have fully faded
	local now = Clock()
	while overlay[1] and (now - overlay[1].born) > (LINE_LIFETIME + FADE_TIME) do
		table.remove(overlay, 1)
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S or not x1 or #overlay == 0 then return end
	if Spring.IsGUIHidden() then return end
	local now = Clock()
	local lh = S.px(LINE_H)

	-- newest entries win when there are more lines than fit
	local total, firstEntry = 0, #overlay
	for i = #overlay, 1, -1 do
		local n = #overlay[i].lines
		if total + n > MAX_LINES then break end
		total = total + n
		firstEntry = i
	end

	local y = y2 - lh
	for i = firstEntry, #overlay do
		local e = overlay[i]
		local age = now - e.born
		local alpha = (age <= LINE_LIFETIME) and 1 or max(0, 1 - (age - LINE_LIFETIME) / FADE_TIME)
		if alpha > 0 then
			for j = 1, #e.lines do
				local segs = e.lines[j]
				for k = 1, #segs do
					local c = segs[k].color
					S.Text(segs[k].text, x1 + segs[k].x, y, TEXT_SIZE, { c[1], c[2], c[3], alpha }, "o")
				end
				y = y - lh
			end
		end
	end
	S.Flush()
end
