-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Chat Log",
		desc    = "Scrollback for chat and console output, with Chat / Console / All tabs. Open it from the Menu or with /slate log. Needs Slate Chat, which collects the lines.",
		author  = "Scary le Poo",
		date    = "2026-10-09",
		license = "GNU GPL, v2 or later",
		layer   = -16,
		enabled = true,
	}
end

local ID = "chatlog"
local WIDTH, HEIGHT = 980, 660      -- design pixels
local TAB_H   = 34
local LINE_H  = 20
local TEXT_SIZE = 14

local floor = math.floor
local min, max = math.min, math.max

local S
local open = false
local tab = 1
local rows = {}                     -- wrapped display lines for the current tab
local scroll = 0                    -- lines scrolled up from the newest
local visible = 1
local builtCount, builtTab, builtWidth = -1, 0, 0
local hits = {}
local closeRect
local wx1, wy1, wx2, wy2

local tabs = {
	{ label = "Chat",    test = function(e, isChat) return isChat(e) end },
	{ label = "Console", test = function(e, isChat) return not isChat(e) end },
	{ label = "All",     test = function() return true end },
}

--------------------------------------------------------------------------------

local function Clock(seconds)
	seconds = floor(seconds or 0)
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- Cut a word that is wider than a whole line into pieces that fit. `room` is
-- the space left on the current line, `full` the width of the lines after it.
local function BreakWord(word, room, full)
	local pieces = {}
	local start, n = 1, #word
	while start <= n do
		local limit = (#pieces == 0) and room or full
		local stop = start
		local fit = start
		while stop <= n do
			-- step over a whole UTF-8 character
			local nextStop = stop
			while nextStop < n and word:byte(nextStop + 1) >= 128 and word:byte(nextStop + 1) < 192 do
				nextStop = nextStop + 1
			end
			if S.TextWidth(word:sub(start, nextStop), TEXT_SIZE) > limit and nextStop > fit then break end
			fit = nextStop
			stop = nextStop + 1
		end
		pieces[#pieces + 1] = word:sub(start, fit)
		start = fit + 1
	end
	return pieces
end

-- Turn the shared history into wrapped lines for this tab and width. Each row
-- is a list of segments { text, color, x }: the name in its team colour, the
-- message in the colour of its channel.
local function Rebuild(width)
	rows = {}
	local chat = WG.SlateChat
	local t = S.theme
	if not chat then
		rows[1] = { segs = { { text = "Slate Chat is switched off, so there is nothing to show. Turn it on in the widget list (F11).", color = t.textDim, x = 0 } } }
		return
	end
	local log = chat.GetLog()
	local test = tabs[tab].test
	local stampW = S.TextWidth("000:00  ", TEXT_SIZE)
	local bodyW = width - stampW
	local indent = S.TextWidth("    ", TEXT_SIZE)
	local space = S.TextWidth("a a", TEXT_SIZE) - S.TextWidth("aa", TEXT_SIZE)

	for i = 1, #log do
		local e = log[i]
		if test(e, chat.IsChat) then
			local color = e.color or t.text
			local segs, offset = {}, 0
			local first = true
			if e.player then
				local lead = e.player .. (e.joined and " " or ":  ")
				segs[1] = { text = lead, color = chat.NameColor and chat.NameColor(e.player) or t.text, x = 0 }
				offset = S.TextWidth(lead, TEXT_SIZE)
			end
			local line, lineW = "", 0
			local function EndRow()
				if line ~= "" then segs[#segs + 1] = { text = line, color = color, x = offset } end
				rows[#rows + 1] = { stamp = first and Clock(e.gameTime) or nil, segs = segs }
				first = false
				segs, offset, line, lineW = {}, indent, "", 0
			end
			for word in (e.body or ""):gmatch("%S+") do
				local w = S.TextWidth(word, TEXT_SIZE)
				local gap = (line ~= "") and space or 0
				if offset + lineW + gap + w <= bodyW then
					line = (line ~= "") and (line .. " " .. word) or word
					lineW = lineW + gap + w
				elseif indent + w <= bodyW then
					EndRow()
					line, lineW = word, w
				else
					-- wider than a whole line (a checksum, a path): cut it up
					local room = bodyW - offset - lineW - gap
					if room < bodyW * 0.25 then
						EndRow()
						room = bodyW - indent
					end
					local pieces = BreakWord(word, room, bodyW - indent)
					for k = 1, #pieces do
						line = (line ~= "") and (line .. " " .. pieces[k]) or pieces[k]
						lineW = S.TextWidth(line, TEXT_SIZE)
						if k < #pieces then EndRow() end
					end
				end
			end
			if line ~= "" or #segs > 0 then EndRow() end
		end
	end
	builtCount, builtTab, builtWidth = #log, tab, width
	scroll = max(0, min(scroll, #rows - visible))
end

local function Close()
	open = false
	if S then S.Unblur(ID) end
end

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
	if command == "slate log" then
		if WG.Slate ~= S then return false end
		if open then Close() else open = true ; scroll = 0 ; builtCount = -1 end
		return true
	end
	return false
end

--------------------------------------------------------------------------------

function widget:DrawScreen()
	if not open or WG.Slate ~= S then return end
	local t = S.theme
	local mx, my = Spring.GetMouseState()
	hits = {}

	local top
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, HEIGHT, "Chat log", mx, my)
	wy2 = top + S.px(44)

	local pad = S.px(18)
	local x1, x2 = wx1 + pad, wx2 - pad - S.px(10)
	local y = top - S.px(12)

	local th, tw = S.px(TAB_H), S.px(100)
	for i = 1, #tabs do
		local tx1 = x1 + (i - 1) * (tw + S.px(6))
		local over = S.Inside(mx, my, tx1, y - th, tx1 + tw, y)
		S.Button(tx1, y - th, tx1 + tw, y, (i == tab) and "active" or (over and "hover" or nil))
		S.Text(tabs[i].label, tx1 + tw * 0.5, y - th * 0.5, 14, t.text, "cv")
		hits[#hits + 1] = { tx1, y - th, tx1 + tw, y, i }
	end
	y = y - th - S.px(12)

	local bottom = wy1 + S.px(16)
	local lh = S.px(LINE_H)
	visible = max(1, floor((y - bottom) / lh))

	-- rebuild only when something changed: new lines, another tab, a resize
	local chat = WG.SlateChat
	local count = chat and #chat.GetLog() or 0
	local width = x2 - x1
	if count ~= builtCount or tab ~= builtTab or width ~= builtWidth then
		local atBottom = (scroll == 0)
		local before = #rows
		Rebuild(width)
		-- stay where the reader was unless they were following the newest line
		if not atBottom then scroll = min(max(0, #rows - visible), scroll + (#rows - before)) end
	end

	local stampW = S.TextWidth("000:00  ", TEXT_SIZE)
	local last = #rows - scroll
	local first = max(1, last - visible + 1)
	local ty = y - lh * 0.5
	for i = first, last do
		local row = rows[i]
		if row.stamp then S.Text(row.stamp, x1, ty, TEXT_SIZE, t.textDim, "v") end
		for k = 1, #row.segs do
			local seg = row.segs[k]
			S.Text(seg.text, x1 + stampW + seg.x, ty, TEXT_SIZE, seg.color, "v")
		end
		ty = ty - lh
	end
	if #rows == 0 then
		S.Text("Nothing here yet.", x1, ty, TEXT_SIZE, t.textDim, "v")
	end

	if #rows > visible then
		local trackTop, trackBot = y, y - visible * lh
		local thumbH = max(S.px(20), (trackTop - trackBot) * visible / #rows)
		local frac = 1 - scroll / (#rows - visible)
		local thumbY = trackTop - (trackTop - trackBot - thumbH) * frac
		S.Rect(x2 + S.px(12), thumbY - thumbH, x2 + S.px(16), thumbY, t.buttonActive, S.px(2))
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
			tab, scroll, builtCount = h[5], 0, -1
			break
		end
	end
	return true
end

function widget:MouseWheel(up)
	if not open or WG.Slate ~= S then return false end
	local mx, my = Spring.GetMouseState()
	if not InWindow(mx, my) then return false end
	scroll = max(0, min(scroll + (up and 3 or -3), #rows - visible))
	return true
end

function widget:KeyPress(key)
	if open and key == 27 then   -- Esc
		Close()
		return true
	end
	return false
end
