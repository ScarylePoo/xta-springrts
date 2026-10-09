-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.
-- Derived from the Static GUI suite in Splinter Faction (same author, GPL v2+).

function widget:GetInfo()
	return {
		name    = "Slate Share",
		desc    = "Give resources or your selected units to an ally. Click an ally in the players list, use the Menu, or /slate share.",
		author  = "Scary le Poo",
		date    = "2026-10-08",
		license = "GNU GPL, v2 or later",
		layer   = -15,
		enabled = true,
	}
end

local ID = "share"
local WIDTH, HEIGHT = 520, 460      -- design pixels
local ROW_H = 34

local floor = math.floor
local min, max = math.min, math.max

local S
local open = false
local closeRect
local wx1, wy1, wx2, wy2
local hits = {}
local allies = {}                   -- { teamID, name, color }
local target                        -- teamID
local fraction = {}                 -- per resource key: 0-1 of what is stored
local drag                          -- { key, x1, x2 }
local notice = ""
local timer = 10

--------------------------------------------------------------------------------

local function TeamName(teamID)
	local _, leader, _, isAI = Spring.GetTeamInfo(teamID, false)
	if isAI then
		local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
		return (aiName and aiName ~= "" and aiName ~= "UNKNOWN") and aiName or shortName or "AI"
	end
	return Spring.GetPlayerInfo(leader or -1, false) or ("Team " .. teamID)
end

local function Rebuild()
	allies = {}
	local myTeam = Spring.GetMyTeamID()
	local teams = Spring.GetTeamList(Spring.GetMyAllyTeamID()) or {}
	local found = false
	for i = 1, #teams do
		local teamID = teams[i]
		local _, _, isDead = Spring.GetTeamInfo(teamID, false)
		if teamID ~= myTeam and not isDead then
			local r, g, b = Spring.GetTeamColor(teamID)
			allies[#allies + 1] = { teamID = teamID, name = TeamName(teamID), color = { r or 1, g or 1, b or 1, 1 } }
			if teamID == target then found = true end
		end
	end
	if not found then target = allies[1] and allies[1].teamID or nil end
end

local function Close()
	open = false
	drag = nil
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
	if command:sub(1, 11) ~= "slate share" then return false end
	if WG.Slate ~= S then return false end
	local wanted = tonumber(command:match("^slate share%s+(%d+)"))
	if open and not wanted then
		Close()
	else
		open = true
		notice = ""
		if wanted then target = wanted end
		Rebuild()
	end
	return true
end

function widget:Update(dt)
	if not open then return end
	timer = timer + dt
	if timer > 1 then timer = 0 ; Rebuild() end
end

--------------------------------------------------------------------------------

local function FractionAt(x1, x2, mx)
	return floor(min(1, max(0, (mx - x1) / (x2 - x1))) * 20 + 0.5) / 20
end

function widget:DrawScreen()
	if not open or WG.Slate ~= S then return end
	local t = S.theme
	local mx, my = Spring.GetMouseState()
	hits = {}

	local top
	wx1, wy1, wx2, top, closeRect = S.Window(ID, WIDTH, HEIGHT, "Share with an ally", mx, my)
	wy2 = top + S.px(44)

	local pad = S.px(18)
	local x1, x2 = wx1 + pad, wx2 - pad
	local y = top - S.px(14)
	local rh = S.px(ROW_H)

	if Spring.GetSpectatingState() then
		S.Text("Spectators cannot share.", x1, y - rh * 0.5, 14, t.textDim, "v")
		S.Flush()
		return
	end
	if #allies == 0 then
		S.Text("You have no allies in this game.", x1, y - rh * 0.5, 14, t.textDim, "v")
		S.Flush()
		return
	end

	-- who receives
	S.Text("GIVE TO", x1, y - S.px(8), 12, t.accent, "v")
	y = y - S.px(22)
	local shown = min(#allies, 5)
	for i = 1, shown do
		local a = allies[i]
		local on = (a.teamID == target)
		local over = S.Inside(mx, my, x1, y - rh + 2, x2, y - 2)
		S.Button(x1, y - rh + 2, x2, y - 2, on and "active" or (over and "hover" or nil))
		local sw = S.px(12)
		local mid = y - rh * 0.5
		S.Rect(x1 + S.px(10), mid - sw * 0.5, x1 + S.px(10) + sw, mid + sw * 0.5, a.color, S.px(2))
		S.Text(S.Fit(a.name, 14, x2 - x1 - S.px(50)), x1 + S.px(32), mid, 14, t.text, "v")
		hits[#hits + 1] = { x1 = x1, y1 = y - rh, x2 = x2, y2 = y, team = a.teamID }
		y = y - rh
	end
	if #allies > shown then
		S.Text("+" .. (#allies - shown) .. " more: click them in the players list", x1, y - S.px(10), 12, t.textDim, "v")
		y = y - S.px(20)
	end
	y = y - S.px(14)

	-- resources: a slider for how much of what you hold, and a Give button
	local myTeam = Spring.GetMyTeamID()
	local resources = S.game.resources or {}
	local giveW = S.px(90)
	for i = 1, #resources do
		local res = resources[i]
		local stored = Spring.GetTeamResources(myTeam, res.key) or 0
		local frac = fraction[res.key] or 0.25
		local amount = floor(stored * frac)
		local mid = y - rh * 0.5

		S.Text(res.label:upper(), x1, mid, 12, res.color, "v")
		local sx1, sx2 = x1 + S.px(80), x2 - giveW - S.px(100)
		local h = S.px(6)
		S.Bar(sx1, mid - h * 0.5, sx2, mid + h * 0.5, frac, res.color)
		local kx = sx1 + (sx2 - sx1) * frac
		local kr = S.px(8)
		S.Rect(kx - kr, mid - kr, kx + kr, mid + kr, t.text, kr)
		S.Text(S.Number(amount), sx2 + S.px(14), mid, 14, t.text, "v")
		local slop = S.px(12)
		hits[#hits + 1] = { x1 = sx1 - slop, y1 = mid - slop, x2 = sx2 + slop, y2 = mid + slop, slider = res.key, sx1 = sx1, sx2 = sx2 }

		local gx1 = x2 - giveW
		local can = amount > 0 and target
		local over = can and S.Inside(mx, my, gx1, y - rh + 3, x2, y - 3)
		S.Button(gx1, y - rh + 3, x2, y - 3, over and "hover" or nil)
		S.Text("Give", (gx1 + x2) * 0.5, mid, 13, can and t.text or t.textDim, "cv")
		if can then
			hits[#hits + 1] = { x1 = gx1, y1 = y - rh, x2 = x2, y2 = y, give = res, amount = amount }
		end
		y = y - rh - S.px(4)
	end
	y = y - S.px(10)

	-- selected units
	local count = Spring.GetSelectedUnitsCount() or 0
	local label = (count > 0) and ("Give " .. count .. " selected unit" .. (count == 1 and "" or "s")) or "Select units to give them"
	local over = count > 0 and S.Inside(mx, my, x1, y - rh, x2, y)
	S.Button(x1, y - rh, x2, y, over and "hover" or nil)
	S.Text(label, (x1 + x2) * 0.5, y - rh * 0.5, 14, (count > 0) and t.text or t.textDim, "cv")
	if count > 0 and target then
		hits[#hits + 1] = { x1 = x1, y1 = y - rh, x2 = x2, y2 = y, units = count }
	end

	S.Text(S.Fit(notice ~= "" and notice or "Gifts cannot be taken back.", 13, x2 - x1), x1, wy1 + S.px(20), 13, t.textDim, "v")
	S.Flush()
end

--------------------------------------------------------------------------------

local function InWindow(mx, my)
	return open and wx1 and S.Inside(mx, my, wx1, wy1, wx2, wy2)
end

local function TargetName()
	for i = 1, #allies do
		if allies[i].teamID == target then return allies[i].name end
	end
	return "ally"
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
			if h.team then
				target = h.team
			elseif h.slider then
				drag = { key = h.slider, x1 = h.sx1, x2 = h.sx2 }
				fraction[h.slider] = FractionAt(h.sx1, h.sx2, mx)
			elseif h.give and target then
				Spring.ShareResources(target, h.give.key, h.amount)
				notice = "Gave " .. S.Number(h.amount) .. " " .. h.give.label:lower() .. " to " .. TargetName() .. "."
			elseif h.units and target then
				Spring.ShareResources(target, "units")
				notice = "Gave " .. h.units .. " unit" .. (h.units == 1 and "" or "s") .. " to " .. TargetName() .. "."
			end
			break
		end
	end
	return true
end

function widget:MouseMove(mx)
	if drag then
		fraction[drag.key] = FractionAt(drag.x1, drag.x2, mx)
		return true
	end
end

function widget:MouseRelease()
	drag = nil
	return true
end

function widget:KeyPress(key)
	if open and key == 27 then   -- Esc
		Close()
		return true
	end
	return false
end
