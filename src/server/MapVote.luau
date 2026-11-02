--!strict
-- The map vote between Normal matches (user 2026-11-02; Config/Cutscenes.Vote, Rules/Cutscenes, src/client/MapVote):
-- src/server/Frontline opens it after the results with the maps on offer (the built frontline maps, the live one
-- first: MapVote.offer), every player may vote for one and change it until it closes (Net "MapVote": (key: string)),
-- and the most votes picks the next map (a tie drawn at random). The state is on the Frontline folder for every client:
-- VoteOffer ("Map1,LanternMeadows"), Votes_<key> (the voters' kits in order, "uniform1,uniform2": the wax seals) and,
-- once closed, VotePick.

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
local order: { Player } = {} -- who voted, first vote first (the seals' order)
local last: { [Player]: number } = {}

-- the maps on offer now: the built frontline maps, the live one first
function MapVote.offer(): { string }
	local built = {}
	local keys = LiveMap.frontline()
	for _, k in keys do
		built[k] = LiveMap.built(k) and SketchCfg.Maps[k] ~= nil -- (its sheet on the vote needs its sketch art)
	end
	return Rules.offer(keys, built, LiveMap.key(), Cfg.maxCards)
end

local function publish()
	local folder = open
	if not folder then
		return
	end
	for _, k in offered do
		local seals = {}
		for _, p in order do
			if votes[p] == k then
				table.insert(seals, kits[p] or "")
			end
		end
		folder:SetAttribute(`Votes_{k}`, table.concat(seals, ","))
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
	open = nil
	table.clear(offered)
	table.clear(votes)
	table.clear(kits)
	table.clear(order)
end

function MapVote.open(folder: Folder, offer: { string })
	MapVote.clear(folder)
	open = folder
	offered = table.clone(offer)
	folder:SetAttribute("VoteOffer", table.concat(offer, ","))
	publish()
end

-- Closes the vote: the map it picks (`r` 0..1 draws a tie), shown as the folder's VotePick.
function MapVote.close(folder: Folder, r: number): string?
	local tally = Rules.tally(votes :: any, offered)
	local pick = Rules.pick(tally, offered, r)
	open = nil
	folder:SetAttribute("VotePick", pick)
	return pick
end

function MapVote.start()
	Net.event("MapVote").OnServerEvent:Connect(function(player: Player, key: unknown)
		if not open or type(key) ~= "string" or not table.find(offered, key) then
			return
		end
		local now = os.clock()
		if now - (last[player] or -math.huge) < Cfg.rate then
			return
		end
		last[player] = now
		if not votes[player] then
			table.insert(order, player)
		end
		votes[player] = key
		kits[player] = Kits.next(player)
		publish()
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
