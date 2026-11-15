--!strict
-- The Supplier's bag (Config/Supply, src/server/Supply): who may take from it. Pure: ids, kits and times.

local Supply = {}

-- Whether soldier `taker` (a UserId, their kit) may take from the bag of `owner` (a UserId, their kit) at `now`, their
-- own wait running until `waitUntil` (nil: none); else why not: "own" (their own bag), "enemy", "wait".
function Supply.canTake(
	taker: number,
	takerKit: any,
	owner: number,
	ownerKit: any,
	now: number,
	waitUntil: number?
): (boolean, string?)
	if taker == owner then
		return false, "own"
	elseif takerKit == nil or takerKit ~= ownerKit then
		return false, "enemy"
	elseif waitUntil ~= nil and now < waitUntil then
		return false, "wait"
	end
	return true, nil
end

-- Whether a prompt kept for kit `onlyKit` and not for player `owner` is shown to the player `me` of kit `myKit`
-- (src/client/Prompts: the bag is hidden from its own Supplier and from the enemy).
function Supply.shown(onlyKit: any, owner: any, me: number, myKit: any): boolean
	return (onlyKit == nil or onlyKit == myKit) and (owner == nil or owner ~= me)
end

return Supply
