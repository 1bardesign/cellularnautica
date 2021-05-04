require("batteries"):export()

bit = require("bit")

lg = love.graphics

lg.setDefaultFilter("nearest", "nearest")

local res = 128

local ca = require("ca")

--

local current_ca = ca(res)

local auto_step = false
function love.update(dt)
	if auto_step then
		current_ca:step()
	end
end

function love.draw()
	lg.clear(0.5, 0.5, 0.5, 1.0)
	lg.push("all")
	lg.scale(4)
	lg.translate(1, 1)
	current_ca:draw()
	lg.pop()
end

function save()
	print("saving")
	local tw = math.max(current_ca.rule_tex:getWidth(), current_ca.visualise:getWidth())
	local th = current_ca.rule_tex:getHeight() + current_ca.palette:getHeight() + res

	--draw to canvas
	local compose = lg.newCanvas(tw, th)
	lg.push("all")
	lg.setCanvas(compose)
	lg.clear(0,0,0,0)
	local function draw_and_shift(texture)
		local w, h = texture:getDimensions()
		lg.draw(
			texture,
			(tw - w) / 2, 0
		)
		lg.translate(0, h)
	end
	for _, v in ipairs({
		current_ca.rule_tex,
		current_ca.palette,
		current_ca.position_indicator,
		current_ca.visualise,
	}) do
		draw_and_shift(v)
	end
	lg.pop()

	local encodable = compose:newImageData()
	--todo: hex name based on rule contents or hash?
	local fname = ("%d.png"):format(os.time())
	local f = io.open(fname, "wb")
	if f then
		f:write(encodable:encode("png"):getString())
		f:close()
		print("saved", fname)
	end
end

function load()
	print("todo: loading")
end

function love.keypressed(k)
	if k == "r" then
		current_ca:gen_buffers()
	end

	if k == "n" then
		current_ca = ca(res)
	end

	if k == "p" then
		current_ca:gen_palette()
		current_ca:update_visualise()
	end

	if k == "m" then
		current_ca:mutate_rule(love.keyboard.isDown("lshift") and 0.05 or 0.005)
	end

	if k == "i" then
		current_ca:step()
	end

	if k == "d" then
		current_ca:next_draw_mode()
	end

	if k == "space" then
		auto_step = not auto_step
	end

	if love.keyboard.isDown("lctrl") then
		if k == "q" then
			love.event.quit()
		elseif k == "r" then
			love.event.quit("restart")
		elseif k == "s" then
			save()
		elseif k == "l" then
			load()
		end
	end
end
