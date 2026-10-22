--!strict
local Cfg = require("../src/shared/Config/Melee")
local D = require("../src/shared/Config/Damage")
local Ragdoll = require("../src/shared/Config/Ragdoll")
local Settings = require("../src/shared/Config/Settings")
local Melee = require("../src/shared/Rules/Melee")

local function hit(zone: string, health: number): (number, string?)
	return Melee.hit(zone, health, D.Melee, D.Knocks.Killed, D.HelmetFloor)
end

return {
	["a bare head goes down in one, the torso in two, a limb in three"] = function()
		assert(hit("Head", D.Health) == 0)
		local once = hit("Torso", D.Health)
		assert(once > 0 and hit("Torso", once) == 0)
		local a = hit("Limb", D.Health)
		local b = hit("Limb", a)
		assert(b > 0 and hit("Limb", b) == 0)
	end,
	["a helmet hit is never fatal by itself"] = function()
		assert(hit("Helmet", D.Health) == D.Health - D.Melee.Damage.Helmet)
		assert(hit("Helmet", 10) == D.HelmetFloor)
	end,
	["alive: the zone's knock; killed: its drop; every knock exists"] = function()
		local _, k = hit("Torso", D.Health)
		assert(k == D.Melee.Knocks.Torso)
		local _, dead = hit("Head", D.Health)
		assert(dead == D.Knocks.Killed.Head)
		for zone, knock in D.Melee.Knocks do
			assert(Ragdoll.Knocks[knock], zone)
		end
	end,
	["unknown zones do nothing"] = function()
		local left = hit("Pack", 80)
		assert(left == 80)
	end,
	["the cooldown, with slack for latency"] = function()
		local c = Cfg.Strike.cooldown
		assert(Melee.ready(nil, 0, c))
		assert(not Melee.ready(10, 10 + c - 0.2, c))
		assert(Melee.ready(10, 10 + c, c))
		assert(Melee.ready(10, 10 + c - 0.1, c, 0.15))
		assert(not Melee.ready(10, 10 + c - 0.2, c, 0.15))
	end,
	["the strike must face where the head looks"] = function()
		local cone = Cfg.Hit.cone
		assert(Melee.facing(0, -1, 0, -1, cone))
		assert(Melee.facing(math.sin(math.rad(cone - 1)), -math.cos(math.rad(cone - 1)), 0, -1, cone))
		assert(not Melee.facing(math.sin(math.rad(cone + 5)), -math.cos(math.rad(cone + 5)), 0, -1, cone))
		assert(not Melee.facing(0, 1, 0, -1, cone), "behind")
		assert(not Melee.facing(0, 0, 0, -1, cone), "straight down")
	end,
	["the hands must be free"] = function()
		assert(Melee.free({}))
		for _, k in { "busy", "ragdolled", "blocked", "striking" } do
			assert(not Melee.free({ [k] = true } :: any), k)
		end
	end,
	["timings hang together and the key is bound"] = function()
		local s = Cfg.Strike
		assert(s.impact > 0 and s.impact < s.length and s.length <= s.cooldown)
		assert(Cfg.Hit.reach > 0 and Cfg.Hit.radius > 0 and Cfg.Hit.slack < s.cooldown)
		assert(Settings.Options.Key_Melee.default == "V")
	end,
}
