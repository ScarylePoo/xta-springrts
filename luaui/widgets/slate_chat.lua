-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Chat",
		desc    = "Recent chat and game messages as plain outlined text, no panel. Replaces the engine console.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = 4,
		enabled = true,
	}
end

local ID = "chat"
local WIDTH, HEIGHT = 520, 170      -- design pixels
local TOP_OFFSET    = 96            -- below the resource bar
local LEFT_OFFSET   = 332           -- right of the minimap frame, until its real size is known
local LINE_H        = 20
local TEXT_SIZE     = 15
local MAX_LINES     = 8
local SHOW_SECONDS  = 14
local FADE_SECONDS  = 2

local floor = math.floor
local min, max = math.min, math.max

local S
local x1, y1, x2, y2
local lines = {}                    -- newest last: { text, born }
local clock = 0
local nameColors = {}
local nameTimer = 10

--------------------------------------------------------------------------------

local function Layout()
	-- start to the right of the minimap frame, which varies with the map
	local left = LEFT_OFFSET
	if S.minimap then left = S.minimap.x2 / S.scale + S.theme.gap end
	x1, y1, x2, y2 = S.Box(ID, "l", "t", left, TOP_OFFSET, WIDTH, HEIGHT)
	-- keep the engine's chat entry line just under the messages
	Spring.SendCommands(string.format("inputtextgeo %.3f %.3f 0.02 0.028",
		x1 / S.vsx, max(0.05, (y1 - S.px(34)) / S.vsy)))
end

local function ColorCode(c)
	local function b(v) return string.char(max(1, min(255, floor(v * 255 + 0.5)))) end
	return "\255" .. b(c[1]) .. b(c[2]) .. b(c[3])
end

local function RefreshNames()
	nameColors = {}
	local players = Spring.GetPlayerList() or {}
	for i = 1, #players do
		local name, _, spectator, teamID = Spring.GetPlayerInfo(players[i], false)
		if name and not spectator and teamID then
			local r, g, b = Spring.GetTeamColor(teamID)
			if r then nameColors[name] = ColorCode({ r, g, b }) end
		end
	end
end

-- Colour the speaker's name with their team colour: "<Name> text" (player)
-- or "[Name] text" (spectator).
local function Decorate(text)
	local name, rest = text:match("^<([^>]+)> (.*)$")
	if not name then name, rest = text:match("^%[([^%]]+)%] (.*)$") end
	if name and nameColors[name] then
		return nameColors[name] .. name .. "\255\236\238\240  " .. rest
	end
	return text
end

local function Push(text)
	-- wrap long messages onto extra lines
	local width = (x2 or 600) - (x1 or 0)
	local line = ""
	for word in text:gmatch("%S+") do
		local try = (line == "") and word or (line .. " " .. word)
		if line ~= "" and S.TextWidth(try, TEXT_SIZE) > width then
			lines[#lines + 1] = { text = line, born = clock }
			line = "    " .. word
		else
			line = try
		end
	end
	if line ~= "" then lines[#lines + 1] = { text = line, born = clock } end
	while #lines > MAX_LINES do table.remove(lines, 1) end
end

--------------------------------------------------------------------------------

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	Spring.SendCommands("console 0")
	S.Register(ID, "Chat", Layout)
	S.OnChange(ID, Layout)
	Layout()
	RefreshNames()
end

function widget:Shutdown()
	Spring.SendCommands("console 1")
	if S then
		S.Unregister(ID)
		S.OffChange(ID)
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then Layout() end
end

function widget:AddConsoleLine(text)
	if WG.Slate ~= S or not text or text == "" then return end
	for part in (text .. "\n"):gmatch("(.-)\r?\n") do
		if part ~= "" then Push(Decorate(part)) end
	end
end

function widget:Update(dt)
	clock = clock + dt
	nameTimer = nameTimer + dt
	if nameTimer > 3 and S and WG.Slate == S then
		nameTimer = 0
		RefreshNames()
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S or not x1 or #lines == 0 then return end
	local t = S.theme
	local lh = S.px(LINE_H)
	local y = y2 - lh
	for i = 1, #lines do
		local age = clock - lines[i].born
		if age < SHOW_SECONDS then
			local alpha = min(1, (SHOW_SECONDS - age) / FADE_SECONDS)
			S.Text(lines[i].text, x1, y, TEXT_SIZE, { t.text[1], t.text[2], t.text[3], alpha }, "o")
			y = y - lh
		end
	end
	S.Flush()
end
