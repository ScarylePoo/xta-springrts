-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Build and Order Menu",
		desc    = "Build grid with category filters and paging, plus the order and unit-state buttons. Replaces the engine's command menu.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = 0,
		enabled = true,
		handler = true,
	}
end

local BUILD_ID, ORDER_ID = "buildmenu", "ordermenu"

-- design pixels
local PANEL_W        = 300
local BUILD_H        = 452
local ORDER_H        = 264
local MINIMAP_H      = 300      -- assumed minimap frame height until Slate Minimap reports the real one
local PAD            = 10
local GAP            = 6
local HEADER_H       = 28
local CHIP_H         = 30
local ORDER_HEADER_H = 22

local spGetActiveCmdDescs   = Spring.GetActiveCmdDescs
local spGetActiveCommand    = Spring.GetActiveCommand
local spGetCmdDescIndex     = Spring.GetCmdDescIndex
local spSetActiveCommand    = Spring.SetActiveCommand
local spGetModKeyState      = Spring.GetModKeyState
local spGetMouseState       = Spring.GetMouseState
local spGetSelectedUnits    = Spring.GetSelectedUnits
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetFullBuildQueue   = Spring.GetFullBuildQueue
local spGetActionHotKeys    = Spring.GetActionHotKeys
local spForceLayoutUpdate   = Spring.ForceLayoutUpdate
local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local S
local bx1, by1, bx2, by2            -- build panel
local ox1, oy1, ox2, oy2            -- order panel

local dirty = true
local builds, orders, states = {}, {}, {}
local filtered = {}                 -- builds after the category filter
local chips = {}                    -- { label, cat } ; cat == nil is "All"
local filter = nil                  -- selected category table, nil = All
local page, pageCount = 1, 1
local buildSignature = ""
local builderName = ""
local queued = {}                   -- unitDefID -> count in the selected factory's queue
local queueTimer = 0
local queueSignature = 0           -- changes when the queue counts change
local refreshCount = 0             -- goes up each time the command list is re-read

-- Hit rectangles rebuilt every frame by the draw code:
-- { x1, y1, x2, y2, kind = "build"|"order"|"state"|"chip"|"prev"|"next", cmd =, chip = }
local hits = {}
local pressed                       -- the hit the mouse went down on
local myHover = false

-- Taking over the menu makes the engine flag every command as hidden, so the
-- commands the game itself hides are noted before that happens.
local reallyHidden = {}

--------------------------------------------------------------------------------
-- Command list
--------------------------------------------------------------------------------

local function CleanName(name)
	name = (name or ""):gsub("\255...", ""):gsub("[\r\n]+", " ")
	return name
end

local function HotKey(action)
	if not action or action == "" or not spGetActionHotKeys then return nil end
	local keys = spGetActionHotKeys(action)
	local k = keys and keys[1]
	if not k then return nil end
	k = k:gsub("^[Aa]ny%+", ""):gsub("sc_", ""):upper()
	if #k > 5 then return nil end
	return k
end

local function Refresh()
	dirty = false
	builds, orders, states = {}, {}, {}
	local hidden = S.game.hiddenCommands or {}
	local descs = spGetActiveCmdDescs() or {}

	for i = 1, #descs do
		local cmd = descs[i]
		local t = cmd.type
		if not reallyHidden[cmd.id] and t ~= CMDTYPE.PREV and t ~= CMDTYPE.NEXT and not hidden[cmd.action or ""] then
			if cmd.id < 0 then
				if UnitDefs[-cmd.id] then
					cmd.slateKey = HotKey(cmd.action)
					builds[#builds + 1] = cmd
				end
			elseif t == CMDTYPE.ICON_MODE and cmd.params and #cmd.params > 1 then
				states[#states + 1] = cmd
			elseif (cmd.name and cmd.name ~= "") or (cmd.texture and cmd.texture ~= "") then
				cmd.slateLabel = CleanName(cmd.name)
				cmd.slateKey = HotKey(cmd.action)
				orders[#orders + 1] = cmd
			end
		end
	end

	-- A different builder: back to the first page of "All".
	local sig = #builds .. ":" .. (builds[1] and builds[1].id or 0) .. ":" .. (builds[#builds] and builds[#builds].id or 0)
	if sig ~= buildSignature then
		buildSignature = sig
		filter, page = nil, 1
	end

	chips = { { label = "All" } }
	local cats = S.game.buildCategories or {}
	for c = 1, #cats do
		local cat = cats[c]
		for i = 1, #builds do
			if cat.match(UnitDefs[-builds[i].id]) then
				chips[#chips + 1] = { label = cat.label, cat = cat }
				break
			end
		end
	end
	if #chips <= 2 then chips = {} ; filter = nil end   -- one category is no choice

	filtered = {}
	for i = 1, #builds do
		if not filter or filter.match(UnitDefs[-builds[i].id]) then
			filtered[#filtered + 1] = builds[i]
		end
	end

	local perPage = (S.game.buildColumns or 4) * (S.game.buildRows or 5)
	pageCount = max(1, ceil(#filtered / perPage))
	page = min(max(1, page), pageCount)

	local sel = spGetSelectedUnits() or {}
	local firstDef, same = nil, true
	for i = 1, #sel do
		local d = spGetUnitDefID(sel[i])
		if firstDef == nil then firstDef = d elseif d ~= firstDef then same = false ; break end
	end
	if #sel == 0 then
		builderName = ""
	elseif same and firstDef and UnitDefs[firstDef] then
		local ud = UnitDefs[firstDef]
		builderName = ud.translatedHumanName or ud.humanName or ud.name or ""
	else
		builderName = #sel .. " units"
	end
end

local function RefreshQueue()
	queued = {}
	queueSignature = 0
	if #builds == 0 or not spGetFullBuildQueue then return end
	local sel = spGetSelectedUnits() or {}
	for i = 1, #sel do
		local ud = UnitDefs[spGetUnitDefID(sel[i]) or -1]
		if ud and ud.isFactory then
			local q = spGetFullBuildQueue(sel[i]) or {}
			for j = 1, #q do
				for defID, count in pairs(q[j]) do
					queued[defID] = (queued[defID] or 0) + count
				end
			end
			for defID, count in pairs(queued) do
				queueSignature = queueSignature + defID * 7 + count * 1009
			end
			return
		end
	end
end

--------------------------------------------------------------------------------
-- Engine menu takeover
--------------------------------------------------------------------------------

local function HideEngineMenu()
	local function layoutHandler(xIcons, yIcons, cmdCount, commands)
		reallyHidden = {}
		for i = 1, cmdCount do
			local c = commands[i]
			if c and c.hidden then reallyHidden[c.id] = true end
		end
		widgetHandler.commands = commands
		widgetHandler.commands.n = cmdCount
		widgetHandler:CommandsChanged()
		local customCmds = widgetHandler.customCommands
		return "", xIcons, yIcons, {}, customCmds, {}, {}, {}, {}, {}, { [1337] = 9001 }
	end
	widgetHandler:ConfigLayoutHandler(layoutHandler)
	spForceLayoutUpdate()
end

local function Layout()
	local t = S.theme
	ox1, oy1, ox2, oy2 = S.Box(ORDER_ID, "l", "b", t.margin, t.margin, PANEL_W, ORDER_H)
	-- the build menu stands on the orders menu and follows it if it is moved,
	-- so it stays put whatever shape the minimap takes
	bx1, by1, bx2, by2 = S.Box(BUILD_ID, "l", "b", ox1 / S.scale, oy2 / S.scale + t.gap, PANEL_W, BUILD_H)
end

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget(self)
		return
	end
	HideEngineMenu()
	S.Register(BUILD_ID, "Build menu", Layout)
	S.Register(ORDER_ID, "Orders", Layout)
	S.OnChange(BUILD_ID, function() Layout() ; dirty = true end)
	Layout()
end

function widget:Shutdown()
	widgetHandler:ConfigLayoutHandler(true)
	spForceLayoutUpdate()
	if S then
		S.Unregister(BUILD_ID) ; S.Unregister(ORDER_ID)
		S.OffChange(BUILD_ID)
		S.Unblur(BUILD_ID) ; S.Unblur(ORDER_ID)
		if myHover then S.hover = nil ; S.hoverAction = nil end
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then Layout() end
end

function widget:CommandsChanged()
	dirty = true
end

function widget:SelectionChanged()
	dirty = true
end

function widget:Update(dt)
	queueTimer = queueTimer + dt
	if queueTimer > 0.25 then
		queueTimer = 0
		if S and WG.Slate == S then RefreshQueue() end
	end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function AddHit(x1, y1, x2, y2, kind, data)
	hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, kind = kind, data = data }
end

local function Hovered(x1, y1, x2, y2, mx, my)
	return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

local function DrawArrow(x1, y1, x2, y2, label, kind, enabled, mx, my)
	local t = S.theme
	S.Button(x1, y1, x2, y2, (enabled and Hovered(x1, y1, x2, y2, mx, my)) and "hover" or nil)
	S.Text(label, (x1 + x2) * 0.5, (y1 + y2) * 0.5, 15, enabled and t.text or t.textDim, "cv")
	if enabled then AddHit(x1, y1, x2, y2, kind) end
end

local hoverBuildCmd

local function DrawBuildPanel(mx, my, activeID)
	local t = S.theme
	S.Panel(bx1, by1, bx2, by2)
	S.Blur(BUILD_ID, bx1, by1, bx2, by2)

	local pad, gap = S.px(PAD), S.px(GAP)
	local ix1, ix2 = bx1 + pad, bx2 - pad
	local y = by2 - pad

	-- header: title, builder, paging
	local hh = S.px(HEADER_H)
	local hy = y - hh
	local tx = ix1
	S.Text("BUILD", tx, hy + hh * 0.5, 12, t.accent, "v")
	tx = tx + S.TextWidth("BUILD", 12) + S.px(8)
	local pagerW = (pageCount > 1) and (hh * 2 + S.px(52)) or 0
	S.Text(S.Fit(builderName, 14, ix2 - pagerW - tx - S.px(4)), tx, hy + hh * 0.5, 14, t.textDim, "v")
	if pageCount > 1 then
		DrawArrow(ix2 - hh, hy, ix2, y, ">", "next", page < pageCount, mx, my)
		S.Text(page .. " / " .. pageCount, ix2 - hh - S.px(26), hy + hh * 0.5, 14, t.text, "cv")
		DrawArrow(ix2 - hh * 2 - S.px(52), hy, ix2 - hh - S.px(52), y, "<", "prev", page > 1, mx, my)
	end
	y = hy - gap

	-- category chips
	if #chips > 0 then
		local ch = S.px(CHIP_H)
		local cw = ((ix2 - ix1) - gap * (#chips - 1)) / #chips
		for i = 1, #chips do
			local c = chips[i]
			local cx1 = floor(ix1 + (i - 1) * (cw + gap))
			local cx2 = floor(cx1 + cw)
			local on = (c.cat == filter)
			S.Button(cx1, y - ch, cx2, y, on and "active" or (Hovered(cx1, y - ch, cx2, y, mx, my) and "hover" or nil))
			S.Text(S.Fit(c.label, 13, cw - S.px(6)), (cx1 + cx2) * 0.5, y - ch * 0.5, 13, t.text, "cv")
			AddHit(cx1, y - ch, cx2, y, "chip", c)
		end
		y = y - ch - gap
	end

	-- build grid
	local cols = S.game.buildColumns or 4
	local rows = S.game.buildRows or 5
	local tw = ((ix2 - ix1) - gap * (cols - 1)) / cols
	local th = ((y - (by1 + pad)) - gap * (rows - 1)) / rows
	local first = (page - 1) * cols * rows
	local picture = S.game.unitPicture
	local hoverDef
	hoverBuildCmd = nil

	for i = 1, cols * rows do
		local cmd = filtered[first + i]
		if not cmd then break end
		local col = (i - 1) % cols
		local row = floor((i - 1) / cols)
		local x1 = floor(ix1 + col * (tw + gap))
		local x2 = floor(x1 + tw)
		local y2 = floor(y - row * (th + gap))
		local y1 = floor(y2 - th)
		local defID = -cmd.id
		local ud = UnitDefs[defID]
		local over = Hovered(x1, y1, x2, y2, mx, my)

		S.Icon(x1 + 1, y1 + 1, x2 - 1, y2 - 1, picture and picture(defID) or ("#" .. defID))
		-- cost strip so the number reads over any picture
		local strip = S.px(16)
		S.Rect(x1 + 1, y1 + 1, x2 - 1, y1 + strip, { 0, 0, 0, 0.60 }, 0)
		if cmd.disabled then
			S.Rect(x1 + 1, y1 + 1, x2 - 1, y2 - 1, t.buttonOff, 0)
		end
		local r = S.px(t.buttonRadius)
		if cmd.id == activeID then
			S.Outline(x1, y1, x2, y2, t.warn, r, max(2, S.px(2)))
		elseif over and not cmd.disabled then
			S.Outline(x1, y1, x2, y2, t.accent, r, max(1, S.px(1.5)))
		else
			S.Outline(x1, y1, x2, y2, t.buttonBorder, r, 1)
		end
		S.Text(S.Cost(ud.metalCost or 0), (x1 + x2) * 0.5, y1 + S.px(4), 11, S.game.resources[1].color, "c")

		local n = queued[defID]
		if n and n > 0 then
			local label = tostring(n)
			local bw = max(S.px(16), S.TextWidth(label, 11) + S.px(6))
			S.Rect(x2 - bw - 2, y2 - S.px(16) - 2, x2 - 2, y2 - 2, t.warn, S.px(3))
			S.Text(label, x2 - 2 - bw * 0.5, y2 - S.px(13), 11, { 0.08, 0.08, 0.07, 1 }, "c")
		end

		if cmd.slateKey then
			local kw = S.TextWidth(cmd.slateKey, 11) + S.px(6)
			S.Rect(x1 + 1, y2 - S.px(15), x1 + 1 + kw, y2 - 1, { 0, 0, 0, 0.60 }, 0)
			S.Text(cmd.slateKey, x1 + 1 + kw * 0.5, y2 - S.px(12), 11, t.text, "c")
		end

		AddHit(x1, y1, x2, y2, "build", cmd)
		if over then hoverDef = defID ; hoverBuildCmd = cmd end
	end
	return hoverDef
end

local function DrawOrderPanel(mx, my, activeID)
	local t = S.theme
	S.Panel(ox1, oy1, ox2, oy2)
	S.Blur(ORDER_ID, ox1, oy1, ox2, oy2)

	local pad, gap = S.px(PAD), S.px(GAP)
	local ix1, ix2 = ox1 + pad, ox2 - pad
	local y = oy2 - pad
	local hh = S.px(ORDER_HEADER_H)
	S.Text("ORDERS", ix1, y - hh * 0.5, 12, t.accent, "v")
	y = y - hh - gap

	local oCols = S.game.orderColumns or 5
	local sCols = S.game.stateColumns or 4
	local oRows = ceil(#orders / oCols)
	local sRows = ceil(#states / sCols)
	if oRows + sRows == 0 then return nil end

	-- Rows share the height that is left; state rows are a little taller.
	local avail = (y - (oy1 + pad)) - gap * (oRows + sRows - 1)
	local unit = avail / (oRows + sRows * 1.15)
	local oh = min(S.px(44), unit)
	local sh = min(S.px(50), unit * 1.15)
	local hoverCmd

	local ow = ((ix2 - ix1) - gap * (oCols - 1)) / oCols
	for i = 1, #orders do
		local cmd = orders[i]
		local col = (i - 1) % oCols
		local row = floor((i - 1) / oCols)
		local x1 = floor(ix1 + col * (ow + gap))
		local x2 = floor(x1 + ow)
		local y2 = floor(y - row * (oh + gap))
		local y1 = floor(y2 - oh)
		local over = Hovered(x1, y1, x2, y2, mx, my)
		local state = (cmd.id == activeID) and "active" or ((over and not cmd.disabled) and "hover" or nil)
		S.Button(x1, y1, x2, y2, state)
		if cmd.slateLabel ~= "" then
			S.Text(S.Fit(cmd.slateLabel, 12.5, ow - S.px(4)), (x1 + x2) * 0.5, y1 + oh * 0.36, 12.5, cmd.disabled and t.textDim or t.text, "cv")
		elseif cmd.texture and cmd.texture ~= "" then
			local inset = S.px(6)
			S.Icon(x1 + inset, y1 + inset, x2 - inset, y2 - inset, cmd.texture)
		end
		if cmd.slateKey and oh >= S.px(34) then
			S.Text(cmd.slateKey, x1 + S.px(4), y2 - S.px(12), 10, t.textDim)
		end
		AddHit(x1, y1, x2, y2, "order", cmd)
		if over then hoverCmd = cmd end
	end
	if oRows > 0 then y = y - oRows * (oh + gap) end

	local sw = ((ix2 - ix1) - gap * (sCols - 1)) / sCols
	for i = 1, #states do
		local cmd = states[i]
		local col = (i - 1) % sCols
		local row = floor((i - 1) / sCols)
		local x1 = floor(ix1 + col * (sw + gap))
		local x2 = floor(x1 + sw)
		local y2 = floor(y - row * (sh + gap))
		local y1 = floor(y2 - sh)
		local over = Hovered(x1, y1, x2, y2, mx, my)
		S.Button(x1, y1, x2, y2, (over and not cmd.disabled) and "hover" or nil)

		local cur = tonumber(cmd.params[1]) or 0
		local count = #cmd.params - 1
		local label = CleanName(cmd.params[cur + 2] or cmd.name)
		S.Text(S.Fit(label, 12, sw - S.px(4)), (x1 + x2) * 0.5, y1 + sh * 0.62, 12, t.text, "cv")

		-- pips: how far along the options this state is (on/off shows one pip)
		local pips = (count == 2) and 1 or count
		local lit = (count == 2) and cur or (cur + 1)
		local ph, pg = max(2, S.px(4)), S.px(3)
		local pw = min(S.px(14), floor((sw - S.px(10) - (pips - 1) * pg) / pips))
		local total = pips * pw + (pips - 1) * pg
		local px = floor((x1 + x2) * 0.5 - total * 0.5)
		local py = y1 + floor(sh * 0.18)
		for p = 1, pips do
			S.Rect(px, py, px + pw, py + ph, (p <= lit) and t.accent or t.track, ph * 0.5)
			px = px + pw + pg
		end
		AddHit(x1, y1, x2, y2, "state", cmd)
		if over then hoverCmd = cmd end
	end
	return hoverCmd
end

local cache
local lastHoverKey

-- Which hit rectangle is under the mouse (0 for none). The rectangles belong
-- to the current recording, so this is also what decides when to redo it.
local function HitIndexAt(mx, my)
	for i = #hits, 1, -1 do
		local h = hits[i]
		if mx >= h.x1 and mx <= h.x2 and my >= h.y1 and my <= h.y2 then return i end
	end
	return 0
end

function widget:DrawScreen()
	if WG.Slate ~= S or not bx1 then return end
	if dirty then
		Refresh()
		RefreshQueue()
		refreshCount = refreshCount + 1
	end

	local mx, my = spGetMouseState()
	local _, activeID = spGetActiveCommand()
	local showBuild = #builds > 0
	local showOrder = (#orders + #states) > 0
	if not showBuild then S.Unblur(BUILD_ID) end
	if not showOrder then S.Unblur(ORDER_ID) end

	-- The menus are the most expensive thing Slate draws, so they are recorded
	-- and only redone when the commands, the page or filter, the active
	-- command, the factory queue or the button under the mouse changes.
	local key = table.concat({
		S.version, refreshCount, page, filter and filter.label or "", activeID or 0,
		HitIndexAt(mx, my), queueSignature, bx1, by1, ox1, oy1,
	}, ":")
	cache = S.Cached(cache, key, function()
		hits = {}
		if showBuild then DrawBuildPanel(mx, my, activeID) end
		if showOrder then DrawOrderPanel(mx, my, activeID) end
	end)

	-- Tell the selection panel what the mouse is over, and the key bindings
	-- widget which button a Ctrl+Insert / Ctrl+Delete would apply to. Only
	-- when it changes, so the selection panel can keep its own recording.
	local h = hits[HitIndexAt(mx, my)]
	local cmd = h and (h.kind == "build" or h.kind == "order" or h.kind == "state") and h.data or nil
	local hoverKey = cmd and (h.kind .. ":" .. tostring(cmd.id)) or nil
	if hoverKey ~= lastHoverKey then
		lastHoverKey = hoverKey
		if cmd and h.kind == "build" then
			local ud = UnitDefs[-cmd.id]
			S.hover = { unitDefID = -cmd.id } ; myHover = true
			S.hoverAction = (cmd.action and cmd.action ~= "") and
				{ action = cmd.action, label = ud.translatedHumanName or ud.humanName or ud.name } or nil
		elseif cmd then
			S.hover = { title = CleanName(cmd.name), text = cmd.tooltip } ; myHover = true
			S.hoverAction = (cmd.action and cmd.action ~= "") and
				{ action = cmd.action, label = CleanName(cmd.name) } or nil
		elseif myHover then
			S.hover = nil ; S.hoverAction = nil ; myHover = false
		end
	end

	S.Flush()
end

--------------------------------------------------------------------------------
-- Mouse
--------------------------------------------------------------------------------

local function OverPanels(mx, my)
	if #builds > 0 and S.Inside(mx, my, bx1, by1, bx2, by2) then return "build" end
	if #orders + #states > 0 and S.Inside(mx, my, ox1, oy1, ox2, oy2) then return "order" end
	return nil
end

local function HitAt(mx, my)
	for i = #hits, 1, -1 do
		local h = hits[i]
		if mx >= h.x1 and mx <= h.x2 and my >= h.y1 and my <= h.y2 then return h end
	end
end

local function Apply(cmd, button)
	local index = spGetCmdDescIndex(cmd.id)
	if not index then return end
	local alt, ctrl, meta, shift = spGetModKeyState()
	spSetActiveCommand(index, button, button == 1, button == 3, alt, ctrl, meta, shift)
end

function widget:IsAbove(mx, my)
	if WG.Slate ~= S or not bx1 then return false end
	return OverPanels(mx, my) ~= nil
end

function widget:GetTooltip(mx, my)
	local h = HitAt(mx, my)
	if h and h.data and h.data.tooltip then return h.data.tooltip end
	return ""
end

function widget:MousePress(mx, my, button)
	if WG.Slate ~= S or not bx1 then return false end
	if not OverPanels(mx, my) then return false end
	pressed = HitAt(mx, my)
	return true
end

function widget:MouseRelease(mx, my, button)
	local h = HitAt(mx, my)
	local was = pressed
	pressed = nil
	if not (h and was) or h.kind ~= was.kind or h.data ~= was.data then return true end

	if h.kind == "build" or h.kind == "order" or h.kind == "state" then
		if not h.data.disabled then
			Apply(h.data, button)
			dirty = true
		end
	elseif h.kind == "chip" then
		filter = h.data.cat
		page = 1
		dirty = true
	elseif h.kind == "next" then
		page = min(pageCount, page + 1)
	elseif h.kind == "prev" then
		page = max(1, page - 1)
	end
	return true
end

function widget:MouseWheel(up)
	if WG.Slate ~= S or not bx1 or pageCount <= 1 or #builds == 0 then return false end
	local mx, my = spGetMouseState()
	if not S.Inside(mx, my, bx1, by1, bx2, by2) then return false end
	if up then page = max(1, page - 1) else page = min(pageCount, page + 1) end
	return true
end
