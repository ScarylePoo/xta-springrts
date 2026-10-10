# Widget handler changes for Slate

The stock LuaUI widget handler only loads widgets from `LuaUI/Widgets/` and
does not look inside subfolders. Slate keeps its widgets in
`luaui/slate/widgets/`, so the handler needs two small edits. Nothing else in
the game has to change.

Both edits are already made in XTA; this file is for adding Slate to another
game.

## 1. `luaui/widgets.lua`: scan the Slate folder too

In `widgetHandler:Initialize()`, find the loop that loads the game's widgets:

```lua
  -- stuff the zip widgets into unsortedWidgets
  local widgetFiles = VFS.DirList(WIDGET_DIRNAME, "*.lua", VFS.ZIP_ONLY)
  for k,wf in ipairs(widgetFiles) do
    local widget = self:LoadWidget(wf, true)
    if (widget) then
      table.insert(unsortedWidgets, widget)
    end
  end
```

Directly after it, and before the `table.sort(unsortedWidgets, ...)` that
follows, add:

```lua
  -- Slate
  for k,wf in ipairs(VFS.DirList(LUAUI_DIRNAME .. 'Slate/Widgets/', "*.lua", VFS.ZIP_ONLY)) do
    local widget = self:LoadWidget(wf, true)
    if (widget) then
      table.insert(unsortedWidgets, widget)
    end
  end
```

(XTA's copy does the same thing through a small `SUITE_WIDGET_DIRS` list at the
top of the file, so further folders can be added in one place.)

## 2. `luaui/main.lua`: make sure the game's handler is the one that runs

Engine installs usually carry their own loose `LuaUI/widgets.lua`. The stock
`main.lua` loads the handler with

```lua
include("widgets.lua")  -- the widget handler
```

which prefers that loose file over the game's copy, so the edit in step 1 would
never run. Replace the line with:

```lua
VFS.Include(LUAUI_DIRNAME .. "widgets.lua", nil, VFS.ZIP_FIRST)
```

This only works if `main.lua` itself is loaded from the game. A game that ships
its own LuaUI already does this from `luaui.lua`:

```lua
VFS.Include(LUAUI_DIRNAME .. 'main.lua', nil, VFS.ZIP_FIRST)
```

## Checking it worked

Start a game and open the widget list (F11). The entries whose names start with
"Slate" should be listed and on. If the engine's plain resource bar and build
menu are showing instead, the handler from step 1 is not the one being run;
recheck step 2.

## Removing Slate

Delete the `luaui/slate/` folder and the lines added in step 1. The change in
step 2 is harmless to leave.

## Other handlers

A handler based on a different codebase (Beyond All Reason's, for example) needs
the same idea in its own terms: one more directory in whatever list or loop it
uses to find widget files.
