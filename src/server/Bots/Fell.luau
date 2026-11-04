--!strict
-- Normal: Engineers fell the trees in the way of their side's works (Config/Bots.Build.Trees, Rules/BotBuild.treesInWay;
-- user 2026-11-03), kept out of src/server/Bots: each commander tick the side's trench lines, nest and gun spots and the
-- guns' firing lines are looked along for standing trees, and the nearest few go on its build list as "Tree" jobs; a
-- bot on one swings its shovel's Destroy at the trunk (src/server/Build, Trees.chop) until it falls, then at its stump
-- until that is cleared too (Config/Damage.Trees.Chop.stumpSwings). What a felled tree changes is put back at the next
-- match (src/server/DevWorld: the tree by its copy, the ground by DevWorld.touch).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local DestructionCfg = require(Shared.Config.Destruction)
local DevCfg = require(Shared.Config.DevTools)
local BotBuild = require(Shared.Rules.BotBuild)
local Build = require(script.Parent.Parent.Build)
local DevWorld = require(script.Parent.Parent.DevWorld)
local Trees = require(script.Parent.Parent.Trees)

local Types = require(script.Parent.Types)
type BuildJob = Types.BuildJob
type SideBuild = Types.SideBuild

local T = Cfg.Build.Trees
local Kinds = { MGNest = true, FieldGun = true, Howitzer = true }

local Fell = {}

-- each side's this match: its tree jobs by tree, the trees felled, the one being chopped
type Side = {
	jobs: { [Model]: BuildJob },
	felled: number,
	current: { tree: Model, name: string, at: Vector3, by: string }?,
}
local sides: { [string]: Side } = {}
local lastFell: { [number]: number } = {} -- each bot's last tree felled (os.clock)
local stumpOf: { [BuildJob]: BasePart } = {} -- a tree job whose tree is down: its stump, still to clear
-- the report's counters since its last line
local counts = { listed = 0, swings = 0, felled = 0, stumps = 0 }

local function sideOf(side: string): Side
	local s = sides[side]
	if not s then
		s = { jobs = {}, felled = 0, current = nil }
		sides[side] = s
	end
	return s :: Side
end

-- whether a tree stands in one of the map's buildings (never felled: the landmarks keep theirs)
local function inBuilding(tree: Model): boolean
	local a = tree.Parent
	while a and a ~= workspace do
		if CollectionService:HasTag(a, DestructionCfg.BuildingTag) then
			return true
		end
		a = a.Parent
	end
	return false
end

-- The side's tree jobs this tick, on `sb.open` (Commander, after its build list): the standing trees in the way of its
-- works, nearest first, the first Trees.open of them; none once the side has felled Trees.perSide.
function Fell.list(side: string, sb: SideBuild?)
	local s = sideOf(side)
	for _, r in s.jobs do
		r.open = false
	end
	if not sb or not sb.front or not BotBuild.mayFell(s.felled, nil, T) then
		s.jobs = {}
		return
	end
	local ways: { { ax: number, az: number, bx: number, bz: number } } = {}
	for _, l in sb.lines do
		table.insert(ways, { ax = l.ax, az = l.az, bx = l.bx, bz = l.bz })
	end
	for _, r in sb.lay do
		local j = r.job
		if Kinds[j.key] then
			local x, z = if r.at then r.at.X else j.x, if r.at then r.at.Z else j.z
			table.insert(ways, { ax = x, az = z, bx = x, bz = z })
			if j.key ~= "MGNest" then
				table.insert(ways, BotBuild.fireLine(x, z, j.fx, j.fz, T.fireLine))
			end
		end
	end
	local seen: { [Model]: boolean } = {}
	local found: { Model } = {}
	local spots: { { x: number, z: number, building: boolean? } } = {}
	for _, w in ways do
		for _, tree in Trees.near(Vector3.new(w.ax, 0, w.az), Vector3.new(w.bx, 0, w.bz), T.clear) do
			if not seen[tree] and tree.Parent and Trees.standing(tree) then
				seen[tree] = true
				local p = tree:GetPivot().Position
				table.insert(found, tree)
				table.insert(spots, { x = p.X, z = p.Z, building = inBuilding(tree) })
			end
		end
	end
	local keep: { [Model]: BuildJob } = {}
	for k, i in BotBuild.treesInWay(spots, ways, T.clear) do
		if k > T.open then
			break
		end
		local tree = found[i]
		local r = s.jobs[tree]
		if not r then
			local at = tree:GetPivot().Position
			local job = { key = "Tree", x = at.X, z = at.Z, fx = 0, fz = 1, work = true }
			r = { job = job, base = job, model = tree, at = at, tries = 0, waitUntil = 0, left = 1, open = true }
			counts.listed += 1
		end
		local rr = r :: BuildJob
		rr.open = true
		keep[tree] = rr
		table.insert(sb.open, rr)
	end
	-- (a felled tree's stump still to clear stays on, and the one being chopped, nearest or not)
	for tree, r in s.jobs do
		local st = stumpOf[r]
		if st and st.Parent and not keep[tree] then
			r.open = true
			keep[tree] = r
			table.insert(sb.open, r)
		elseif st and not st.Parent then
			stumpOf[r] = nil
		end
	end
	local c = s.current
	if c and not keep[c.tree] then
		local r = s.jobs[c.tree]
		if r and (Trees.standing(c.tree) or stumpOf[r]) then
			r.open = true
			keep[c.tree] = r
			table.insert(sb.open, r)
		else
			s.current = nil
		end
	end
	s.jobs = keep
end

-- whether bot `id` may take a tree job now (one per Engineer every Trees.every s)
function Fell.ready(id: number): boolean
	local last = lastFell[id]
	return BotBuild.mayFell(0, if last then os.clock() - last else nil, T)
end

-- One Destroy swing by bot `model` (its BotId `id`, its side `side`) at tree job `r`'s trunk, then its stump, as
-- Build.workAs: nil when it landed. A tree that falls counts to its side; the job closes once its stump is cleared too.
function Fell.chop(model: Model, id: number, side: string, r: BuildJob): string?
	local tree = r.model
	local st = stumpOf[r]
	if st then
		if not st.Parent then
			stumpOf[r] = nil
			r.open = false
			return "Gone"
		end
		local reason = Build.workAs(model, st, "Destroy")
		if reason ~= nil then
			return reason
		end
		counts.swings += 1
		if not st.Parent then
			stumpOf[r] = nil
			sideOf(side).current = nil
			counts.stumps += 1
			r.open = false
		end
		return nil
	end
	local trunk = tree and tree:FindFirstChild("Trunk")
	if not tree or not trunk or not Trees.standing(tree) then
		r.open = false
		return "Gone"
	end
	local reason = Build.workAs(model, trunk, "Destroy")
	if reason ~= nil then
		return reason
	end
	counts.swings += 1
	local s = sideOf(side)
	s.current = { tree = tree, name = tree.Name, at = r.at :: Vector3, by = model.Name }
	if not Trees.standing(tree) then
		-- (where it lies and its imprint, put back at the next match)
		local p, size = tree:GetPivot().Position, tree:GetExtentsSize()
		local reach = math.max(size.X, size.Y, size.Z) + 8
		DevWorld.touch(p - Vector3.one * reach, p + Vector3.one * reach)
		s.felled += 1
		-- (not left lying across the lines it was felled for: Trenches' "In the way", user 2026-11-04 trench priority)
		Trees.clearAway(tree)
		counts.felled += 1
		lastFell[id] = os.clock()
		local stump = tree and Trees.stumpOf(tree)
		if stump then
			stumpOf[r] = stump
			s.current = { tree = tree, name = `{tree.Name} stump`, at = r.at :: Vector3, by = model.Name }
		else
			s.current = nil
			r.open = false
		end
	end
	return nil
end

-- The admin panel's tree readout (Config/DevTools.Admin.BotTrees): each side's trees felled and the one being chopped,
-- on Workspace
function Fell.readout()
	local A = DevCfg.Admin.BotTrees
	for _, side in { "West", "East" } do
		local s = sideOf(side)
		local c = s.current
		local waiting = 0
		for _, r in s.jobs do
			waiting += if r.open then 1 else 0
		end
		local now = if c
			then `now {c.name} at ({math.round(c.at.X)}, {math.round(c.at.Z)}) by {c.by}`
			else `{waiting} waiting`
		workspace:SetAttribute(A.attribute .. side, `{side}: {s.felled}/{T.perSide} felled · {now}`)
	end
end

-- the report line's counters since the last (then cleared): tree jobs put on the lists, swings at trunks and stumps,
-- trees felled, stumps cleared, each side's felled this match
function Fell.report(): string
	local w, e = sideOf("West"), sideOf("East")
	local text = `trees {counts.listed} listed, {counts.swings} chops, {counts.felled} felled, {counts.stumps} stumps `
		.. `cleared (W {w.felled}, E {e.felled})`
	counts.listed, counts.swings, counts.felled, counts.stumps = 0, 0, 0, 0
	return text
end

-- a new match (Bots.forgetMap): the counts start again
function Fell.clear()
	table.clear(sides)
	table.clear(lastFell)
	table.clear(stumpOf)
end

return Fell
