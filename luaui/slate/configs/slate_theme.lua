--------------------------------------------------------------------------------
-- Slate theme
--
-- Every colour, opacity and size the Slate panels use lives here. A game that
-- adopts Slate restyles it by editing this one file; no panel widget hardcodes
-- a colour.
--
-- Sizes are in pixels at a 1080-pixel-high screen and scale with resolution.
-- Colours are {r, g, b, a}.
--------------------------------------------------------------------------------

return {
	-- Panel glass. `opacity` is the alpha of the panel body (0 = invisible,
	-- 1 = solid). Players can change it in game with "/slate opacity 0.6".
	opacity      = 0.60,
	-- Blur the game world behind panels (needs the GUI-Shader widget, which
	-- Slate switches on when this is true). "/slate blur" toggles it.
	blur         = true,
	-- Overall size multiplier on top of resolution scaling.
	scale        = 1.0,
	-- Minimap size multiplier. Players change it in the settings screen or by
	-- dragging the corner grip in tweak mode (Ctrl+F11).
	minimapSize  = 1.0,

	font         = "Saira_SemiCondensed-SemiBold.ttf",

	-- Colour tint. `tint` names one of the entries in `tints`; `tintStrength`
	-- (0-1) is how far the panel glass, borders and accent lean towards it.
	-- Players pick both in the settings screen.
	tint         = "None",
	tintStrength = 0.5,
	tints = {
		{ name = "None" },
		{ name = "Blue",   color = { 0.20, 0.45, 0.95 } },
		{ name = "Teal",   color = { 0.10, 0.70, 0.65 } },
		{ name = "Green",  color = { 0.25, 0.72, 0.30 } },
		{ name = "Amber",  color = { 0.95, 0.62, 0.15 } },
		{ name = "Red",    color = { 0.90, 0.25, 0.22 } },
		{ name = "Pink",   color = { 0.95, 0.40, 0.70 } },
		{ name = "Purple", color = { 0.58, 0.36, 0.92 } },
	},

	panel        = { 0.050, 0.055, 0.063 },          -- body colour (alpha = opacity)
	border       = { 1.00, 1.00, 1.00, 0.14 },
	radius       = 8,
	margin       = 16,                                -- gap from the screen edge
	gap          = 16,                                -- gap between stacked panels

	accent       = { 0.663, 0.741, 0.816, 1.0 },      -- headings, active filter, state pips
	text         = { 0.925, 0.933, 0.941, 1.0 },
	textDim      = { 0.710, 0.729, 0.757, 1.0 },
	good         = { 0.608, 0.906, 0.659, 1.0 },      -- income, health
	bad          = { 1.000, 0.702, 0.651, 1.0 },      -- drain
	warn         = { 0.949, 0.761, 0.188, 1.0 },      -- active build order, queue badge

	button       = { 1.00, 1.00, 1.00, 0.07 },
	buttonBorder = { 1.00, 1.00, 1.00, 0.13 },
	buttonHover  = { 1.00, 1.00, 1.00, 0.16 },
	buttonActive = { 1.00, 1.00, 1.00, 0.20 },
	buttonOff    = { 0.00, 0.00, 0.00, 0.55 },        -- overlay on disabled buttons
	track        = { 1.00, 1.00, 1.00, 0.10 },        -- empty part of a bar

	-- Chat: the body colour per channel. Names take their team colour;
	-- spectators, who have none, use spectatorName.
	chat = {
		public        = { 1.00, 1.00, 1.00, 1 },
		ally          = { 0.45, 1.00, 0.50, 1 },
		whisper       = { 1.00, 0.50, 0.50, 1 },
		spectator     = { 1.00, 0.95, 0.40, 1 },
		event         = { 0.55, 0.82, 1.00, 1 },   -- speed changes, pause
		system        = { 0.75, 0.75, 0.75, 1 },   -- engine console output
		spectatorName = { 0.85, 0.85, 0.85, 1 },
	},

	-- Two-series charts (income against demand). Checked to stay distinct for
	-- colour-blind players on a dark panel; team charts use team colours.
	chartA       = { 0.239, 0.545, 0.910, 1.0 },
	chartB       = { 0.851, 0.467, 0.184, 1.0 },
	chartGrid    = { 1.00, 1.00, 1.00, 0.08 },
	buttonRadius = 5,
}
