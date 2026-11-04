--!strict
-- The map vote between Normal matches on the map board (user 2026-11-02; Config/Cutscenes.Vote, Rules/Cutscenes,
-- src/client/EndScenes): src/server/Frontline opens it after the battle table with the maps on offer (the built
-- frontline maps, the live one first: MapVote.offer) and who may sign (the winners: Rules/Cutscenes.maySign). A signer
-- signs one sheet, once: a signature can't be taken back (user 2026-11-03; Rules/Cutscenes.signs: a later one is
-- ignored) (Net "MapVote": (key: string)); the most signatures
-- picks the next map (a tie drawn at random). The state is on the Frontline folder for every client: VoteOffer
-- ("Map1,LanternMeadows"), Votes_<key> (the signatures in order, "Name:kit|Name:kit": the name written in the kit's ink)
-- and, once closed, VotePick; each player's MaySign attribute says whether they may sign this vote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cutscenes).Vote
local SketchCfg = require(Shared.Config.SketchMap) :: any
local LiveMap = require(Shared.LiveMap)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Cutscenes)
local Kits = require(script.Parent.Kits)

local MapVote = {}

local open: Folder? = nil
local offered: { string } = {}
local votes: { [Player]: string } = {}
local kits: { [Player]: string } = {}
local order: { Player } = {} -- who signed, first first (the signatures' order on a sheet)
local last: { [Player]: number } = {}
local may: (Player) -> boolean = function(_: Player): boolean
	return true
end

-- the maps on offer now: the built frontline maps, the live one first
function MapVote.offer(): { string }
	local built = {}
	local keys = LiveMap.frontline()
	for _, k in keys do
		built[k] = LiveMap.built(k) and SketchCfg.Maps[k] ~= nil -- (its sheet on the board needs its sketch art)
	end
	return Rules.offer(keys, built, LiveMap.key(), Cfg.maxCards)
end

local function publish()
	local folder = open
	if not folder then
		return
	end
	for _, k in offered do
		local names = {}
		for _, p in order do
			if votes[p] == k then
				table.insert(names, `{p.DisplayName}:{kits[p] or ""}`)
			end
		end
		folder:SetAttribute(`Votes_{k}`, table.concat(names, "|"))
	end
end

-- Takes the vote's attributes off `folder` (a new match, or a vote cut short).
function MapVote.clear(folder: Folder?)
	if folder then
		for name in folder:GetAttributes() do
			if name == "VoteOffer" or name == "VotePick" or string.sub(name, 1, 6) == "Votes_" then
				folder:SetAttribute(name, nil)
			end
		end
	end
	for _, p in Players:GetPlayers() do
		p:SetAttribute("MaySign", nil)
	end
	open = nil
	table.clear(offered)
	table.clear(votes)
	table.clear(kits)
	table.clear(order)
end

-- Opens the vote on `offer`; `maySign(player)`: whether that player signs (asked now and for anyone who joins).
function MapVote.open(folder: Folder, offer: { string }, maySign: ((Player) -> boolean)?)
	MapVote.clear(folder)
	open = folder
	offered = table.clone(offer)
	may = maySign or function(_: Player): boolean
		return true
	end
	for _, p in Players:GetPlayers() do
		p:SetAttribute("MaySign", may(p))
	end
	folder:SetAttribute("VoteOffer", table.concat(offer, ","))
	publish()
end

-- Closes the vote: the map it picks (`r` 0..1 draws a tie), shown as the folder's VotePick.
function MapVote.close(folder: Folder, r: number, force: string?): string?
	local tally = Rules.tally(votes :: any, offered)
	local pick = if force and table.find(offered, force) then force else Rules.pick(tally, offered, r)
	open = nil
	folder:SetAttribute("VotePick", pick)
	return pick
end

function MapVote.start()
	Net.event("MapVote").OnServerEvent:Connect(function(player: Player, key: unknown)
		if not open or type(key) ~= "string" or not may(player) then
			return
		end
		local now = os.clock()
		if now - (last[player] or -math.huge) < Cfg.rate then
			return
		end
		last[player] = now
		if not Rules.signs(votes[player], key, offered) then
			return -- (signed already: the vote stands)
		end
		table.insert(order, player)
		votes[player] = key
		kits[player] = Kits.next(player)
		publish()
	end)
	Players.PlayerAdded:Connect(function(player)
		if open then
			player:SetAttribute("MaySign", may(player))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
		if votes[player] then
			votes[player] = nil
			kits[player] = nil
			local i = table.find(order, player)
			if i then
				table.remove(order, i)
			end
			publish()
		end
	end)
end

return MapVote
