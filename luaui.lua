-- LuaUI bootstrap for Recoil: the engine only loads LuaUI from the game archive,
-- so XTA ships the stock widget handler itself (see luaui/main.lua).
LUAUI_VERSION = "LuaUI v0.3"
LUAUI_DIRNAME = 'LuaUI/'
VFS.DEF_MODE = VFS.RAW_FIRST
Spring.Echo('Using LUAUI_DIRNAME = ' .. LUAUI_DIRNAME)

-- Recoil dropped the 'n' count key from these tables (it is now the second
-- return value). XTA's widgets were written against Spring 104, so restore it.
do
  local function withN(fn)
    return function(...)
      local t, n = fn(...)
      if type(t) == 'table' then t.n = n end
      return t, n
    end
  end
  Spring.GetSelectedUnitsCounts = withN(Spring.GetSelectedUnitsCounts)
  Spring.GetSelectedUnitsSorted = withN(Spring.GetSelectedUnitsSorted)
end

VFS.Include(LUAUI_DIRNAME .. 'main.lua', nil, VFS.ZIP_FIRST)
