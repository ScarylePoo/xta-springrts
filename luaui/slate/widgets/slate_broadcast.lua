-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.

function widget:GetInfo()
	return {
		name    = "Slate Broadcast",
		desc    = "Tells the other players' Slate your frame rate, system and camera position, and collects theirs for the players list (FPS column, system details, click-to-follow for spectators). Only works between players running Slate.",
		author  = "Scary le Poo",
		date    = "2026-10-10",
		license = "GNU GPL, v2 or later",
		layer   = -99000,
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- HOW THIS WORKS
--
-- Everything travels as interface-to-interface messages (Spring.SendLuaUIMsg /
-- widget:RecvLuaMsg), so no gadget and nothing in the game's rules is needed.
-- A message is "slate|<kind>|<payload>":
--
--   f  frame rate, to everyone, when it changes (at most every few seconds)
--   s  one line each for graphics card, system and screen size, to everyone,
--      at the start and again now and then for late joiners
--   c  camera state, to spectators only, a few times a second while it moves
--
-- What was received is published as WG.SlateBroadcast:
--   .fps[playerID]     number
--   .system[playerID]  { line, line, ... }
--   .camera[playerID]  { time = seconds since this widget started, state = table }
--   .now()             that same clock
--
-- The player can stop sending with the "Broadcast my camera, FPS and system"
-- setting (theme key `broadcast`). Receiving always works.
--------------------------------------------------------------------------------

local PREFIX = "slate|"
local FPS_PERIOD    = 4
local SYSTEM_PERIOD = 90
local CAMERA_PERIOD = 0.3

local spSendLuaUIMsg = Spring.SendLuaUIMsg
local floor = math.floor

local clock = 0
local fpsTimer, systemTimer, cameraTimer = FPS_PERIOD, SYSTEM_PERIOD - 3, 0
local lastFps, lastCamera

local data = { fps = {}, system = {}, camera = {} }
data.now = function() return clock end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

local function Enabled()
	local S = WG.Slate
	return not (S and S.theme and S.theme.broadcast == false)
end

local function Clean(s)
	return (tostring(s or ""):gsub("[|\r\n]", " "):gsub("%s+", " "):sub(1, 80))
end

local function SystemText()
	local P = Platform or {}
	local vsx, vsy = Spring.GetViewGeometry()
	local lines = {}
	if P.gpu and P.gpu ~= "" then
		local mem = tonumber(P.gpuMemorySize)
		lines[#lines + 1] = Clean(P.gpu) .. ((mem and mem > 0) and string.format(" (%.0f GB)", mem / (1024 * 1024)) or "")
	end
	if P.osName and P.osName ~= "" then lines[#lines + 1] = Clean(P.osName) end
	lines[#lines + 1] = vsx .. " x " .. vsy
	return table.concat(lines, "|")
end

local function CameraText()
	local state = Spring.GetCameraState()
	if type(state) ~= "table" or not state.name then return nil end
	local parts = { tostring(state.name) }
	local keys = {}
	for k, v in pairs(state) do
		if type(k) == "string" and type(v) == "number" then keys[#keys + 1] = k end
	end
	table.sort(keys)
	for i = 1, #keys do
		parts[#parts + 1] = keys[i] .. "=" .. string.format("%.3f", state[keys[i]]):gsub("%.?0+$", "")
	end
	return table.concat(parts, ";")
end

--------------------------------------------------------------------------------
-- Receiving. playerID comes from the engine, the rest is whatever the other
-- side sent, so nothing is trusted beyond numbers and short strings.
--------------------------------------------------------------------------------

local function ReadCamera(text)
	local state = {}
	local first = true
	for part in text:gmatch("[^;]+") do
		if first then
			if not part:match("^%a[%w_]*$") then return nil end
			state.name = part
			first = false
		else
			local k, v = part:match("^([%a_][%w_]*)=(-?[%d%.]+)$")
			v = tonumber(v)
			if k and v then state[k] = v end
		end
	end
	return state.name and state or nil
end

function widget:RecvLuaMsg(msg, playerID)
	if type(msg) ~= "string" or msg:sub(1, #PREFIX) ~= PREFIX or #msg > 1200 then return end
	local kind, payload = msg:match("^slate|(%a)|(.*)$")
	if kind == "f" then
		local n = tonumber(payload)
		if n and n >= 0 and n < 100000 then data.fps[playerID] = floor(n) end
	elseif kind == "s" then
		local lines = {}
		for line in payload:gmatch("[^|]+") do
			if #lines < 4 then lines[#lines + 1] = line:sub(1, 80) end
		end
		data.system[playerID] = lines
	elseif kind == "c" then
		local state = ReadCamera(payload)
		if state then
			data.camera[playerID] = { time = clock, state = state }
		end
	elseif kind == "x" then
		-- the player stopped broadcasting
		data.fps[playerID], data.system[playerID], data.camera[playerID] = nil, nil, nil
	end
end

function widget:PlayerRemoved(playerID)
	data.fps[playerID], data.camera[playerID] = nil, nil
end

--------------------------------------------------------------------------------

local wasEnabled = true

function widget:Initialize()
	WG.SlateBroadcast = data
end

function widget:Shutdown()
	WG.SlateBroadcast = nil
end

function widget:Update(dt)
	clock = clock + dt
	local enabled = Enabled()
	if enabled ~= wasEnabled then
		wasEnabled = enabled
		if not enabled then
			spSendLuaUIMsg(PREFIX .. "x|")
		else
			fpsTimer, systemTimer, lastFps, lastCamera = FPS_PERIOD, SYSTEM_PERIOD, nil, nil
		end
	end
	if not enabled then return end
	if Spring.IsReplay and Spring.IsReplay() then return end

	fpsTimer = fpsTimer + dt
	if fpsTimer >= FPS_PERIOD then
		fpsTimer = 0
		local fps = Spring.GetFPS() or 0
		if fps ~= lastFps then
			lastFps = fps
			spSendLuaUIMsg(PREFIX .. "f|" .. fps)
		end
	end

	systemTimer = systemTimer + dt
	if systemTimer >= SYSTEM_PERIOD then
		systemTimer = 0
		spSendLuaUIMsg(PREFIX .. "s|" .. SystemText())
	end

	-- spectators' own cameras are of no use to anyone
	cameraTimer = cameraTimer + dt
	if cameraTimer >= CAMERA_PERIOD and not Spring.GetSpectatingState() then
		cameraTimer = 0
		local text = CameraText()
		if text and text ~= lastCamera then
			lastCamera = text
			spSendLuaUIMsg(PREFIX .. "c|" .. text, "s")
		end
	end
end
