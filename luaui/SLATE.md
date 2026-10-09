# Slate

A game-neutral in-game UI for Total Annihilation style games on the Recoil
engine. Dark translucent panels, no faction styling. Derived from the Static
GUI suite in Splinter Faction (same author, GPL v2 or later).

## What is in it

| File | Purpose |
|---|---|
| `widgets/slate_api_draw.lua` | Batched shape renderer (rounded rects, outlines, icons) |
| `widgets/slate_api_layout.lua` | Drag panels in tweak mode (Ctrl+F11); positions are saved |
| `widgets/slate_api_core.lua` | Loads the two config files; shared scaling, font and drawing helpers |
| `widgets/slate_resourcebar.lua` | Metal and energy, share-level marker, optional wind and tidal read-outs |
| `widgets/slate_commands.lua` | Build grid (filters, paging, queue counts) and order/state buttons |
| `widgets/slate_selection.lua` | Selected unit or group, unit under cursor, build/order descriptions |
| `widgets/slate_playerslist.lua` | Players by team with resource levels and ping |
| `widgets/slate_chat.lua` | Recent chat and messages as outlined text |
| `widgets/slate_topbar.lua` | Clock, speed, frame rate, Menu |
| `widgets/slate_minimap.lua` | Pins the engine minimap top-left, sized to the map, and frames it (not draggable) |
| `widgets/slate_settings.lua` | Settings window: interface look (opacity, blur, colour tint, size), graphics, sound |
| `widgets/slate_widgetlist.lua` | Widget list on F11 |
| `widgets/slate_econgraph.lua` | Income and demand over time, one chart per resource |
| `widgets/slate_teamstats.lua` | Per-team statistics over the game; opens at game end |
| `widgets/slate_keybinds.lua` | View and change key bindings; changes are saved and re-applied |
| `widgets/slate_share.lua` | Give resources or selected units to an ally |
| `configs/slate_theme.lua` | Every colour, opacity and size |
| `configs/slate_game.lua` | Everything specific to the game |
| `fonts/Saira_SemiCondensed-SemiBold.ttf` | UI font (SIL Open Font License) |

## Using it in another game

1. Copy the files above into the game's `luaui/` folder.
2. Edit `configs/slate_game.lua`: resources, build categories, hidden commands,
   unit stats, menu entries.
3. Edit `configs/slate_theme.lua` to taste.
4. Disable or remove any widgets that draw the same things (resource bar,
   build menu, tooltip, console, player list, minimap frame).

Slate needs the stock LuaUI widget handler and nothing else from the game. Blur
behind panels uses a `GUI-Shader` widget (`WG['guishader_api']`) if the game
has one and is skipped otherwise.

## In-game commands

| Command | Effect |
|---|---|
| `/slate settings` | Open the settings window (also in the Menu) |
| `/slate widgets` | Open the widget list (also F11) |
| `/slate economy` | Open the economy graph |
| `/slate stats` | Open team statistics |
| `/slate keys` | Open key bindings |
| `/slate share` | Open the share window (or click an ally in the players list) |
| `/slate opacity 0.6` | Panel opacity, 0.1 to 1 |
| `/slate blur` | Toggle blur behind panels |
| `/slate wind` | Toggle the wind read-out |
| `/slate tidal` | Toggle the tidal read-out (only shown on maps with water) |
| `/resetlayout` | Put every panel back in its default place |
| Ctrl+F11 | Tweak mode: drag panels, right-click one to reset it |

These choices are saved per player. Colour tints are listed in
`slate_theme.lua` (`tints`); add or change entries there.
