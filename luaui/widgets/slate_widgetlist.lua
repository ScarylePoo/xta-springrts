-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Widget List",
		desc    = "Turn widgets on and off. F11, the Menu, or /slate widgets.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = -11,
		enabled = true,
		handler = true,
	}
end

local ID = "widgetlist"
local WIDTH, HEIGHT = 620, 660      -- design pixels
local ROW_H = 30
local TAB_H = 34

local floor = math.floor
local min, max = math.min, math.max

local S
local open = false
local filter = 1
local scroll = 0                    -- index of the first visible row, 0-based
local list = {}                     -- filtered, sorted: { name, active, enabled, desc, author }
local visibleRows = 1
local hits = {}
local closeRect
local wx1, wy1, wx2, wy2
local timer = 1

local filters = {
	{ label = "All",   test = function() return true end },
	{ label = "On",    test = function(w) return w.enabled end },
	{ label = "Off",   test = function(w) return not w.enabled end },
	{ label = "Slate", test = function(w) return w.name:sub(1, 5) == "Slate" end },
}

--------------------------------------------------------------------------------

local function Rebuild()
	list = {}
	local order = widgetHandler.orderList or {}
	for name, info in pairs(widgetHandler.knownWidgets or {}) do
		local entry = {
			name = name,
			active = info.active and true or false,
			enabled = (order[name] or 0) > 0,
			desc = info.desc or "",
			author = info.author or "",
		}
		if filters[filter].test(entry) then list[#list + 1] = entry end
	end
	table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
	scroll = max(0, min(scroll, #list - visibleRows))
end

local function Close()
	open = false
	if S then S.Unblur(ID) end
end

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget(self)
		return
	end
	Spring.SendCommands("unbindkeyset f11", "bind f11 luaui slate widgets")
end

function widget:Shutdown()
	Spring.SendCommands("unbindkeyset f11", "bind f11 luaui selector")
	if S then S.Unblur(ID) end
end

function widget:TextCommand(command)
	if command == "slate widgets" then
		if WG.Slate ~= S then return false end
		if open then Close() else open = true ; Rebuild() end
		return true
	end
	return false
end

function widget:Update(dt)
	if not open then return end
	timer = timer + dt
	if timer > 0.5 then
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
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, HEIGHT, "Widgets", mx, my)
	wy2 = top + S.px(44)

	local pad = S.px(18)
	local x1, x2 = wx1 + pad, wx2 - pad
	local y = top - S.px(12)

	local th, tw = S.px(TAB_H), S.px(90)
	for i = 1, #filters do
		local tx1 = x1 + (i - 1) * (tw + S.px(6))
		local over = S.Inside(mx, my, tx1, y - th, tx1 + tw, y)
		S.Button(tx1, y - th, tx1 + tw, y, (i == filter) and "active" or (over and "hover" or nil))
		S.Text(filters[i].label, tx1 + tw * 0.5, y - th * 0.5, 14, t.text, "cv")
		hits[#hits + 1] = { x1 = tx1, y1 = y - th, x2 = tx1 + tw, y2 = y, filter = i }
	end
	S.Text(#list .. " widgets", x2, y - th * 0.5, 13, t.textDim, "rv")
	y = y - th - S.px(10)

	local footer = S.px(52)
	local rh = S.px(ROW_H)
	visibleRows = max(1, floor((y - (wy1 + footer)) / rh))
	scroll = max(0, min(scroll, #list - visibleRows))
	local hovered

	for i = 1, visibleRows do
		local w = list[scroll + i]
		if not w then break end
		local ry2 = y - (i - 1) * rh
		local ry1 = ry2 - rh
		local over = S.Inside(mx, my, x1, ry1, x2, ry2)
		if over then
			S.Rect(x1 - S.px(6), ry1 + 1, x2 + S.px(6), ry2 - 1, t.buttonHover, S.px(t.buttonRadius))
			hovered = w
		end
		local mid = (ry1 + ry2) * 0.5

		-- state pill: on, switched on but not running (failed, or finished its job), off
		local pw, ph = S.px(40), S.px(18)
		local color, label = t.track, "Off"
		if w.active then color, label = t.good, "On"
		elseif w.enabled then color, label = t.warn, "Idle" end
		S.Rect(x1, mid - ph * 0.5, x1 + pw, mid + ph * 0.5, color, ph * 0.5)
		S.Text(label, x1 + pw * 0.5, mid, 11, w.enabled and { 0.08, 0.09, 0.10, 1 } or t.textDim, "cv")

		local nameX = x1 + pw + S.px(12)
		local authorW = S.px(170)
		S.Text(S.Fit(w.name, 15, x2 - authorW - nameX), nameX, mid, 15, w.enabled and t.text or t.textDim, "v")
		S.Text(S.Fit(w.author, 12, authorW - S.px(8)), x2, mid, 12, t.textDim, "rv")
		hits[#hits + 1] = { x1 = x1, y1 = ry1, x2 = x2, y2 = ry2, widget = w.name }
	end

	-- scroll position
	if #list > visibleRows then
		local trackTop, trackBot = y, y - visibleRows * rh
		local frac = visibleRows / #list
		local thumbH = max(S.px(20), (trackTop - trackBot) * frac)
		local thumbY = trackTop - (trackTop - trackBot - thumbH) * (scroll / (#list - visibleRows))
		S.Rect(x2 + S.px(8), thumbY - thumbH, x2 + S.px(12), thumbY, t.buttonActive, S.px(2))
	end

	local fy = wy1 + footer * 0.5
	if hovered then
		S.Text(S.Fit(hovered.desc, 13, x2 - x1), x1, fy, 13, t.text, "v")
	else
		S.Text("Click a widget to turn it on or off. Scroll for more.", x1, fy, 13, t.textDim, "v")
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
	for i = #hits, 1, -1 do
		local h = hits[i]
		if mx >= h.x1 and mx <= h.x2 and my >= h.y1 and my <= h.y2 then
			if h.filter then
				filter = h.filter
				scroll = 0
			elseif h.widget then
				widgetHandler:ToggleWidget(h.widget)
			end
			Rebuild()
			break
		end
	end
	return true
end

function widget:MouseWheel(up)
	if not open or WG.Slate ~= S then return false end
	local mx, my = Spring.GetMouseState()
	if not InWindow(mx, my) then return false end
	scroll = max(0, min(scroll + (up and -3 or 3), #list - visibleRows))
	return true
end

function widget:KeyPress(key)
	if open and key == 27 then   -- Esc
		Close()
		return true
	end
	return false
end
