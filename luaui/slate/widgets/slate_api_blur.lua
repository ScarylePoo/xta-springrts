-- Part of Slate, a game-neutral UI suite for Total Annihilation style games.

function widget:GetInfo()
	return {
		name    = "Slate Blur",
		desc    = "Blurs the game world behind Slate panels. Switch it off here or in the settings for a little more speed.",
		author  = "Scary le Poo",
		date    = "2026-10-09",
		license = "GNU GPL, v2 or later",
		layer   = -99990,
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- HOW THIS WORKS
--
-- After the world is drawn and before any interface, the frame is copied once
-- and shrunk in steps (1/2, 1/4, 1/8), then grown back to 1/2 size, blurring a
-- little at every step ("dual Kawase" blur). Because nearly all the work is
-- done on small images, a wide, smooth blur costs less than one full-screen
-- pass. The blurred image is then drawn only inside the rectangles the panels
-- asked for through WG.Slate.Blur(); the rest of the screen is not touched.
--
-- Nothing is done at all while no panel wants blur or blur is switched off.
-- If the graphics card cannot do it, the widget removes itself and panels are
-- simply drawn without blur.
--------------------------------------------------------------------------------

local LEVELS = 3                    -- 1/2, 1/4, 1/8
local INSET  = 2                    -- keep clear of the panels' rounded corners

local glTexture         = gl.Texture
local glTexRect         = gl.TexRect
local glUseShader       = gl.UseShader
local glUniform         = gl.Uniform
local glRenderToTexture = gl.RenderToTexture
local glCopyToTexture   = gl.CopyToTexture
local floor = math.floor
local max = math.max

local vsx, vsy = Spring.GetViewGeometry()
local copyTex
local down = {}                     -- [level] = { tex, w, h }
local up = {}                       -- [level] = { tex, w, h } for levels 1 .. LEVELS-1
local downShader, upShader
local downHalf, upHalf

local FRAG_DOWN = [[
#version 150 compatibility
uniform sampler2D tex0;
uniform vec2 halfpixel;
void main() {
	vec2 uv = gl_TexCoord[0].st;
	vec4 sum = texture2D(tex0, uv) * 4.0;
	sum += texture2D(tex0, uv - halfpixel);
	sum += texture2D(tex0, uv + halfpixel);
	sum += texture2D(tex0, uv + vec2(halfpixel.x, -halfpixel.y));
	sum += texture2D(tex0, uv - vec2(halfpixel.x, -halfpixel.y));
	gl_FragColor = vec4(sum.rgb / 8.0, 1.0);
}
]]

local FRAG_UP = [[
#version 150 compatibility
uniform sampler2D tex0;
uniform vec2 halfpixel;
void main() {
	vec2 uv = gl_TexCoord[0].st;
	vec4 sum = texture2D(tex0, uv + vec2(-halfpixel.x * 2.0, 0.0));
	sum += texture2D(tex0, uv + vec2(-halfpixel.x, halfpixel.y)) * 2.0;
	sum += texture2D(tex0, uv + vec2(0.0, halfpixel.y * 2.0));
	sum += texture2D(tex0, uv + vec2(halfpixel.x, halfpixel.y)) * 2.0;
	sum += texture2D(tex0, uv + vec2(halfpixel.x * 2.0, 0.0));
	sum += texture2D(tex0, uv + vec2(halfpixel.x, -halfpixel.y)) * 2.0;
	sum += texture2D(tex0, uv + vec2(0.0, -halfpixel.y * 2.0));
	sum += texture2D(tex0, uv + vec2(-halfpixel.x, -halfpixel.y)) * 2.0;
	gl_FragColor = vec4(sum.rgb / 12.0, 1.0);
}
]]

--------------------------------------------------------------------------------

local function FreeTextures()
	if copyTex then gl.DeleteTexture(copyTex) end
	copyTex = nil
	for _, list in ipairs({ down, up }) do
		for _, e in pairs(list) do
			if e.tex then (gl.DeleteTextureFBO or gl.DeleteTexture)(e.tex) end
		end
	end
	down, up = {}, {}
end

local function Target(w, h)
	local tex = gl.CreateTexture(w, h, {
		border = false, fbo = true,
		min_filter = GL.LINEAR, mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE, wrap_t = GL.CLAMP_TO_EDGE,
	})
	return tex and { tex = tex, w = w, h = h } or nil
end

local function MakeTextures()
	FreeTextures()
	copyTex = gl.CreateTexture(vsx, vsy, {
		border = false,
		min_filter = GL.LINEAR, mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE, wrap_t = GL.CLAMP_TO_EDGE,
	})
	if not copyTex then return false end
	local w, h = vsx, vsy
	for i = 1, LEVELS do
		w, h = max(1, floor(w / 2)), max(1, floor(h / 2))
		down[i] = Target(w, h)
		if not down[i] then return false end
		if i < LEVELS then
			up[i] = Target(w, h)
			if not up[i] then return false end
		end
	end
	return true
end

function widget:Initialize()
	if not (glCopyToTexture and glRenderToTexture and gl.CreateShader) then
		widgetHandler:RemoveWidget()
		return
	end
	downShader = gl.CreateShader({ fragment = FRAG_DOWN, uniformInt = { tex0 = 0 } })
	upShader   = gl.CreateShader({ fragment = FRAG_UP, uniformInt = { tex0 = 0 } })
	if not downShader or not upShader then
		Spring.Echo("[Slate] blur is not available on this graphics card: " .. tostring(gl.GetShaderLog()))
		widgetHandler:RemoveWidget()
		return
	end
	downHalf = gl.GetUniformLocation(downShader, "halfpixel")
	upHalf   = gl.GetUniformLocation(upShader, "halfpixel")
	if not MakeTextures() then
		Spring.Echo("[Slate] blur is not available: could not create its textures")
		widgetHandler:RemoveWidget()
		return
	end
end

function widget:Shutdown()
	FreeTextures()
	if downShader then gl.DeleteShader(downShader) end
	if upShader then gl.DeleteShader(upShader) end
end

function widget:ViewResize(nx, ny)
	vsx, vsy = nx, ny
	if downShader and not MakeTextures() then widgetHandler:RemoveWidget() end
end

--------------------------------------------------------------------------------

function widget:DrawScreenEffects()
	local S = WG.Slate
	if not S or not S.theme or not S.theme.blur or not copyTex then return end
	local rects = S.blurRects
	if not rects or not next(rects) then return end
	if Spring.IsGUIHidden() then return end

	gl.Blending(false)
	gl.Color(1, 1, 1, 1)
	glCopyToTexture(copyTex, 0, 0, 0, 0, vsx, vsy)

	-- shrink
	glUseShader(downShader)
	local src, sw, sh = copyTex, vsx, vsy
	for i = 1, LEVELS do
		glUniform(downHalf, 0.5 / sw, 0.5 / sh)
		glTexture(src)
		glRenderToTexture(down[i].tex, glTexRect, -1, 1, 1, -1)
		src, sw, sh = down[i].tex, down[i].w, down[i].h
	end
	-- grow back to half size
	glUseShader(upShader)
	for i = LEVELS - 1, 1, -1 do
		glUniform(upHalf, 0.5 / sw, 0.5 / sh)
		glTexture(src)
		glRenderToTexture(up[i].tex, glTexRect, -1, 1, 1, -1)
		src, sw, sh = up[i].tex, up[i].w, up[i].h
	end
	glUseShader(0)

	-- only where a panel asked for it
	glTexture(src)
	for _, r in pairs(rects) do
		local x1, y1, x2, y2 = r[1] + INSET, r[2] + INSET, r[3] - INSET, r[4] - INSET
		if x2 > x1 and y2 > y1 then
			glTexRect(x1, y1, x2, y2, x1 / vsx, y1 / vsy, x2 / vsx, y2 / vsy)
		end
	end
	glTexture(false)
	gl.Blending(true)
end
