-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Top Bar",
		desc    = "Game clock, speed, frame rate and a Menu button. Menu entries come from slate_game.lua.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = 5,
		enabled = true,
	}
end

local ID = "topbar"
local WIDTH, HEIGHT = 300, 44       -- design pixels
local BUTTON_W      = 70
local ENTRY_H       = 36

local floor = math.floor
local max = math.max

local S
local x1, y1, x2, y2
local bx1, by1, bx2, by2            -- Menu button
local open = false
local oldClock, oldFPS

--------------------------------------------------------------------------------

local function Layout()
	x1, y1, x2, y2 = S.Box(ID, "r", "t", S.theme.margin, S.theme.margin, WIDTH, HEIGHT)
	local inset = S.px(6)
	bx2, by1, by2 = x2 - inset, y1 + inset, y2 - inset
	bx1 = bx2 - S.px(BUTTON_W)
end

-- Entries marked playersOnly are left out while spectating.
local function Entries()
	local all = S.game.menu or {}
	if not Spring.GetSpectatingState() then return all end
	local list = {}
	for i = 1, #all do
		if not all[i].playersOnly then list[#list + 1] = all[i] end
	end
	return list
end

-- An entry with `confirm` needs a second click within a few seconds.
local armed, armedAt
local ARM_SECONDS = 4

local function Armed()
	if armed and Spring.DiffTimers(Spring.GetTimer(), armedAt) > ARM_SECONDS then armed = nil end
	return armed
end

local function MenuRect()
	local entries = Entries()
	local h = #entries * S.px(ENTRY_H) + S.px(12)
	local w = S.px(190)
	return x2 - w, y1 - S.px(8) - h, x2, y1 - S.px(8)
end

local function EntryAt(mx, my)
	if not open then return nil end
	local mx1, my1, mx2, my2 = MenuRect()
	if not S.Inside(mx, my, mx1, my1, mx2, my2) then return nil end
	local entries = Entries()
	local i = floor((my2 - S.px(6) - my) / S.px(ENTRY_H)) + 1
	return entries[i], i
end

--------------------------------------------------------------------------------

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	oldClock = Spring.GetConfigInt("ShowClock", 1) or 1
	oldFPS   = Spring.GetConfigInt("ShowFPS", 0) or 0
	Spring.SendCommands("clock 0", "fps 0")
	S.Register(ID, "Clock and menu", Layout)
	S.OnChange(ID, Layout)
	Layout()
end

function widget:Shutdown()
	Spring.SendCommands("clock " .. (oldClock or 1), "fps " .. (oldFPS or 0))
	if S then
		S.Unregister(ID)
		S.OffChange(ID)
		S.Unblur(ID) ; S.Unblur(ID .. "_menu")
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then Layout() end
end

local cache

local function DrawPanel()
	local t = S.theme
	local mx, my = Spring.GetMouseState()
	S.Panel(x1, y1, x2, y2)
	S.Blur(ID, x1, y1, x2, y2)

	local mid = (y1 + y2) * 0.5
	local secs = floor(Spring.GetGameSeconds() or 0)
	local clock
	if secs >= 3600 then
		clock = string.format("%d:%02d:%02d", floor(secs / 3600), floor(secs / 60) % 60, secs % 60)
	else
		clock = string.format("%d:%02d", floor(secs / 60), secs % 60)
	end
	local x = x1 + S.px(14)
	S.Text(clock, x, mid, 16, t.text, "v")
	x = x + max(S.TextWidth(clock, 16), S.px(44)) + S.px(14)

	local _, speed, paused = Spring.GetGameSpeed()
	local speedStr = paused and "Paused" or string.format("%.1fx", speed or 1)
	S.Text(speedStr, x, mid, 14, paused and t.warn or t.textDim, "v")
	x = x + S.TextWidth(speedStr, 14) + S.px(14)
	S.Text((Spring.GetFPS() or 0) .. " fps", x, mid, 14, t.textDim, "v")

	local overButton = S.Inside(mx, my, bx1, by1, bx2, by2)
	S.Button(bx1, by1, bx2, by2, open and "active" or (overButton and "hover" or nil))
	S.Text("Menu", (bx1 + bx2) * 0.5, mid, 14, t.text, "cv")

	if open then
		local mx1, my1, mx2, my2 = MenuRect()
		S.Panel(mx1, my1, mx2, my2)
		S.Blur(ID .. "_menu", mx1, my1, mx2, my2)
		local entries = Entries()
		local _, hot = EntryAt(mx, my)
		local waiting = Armed()
		local eh = S.px(ENTRY_H)
		local ey = my2 - S.px(6)
		for i = 1, #entries do
			if i == hot then
				S.Rect(mx1 + S.px(6), ey - eh, mx2 - S.px(6), ey, t.buttonHover, S.px(t.buttonRadius))
			end
			if entries[i] == waiting then
				S.Text("Click again to " .. entries[i].label:lower(), mx1 + S.px(16), ey - eh * 0.5, 14, t.warn, "v")
			else
				S.Text(entries[i].label, mx1 + S.px(16), ey - eh * 0.5, 14, t.text, "v")
			end
			ey = ey - eh
		end
	else
		S.Unblur(ID .. "_menu")
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S or not x1 then return end
	-- redo the recording only when something shown changes
	local mx, my = Spring.GetMouseState()
	local _, speed, paused = Spring.GetGameSpeed()
	local _, hot = EntryAt(mx, my)
	local key = table.concat({
		S.version, floor(Spring.GetGameSeconds() or 0), floor((speed or 1) * 10), paused and 1 or 0,
		Spring.GetFPS() or 0, open and 1 or 0, S.Inside(mx, my, bx1, by1, bx2, by2) and 1 or 0, hot or 0,
		Armed() and 1 or 0, Spring.GetSpectatingState() and 1 or 0,
	}, ":")
	cache = S.Cached(cache, key, DrawPanel)
	S.Flush()
end

--------------------------------------------------------------------------------

function widget:IsAbove(mx, my)
	if WG.Slate ~= S or not x1 then return false end
	if S.Inside(mx, my, x1, y1, x2, y2) then return true end
	if open then
		local mx1, my1, mx2, my2 = MenuRect()
		return S.Inside(mx, my, mx1, my1, mx2, my2)
	end
	return false
end

function widget:GetTooltip()
	return ""
end

function widget:MousePress(mx, my, button)
	if WG.Slate ~= S or not x1 then return false end
	if S.Inside(mx, my, bx1, by1, bx2, by2) then
		open = not open
		armed = nil
		return true
	end
	local entry = EntryAt(mx, my)
	if entry then
		if entry.confirm and Armed() ~= entry then
			armed, armedAt = entry, Spring.GetTimer()
			return true
		end
		armed = nil
		open = false
		if entry.command then Spring.SendCommands(entry.command) end
		return true
	end
	if open then
		-- a click anywhere else closes the menu
		open = false
		armed = nil
		local mx1, my1, mx2, my2 = MenuRect()
		return S.Inside(mx, my, mx1, my1, mx2, my2)
	end
	return S.Inside(mx, my, x1, y1, x2, y2)
end
