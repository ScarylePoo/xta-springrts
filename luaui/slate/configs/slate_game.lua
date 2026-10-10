--------------------------------------------------------------------------------
-- Slate game config
--
-- Everything Slate needs to know about the game it is running in. The panel
-- widgets read only this table, so adopting Slate in another Total
-- Annihilation style game means copying the slate_* widgets plus the two
-- slate_*.lua config files, then editing this one.
--------------------------------------------------------------------------------

local function HasWeapons(ud)
	return ud.weapons and #ud.weapons > 0
end

local function IsEconomy(ud)
	if ud.isFactory or HasWeapons(ud) then return false end
	return (ud.extractsMetal or 0) > 0
		or (ud.energyMake or 0) > 0 or (ud.metalMake or 0) > 0
		or (ud.windGenerator or 0) > 0 or (ud.tidalGenerator or 0) > 0
		or (ud.energyStorage or 0) > 0 or (ud.metalStorage or 0) > 0
		or (ud.energyUpkeep or 0) < 0 or (ud.makesMetal or 0) > 0
end

return {
	-- Resources shown in the resource bar, left to right. `key` is the engine
	-- resource name passed to Spring.GetTeamResources.
	resources = {
		{ key = "metal",  label = "Metal",  color = { 0.788, 0.827, 0.871, 1 } },
		{ key = "energy", label = "Energy", color = { 0.949, 0.831, 0.361, 1 } },
	},

	-- Optional read-outs under the resource bar. Players toggle them with
	-- "/slate wind" and "/slate tidal". Tidal hides itself on maps without water.
	addons = {
		wind  = true,
		tidal = true,
	},

	-- Build menu. Filters are offered only when the current builder has at
	-- least one matching entry; "All" is always first.
	buildColumns = 4,
	buildRows    = 5,
	buildCategories = {
		{ label = "Economy",   match = IsEconomy },
		{ label = "Defence",   match = function(ud) return ud.isBuilding and HasWeapons(ud) end },
		{ label = "Factories", match = function(ud) return ud.isFactory end },
		{ label = "Units",     match = function(ud) return not ud.isImmobile end },
	},
	-- Picture for a build tile or the selection panel.
	unitPicture = function(unitDefID) return "#" .. unitDefID end,

	-- Commands never shown in the order grid (matched against the command's
	-- action name). The engine still accepts them from hotkeys.
	hiddenCommands = {
		timewait = true, deathwait = true, squadwait = true, gatherwait = true,
		loadonto = true, selfd = true,
	},
	orderColumns = 5,
	stateColumns = 4,

	-- Stat cells in the selection panel for a single unit. Each entry returns a
	-- string, or nil to leave the cell out. `res` is { metalMake, metalUse,
	-- energyMake, energyUse } for a live unit, nil for a build-menu preview.
	unitStats = {
		{ label = "Metal",  value = function(ud, res)
			if res then return string.format("%+.1f", res[1] - res[2]) end
			return string.format("%d", ud.metalCost)
		end },
		{ label = "Energy", value = function(ud, res)
			if res then return string.format("%+.0f", res[3] - res[4]) end
			return string.format("%d", ud.energyCost)
		end },
		{ label = "Build power", value = function(ud)
			if (ud.buildSpeed or 0) > 0 then return string.format("%d", ud.buildSpeed) end
		end },
		{ label = "Speed", value = function(ud)
			if (ud.speed or 0) > 0 then return string.format("%d", ud.speed) end
		end },
		{ label = "Range", value = function(ud)
			if (ud.maxWeaponRange or 0) > 0 then return string.format("%d", ud.maxWeaponRange) end
		end },
	},

	-- Start each game in line-of-sight view (the L key view that shades what
	-- you cannot see). Players can still switch it off.
	losView = true,

	-- Sounds for incoming chat by channel (public, ally, spectator, whisper),
	-- as names for Spring.PlaySoundFile. Leave nil for silence.
	chatSounds = nil,

	-- Entries in the Menu dropdown. `command` goes to Spring.SendCommands.
	menu = {
		{ label = "Settings",        command = "slate settings" },
		{ label = "Economy graph",   command = "slate economy" },
		{ label = "Team statistics", command = "slate stats" },
		{ label = "Share (H)",       command = "slate share" },
		{ label = "Chat log",        command = "slate log" },
		{ label = "Key bindings",    command = "slate keys" },
		{ label = "Widgets (F11)",   command = "slate widgets" },
		{ label = "Pause",           command = "pause" },
		{ label = "Quit",            command = "quitmenu" },
	},
}
