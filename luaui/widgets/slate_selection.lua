-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Selection Panel",
		desc    = "Shows the selected unit or group, the unit under the cursor, or what a build or order button does. Replaces the engine tooltip.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = 2,
		enabled = true,
	}
end

local ID = "selection"
local WIDTH, HEIGHT = 760, 128      -- design pixels
local PAD = 12
local MAX_GROUP_ICONS = 12

local spGetSelectedUnits       = Spring.GetSelectedUnits
local spGetSelectedUnitsCounts = Spring.GetSelectedUnitsCounts
local spGetUnitDefID           = Spring.GetUnitDefID
local spGetUnitHealth          = Spring.GetUnitHealth
local spGetUnitResources       = Spring.GetUnitResources
local spGetMouseState          = Spring.GetMouseState
local spTraceScreenRay         = Spring.TraceScreenRay
local spGetCurrentTooltip      = Spring.GetCurrentTooltip
local spIsGUIHidden            = Spring.IsGUIHidden
local floor = math.floor
local min, max = math.min, math.max

local S
local x1, y1, x2, y2
local wrapCache = {}
local wrapCount = 0

-- What to show, decided a few times a second (not every frame).
local view = nil
local viewVersion = 0
local cache
local timer = 1

--------------------------------------------------------------------------------

local function Layout()
	x1, y1, x2, y2 = S.Box(ID, "c", "b", 0, S.theme.margin, WIDTH, HEIGHT)
	wrapCache, wrapCount = {}, 0
end

local function UnitName(ud)
	return ud.translatedHumanName or ud.humanName or ud.name or "?"
end

local function UnitBlurb(ud)
	return ud.translatedTooltip or ud.tooltip or ""
end

-- Break text into at most `maxLines` lines no wider than `width` pixels.
local function Wrap(text, size, width, maxLines)
	local key = size .. "|" .. floor(width) .. "|" .. maxLines .. "|" .. text
	local hit = wrapCache[key]
	if hit then return hit end

	local lines = {}
	for paragraph in (text .. "\n"):gmatch("(.-)\r?\n") do
		local line = ""
		for word in paragraph:gmatch("%S+") do
			local try = (line == "") and word or (line .. " " .. word)
			if line ~= "" and S.TextWidth(try, size) > width then
				lines[#lines + 1] = line
				line = word
			else
				line = try
			end
		end
		if line ~= "" then lines[#lines + 1] = line end
	end
	while #lines > maxLines do lines[#lines] = nil end

	if wrapCount > 200 then wrapCache, wrapCount = {}, 0 end
	wrapCache[key] = lines
	wrapCount = wrapCount + 1
	return lines
end

--------------------------------------------------------------------------------
-- Deciding what to show
--------------------------------------------------------------------------------

local function StatCells(ud, res)
	local cells = {}
	local defs = S.game.unitStats or {}
	for i = 1, #defs do
		local ok, value = pcall(defs[i].value, ud, res)
		if ok and value then
			cells[#cells + 1] = { label = defs[i].label, value = value }
		end
	end
	return cells
end

local function UnitView(unitID, defID)
	local ud = UnitDefs[defID]
	if not ud then return nil end
	local health, maxHealth = spGetUnitHealth(unitID)
	local mm, mu, em, eu = spGetUnitResources(unitID)
	local res = mm and { mm, mu or 0, em or 0, eu or 0 } or nil
	return {
		kind = "unit", defID = defID, title = UnitName(ud), blurb = UnitBlurb(ud),
		health = health, maxHealth = maxHealth,
		cells = StatCells(ud, res),
	}
end

local function Decide()
	local hover = S.hover
	if hover and hover.unitDefID and UnitDefs[hover.unitDefID] then
		local ud = UnitDefs[hover.unitDefID]
		local cells = StatCells(ud, nil)
		cells[#cells + 1] = { label = "Build time", value = S.Number(ud.buildTime or 0) }
		return { kind = "unit", defID = hover.unitDefID, title = UnitName(ud), blurb = UnitBlurb(ud), cells = cells }
	elseif hover and (hover.title or hover.text) then
		return { kind = "text", title = hover.title or "", text = hover.text or "" }
	end

	-- a hint from whichever Slate panel the mouse is over
	local mx, my = spGetMouseState()
	local tipTitle, tipText = S.TipAt(mx, my)
	if tipTitle then
		return { kind = "text", title = tipTitle, text = tipText or "" }
	end

	local sel = spGetSelectedUnits() or {}
	if #sel == 1 then
		return UnitView(sel[1], spGetUnitDefID(sel[1]))
	elseif #sel > 1 then
		local counts = spGetSelectedUnitsCounts() or {}
		local types = {}
		for defID, n in pairs(counts) do
			if type(defID) == "number" and UnitDefs[defID] then
				types[#types + 1] = { defID = defID, count = n }
			end
		end
		table.sort(types, function(a, b)
			if a.count ~= b.count then return a.count > b.count end
			return a.defID < b.defID
		end)
		local health, maxHealth = 0, 0
		for i = 1, min(#sel, 300) do
			local h, m = spGetUnitHealth(sel[i])
			if h and m then health = health + h ; maxHealth = maxHealth + m end
		end
		return { kind = "group", total = #sel, types = types, health = health, maxHealth = maxHealth }
	end

	-- Nothing selected: describe what the cursor is on, if anything.
	local what, id = spTraceScreenRay(mx, my)
	if what == "unit" then
		local defID = spGetUnitDefID(id)
		if defID then return UnitView(id, defID) end
	end
	if what == "unit" or what == "feature" then
		local tip = spGetCurrentTooltip()
		if tip and tip ~= "" then
			local title, rest = tip:match("^([^\r\n]*)[\r\n]*(.*)$")
			return { kind = "text", title = title or "", text = rest or "" }
		end
	end
	return nil
end

--------------------------------------------------------------------------------

function widget:Initialize()
	S = WG.Slate
	if not S then
		widgetHandler:RemoveWidget()
		return
	end
	Spring.SendCommands("tooltip 0")
	if Spring.SetDrawSelectionInfo then Spring.SetDrawSelectionInfo(false) end
	S.Register(ID, "Selection", Layout)
	S.OnChange(ID, Layout)
	Layout()
end

function widget:Shutdown()
	Spring.SendCommands("tooltip 1")
	if Spring.SetDrawSelectionInfo then Spring.SetDrawSelectionInfo(true) end
	if S then
		S.Unregister(ID)
		S.OffChange(ID)
		S.Unblur(ID)
	end
end

function widget:ViewResize()
	if S and WG.Slate == S then Layout() end
end

function widget:Update(dt)
	timer = timer + dt
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function DrawCells(cells, cx1, cx2, baseY)
	local t = S.theme
	local n = min(#cells, 6)
	if n == 0 then return end
	local w = (cx2 - cx1) / max(n, 5)
	for i = 1, n do
		local x = cx1 + (i - 1) * w
		S.Text(cells[i].label:upper(), x, baseY + S.px(19), 11, t.textDim)
		S.Text(cells[i].value, x, baseY, 15, t.text)
	end
end

local function DrawHealth(cx1, cx2, y, health, maxHealth)
	local t = S.theme
	local label = S.Number(health) .. " / " .. S.Number(maxHealth)
	local lw = S.TextWidth(label, 14) + S.px(10)
	local bh = S.px(8)
	S.Bar(cx1, y, cx2 - lw, y + bh, (maxHealth > 0) and (health / maxHealth) or 0, t.good)
	S.Text(label, cx2, y - S.px(2), 14, t.text, "r")
end

local function DrawUnit(v)
	local t = S.theme
	local pad = S.px(PAD)
	local pic = (y2 - y1) - pad * 2
	local px1, py1 = x1 + pad, y1 + pad
	local picture = S.game.unitPicture
	S.Icon(px1, py1, px1 + pic, py1 + pic, picture and picture(v.defID) or ("#" .. v.defID))
	S.Outline(px1, py1, px1 + pic, py1 + pic, t.buttonBorder, S.px(t.buttonRadius), 1)

	local cx1, cx2 = px1 + pic + S.px(14), x2 - pad
	local ty = y2 - pad - S.px(18)
	S.Text(v.title, cx1, ty, 20, t.text)
	local tw = S.TextWidth(v.title, 20) + S.px(12)
	S.Text(S.Fit(v.blurb, 14, cx2 - cx1 - tw), cx1 + tw, ty, 14, t.textDim)

	if v.health and v.maxHealth then
		DrawHealth(cx1, cx2, ty - S.px(22), v.health, v.maxHealth)
	end
	DrawCells(v.cells, cx1, cx2, y1 + pad + S.px(4))
end

local function DrawGroup(v)
	local t = S.theme
	local pad = S.px(PAD)
	local cx1, cx2 = x1 + pad, x2 - pad
	local ty = y2 - pad - S.px(18)
	S.Text(v.total .. " units selected", cx1, ty, 20, t.text)
	if v.maxHealth > 0 then
		local tw = S.TextWidth(v.total .. " units selected", 20) + S.px(20)
		DrawHealth(cx1 + tw, cx2, ty + S.px(4), v.health, v.maxHealth)
	end

	local size = (ty - S.px(12)) - (y1 + pad)
	local gap = S.px(6)
	local picture = S.game.unitPicture
	local shown = min(#v.types, MAX_GROUP_ICONS)
	for i = 1, shown do
		local e = v.types[i]
		local ix = cx1 + (i - 1) * (size + gap)
		if ix + size > cx2 then break end
		S.Icon(ix, y1 + pad, ix + size, y1 + pad + size, picture and picture(e.defID) or ("#" .. e.defID))
		S.Outline(ix, y1 + pad, ix + size, y1 + pad + size, t.buttonBorder, S.px(t.buttonRadius), 1)
		local label = tostring(e.count)
		local bw = max(S.px(18), S.TextWidth(label, 12) + S.px(6))
		S.Rect(ix + size - bw, y1 + pad, ix + size, y1 + pad + S.px(17), { 0, 0, 0, 0.65 }, 0)
		S.Text(label, ix + size - bw * 0.5, y1 + pad + S.px(4), 12, t.text, "c")
	end
end

local function DrawText(v)
	local t = S.theme
	local pad = S.px(PAD)
	local cx1, cx2 = x1 + pad + S.px(4), x2 - pad - S.px(4)
	local ty = y2 - pad - S.px(18)
	S.Text(S.Fit(v.title, 18, cx2 - cx1), cx1, ty, 18, t.text)
	local lines = Wrap(v.text, 14, cx2 - cx1, 4)
	for i = 1, #lines do
		S.Text(lines[i], cx1, ty - S.px(4) - i * S.px(19), 14, t.textDim)
	end
end

function widget:DrawScreen()
	if WG.Slate ~= S or not x1 then return end
	if spIsGUIHidden and spIsGUIHidden() then return end

	-- Hover changes should feel instant; everything else can wait a moment.
	if timer > 0.15 or S.hover ~= (view and view.hoverRef) then
		timer = 0
		view = Decide()
		if view then view.hoverRef = S.hover end
		viewVersion = viewVersion + 1
	end

	if not view then
		S.Unblur(ID)
		return
	end

	cache = S.Cached(cache, S.version .. ":" .. viewVersion, function()
		S.Panel(x1, y1, x2, y2)
		S.Blur(ID, x1, y1, x2, y2)
		if view.kind == "unit" then DrawUnit(view)
		elseif view.kind == "group" then DrawGroup(view)
		else DrawText(view) end
	end)
	S.Flush()
end

function widget:IsAbove(mx, my)
	return WG.Slate == S and view ~= nil and S.Inside(mx, my, x1, y1, x2, y2) or false
end

function widget:GetTooltip()
	return ""
end

function widget:MousePress(mx, my)
	-- swallow clicks on the panel so they do not reach the map underneath
	return WG.Slate == S and view ~= nil and S.Inside(mx, my, x1, y1, x2, y2) or false
end
