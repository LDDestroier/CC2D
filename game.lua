-- pastebin run W5ZkVYSi LDDestroier CC2D

local deriveControls = function(keyList)
	return {
		up = keyList[keys.up],
		down = keyList[keys.down],
		left = keyList[keys.left],
		right = keyList[keys.right],
		jump = keyList[keys.x],
		slide = keyList[keys.c],
		shoot = keyList[keys.z]
	}
end

local config = {}
config.downJumpSlide = true

local game = {}
game.path = fs.combine(fs.getDir(shell.getRunningProgram()),"data")
game.apiPath = fs.combine(game.path, "api")
game.spritePath = fs.combine(game.path, "sprites")
game.mapPath = fs.combine(game.path, "maps")
game.imagePath = fs.combine(game.path, "image")

local scr_x, scr_y = term.getSize()
local mapname = "testmap"

local scrollX = 0
local scrollY = 0
local killY = 100

local keysDown = {}

local tsv = function(visible)
	if term.current().setVisible then
		term.current().setVisible(visible)
	end
end

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
		xsize = 3,				-- hitbox x size
		ysize = 5,				-- hitbox y size
		x = x,					-- x position
		y = y,					-- y position
		xadj = 0,				-- adjust x for good looks
		yadj = 0,				-- adjust y for good looks
		xvel = 0,				-- x velocity
		yvel = 0,				-- y velocity
		maxVelocity = 8,		-- highest posible speed in any direction
		jumpHeight = 2,			-- height of jump
		jumpAssist = 0.5,		-- assists jump while in air
		moveSpeed = 1,			-- speed of walking
		friction = 0.75,		-- speed of slowing down after walking, from 0-1
		gravity = 0.75,			-- force of gravity
		slideSpeed = 5,			-- speed of sliding
		grounded = false,		-- is on solid ground
		shots = 0,				-- how many shots onscreen
		maxShots = 5,			-- maximum shots onscreen
		lemonSpeed = 4,			-- speed of megabuster shots
		chargeLevel = 0,		-- current charged buster level
		cycle = {				-- used for animation cycles
			run = 0,				-- used for run sprite
			shoot = 0,				-- determines duration of shoot sprite
			shootHold = 0,			-- forces user to release then push shoot
			stand = 0,				-- used for high-octane eye blinking action
			slide = 0,				-- used to limit slide length
			slideHold = 0,			-- used to prevent supersliding
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

you = 1
players[1] = newPlayer("LDD", "stickdude", 50, 8)

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
			-- player/player collision doesn't work, alas
			for num, p in pairs(players) do
				if player ~= p then
					if x >= p.x and x <= (p.xsize + p.x - 1) then
						if y >= p.y and y <= (p.ysize + p.y - 1) then
							--return "player"
						end
					end
				end
			end
		end
	end
	return false
end

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
			else
				player.xvel = 0
				break
			end
		else
			if player.grounded and (isPlayerTouchingSolid(player, i, 2) and not isPlayerTouchingSolid(player, i, 1)) then	-- downward slope detection
				player.y = player.y + 1
			end
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
		life = 48,
		cycle = 0,
		phaze = false,
	}
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
			if math.abs(player.xvel) < 0.5 then
				player.cycle.run = -1
				player.cycle.stand = (player.cycle.stand + 1) % 40
				if player.cycle.shoot > 0 then
					output = "shoot"
					if player.direction == -1 then
						player.xadj = -1
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

local pwalkspeed
local moveTick = function()
	local i
	for num, player in pairs(players) do

		-- falling
		player.yvel = player.yvel - player.gravity

		-- jumping

		if player.control.jump then
			if player.grounded then
				if player.cycle.jump == 0 then
					if not (player.control.down and player.cycle.slide == 0) and not isPlayerTouchingSolid(player, 0, -1, 0) then
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
		if player.cycle.slide == 0 then
			if ((config.downJumpSlide and player.control.down and player.control.jump) or player.control.slide) then
				if player.cycle.slideHold == 0 then
					player.cycle.slide = 6
					player.cycle.slideHold = 1
				end
			else
				player.cycle.slideHold = 0
			end
		end

		-- walking
		player.xvel = player.xvel * player.friction
		if player.cycle.slide > 0 then
			pwalkspeed = pwalkspeed or player.xvel
			player.xvel = player.direction * player.slideSpeed
		else
			if pwalkspeed then
				player.xvel = pwalkspeed
				pwalkspeed = nil
			else
				if player.control.right then
					player.direction = 1
					player.xvel = player.xvel + player.moveSpeed
				end
				if player.control.left then
					player.direction = -1
					player.xvel = player.xvel - player.moveSpeed
				end
			end
		end
		-- shooting

		if player.control.shoot then
			if player.cycle.shootHold == 0 then
				if player.shots < player.maxShots and player.cycle.slide == 0 then
					spawnProjectile(
						bullet.lemon,
						player,
						player.x + player.xsize * player.direction,
						player.y,
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
							player.x + math.max(0, player.direction * (player.xsize - 1)),
							player.y - 2,
							player.lemonSpeed * player.direction,
							0
						)
					else
						spawnProjectile(
							bullet.lemon2,
							player,
							player.x + math.max(0, player.direction * player.xsize),
							player.y - 1,
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
			player.x = 50
			player.y = -80
			player.xvel = 0
		end

		movePlayer(player, xvel, yvel)
		if num == you then
			scrollX = player.x - math.floor(scr_x / 2) + math.floor(player.xsize / 2)
			scrollY = player.y - math.floor(scr_y / 2) + math.floor(player.ysize / 2)
		end

		-- projectile management

		player.sprite = determineSprite(player)

	end
	for i = #projectiles, 1, -1 do
		projectiles[i].x = projectiles[i].x + projectiles[i].xvel
		projectiles[i].y = projectiles[i].y + projectiles[i].yvel
		projectiles[i].cycle = projectiles[i].cycle + 1
		projectiles[i].life = projectiles[i].life - 1
		if projectiles[i].life <= 0 then
			projectiles[i].owner.shots = projectiles[i].owner.shots - 1
			table.remove(projectiles, i)
		end
	end
end

local render = function()
	tsv(false)
	term.clear()
	nfte.drawImage(maps[mapname], -scrollX + 1, -scrollY + 1)
	term.setCursorPos(1,1)
	for num,player in pairs(players) do
		print("(" .. player.x .. ", " .. player.y .. ")")
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
	tsv(true)
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
		players[you].control = deriveControls(keysDown)
		moveTick()
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
