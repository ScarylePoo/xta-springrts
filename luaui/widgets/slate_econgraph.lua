-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Economy Graph",
		desc    = "Your income and demand over the game, one chart per resource. Open it from the Menu or with /slate economy.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = -12,
		enabled = true,
	}
end

local ID = "econgraph"
local WIDTH, HEIGHT = 780, 600      -- design pixels
local MAX_SAMPLES   = 600           -- when full, every other sample is dropped
local floor = math.floor

local S
local open = false
local closeRect
local wx1, wy1, wx2, wy2

-- history[key] = { income = {...}, demand = {...} }, all the same length
local history = {}
local times = {}                    -- game seconds of each sample
local interval = 2                  -- seconds between samples; doubles as the game runs long
local lastSample = -100

--------------------------------------------------------------------------------

local function Clock(seconds)
	seconds = floor(seconds or 0)
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60)
	end
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

local function Halve(list)
	local out = {}
	for i = 1, #list, 2 do out[#out + 1] = list[i] end
	return out
end

local function Sample()
	local teamID = Spring.GetMyTeamID()
	if not teamID then return end
	local resources = S.game.resources or {}
	for i = 1, #resources do
		local key = resources[i].key
		local h = history[key]
		if not h then h = { income = {}, demand = {} } ; history[key] = h end
		local _, _, pull, income = Spring.GetTeamResources(teamID, key)
		h.income[#h.income + 1] = income or 0
		h.demand[#h.demand + 1] = pull or 0
	end
	times[#times + 1] = Spring.GetGameSeconds()

	if #times >= MAX_SAMPLES then
		times = Halve(times)
		for _, h in pairs(history) do
			h.income = Halve(h.income)
			h.demand = Halve(h.demand)
		end
		interval = interval * 2
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
	if command == "slate economy" then
		if WG.Slate ~= S then return false end
		if open then Close() else open = true end
		return true
	end
	return false
end

function widget:GameFrame(frame)
	if WG.Slate ~= S or frame % 30 ~= 0 then return end
	local now = Spring.GetGameSeconds()
	if now - lastSample >= interval then
		lastSample = now
		Sample()
	end
end

function widget:DrawScreen()
	if not open or WG.Slate ~= S then return end
	local t = S.theme
	local mx, my = Spring.GetMouseState()
	local top
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, HEIGHT, "Economy", mx, my)
	wy2 = top + S.px(44)

	local pad = S.px(20)
	local x1, x2 = wx1 + pad, wx2 - pad
	local resources = S.game.resources or {}
	local n = math.max(1, #resources)
	local gap = S.px(18)
	local chartH = ((top - S.px(12)) - (wy1 + pad) - gap * (n - 1)) / n
	local opts = { xLabel = function(i) return Clock(times[i]) end }

	for i = 1, #resources do
		local res = resources[i]
		local h = history[res.key] or { income = {}, demand = {} }
		local cy2 = top - S.px(12) - (i - 1) * (chartH + gap)
		opts.title = res.label .. " per second"
		S.LineChart(x1, cy2 - chartH, x2, cy2, {
			{ label = "Income", color = t.chartA, points = h.income },
			{ label = "Demand", color = t.chartB, points = h.demand },
		}, opts, mx, my)
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
	if button == 1 and closeRect and S.Inside(mx, my, closeRect[1], closeRect[2], closeRect[3], closeRect[4]) then
		Close()
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
