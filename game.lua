local class = function(base)
	local c = { }    -- a new class instance
	if type(base) == 'table' then
		-- our new class is a shallow copy of the base class!
		for i,v in pairs(base) do
			c[i] = v
		end
		c._base = base
	end
	-- the class will be the metatable for all its objects,
	-- and they will look up their methods in it.
	c.__index = c

	-- expose a constructor which can be called by <classname>(<args>)
	setmetatable(c, {
		__call = function(class_tbl, ...)
			local obj = { }
			setmetatable(obj,c)
			if class_tbl.init then
				class_tbl.init(obj, ...)
			else
				-- make sure that any stuff from the base class is initialized!
				if base and base.init then
					base.init(obj, ...)
				end
			end
			return obj
		end
	})

	c.is_a =
		function(self, klass)
			local m = getmetatable(self)
			while m do
				if m == klass then return true end
				m = m._base
			end
			return false
		end
	return c
end

local _rep = string.rep
local _sub = string.sub
local _gsub = string.gsub
local colors = _G.colors

local Canvas = class()

Canvas.colorPalette = { }
Canvas.darkPalette = { }
Canvas.grayscalePalette = { }

for n = 1, 16 do
	Canvas.colorPalette[2 ^ (n - 1)]     = _sub("0123456789abcdef", n, n)
	Canvas.grayscalePalette[2 ^ (n - 1)] = _sub("088888878877787f", n, n)
	Canvas.darkPalette[2 ^ (n - 1)]      = _sub("8777777f77fff77f", n, n)
end

function Canvas:init(args)
	self.x = 1
	self.y = 1

	for k,v in pairs(args) do
		self[k] = v
	end

	self.ex = self.x + self.width - 1
	self.ey = self.y + self.height - 1

	if not self.palette then
		if self.isColor then
			self.palette = Canvas.colorPalette
		else
			self.palette = Canvas.grayscalePalette
		end
	end

	self.lines = { }
	for i = 1, self.height do
		self.lines[i] = { }
	end
end

function Canvas:resize(w, h)
	for i = self.height, h do
		self.lines[i] = { }
	end

	while #self.lines > h do
		table.remove(self.lines, #self.lines)
	end

	if w ~= self.width then
		for i = 1, self.height do
			self.lines[i] = { dirty = true }
		end
	end

	self.ex = self.x + w - 1
	self.ey = self.y + h - 1
	self.width = w
	self.height = h
end

function Canvas:write(x, y, text, bg, fg)
	if bg then
		bg = _rep(self.palette[bg], #text)
	end
	if fg then
		fg = _rep(self.palette[fg], #text)
	end
	self:writeBlit(x, y, text, bg, fg)
end

function Canvas:writeBlit(x, y, text, bg, fg)
	if y > 0 and y <= #self.lines and x <= self.width then
		local width = #text

		-- fix ffs
		if x < 1 then
			text = _sub(text, 2 - x)
			if bg then
				bg = _sub(bg, 2 - x)
			end
			if bg then
				fg = _sub(fg, 2 - x)
			end
			width = width + x - 1
			x = 1
		end

		if x + width - 1 > self.width then
			text = _sub(text, 1, self.width - x + 1)
			if bg then
				bg = _sub(bg, 1, self.width - x + 1)
			end
			if bg then
				fg = _sub(fg, 1, self.width - x + 1)
			end
			width = #text
		end

		if width > 0 then

			local function replace(sstr, pos, rstr, width)
				if pos == 1 and width == self.width then
					return rstr
				elseif pos == 1 then
					return rstr .. _sub(sstr, pos+width)
				elseif pos + width > self.width then
					return _sub(sstr, 1, pos-1) .. rstr
				end
				return _sub(sstr, 1, pos-1) .. rstr .. _sub(sstr, pos+width)
			end

			local line = self.lines[y]
			line.dirty = true
			line.text = replace(line.text, x, text, width)
			if fg then
				line.fg = replace(line.fg, x, fg, width)
			end
			if bg then
				line.bg = replace(line.bg, x, bg, width)
			end
		end
	end
end

function Canvas:writeLine(y, text, fg, bg)
	self.lines[y].dirty = true
	self.lines[y].text = text
	self.lines[y].fg = fg
	self.lines[y].bg = bg
end

function Canvas:reset()
	self.regions = nil
end

function Canvas:clear(bg, fg)
	local text = _rep(' ', self.width)
	fg = _rep(self.palette[fg or colors.white], self.width)
	bg = _rep(self.palette[bg or colors.black], self.width)
	for i = 1, self.height do
		self:writeLine(i, text, fg, bg)
	end
end

function Canvas:redraw(device)
	self:reset()
	self:blit(device)
	self:clean()
end

function Canvas:isDirty()
	for _, line in pairs(self.lines) do
		if line.dirty then
			return true
		end
	end
end

function Canvas:dirty()
	for _, line in pairs(self.lines) do
		line.dirty = true
	end
end

function Canvas:clean()
	for _, line in pairs(self.lines) do
		line.dirty = false
	end
end

function Canvas:render(device) --- redrawAll ?
	self:blit(device)
	self:clean()
end

function Canvas:blit(device, src, tgt)
	src = src or { x = 1, y = 1, ex = self.ex - self.x + 1, ey = self.ey - self.y + 1 }
	tgt = tgt or self

	for i = 0, src.ey - src.y do
		local line = self.lines[src.y + i]
		if line and line.dirty then
			local t, fg, bg = line.text, line.fg, line.bg
			if src.x > 1 or src.ex < self.ex then
				t  = _sub(t, src.x, src.ex)
				fg = _sub(fg, src.x, src.ex)
				bg = _sub(bg, src.x, src.ex)
			end
			--if tgt.y + i > self.ey then -- wrong place to do clipping ??
			--  break
			--end
			device.setCursorPos(tgt.x, tgt.y + i)
			device.blit(t, fg, bg)
		end
	end
end

function Canvas:applyPalette(palette)

	local lookup = { }
	for n = 1, 16 do
		lookup[self.palette[2 ^ (n - 1)]] = palette[2 ^ (n - 1)]
	end

	for _, l in pairs(self.lines) do
		l.fg = _gsub(l.fg, '%w', lookup)
		l.bg = _gsub(l.bg, '%w', lookup)
		l.dirty = true
	end

	self.palette = palette
end

function Canvas.convertWindow(win, parent, wx, wy)
	local w, h = win.getSize()

	win.canvas = Canvas({
		x       = wx,
		y       = wy,
		width   = w,
		height  = h,
		isColor = win.isColor(),
	})

	function win.clear()
		win.canvas:clear(win.getBackgroundColor(), win.getTextColor())
	end

	function win.clearLine()
		local _, y = win.getCursorPos()
		win.canvas:write(1,
			y,
			_rep(' ', win.canvas.width),
			win.getBackgroundColor(),
			win.getTextColor())
	end

	function win.write(str)
		local x, y = win.getCursorPos()
		win.canvas:write(x,
			y,
			str,
			win.getBackgroundColor(),
			win.getTextColor())
		win.setCursorPos(x + #str, y)
	end

	function win.blit(text, fg, bg)
		local x, y = win.getCursorPos()
		win.canvas:writeBlit(x, y, text, bg, fg)
	end

	function win.redraw()
		win.canvas:redraw(parent)
	end

	function win.scroll(n)
		table.insert(win.canvas.lines, table.remove(win.canvas.lines, 1))
		win.canvas.lines[#win.canvas.lines].text = _rep(' ', win.canvas.width)
		win.canvas:dirty()
	end

	function win.reposition(x, y, width, height)
		win.canvas.x, win.canvas.y = x, y
		win.canvas:resize(width or win.canvas.width, height or win.canvas.height)
	end

	win.clear()
end

local currTerm = term.current()
local w, h = term.getSize()
local win = window.create(currTerm, 1, 1, w, h, true)
Canvas.convertWindow(win, currTerm, 1, 1)

term = win

local game = {}
game.path = fs.combine(fs.getDir(shell.getRunningProgram()),"data")
game.apiPath = fs.combine(game.path, "api")
game.spritePath = fs.combine(game.path, "sprites")
game.mapPath = fs.combine(game.path, "maps")
game.imagePath = fs.combine(game.path, "image")
game.configPath = fs.combine(game.path, "config.cfg")

local scr_x, scr_y = term.getSize()
local mapname = "testmap"

local scrollX = 0
local scrollY = 0
local killY = 100

local keysDown = {}

local getAPI = function(apiName, apiPath, apiURL, doDoFile)
	apiPath = fs.combine(game.apiPath, apiPath)
	if not fs.exists(apiPath) then
		write("Getting " .. apiName .. "...")
		local prog = http.get(apiURL)
		if prog then
			print("success!")
			local file = fs.open(apiPath, "w")
			file.write(prog.readAll())
			file.close()
		else
			error("fail!")
		end
	end
	if doDoFile then
		_ENV[fs.getName(apiPath)] = dofile(apiPath)
	else
		os.loadAPI(apiPath)
	end
end

getAPI("NFT Extra", "nfte", "https://github.com/LDDestroier/NFT-Extra/raw/master/nfte", false)

-- load sprites from sprite folder
-- sprites are separated into "sets", but the only one here is "megaman" so whatever

local sprites, maps = {}, {}
for k, set in pairs(fs.list(game.spritePath)) do
	sprites[set] = {}
	for num, name in pairs(fs.list(fs.combine(game.spritePath, set))) do
		sprites[set][name:gsub(".nft", "")] = nfte.loadImage(fs.combine(game.spritePath, set .. "/" .. name))
		print("Loaded sprite " .. name:gsub(".nft",""))
	end
end
for num, name in pairs(fs.list(game.mapPath)) do
	maps[name:gsub(".nft", "")] = nfte.loadImage(fs.combine(game.mapPath, name))
	print("Loaded map " .. name:gsub(".nft",""))
end

local projectiles = {}
local players = {}

local newPlayer = function(name, spriteset, x, y)
	return {
		name = name,			-- player name
		spriteset = spriteset,	-- set of sprites to use
		sprite = "stand",		-- current sprite
		direction = 1,			-- 1 is right, -1 is left
		xsize = 10,				-- hitbox x size
		ysize = 8,				-- hitbox y size
		x = x,					-- x position
		y = y,					-- y position
		xadj = 0,				-- adjust x for good looks
		yadj = 0,				-- adjust y for good looks
		xvel = 0,				-- x velocity
		yvel = 0,				-- y velocity
		maxVelocity = 8,		-- highest posible speed in any direction
		jumpHeight = 2,			-- height of jump
		jumpAssist = 0.5,		-- assists jump while in air
		moveSpeed = 2,			-- speed of walking
		gravity = 0.75,			-- force of gravity
		slideSpeed = 4,			-- speed of sliding
		grounded = false,		-- is on solid ground
		shots = 0,				-- how many shots onscreen
		maxShots = 3,			-- maximum shots onscreen
		lemonSpeed = 3,			-- speed of megabuster shots
		chargeLevel = 0,		-- current charged buster level
		cycle = {				-- used for animation cycles
			run = 0,				-- used for run sprite
			shoot = 0,				-- determines duration of shoot sprite
			shootHold = 0,			-- forces user to release then push shoot
			stand = 0,				-- used for high-octane eye blinking action
			slide = 0,				-- used to limit slide length
			jump = 0,				-- used to prevent auto-bunnyhopping
			shootCharge = 0,		-- records how charged your megabuster is
			ouch = 0,				-- records hitstun
			iddqd = 0				-- records invincibility frames
		},
		chargeDiscolor = {		-- swaps colors during buster charging
			[0] = {{}},
			[1] = {					-- charge level one
				{
					["b"] = "a"
				},
				{
					["b"] = "b"
				}
			},
			[2] = {					-- woAH charge level two
				{
					--["f"] = "b",
					["b"] = "3",
					["3"] = "f"
				},
				{
					--["f"] = "3",
					["3"] = "b",
					["b"] = "f"
				},
				{
					--["f"] = "3",
					["3"] = "b",
					["b"] = "8"
				}
			}
		},
		control = {				-- inputs
			up = false,				-- move up ladders
			down = false,			-- move down ladders, or slide
			left = false,			-- point and walk left
			right = false,			-- point and walk right
			jump = false,			-- jump, or slide
			shoot = false			-- fire your weapon
		}
	}
end

local deriveControls = function(keyList)
	return {
		up = keyList[keys.up],
		down = keyList[keys.down],
		left = keyList[keys.left],
		right = keyList[keys.right],
		jump = keyList[keys.x],
		shoot = keyList[keys.z]
	}
end

-- main colision function
local isSolid = function(x, y)
	x = math.floor(x)
	y = math.floor(y)
	if (not maps[mapname][1][y]) or (x < 1) then
		return false
	else
		if (maps[mapname][1][y]:sub(x,x) == " " or
		maps[mapname][1][y]:sub(x,x) == "") and
		(maps[mapname][3][y]:sub(x,x) == " " or
		maps[mapname][3][y]:sub(x,x) == "") then
			return false
		else
			return true
		end
	end
end

local isPlayerTouchingSolid = function(player, xmod, ymod, ycutoff)
	for y = player.y + (ycutoff or 0), player.ysize + player.y - 1 do
		for x = player.x, player.xsize + player.x - 1 do
			if isSolid(x + (xmod or 0), y + (ymod or 0)) then
				return "map"
			end
		end
	end
	return false
end

you = 1
players[you] = newPlayer("LDD", "megaman", 40, 8)

local movePlayer = function(player, x, y)
	i = player.yvel / math.abs(player.yvel)
	for y = 1, math.abs(player.yvel) do
		if isPlayerTouchingSolid(player, 0, -i, (player.cycle.slide > 0 and 2 or 0)) then
			if player.yvel < 0 then
				player.grounded = true
			end
			player.yvel = 0
			break
		else
			player.y = player.y - i
			player.grounded = false
		end
	end
	i = player.xvel / math.abs(player.xvel)
	for x = 1, math.abs(player.xvel) do
		if isPlayerTouchingSolid(player, i, 0, (player.cycle.slide > 0 and 2 or 0)) then
			if player.grounded and not isPlayerTouchingSolid(player, i, -1) then -- upward slope detection
				player.y = player.y - 1
				player.x = player.x + i
				grounded = true
			else
				player.xvel = 0
				break
			end
		else
			player.x = player.x + i
		end
	end
end

-- types of projectiles

local bullet = {
	lemon = {
		damage = 1,
		element = "neutral",
		sprites = {
			sprites["megaman"]["buster1"]
		},
	},
	lemon2 = {
		damage = 1,
		element = "neutral",
		sprites = {
			sprites["megaman"]["buster2-1"],
			sprites["megaman"]["buster2-2"]
		}
	},
	lemon3 = {
		damage = 4,
		element = "neutral",
		sprites = {
			sprites["megaman"]["buster3-1"],
			sprites["megaman"]["buster3-2"],
			sprites["megaman"]["buster3-3"],
			sprites["megaman"]["buster3-4"],
		}
	}
}

local spawnProjectile = function(boolit, owner, x, y, xvel, yvel)
	projectiles[#projectiles+1] = {
		owner = owner,
		bullet = boolit,
		x = x,
		y = y,
		xvel = xvel,
		yvel = yvel,
		direction = xvel / math.abs(xvel),
		life = 32,
		cycle = 0,
		phaze = false,
	}
end

local moveTick = function()
	local i
	for num, player in pairs(players) do

		-- falling
		player.yvel = player.yvel - player.gravity

		-- jumping

		if player.control.jump then
			if player.grounded then
				if player.cycle.jump == 0 then
					if player.control.down and player.cycle.slide == 0 then
						player.cycle.slide = 6
					elseif not isPlayerTouchingSolid(player, 0, -1, 0) then
						player.yvel = player.jumpHeight
						player.cycle.slide = 0
						player.grounded = false
					end
				end
				player.cycle.jump = 1
			end
			if player.yvel > 0 and not player.grounded then
				player.yvel = player.yvel + player.jumpAssist
			end
		else
			player.cycle.jump = 0
		end

		-- walking

		if player.control.right then
			player.direction = 1
			player.xvel = player.moveSpeed
		elseif player.control.left then
			player.direction = -1
			player.xvel = -player.moveSpeed
		else
			player.xvel = 0
		end
		if player.cycle.slide > 0 then
			player.xvel = player.direction * player.slideSpeed
		end

		-- shooting

		if player.control.shoot then
			if player.cycle.shootHold == 0 then
				if player.shots < player.maxShots and player.cycle.slide == 0 then
					spawnProjectile(
						bullet.lemon,
						player,
						player.x + player.xsize * player.direction,
						player.y + 2,
						player.lemonSpeed * player.direction,
						0
					)
					player.cycle.shoot = 5
					player.shots = player.shots + 1
				end
				player.cycle.shootHold = 1
			end
			if player.cycle.shootHold == 1 then
				player.cycle.shootCharge = player.cycle.shootCharge + 1
				if player.cycle.shootCharge < 16 then
					player.chargeLevel = 0
				elseif player.cycle.shootCharge < 32 then
					player.chargeLevel = 1
				else
					player.chargeLevel = 2
				end
			end
		else
			player.cycle.shootHold = 0
			if player.shots < player.maxShots and player.cycle.slide == 0 then
				if player.cycle.shootCharge > 16 then
					if player.cycle.shootCharge >= 32 then
						spawnProjectile(
							bullet.lemon3,
							player,
							player.x + math.max(0, player.direction * player.xsize),
							player.y,
							player.lemonSpeed * player.direction,
							0
						)
					else
						spawnProjectile(
							bullet.lemon2,
							player,
							player.x + math.max(0, player.direction * player.xsize),
							player.y + 1,
							player.lemonSpeed * player.direction,
							0
						)
					end
					player.shots = player.shots + 1
					player.cycle.shoot = 5
				end
			end
			player.cycle.shootCharge = 0
			player.chargeLevel = 0
		end

		-- movement
		if player.xvel > 0 then
			player.xvel = math.min(player.xvel, player.maxVelocity)
		else
			player.xvel = math.max(player.xvel, -player.maxVelocity)
		end
		if player.yvel > 0 then
			player.yvel = math.min(player.yvel, player.maxVelocity)
		else
			player.yvel = math.max(player.yvel, -player.maxVelocity)
		end

		if player.y > killY then
			player.x = 40
			player.y = -80
			player.xvel = 0
		end

		movePlayer(player, xvel, yvel)

		scrollX = player.x - math.floor(scr_x / 2) + math.floor(player.xsize / 2)
		scrollY = player.y - math.floor(scr_y / 2) + math.floor(player.ysize / 2)

		-- projectile management

		for i = #projectiles, 1, -1 do
			projectiles[i].x = projectiles[i].x + projectiles[i].xvel
			projectiles[i].y = projectiles[i].y + projectiles[i].yvel
			projectiles[i].cycle = projectiles[i].cycle + 1
			projectiles[i].life = projectiles[i].life - 1
			if projectiles[i].life <= 0 then
				table.remove(projectiles, i)
				player.shots = player.shots - 1
			end
		end

	end
end

local render = function()
	term.clear()
	nfte.drawImage(maps[mapname], -scrollX + 1, -scrollY + 1)
	for num,player in pairs(players) do
		term.setCursorPos(1,num)
		print("(" .. player.x .. ", " .. player.y .. ", " .. tostring(player.shots) .. ")")
		if player.direction == -1 then
			nfte.drawImageTransparent(
				nfte.colorSwap(
					nfte.flipX(
						sprites[player.spriteset][player.sprite]
					),
					player.chargeDiscolor[player.chargeLevel][
						(math.floor(player.cycle.shootCharge / 2) % #player.chargeDiscolor[player.chargeLevel]) + 1
					]
				),
				player.x - scrollX + player.xadj,
				player.y - scrollY + player.yadj
			)
		else
			nfte.drawImageTransparent(
				nfte.colorSwap(
					sprites[player.spriteset][player.sprite],
					player.chargeDiscolor[player.chargeLevel][
						(math.floor(player.cycle.shootCharge / 2) % #player.chargeDiscolor[player.chargeLevel]) + 1
					]
				),
				player.x - scrollX,
				player.y - scrollY
			)
		end
	end
	for num,p in pairs(projectiles) do
		if p.direction == -1 then
			nfte.drawImageTransparent(
				nfte.flipX(p.bullet.sprites[(p.cycle % #p.bullet.sprites) + 1]),
				p.x - scrollX,
				p.y - scrollY
			)
		else
			nfte.drawImageTransparent(
				p.bullet.sprites[(p.cycle % #p.bullet.sprites) + 1],
				p.x - scrollX,
				p.y - scrollY
			)
		end
	end
end

-- determines what sprite a player uses
local determineSprite = function(player)
	local output
	player.xadj = 0
	player.yadj = 0
	if player.grounded then
		if player.cycle.slide > 0 then
			player.cycle.slide = math.max(player.cycle.slide - 1, isPlayerTouchingSolid(player, 0, 0, 0) and 1 or 0)
			output = "slide"
		else
			if player.xvel == 0 then
				player.cycle.run = -1
				player.cycle.stand = (player.cycle.stand + 1) % 40
				if player.cycle.shoot > 0 then
					output = "shoot"
					if player.direction == -1 then
						player.xadj = -5
					end
				else
					output = player.cycle.stand == 39 and "stand2" or "stand1"
				end
			else
				if player.cycle.run == -1 and player.cycle.shoot == 0 then
					player.cycle.run = 0
					output = "walk0"
				else
					player.cycle.run = (player.cycle.run + 0.35) % 4
					if player.cycle.shoot > 0 then
						output = "walkshoot" .. (math.floor(player.cycle.run) + 1)
					else
						output = "walk" .. (math.floor(player.cycle.run) + 1)
					end
				end
			end
		end
	else
		player.cycle.slide = isPlayerTouchingSolid(player, 0, 0, 0) and 1 or 0
		if player.cycle.shoot > 0 then
			output = "jumpshoot"
			if player.direction == -1 then
				player.xadj = -1
			end
		else
			output = "jump"
		end
	end
	player.cycle.shoot = math.max(player.cycle.shoot - 1, 0)
	return output
end

local getInput = function()
	local evt
	while true do
		evt = {os.pullEvent()}
		if evt[1] == "key" then
			keysDown[evt[2]] = true
		elseif evt[1] == "key_up" then
			keysDown[evt[2]] = false
		end
	end
end

local main = function()
	while true do
		win.redraw()
		players[you].control = deriveControls(keysDown)
		moveTick()
		players[you].sprite = determineSprite(players[you])
		render()
		if keysDown[keys.q] then
			return
		end
		sleep(0.05)
	end
end

parallel.waitForAny(getInput, main)

term.setCursorPos(1, scr_y)
term.clearLine()
