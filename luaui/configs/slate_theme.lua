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

	font         = "Saira_SemiCondensed-SemiBold.ttf",

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
	buttonRadius = 5,
}
