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
| `widgets/slate_chat.lua` | On-screen chat with team-coloured names and a colour per channel; console output is kept out |
| `widgets/slate_chatlog.lua` | Scrollback window with Chat / Console / All tabs |
| `widgets/slate_topbar.lua` | Clock, speed, frame rate, Menu |
| `widgets/slate_minimap.lua` | Pins the engine minimap top-left, sized to the map, and frames it (not draggable) |
| `widgets/slate_settings.lua` | Settings window: interface look (opacity, blur, colour tint, size), graphics, sound |
| `widgets/slate_widgetlist.lua` | Widget list on F11 |
| `widgets/slate_econgraph.lua` | Income and demand over time, one chart per resource |
| `widgets/slate_teamstats.lua` | End-of-game graph: a line per team for eight statistics; replaces the engine's |
| `widgets/slate_ecostats.lua` | Spectators only: every team's income side by side with alliance totals |
| `widgets/slate_keybinds.lua` | View and change key bindings; changes go to a per-game file (see below) |
| `widgets/slate_share.lua` | Give resources or selected units to an ally |
| `configs/slate_theme.lua` | Every colour, opacity and size |
| `configs/slate_game.lua` | Everything specific to the game |
| `fonts/Saira_SemiCondensed-SemiBold.ttf` | UI font (SIL Open Font License) |

## Using it in another game

Everything Slate needs is in this one folder (`luaui/slate/`): `widgets/`,
`configs/` and `fonts/`. Nothing in it names the game it sits in.

1. Copy the `luaui/slate/` folder into the game.
2. Make the game's widget handler load widgets from `luaui/slate/widgets/` as
   well. It is two small edits; [HANDLER.md](HANDLER.md) has them line for line.
3. Copy `configs/slate_game.lua` to the game's own `luaui/configs/` and edit it
   there: resources, build categories, hidden commands, unit stats, menu
   entries. Do the same with `slate_theme.lua` to change the look. A file in
   `luaui/configs/` is read in preference to the one in this folder, so the
   folder can later be swapped for a newer Slate without losing the game's
   settings. (Editing the files in place works too.)
4. Disable or remove any widgets that draw the same things (resource bar,
   build menu, tooltip, console, player list, minimap frame).

To take Slate out again, delete the folder and the lines from step 2.

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
| `/slate log` | Open the chat log |
| `/slate keys` | Open key bindings |
| Ctrl+Insert | While hovering a build or order button: bind it to the next key pressed |
| Ctrl+Delete | While hovering a build or order button: remove its key |
| `/slate share` | Open the share window (or click an ally in the players list) |
| `/slate opacity 0.6` | Panel opacity, 0.1 to 1 |
| `/slate blur` | Toggle blur behind panels |
| `/slate wind` | Toggle the wind read-out |
| `/slate tidal` | Toggle the tidal read-out (only shown on maps with water) |
| `/resetlayout` | Put every panel back in its default place |
| Ctrl+F11 | Tweak mode: drag panels, right-click one to reset it |

These choices are saved per player. Colour tints are listed in
`configs/slate_theme.lua` (`tints`); add or change entries there.

## Key binding files

Slate never writes to the player's `uikeys.txt`. Bindings are layered:

1. the engine defaults and the player's own `uikeys.txt`;
2. `luaui/configs/<game>_keys.txt` in the game archive, if the game ships one;
3. `<game>_uikeys.txt` in the player's Recoil folder, holding changes made in game.

`<game>` is the game's short name in lower case (`xta_uikeys.txt` here), so
several games on one install keep separate changes.
