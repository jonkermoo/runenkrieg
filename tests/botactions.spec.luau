--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotActions")

local A = Cfg.Actions

local function mate(distance: number, health: number, down: boolean?, busy: boolean?, exposed: boolean?): R.Mate
	return { distance = distance, health = health, down = down == true, busy = busy == true, exposed = exposed == true }
end

local function enemy(x: number, z: number, visible: boolean?, hiddenFor: number?): R.Enemy
	return { x = x, z = z, distance = math.sqrt(x * x + z * z), visible = visible ~= false, hiddenFor = hiddenFor or 0 }
end

return {

	["mayTend: safe, or in a fight only from cover or to a teammate in cover"] = function()
		assert(R.mayTend(true, false, true), "safe")
		assert(not R.mayTend(false, false, true), "in a fight, both in the open")
		assert(R.mayTend(false, true, true), "the bot in cover")
		assert(R.mayTend(false, false, false), "the teammate in cover")
	end,
	["calm: nobody shooting at it or hitting it for long enough"] = function()
		assert(R.calm(5, 5, A.Heal.calm))
		assert(not R.calm(1, 5, A.Heal.calm), "shot at lately")
		assert(not R.calm(5, 1, A.Heal.calm), "hit lately")
	end,
	["healPick: the nearest hurt teammate in reach, not being healed"] = function()
		local list = { mate(20, 0.5), mate(10, 0.6), mate(5, 0.9), mate(3, 0.4, false, true), mate(40, 0.2) }
		assert(R.healPick(list, A.Heal) == 2, "nearest hurt one (5 is healthy, 3 being healed, 40 too far)")
		assert(R.healPick({ mate(5, 0) }, A.Heal) == nil, "dead")
		assert(R.healPick({}, A.Heal) == nil)
	end,
	["dragPick: the nearest downed teammate in the open"] = function()
		local list = {
			mate(8, 0.5, true, false, true),
			mate(4, 0.5, true, false, false), -- in cover already
			mate(6, 0.5, false, false, true), -- on their feet
			mate(5, 0.5, true, true, true), -- dragged already
			mate(20, 0.5, true, false, true), -- too far
		}
		assert(R.dragPick(list, A.Drag) == 1)
		assert(R.dragPick({ mate(4, 0, true, false, true) }, A.Drag) == nil, "dead")
	end,
	["grenadeAt: a group in range, never near a teammate"] = function()
		local G = A.Grenade
		local group = { enemy(25, 0), enemy(27, 2), enemy(80, 0) }
		local i, n = R.grenadeAt(group, {}, G)
		assert(i == 1 and n == 2, "the pair at 25-27")
		assert(R.grenadeAt(group, { { x = 22, z = 0 } }, G) == nil, "a teammate by them")
		assert(R.grenadeAt({ enemy(25, 0) }, {}, G) == nil, "one in the open: shoot it")
		assert(R.grenadeAt({ enemy(25, 0, false, G.hidden + 1) }, {}, G) == 1, "one in cover long enough")
		assert(R.grenadeAt({ enemy(25, 0, false, G.hidden - 1) }, {}, G) == nil, "not hidden long enough yet")
		assert(R.grenadeAt({ enemy(8, 0), enemy(9, 1) }, {}, G) == nil, "too close to throw")
		assert(R.grenadeAt({ enemy(50, 0), enemy(51, 1) }, {}, G) == nil, "too far")
	end,
	["lobPitch: the low arc lands where asked"] = function()
		local v, g = 128, 196.2
		for _, d in { 15, 25, 35 } do
			for _, h in { -3, 0, 4 } do
				local p = R.lobPitch(d, h, v, g) :: number
				assert(p and p > -math.pi / 2 and p < math.pi / 4, "low arc")
				-- the height when it has gone d studs
				local t = d / (v * math.cos(p))
				local y = v * math.sin(p) * t - g * t * t / 2
				assert(math.abs(y - h) < 1e-6, `lands at {y}, not {h}`)
			end
		end
		assert(R.lobPitch(5000, 0, v, g) == nil, "out of reach")
	end,
}
