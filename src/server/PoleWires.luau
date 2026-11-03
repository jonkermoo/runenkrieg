--!strict
-- The telegraph wires come down with their poles (user 2026-11-03: "make sure the telephone pole wires disappear too";
-- Config/Destruction.Wires, Rules/PoleWires). The map builds each wire as loose segments in a "Wires" folder beside
-- the poles (src/dev/Greybox/VillageBuild, src/dev/Props.wire); at the start each span between two poles becomes one
-- model, tagged so the match reset puts it back (src/server/DevWorld). When a pole a span hangs from goes (blown up,
-- shot to pieces, its top cut off to Remains), the span falls as debris (Net "SectionBroken", "fall": src/client/Debris)
-- and goes; a pole put back by the reset is a new pole, and its spans hang from it again.
--   PoleWires.start()

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local D = require(Shared.Config.Destruction)
local Rules = require(Shared.Rules.PoleWires)
local Net = require(Shared.Net)
local Hitches = require(Shared.Hitches)

local W = D.Wires

local PoleWires = {}

local function point(v: Vector3): Rules.Point
	return { v.X, v.Y, v.Z }
end

-- the poles' insulator points beside a span (its Wires folder's parent), each with the pole section it is on
local function insulators(span: Model): ({ Rules.Point }, { Model })
	local points, sections = {}, {}
	local poles = span.Parent and span.Parent.Parent
	if not poles then
		return points, sections
	end
	for _, d in poles:GetDescendants() do
		if d:IsA("Attachment") and string.match(d.Name, "^Wire%d$") then
			local s = d:FindFirstAncestorWhichIsA("Model")
			while s and not CollectionService:HasTag(s, D.SectionTag) do
				s = s:FindFirstAncestorWhichIsA("Model")
			end
			if s then
				table.insert(points, point(d.WorldPosition))
				table.insert(sections, s)
			end
		end
	end
	return points, sections
end

-- the span falls (every client's debris) and goes
local function drop(span: Model)
	local pieces = {}
	for _, p in span:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(pieces, { cf = p.CFrame, size = p.Size, color = p.Color, t = p.Transparency, m = "fall" })
		end
	end
	if #pieces > 0 then
		Net.event("SectionBroken"):FireAllClients(pieces, span:GetPivot().Position)
	end
	span:Destroy()
end

-- the poles each span watches (a pole section going: is the span still held?)
local watched: { [Model]: { [Model]: boolean } } = {}

local link: (Model) -> ()

local function check(span: Model)
	if not span.Parent then
		return
	end
	local points = insulators(span)
	local a, b = span:GetAttribute("A"), span:GetAttribute("B")
	if
		typeof(a) == "Vector3"
		and typeof(b) == "Vector3"
		and Rules.held(point(a), points, W.reach)
		and Rules.held(point(b), points, W.reach)
	then
		link(span) -- (still held: the reset put a new pole up in the old one's place)
	else
		drop(span)
	end
end

-- watch the pole sections holding the span's ends
link = function(span: Model)
	local a, b = span:GetAttribute("A"), span:GetAttribute("B")
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return
	end
	local mine = watched[span] or {}
	watched[span] = mine
	local points, sections = insulators(span)
	for i, p in points do
		local s = sections[i]
		if not mine[s] and (Rules.held(p, { point(a) }, W.reach) or Rules.held(p, { point(b) }, W.reach)) then
			mine[s] = true
			s.Destroying:Connect(function()
				mine[s] = nil
				-- (deferred: the reset puts the new pole up in the same step it takes the old one away)
				task.defer(check, span)
			end)
		end
	end
end

-- a Wires folder's loose segments, one model per span
local function group(folder: Instance)
	local parts: { BasePart } = {}
	local segs: { Rules.Segment } = {}
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			local half = Vector3.new(0, 0, p.Size.Z / 2)
			table.insert(parts, p)
			table.insert(
				segs,
				{ a = point(p.CFrame:PointToWorldSpace(half)), b = point(p.CFrame:PointToWorldSpace(-half)) }
			)
		end
	end
	local stops = {}
	for _, a in (folder.Parent :: Instance):GetDescendants() do
		if a:IsA("Attachment") and string.match(a.Name, "^Wire%d$") then
			table.insert(stops, point(a.WorldPosition))
		end
	end
	for _, s in Rules.spans(segs, W.join, stops) do
		local span = Instance.new("Model")
		span.Name = "WireSpan"
		span:SetAttribute("A", Vector3.new(s.a[1], s.a[2], s.a[3]))
		span:SetAttribute("B", Vector3.new(s.b[1], s.b[2], s.b[3]))
		for _, i in s.members do
			parts[i].Parent = span
		end
		span.Parent = folder
		CollectionService:AddTag(span, W.Tag)
	end
end

function PoleWires.start()
	local t0 = os.clock()
	for _, d in workspace:GetDescendants() do
		if d:IsA("Folder") and d.Name == "Wires" and d.Parent and d.Parent.Name == "Poles" then
			group(d)
		end
	end
	for _, span in CollectionService:GetTagged(W.Tag) do
		link(span :: Model)
	end
	-- a span the reset put back: it hangs from the poles there now
	CollectionService:GetInstanceAddedSignal(W.Tag):Connect(function(span)
		task.defer(link, span :: Model)
	end)
	CollectionService:GetInstanceRemovedSignal(W.Tag):Connect(function(span)
		watched[span :: Model] = nil
	end)
	Hitches.since("Pole wires", t0)
end

return PoleWires
