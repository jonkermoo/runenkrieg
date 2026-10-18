--!strict
local D = require("../src/shared/Config/Damage")
local W = require("../src/shared/Config/Weapons")
local Metrics = require("../src/shared/Config/Metrics")
local Ragdoll = require("../src/shared/Config/Ragdoll")
local Damage = require("../src/shared/Rules/Damage")

local RIFLE = D.Weapons.BoltRifle
local SHOTGUN = D.Weapons.Shotgun

-- a rifle shot's hits on one soldier, then the health left
local function shoot(health: number, zones: { string }): number
	local hits = {}
	for _, z in zones do
		table.insert(hits, { zone = z, amount = Damage.amount(RIFLE, z) })
	end
	local total, helmet = Damage.sum(hits)
	return Damage.after(health, total, helmet, D.HelmetFloor)
end

return {
	["body parts map to zones; gear and anything else is no hit"] = function()
		assert(Damage.zone("Head") == "Head")
		assert(Damage.zone("Torso") == "Torso" and Damage.zone("HumanoidRootPart") == "Torso")
		for _, limb in { "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
			assert(Damage.zone(limb) == "Limb", limb)
		end
		assert(Damage.zone("Helmet") == nil and Damage.zone("FaceCard") == nil and Damage.zone("Handle") == nil)
	end,
	["rifles kill in 1-2 hits: a headshot kills, torso and limbs take 2"] = function()
		local H = D.Health
		assert(shoot(H, { "Head" }) == 0, "one headshot kills")
		assert(shoot(H, { "Torso" }) > 0 and shoot(H, { "Torso", "Torso" }) == 0, "torso: 2 hits")
		assert(shoot(H, { "Limb" }) > 0 and shoot(H, { "Limb", "Limb" }) == 0, "limbs: 2 hits")
		assert(shoot(H, { "Limb", "Torso" }) == 0, "a limb then the torso kills")
	end,
	["a helmet hit is never fatal by itself"] = function()
		assert(shoot(100, { "Helmet" }) == 100 - RIFLE.Helmet, "the helmet takes the hit")
		assert(shoot(30, { "Helmet" }) == 1, "already hurt: left at 1, not killed")
		assert(shoot(1, { "Helmet" }) == 1, "at 1: stays at 1")
		assert(shoot(30, { "Helmet", "Torso" }) == 0, "the rest of the shot alone kills: dead")
		assert(Damage.after(0.5, 40, 40, D.HelmetFloor) == 0.5, "never raised above what was left")
	end,
	["shotgun pellets: full to 15 m, fading to none at 50 m"] = function()
		local p = W.shotgun_m1897.pellets :: any
		assert(Damage.falloff(0, p.full, p.none) == 1 and Damage.falloff(p.full, p.full, p.none) == 1)
		local mid = Damage.falloff((p.full + p.none) / 2, p.full, p.none)
		assert(math.abs(mid - 0.5) < 1e-9, "halfway: half")
		assert(Damage.falloff(p.none, p.full, p.none) == 0 and Damage.falloff(1e6, p.full, p.none) == 0)
		assert(Damage.falloff(-5, p.full, p.none) == 1, "negative distance: full")
		-- a close shot with most pellets in the torso kills; a far one does nothing
		local close = 0
		for _ = 1, 5 do
			close += Damage.amount(SHOTGUN, "Torso", Damage.falloff(10, p.full, p.none))
		end
		assert(close >= D.Health, "5 torso pellets up close kill")
		assert(Damage.amount(SHOTGUN, "Head", Damage.falloff(p.none + 1, p.full, p.none)) == 0)
		assert(Damage.amount(SHOTGUN, "Nowhere", 1) == 0, "an unknown zone does nothing")
	end,
	["the knock is by the zone that took the most, alive or killed"] = function()
		local total, helmet, top = Damage.sum({
			{ zone = "Limb", amount = 12 },
			{ zone = "Torso", amount = 20 },
			{ zone = "Limb", amount = 12 },
		})
		assert(total == 44 and helmet == 0 and top == "Limb", "two limb pellets beat one torso pellet")
		assert(Damage.knock(top, false, D.Knocks) == "Limb", "limb, alive: a slight knockback")
		assert(Damage.knock("Torso", false, D.Knocks) == "Torso", "torso, alive: a medium ragdoll")
		assert(Damage.knock("Head", true, D.Knocks) == "HeadDrop", "headshot kill: a drop")
		assert(Damage.knock(nil, true, D.Knocks) == nil)
		local _, _, none = Damage.sum({})
		assert(none == nil, "no hits: no knock")
		-- every knock named exists
		for _, side in { D.Knocks.Alive, D.Knocks.Killed } do
			for _, k in side do
				assert(Ragdoll.Knocks[k], "knock " .. k)
			end
		end
		for _, list in { D.Staff.Knock, D.Staff.Killed } do
			for _, k in list do
				assert(Ragdoll.Knocks[k], "staff knock " .. k)
			end
		end
		for _, b in D.Blast.Knocks do
			assert(Ragdoll.Knocks[b.knock], "blast knock " .. b.knock)
		end
	end,
	["a headshot kill is thrown back, torso hits throw further than limbs"] = function()
		local K = Ragdoll.Knocks
		assert(K.LimbDrop.push < K.TorsoDrop.push, "killed by a limb hit: less than the torso")
		assert(
			K.HeadDrop.push > K.LimbDrop.push and K.HeadDrop.tumble >= K.Torso.tumble,
			"a headshot kill is thrown back"
		)
		assert(K.Limb.push < K.Torso.push and K.Torso.push < K.StaffThrow.push, "limbs slight, torso medium, beam big")
		for name, k in K do
			assert(k.tumble > 0, `{name}: tips over (nobody ragdolls standing up)`)
		end
	end,
	["the staff: range grows per stage, no falloff, stage 3 kills"] = function()
		local S = D.Staff
		assert(#S.Range == 3 and S.Range[1] < S.Range[2] and S.Range[2] < S.Range[3])
		local left, knock = Damage.staff(1, 100, S)
		assert(left == 100 - S.Damage[1] and knock == S.Knock[1])
		left, knock = Damage.staff(2, 100, S)
		assert(left and left > 0 and knock == "Torso", "stage 2: alive from full, a medium ragdoll")
		left, knock = Damage.staff(2, left :: number, S)
		assert(left == 0 and knock == S.Killed[2], "stage 2 twice kills")
		left, knock = Damage.staff(3, 100, S)
		assert(left == 0 and knock == "StaffThrow", "the full beam kills and throws")
		assert(Damage.staff(4, 100, S) == nil and Damage.staff(0, 100, S) == nil)
		assert(S.Charge[1] == 0 and S.Charge[2] > 0 and S.Charge[3] > S.Charge[2], "stage 2 a small blast, 3 a big one")
	end,
	["respawn after the agreed delay"] = function()
		assert(Metrics.Combat.RespawnDelay == 10)
	end,
}
