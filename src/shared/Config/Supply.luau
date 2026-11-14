--!strict
-- The Supplier's bag (user 2026-11-13: "Players resupply by going up to the bag"; numbers 2026-11-14): a prompt on the
-- Supplier's pack for their teammates. A take fills every gun's spare rounds back to full (Config/Firing.Spare) and a
-- Grenadier's grenades back to Config/Grenades.Carried; then that taker waits `cooldown` s before taking again from
-- any bag. The Supplier can't take from their own bag; enemies don't see it. A take that gave something pays the
-- Supplier Config/Classes.Earn.Resupply. Players only for now (bots: unlimited ammunition, no bot Suppliers).
-- src/server/Supply, Rules/Supply. Data only.

local Supply = {
	Class = "Supplier", -- the Config/Classes key whose pack carries the prompt
	-- the part of the pack the prompt hangs on (the bag's main mesh); else the pack's largest part
	Part = "Body",
	reach = 8, -- studs
	hold = 0.6, -- seconds the key is held
	cooldown = 60, -- seconds before the same taker can take again
	object = "Supplier's bag",
	action = "Take ammunition",
	-- the taker's attribute: the server time (workspace:GetServerTimeNow) until which they can't take again
	WaitAttr = "ResupplyUntil",
}

return table.freeze(Supply)
