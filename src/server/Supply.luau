--!strict
-- The Supplier's bag (Config/Supply, Rules/Supply; user 2026-11-13/14): a Supplier spawns with a prompt on their pack
-- (Supply.dress, from src/server/Bodies once the pack is on). A teammate who holds it gets every gun's spare rounds
-- back to full (src/server/Firing.resupply) and, as a Grenadier, their grenades back to Config/Grenades.Carried; then
-- they wait Config/Supply.cooldown s (their "ResupplyUntil" attribute, shown on the prompt as the "Wait" reason). A
-- take that gave something pays the Supplier Config/Classes.Earn.Resupply. The prompt is kept for the Supplier's kit
-- and hidden from the Supplier (Config/Prompts OnlyKitAttr / OwnerAttr; src/client/Prompts). Players only for now.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Supply)
local G = require(Shared.Config.Grenades)
local PromptCfg = require(Shared.Config.Prompts)
local Rules = require(Shared.Rules.Supply)
local Armory = require(script.Parent.Armory)
local Firing = require(script.Parent.Firing)
local Loadouts = require(script.Parent.Loadouts)

local Supply = {}

-- The part of the worn pack the prompt hangs on: the bag's `Part`, else its largest part.
local function anchor(pack: Instance): BasePart?
	local named = pack:FindFirstChild(Cfg.Part, true)
	if named and named:IsA("BasePart") then
		return named
	end
	local best, size = nil, -1
	for _, p in pack:GetDescendants() do
		if p:IsA("BasePart") and p.Size.Magnitude > size then
			best, size = p, p.Size.Magnitude
		end
	end
	return best
end

local function alive(character: Model?): boolean
	local h = character and character:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

-- A Grenadier's grenades back to Config/Grenades.Carried (a new one in the slot if the last was thrown). Whether it
-- gave any.
local function grenades(player: Player, character: Model): boolean
	local name = Loadouts.gear(character).Grenade
	if not name then
		return false
	end
	for _, holder in { character, player:FindFirstChildOfClass("Backpack") } do
		for _, t in if holder then holder:GetChildren() else {} do
			if t:IsA("Tool") and t:GetAttribute("Weapon") == name then
				local count = t:GetAttribute("Count")
				if type(count) == "number" and count >= G.Carried then
					return false
				end
				t:SetAttribute("Count", G.Carried)
				t.Name = Armory.label(name, G.Carried)
				return true
			end
		end
	end
	Armory.give(player, name) -- (the last one was thrown: the hand was empty)
	return true
end

local function take(owner: Player, bag: Instance, taker: Player)
	local mine, theirs = owner.Character, taker.Character
	if not mine or not theirs or bag.Parent ~= mine or not alive(mine) or not alive(theirs) then
		return
	end
	local now = workspace:GetServerTimeNow()
	local wait = taker:GetAttribute(Cfg.WaitAttr)
	local ok = Rules.canTake(
		taker.UserId,
		theirs:GetAttribute("Kit"),
		owner.UserId,
		mine:GetAttribute("Kit"),
		now,
		if type(wait) == "number" then wait else nil
	)
	if not ok then
		return
	end
	local gave = Firing.resupply(taker)
	gave = grenades(taker, theirs) or gave
	if gave then
		taker:SetAttribute(Cfg.WaitAttr, now + Cfg.cooldown)
		Loadouts.award(owner, "Resupply")
	end
end

-- Puts the bag's prompt on `character`'s pack when it is a player's Supplier (after src/server/Packs has dressed it).
function Supply.dress(character: Model)
	local owner = Players:GetPlayerFromCharacter(character)
	local pack = character:FindFirstChild("Pack")
	if not owner or not pack or Loadouts.classOf(character) ~= Cfg.Class then
		return
	end
	local part = anchor(pack)
	if not part then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SupplyPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ObjectText = Cfg.object
	prompt.ActionText = Cfg.action
	prompt.HoldDuration = Cfg.hold
	prompt.MaxActivationDistance = Cfg.reach
	prompt.RequiresLineOfSight = false -- (the Supplier's own body is in the way from the front)
	prompt:SetAttribute(PromptCfg.OnlyKitAttr, character:GetAttribute("Kit"))
	prompt:SetAttribute(PromptCfg.OwnerAttr, owner.UserId)
	prompt:SetAttribute(PromptCfg.WaitAttr, Cfg.WaitAttr)
	CollectionService:AddTag(prompt, PromptCfg.Tag)
	prompt.Triggered:Connect(function(taker: Player)
		take(owner, pack, taker)
	end)
	prompt.Parent = part
end

return Supply
