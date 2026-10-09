-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Key Bindings",
		desc    = "See every key binding and change one by clicking it and pressing a key. Open it from the Menu or with /slate keys.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = -14,
		enabled = true,
	}
end

local ID = "keybinds"
local WIDTH, HEIGHT = 680, 680      -- design pixels
local ROW_H = 30
local TAB_H = 34

local floor = math.floor
local min, max = math.min, math.max

local S
local open = false
local tab = 1
local scroll = 0
local visibleRows = 1
local rows = {}                     -- { id, command, extra, keys = { "a", ... }, changed }
local hits = {}
local closeRect
local wx1, wy1, wx2, wy2
local listening                     -- row id waiting for a key press
local notice = ""

-- Saved between games:
--   changed[id]  = keyset the player chose ("" = no key)
--   original[id] = { keysets the action had before the first change }
local changed, original = {}, {}

--------------------------------------------------------------------------------
-- Sorting actions into tabs
--------------------------------------------------------------------------------

local orderActions = {
	attack = true, move = true, stop = true, patrol = true, fight = true, guard = true,
	repair = true, reclaim = true, resurrect = true, capture = true, restore = true,
	wait = true, manualfire = true, dgun = true, selfd = true, onoff = true, cloak = true,
	wantcloak = true, ["repeat"] = true, movestate = true, firestate = true,
	loadunits = true, unloadunits = true, areaattack = true, stockpile = true,
	trajectory = true, idlemode = true, autorepairlevel = true, buildspacing = true,
	buildfacing = true, areamex = true,
}

local function Category(command)
	if orderActions[command] or command:find("^buildunit_") then return "Orders" end
	if command:find("^select") or command:find("^group") or command == "selectcomm" then return "Selection" end
	if command:find("^view") or command:find("^move") or command:find("^track") or command:find("cam")
		or command:find("^toggleoverview") or command:find("^increaseview") or command:find("^decreaseview")
		or command:find("^yardmap") then
		return "Camera"
	end
	return "Other"
end

local tabs = { "Orders", "Selection", "Camera", "Other", "Changed" }

--------------------------------------------------------------------------------

local function RowID(command, extra)
	return (extra and extra ~= "") and (command .. " " .. extra) or command
end

-- "Any+sc_a" -> "A", "Ctrl+sc_f11" -> "Ctrl+F11"
local function Pretty(keyset)
	local parts = {}
	for part in keyset:gmatch("[^+]+") do
		if part:lower() ~= "any" then
			part = part:gsub("^sc_", "")
			if #part <= 3 then part = part:upper() else part = part:sub(1, 1):upper() .. part:sub(2) end
			parts[#parts + 1] = part
		end
	end
	return table.concat(parts, "+")
end

local function Rebuild()
	local byID, list = {}, {}
	local bindings = Spring.GetKeyBindings() or {}
	for i = 1, #bindings do
		local b = bindings[i]
		local command = b.command or ""
		if command ~= "" then
			local id = RowID(command, b.extra)
			local row = byID[id]
			if not row then
				row = { id = id, command = command, extra = b.extra or "", keys = {} }
				byID[id] = row
				list[#list + 1] = row
			end
			row.keys[#row.keys + 1] = b.boundWith or ""
		end
	end
	-- actions the player cleared no longer appear in the engine's list
	for id, keyset in pairs(changed) do
		if not byID[id] then
			local command, extra = id:match("^(%S+)%s*(.*)$")
			local row = { id = id, command = command or id, extra = extra or "", keys = {} }
			byID[id] = row
			list[#list + 1] = row
		end
		byID[id].changed = true
	end

	rows = {}
	local want = tabs[tab]
	for i = 1, #list do
		local row = list[i]
		if (want == "Changed" and row.changed) or (want ~= "Changed" and Category(row.command) == want) then
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b) return a.id < b.id end)
	scroll = max(0, min(scroll, #rows - visibleRows))
end

--------------------------------------------------------------------------------
-- Changing a binding
--------------------------------------------------------------------------------

local function CurrentKeys(command, extra)
	local keys = {}
	local bindings = Spring.GetKeyBindings() or {}
	for i = 1, #bindings do
		local b = bindings[i]
		if b.command == command and (b.extra or "") == (extra or "") then
			keys[#keys + 1] = b.boundWith
		end
	end
	return keys
end

local function Action(row)
	return (row.extra ~= "") and (row.command .. " " .. row.extra) or row.command
end

-- Replace every key on this action with `keyset` ("" removes them all).
local function SetBinding(row, keyset)
	local current = CurrentKeys(row.command, row.extra)
	if not original[row.id] then original[row.id] = current end
	for i = 1, #current do
		Spring.SendCommands("unbind " .. current[i] .. " " .. Action(row))
	end
	if keyset ~= "" then
		Spring.SendCommands("bind " .. keyset .. " " .. Action(row))
	end
	changed[row.id] = keyset
end

local function ResetRow(row)
	local current = CurrentKeys(row.command, row.extra)
	for i = 1, #current do
		Spring.SendCommands("unbind " .. current[i] .. " " .. Action(row))
	end
	local keys = original[row.id] or {}
	for i = 1, #keys do
		Spring.SendCommands("bind " .. keys[i] .. " " .. Action(row))
	end
	changed[row.id], original[row.id] = nil, nil
end

local function ResetAll()
	for id in pairs(changed) do
		local command, extra = id:match("^(%S+)%s*(.*)$")
		ResetRow({ id = id, command = command or id, extra = extra or "" })
	end
	notice = "All key bindings are back to the game's defaults."
end

-- Who else uses this keyset? (The engine lets several actions share a key.)
local function OtherUsers(keyset, exceptID)
	local names = {}
	local bindings = Spring.GetKeyBindings(keyset) or {}
	for i = 1, #bindings do
		local id = RowID(bindings[i].command or "", bindings[i].extra)
		if id ~= exceptID and id ~= "" then names[#names + 1] = id end
	end
	return names
end

local modifierKeys = {
	lshift = true, rshift = true, lctrl = true, rctrl = true, lalt = true, ralt = true,
	lmeta = true, rmeta = true, lgui = true, rgui = true, shift = true, ctrl = true, alt = true, meta = true,
}

--------------------------------------------------------------------------------

local function Close()
	open = false
	listening = nil
	if S then S.Unblur(ID) end
end

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	-- put the player's saved changes back on top of the game's defaults
	for id, keyset in pairs(changed) do
		local command, extra = id:match("^(%S+)%s*(.*)$")
		local row = { id = id, command = command or id, extra = extra or "" }
		local keep = original[id]
		SetBinding(row, keyset)
		original[id] = keep or original[id]
	end
end

function widget:Shutdown()
	if S then S.Unblur(ID) end
end

function widget:GetConfigData()
	return { changed = changed, original = original }
end

function widget:SetConfigData(data)
	if type(data) == "table" then
		changed = type(data.changed) == "table" and data.changed or {}
		original = type(data.original) == "table" and data.original or {}
	end
end

function widget:TextCommand(command)
	if command == "slate keys" then
		if WG.Slate ~= S then return false end
		if open then Close() else open = true ; notice = "" ; Rebuild() end
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
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, HEIGHT, "Key bindings", mx, my)
	wy2 = top + S.px(44)

	local pad = S.px(18)
	local x1, x2 = wx1 + pad, wx2 - pad
	local y = top - S.px(12)

	local th, tw = S.px(TAB_H), S.px(96)
	for i = 1, #tabs do
		local tx1 = x1 + (i - 1) * (tw + S.px(6))
		local over = S.Inside(mx, my, tx1, y - th, tx1 + tw, y)
		S.Button(tx1, y - th, tx1 + tw, y, (i == tab) and "active" or (over and "hover" or nil))
		S.Text(tabs[i], tx1 + tw * 0.5, y - th * 0.5, 14, t.text, "cv")
		hits[#hits + 1] = { x1 = tx1, y1 = y - th, x2 = tx1 + tw, y2 = y, tab = i }
	end
	y = y - th - S.px(10)

	local footer = S.px(64)
	local rh = S.px(ROW_H)
	visibleRows = max(1, floor((y - (wy1 + footer)) / rh))
	scroll = max(0, min(scroll, #rows - visibleRows))
	local keyW = S.px(190)
	local resetW = S.px(60)

	if #rows == 0 then
		S.Text((tabs[tab] == "Changed") and "You have not changed any key bindings." or "Nothing here.",
			x1, y - rh * 0.5, 14, t.textDim, "v")
	end

	for i = 1, visibleRows do
		local row = rows[scroll + i]
		if not row then break end
		local ry2 = y - (i - 1) * rh
		local ry1 = ry2 - rh
		local mid = (ry1 + ry2) * 0.5
		local kx2 = row.changed and (x2 - resetW - S.px(8)) or x2
		local kx1 = kx2 - keyW
		local over = S.Inside(mx, my, kx1, ry1 + 2, kx2, ry2 - 2)
		local waiting = (listening == row.id)

		S.Text(S.Fit(row.id, 14, kx1 - x1 - S.px(10)), x1, mid, 14, row.changed and t.accent or t.text, "v")
		S.Button(kx1, ry1 + 2, kx2, ry2 - 2, waiting and "warn" or (over and "hover" or nil))
		local label
		if waiting then
			label = "Press a key..."
		else
			local pretty = {}
			for k = 1, #row.keys do pretty[k] = Pretty(row.keys[k]) end
			label = (#pretty > 0) and table.concat(pretty, ",  ") or "-"
		end
		S.Text(S.Fit(label, 13, keyW - S.px(10)), (kx1 + kx2) * 0.5, mid, 13, waiting and t.warn or t.text, "cv")
		hits[#hits + 1] = { x1 = kx1, y1 = ry1, x2 = kx2, y2 = ry2, row = row }

		if row.changed then
			local rx1 = x2 - resetW
			local overReset = S.Inside(mx, my, rx1, ry1 + 2, x2, ry2 - 2)
			S.Button(rx1, ry1 + 2, x2, ry2 - 2, overReset and "hover" or nil)
			S.Text("Reset", (rx1 + x2) * 0.5, mid, 12, t.textDim, "cv")
			hits[#hits + 1] = { x1 = rx1, y1 = ry1, x2 = x2, y2 = ry2, reset = row }
		end
	end

	if #rows > visibleRows then
		local trackTop, trackBot = y, y - visibleRows * rh
		local thumbH = max(S.px(20), (trackTop - trackBot) * visibleRows / #rows)
		local thumbY = trackTop - (trackTop - trackBot - thumbH) * (scroll / (#rows - visibleRows))
		S.Rect(x2 + S.px(8), thumbY - thumbH, x2 + S.px(12), thumbY, t.buttonActive, S.px(2))
	end

	-- footer: guidance or the result of the last change, and Reset all
	local fy = wy1 + footer * 0.5
	local bw, bh = S.px(110), S.px(30)
	local overAll = S.Inside(mx, my, x2 - bw, fy - bh * 0.5, x2, fy + bh * 0.5)
	S.Button(x2 - bw, fy - bh * 0.5, x2, fy + bh * 0.5, overAll and "hover" or nil)
	S.Text("Reset all", x2 - bw * 0.5, fy, 13, t.text, "cv")
	hits[#hits + 1] = { x1 = x2 - bw, y1 = fy - bh * 0.5, x2 = x2, y2 = fy + bh * 0.5, resetAll = true }

	local help = notice
	if listening then
		help = "Press the new key (with Ctrl, Alt or Shift if you like). Backspace removes the key. Esc cancels."
	elseif help == "" then
		help = "Click a key to change it. Changes are saved."
	end
	S.Text(S.Fit(help, 13, x2 - bw - x1 - S.px(12)), x1, fy, 13, listening and t.warn or t.textDim, "v")
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
	listening = nil
	for i = #hits, 1, -1 do
		local h = hits[i]
		if mx >= h.x1 and mx <= h.x2 and my >= h.y1 and my <= h.y2 then
			if h.tab then
				tab, scroll = h.tab, 0
			elseif h.reset then
				ResetRow(h.reset)
				notice = h.reset.id .. " is back to its default."
			elseif h.resetAll then
				ResetAll()
			elseif h.row then
				listening = h.row.id
				notice = ""
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
	scroll = max(0, min(scroll + (up and -3 or 3), #rows - visibleRows))
	return true
end

function widget:KeyPress(key, mods)
	if not open then return false end
	if not listening then
		if key == 27 then Close() ; return true end
		return false
	end

	local symbol = (Spring.GetKeySymbol(key) or ""):lower()
	if symbol == "" or modifierKeys[symbol] then return true end   -- wait for the real key
	local row
	for i = 1, #rows do if rows[i].id == listening then row = rows[i] end end
	listening = nil
	if not row or symbol == "escape" or key == 27 then
		notice = ""
		return true
	end

	if symbol == "backspace" or symbol == "delete" then
		SetBinding(row, "")
		notice = row.id .. " no longer has a key."
	else
		local keyset = (mods.ctrl and "Ctrl+" or "") .. (mods.alt and "Alt+" or "")
			.. (mods.shift and "Shift+" or "") .. (mods.meta and "Meta+" or "") .. symbol
		local others = OtherUsers(keyset, row.id)
		SetBinding(row, keyset)
		notice = row.id .. " is now " .. Pretty(keyset) .. "."
		if #others > 0 then
			notice = notice .. " That key is also used by: " .. table.concat(others, ", ") .. "."
		end
	end
	Rebuild()
	return true
end
