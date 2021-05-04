--[[
	cellular automata class
]]

local ca = class()

function ca:new(res)
	self = self:init({
		res = res,
		draw_mode = "threestate",
	})

	self:gen_palette()
	self:gen_rule()
	self:gen_buffers()

	return self
end

function ca:gen_buffers()
	self.buffers = functional.generate(2, function()
		local c = lg.newCanvas(self.res, self.res, {format = "r8"})
		c:setWrap("repeat")
		return c
	end)
	self.buffers[1]:renderTo(function()
		lg.push("all")
		local r = self.res
		local hr = r / 2
		lg.translate(hr, hr)
		for i = 1, r do
			lg.points(
				love.math.randomNormal() * r / 30,
				love.math.randomNormal() * r / 30
			)
		end
		lg.pop()
	end)
	self.buffers[2]:renderTo(function()
		lg.draw(self.buffers[1])
	end)
	self.visualise = lg.newCanvas(self.res, self.res)
	self:update_visualise()
end

function ca:gen_palette()
	self.palette = lg.newCanvas(3, 1)
	self.palette:renderTo(function()
		lg.push("all")
		lg.translate(-0.5, -0.5)
		local h = love.math.random()
		local min = 0.15
		local max = 0.85
		local s = math.lerp(min, max, love.math.random())
		local l = math.lerp(min, max, love.math.random())
		local hue_direction = math.random_sign()
		for i = 1, 3 do
			local r, g, b = colour.hsl_to_rgb(h, s, l)
			lg.setColor(r, g, b, 1)
			lg.points(i, 1)
			--mutate next colour
			h = h + hue_direction * math.lerp(0.05, 0.4, love.math.random())
			s = s + math.random_sign() * math.lerp(0.05, 0.1, love.math.random())
			l = l + math.random_sign() * math.lerp(0.3, 0.4, love.math.random())
			s = math.clamp(s, min, max)
			l = math.clamp(l, min, max)
		end
		lg.pop()
	end)
end

function ca:gen_rule()
	self.chance = math.lerp(0.05, 0.3, love.math.random())

	local range = 1
	local ortho = love.math.random() < 0.5
	local full_ortho = ortho and love.math.random() < 0.5

	self.rule_positions = {}
	while #self.rule_positions < 8 do
		local x = math.round(love.math.randomNormal() * range)
		local y = math.round(love.math.randomNormal() * range)

		if ortho then
			local i = #self.rule_positions
			if i < 4 then
				if i == 0 then x, y =  1,  0 end
				if i == 1 then x, y = -1,  0 end
				if i == 2 then x, y =  0,  1 end
				if i == 3 then x, y =  0, -1 end
			end
			if full_ortho and i < 8 then
				if i == 4 then x, y = -1, -1 end
				if i == 5 then x, y = -1,  1 end
				if i == 6 then x, y =  1,  1 end
				if i == 7 then x, y =  1, -1 end
			end
		end

		if (x == 0 and y == 0) or functional.any(self.rule_positions, function(v)
			return v[1] == x and v[2] == y
		end) then
			--dud position
		else
			table.insert(self.rule_positions, {x, y})
		end
	end

	--trip down to the required length
	table.shuffle(self.rule_positions)
	local samples_count = love.math.random(4, 8)
	while #self.rule_positions > samples_count do
		table.remove(self.rule_positions)
	end

	--establish consistent ordering
	table.stable_sort(self.rule_positions, function(a, b)
		return a[2] < b[2] or a[1] < b[1]
	end)
	local indicator_res = 15
	self.position_indicator = lg.newCanvas(indicator_res, indicator_res)
	self.position_indicator:renderTo(function()
		lg.push("all")
		lg.clear(0,0,0,1)
		lg.translate(indicator_res / 2, indicator_res / 2)
		for _, v in ipairs(self.rule_positions) do
			lg.points(v[1], v[2])
		end
		lg.setColor(1, 0, 0, 1)
		lg.points(0,0)
		lg.pop()
	end)

	local rule_elements = bit.lshift(1, #self.rule_positions)

	self.rule_tex = lg.newCanvas(rule_elements, 2, {format = "r8"})
	self.rule_tex:renderTo(function()
		lg.push("all")
		lg.translate(-0.5, -0.5)
		local w, h = self.rule_tex:getDimensions()
		for x = 1, w do
			for y = 1, h do
				local v = love.math.random() < self.chance and 1 or 0
				lg.setColor(v, v, v, 1)
				lg.points(x, y)
			end
		end
		lg.pop()
	end)
end

function ca:mutate_rule(proportion)
	local w, h = self.rule_tex:getDimensions()
	local size = w * h
	--todo: mutate positions
	local indices = functional.generate(size, functional.identity)
	table.shuffle(indices)
	self.rule_tex:renderTo(function()
		lg.push("all")
		lg.translate(-0.5, -0.5)
		for i = 1, math.ceil(size * proportion) do
			local index = indices[i] - 1
			local v = love.math.random() < self.chance and 1 or 0
			lg.setColor(v, v, v, 1)
			local x = math.floor(index % w) + 1
			local y = math.floor(index / w) + 1
			lg.points(x, y)
		end
		lg.pop()
	end)
end

local step_shader = lg.newShader([[
#pragma language glsl3
const int RULE_MAX = 8;
uniform Image rule;
uniform vec2 rule_positions[RULE_MAX];
uniform int rule_count;

uniform float rule_size;
uniform vec2 input_res;

vec4 effect(vec4 c, Image t, vec2 uv, vec2 px) {
	int rule_i = 0;
	int rule_id = 0;

	for (int i = 0; i < rule_count; i++) {
		vec2 o = rule_positions[i] / input_res;
		if (Texel(t, uv + o).r > 0.5) {
			rule_id |= (1 << rule_i);
		}
		rule_i++;
	}

	vec2 rule_uv = vec2(rule_id, Texel(t, uv).r);
	rule_uv += vec2(0.5);
	rule_uv /= vec2(rule_size, 1.0);

	float v = Texel(rule, rule_uv).r;

	return vec4(v, 0.0, 0.0, 1.0);
}
]])

function ca:step()
	--swap
	table.swap(self.buffers, 1, 2)
	lg.push("all")
	step_shader:send("input_res", {self.buffers[1]:getDimensions()})
	step_shader:send("rule", self.rule_tex)
	step_shader:send("rule_size", self.rule_tex:getWidth())
	step_shader:send("rule_count", #self.rule_positions)
	step_shader:send("rule_positions", unpack(self.rule_positions))

	lg.setShader(step_shader)
	lg.setCanvas(self.buffers[1])
	lg.clear(0, 0, 0, 0)
	lg.draw(self.buffers[2])
	lg.pop()

	self:update_visualise()
end

local three_colour_shader = lg.newShader([[
#pragma language glsl3
uniform Image previous;
uniform Image palette;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 px) {
	float cur = Texel(t, uv).r;
	float pre = Texel(previous, uv).r;
	vec2 p_uv = vec2(cur, 0.0);
	if (cur != pre) {
		p_uv.x = 2.0;
	}

	p_uv += vec2(0.5);
	p_uv /= vec2(3.0, 1.0);

	return Texel(palette, p_uv);
}
]])

local alpha_shader = lg.newShader([[
#pragma language glsl3
uniform Image palette;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 px) {
	float cur = Texel(t, uv).r;
	vec2 p_uv = vec2(cur, 0.5);
	return Texel(palette, p_uv);
}
]])
function ca:update_visualise()
	--visualise
	lg.push("all")
	lg.setCanvas(self.visualise)
	if self.draw_mode == "threestate" then
		three_colour_shader:send("previous", self.buffers[2])
		three_colour_shader:send("palette", self.palette)
		lg.setShader(three_colour_shader)
		self.palette:setFilter("nearest")
		lg.draw(self.buffers[1])
	elseif self.draw_mode == "alpha" then
		if not self._alpha_tex then
			self._alpha_tex = lg.newCanvas(self.res, self.res, {format = "r32f"})
		end
		lg.push("all")
		lg.origin()
		lg.setCanvas(self._alpha_tex)
		lg.setColor(1, 1, 1, 0.05)
		lg.draw(self.buffers[1])
		lg.pop()
		alpha_shader:send("palette", self.palette)
		self.palette:setFilter("linear")
		lg.setShader(alpha_shader)
		lg.draw(self._alpha_tex)
	end
	lg.pop()
end

function ca:draw()
	lg.push("all")

	lg.draw(self.position_indicator, 0, 0)
	lg.draw(self.rule_tex, 20, 0)
	lg.draw(self.palette, 20, 3, 0, 20, 2)
	lg.draw(self.visualise, 0, 20)

	lg.pop()
end

function ca:next_draw_mode()
	self.draw_mode =
		self.draw_mode == "threestate" and "alpha"
		or self.draw_mode == "alpha" and "threestate"
		or "threestate"
	self:update_visualise()
end

return ca
