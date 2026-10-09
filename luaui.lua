-- LuaUI bootstrap for Recoil: the engine only loads LuaUI from the game archive,
-- so XTA ships the stock widget handler itself (see luaui/main.lua).
LUAUI_VERSION = "LuaUI v0.3"
LUAUI_DIRNAME = 'LuaUI/'
VFS.DEF_MODE = VFS.RAW_FIRST
Spring.Echo('Using LUAUI_DIRNAME = ' .. LUAUI_DIRNAME)
VFS.Include(LUAUI_DIRNAME .. 'main.lua', nil, VFS.ZIP_FIRST)
