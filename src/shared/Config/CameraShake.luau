--!strict
-- The camera shake (src/client/CameraShake, Rules/CameraShake; user 2026-10-22: "also make camera shake according to
-- explosions"). Every explosion (grenades, staff blasts, artillery shells, the dev menu's bombs) kicks the camera
-- `Blast.size` degrees within `Blast.reach` studs, both x the charge's cube root (kg of TNT), falling off squared with
-- the distance. Kicks add up, each dying away squared over `time` s, wobbling at `speed` (radians per second).
-- Stages: the charge a staff stage's blast shakes as (2 and 3 as Config/Damage.Staff.Charge; stage 1 does no damage,
-- a small one). The guns' own shot kick is in Config/Artillery.Fx.Shake.

return table.freeze({
	Blast = { size = 1.2, reach = 90 },
	Stages = { 0.05, 0.5, 10 },
	time = 0.6,
	speed = 55,
})
