--!strict
-- Player building on the server (phase 4.4; Config/Build, Rules/Build, shared/BuildSurvey). The client lays a
-- blueprint (Net "Build" "Place": the piece and where); the server surveys the ground, checks the rules and the caps,
-- and lays it in Workspace[Config/Build.Folder]. Trenches are planned and dug in src/server/Trenches (Net "Build"
-- "Plan": start and end).
-- Every shovel swing (Net "Build" "Work", the target and the shovel's mode, user 2026-10-23):
-- - Build at your team's piece adds a unit of work; it rises in stages and stands at full work;
-- - Destroy at any piece, any team's, takes one off; at 0 it is torn down; at a tree it chops it (src/server/Trees).
-- - Sandbag piles: Config/Assets sandbag_pile's bags in one "Sandbag" section, on HP (Config/Build.Sandbags.hp): laid
--   at stage 1 (scraped ground, empty sacks), Build swings add HP, Destroy swings and weapons take it, its bags
--   standing by HP.
-- - Barbed wire: Config/Assets barbed_wire's meshes in three looks (Rules.wireLook: on the ground, standing, broken),
--   nothing queries them (bullets pass); src/server/Wire slows soldiers in it and hurts the enemy. Once it has stood,
--   swings go to its HP (Rules.wireSwing): Destroy breaks it then takes it away, its team's Build stands it back up.
-- - Hesco barriers (kind "Hesco"; Config/Build.Hesco): on HP (its work is its HP), laid with the empty perimeter
--   standing; the model's pieces for the stage its HP stands at (Rules.hescoStage: the perimeter, then the dirt rising,
--   slumping as it wears), cloned from the asset library; only the dirt collides and stops bullets; gone at 0.
-- - Guns (Config/Build.Pieces kind "Gun"; Config/Build.Guns): a holder model in the folder (what swings go to) with the
--   gun's parts in it (src/server/Artillery.parts), laid out on the ground and fitted a quarter of the work at a time
--   (Artillery.assemble, Config/Artillery.Assembly), a building site round them (Rules/Scaffold); a howitzer's pit (Ground.pit from the ground as it was) deepens
--   with each stage, the parts down on its floor. At full work the real gun stands (src/server/Artillery.place, in the
--   team's paint), its HP shown on the holder ("HP", "MaxHP") for the shovel's panel; taken apart (Rules.gunStands) it
--   is in parts again, its pit filling back, the ground as it was at 0.
-- - Bridges (Config/Build.Bridge): laid on a trench square (Survey.bridgeSpot), its planks the Config/Assets
--   bridge_pieces layout its seed rolls, stretched to the square's length; on HP (Bridge.hp): laid at stage 1, Build
--   swings add HP, Destroy swings and weapons take it, its boards standing by HP (Rules.bridgeStage). At 0, or once its
--   square is buried under Trench.hp.bare% (or gone), it is simply gone: no debris.
-- Build.blast (from src/server/Damage.blast) and Build.shot (src/server/Firing): weapons wear down trenches, sandbags,
-- wire and bridges by Config/Build.Structures.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local D = require(Shared.Config.Destruction)
local Palette = require(Shared.Config.Palette)
local Assets = require(Shared.Config.Assets)
local ShovelCfg = require(Shared.Config.Shovel)
local ArtilleryCfg = require(Shared.Config.Artillery)
local W = require(Shared.Config.Weapons)
local DevCfg = require(Shared.Config.DevTools)
local Rules = require(Shared.Rules.Build)
local Scaffold = require(Shared.Rules.Scaffold)
local Survey = require(Shared.BuildSurvey)
local Net = require(Shared.Net)
local Destruction = require(script.Parent.Destruction)
local Ground = require(script.Parent.Ground)
local Trees = require(script.Parent.Trees)
local Trenches = require(script.Parent.Trenches)
local Loadouts = require(script.Parent.Loadouts)

local Build = {}

-- the shortest time between two shovel strikes (a swing comes too soon under SwingSlack of it)
local GAP = Rules.strikeGap({ ShovelCfg.Dig, ShovelCfg.Chip })

type Rec = {
	model: Model,
	piece: Rules.Piece,
	team: string,
	owner: number,
	work: number,
	need: number,
	built: boolean, -- has stood once
	paid: boolean?, -- its builder has had the points for it (once per piece)
	born: number,
	worked: number,
	frame: CFrame,
	hp: number?, -- barbed wire: what blasts and Destroy swings have left of Structures.wireHP
	grassed: boolean?, -- barbed wire: the grass under it cleared
	base: CFrame?, -- a Hesco barrier: its footprint's centre on the lowest ground under it
	shown: number?, -- a Hesco barrier: the stage its pieces show
	stageParts: { [number]: { BasePart } }?, -- a Hesco barrier: every stage's pieces, laid out once
	-- a gun piece: where the gun stands (on the ground before its pit), its blueprint or the gun standing, its pit's
	-- ground as it was (Ground.pitBase) and the share of it dug now
	at: CFrame?,
	parts: Model?,
	site: Model?, -- its scaffold and tools while it is built (Config/Build.Scaffold)
	gun: Model?,
	standing: boolean?,
	pitBase: Ground.PitBase?,
	dug: number?,
	square: Model?, -- a bridge: the trench square it is on
	watch: { RBXScriptConnection }?, -- and its watch on that square
}

-- src/server/Artillery, handed in at start (it needs Damage, which needs this)
type Guns = {
	place: (string, Vector3, Vector3, { paint: string?, dug: boolean? }?) -> Model?,
	parts: (string, string?) -> Model?,
	assemble: (Model, string, CFrame, number) -> (),
	repair: (Model, number) -> (string?, number),
	setHp: (Model, number) -> (),
	harm: (Model, number) -> boolean,
}
local guns: Guns? = nil

local recs: { [Model]: Rec } = {}
local bridgeRoll = Random.new() -- (each bridge's board layout, Config/Build.Bridge.variants)
local showGun: (Rec) -> ()
local lastSwing: { [Player]: number } = {}

local function rgb(c: { number }, jitter: number?): Color3
	local k = 1 + (jitter or 0)
	return Color3.fromRGB(math.clamp(c[1] * k, 0, 255), math.clamp(c[2] * k, 0, 255), math.clamp(c[3] * k, 0, 255))
end

local function folder(): Folder
	local f = workspace:FindFirstChild(C.Folder)
	if not f then
		f = Instance.new("Folder")
		f.Name = C.Folder
		f.Parent = workspace
	end
	return f :: Folder
end

local function teamOf(character: Model): string?
	local kit = character:GetAttribute("Kit")
	return if type(kit) == "string" then kit else nil
end

local function holdsShovel(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	local name = tool and tool:GetAttribute("Weapon")
	return type(name) == "string" and W[name] ~= nil and W[name].class == "Shovel"
end

-- a dev player's admin dig step (Config/DevTools.Admin.Dig, set by src/server/DevTools), nil for everyone else
local function digShare(player: Player): number?
	local share = player:GetAttribute(DevCfg.Admin.Dig.attribute)
	return if player:GetAttribute(DevCfg.Attribute) == true and type(share) == "number" then share else nil
end

-- a dev player with the admin panel's build anything on (Config/DevTools.Admin.BuildAllAttribute): any class builds
-- every piece
local function buildsAll(player: Player): boolean
	return player:GetAttribute(DevCfg.Attribute) == true and player:GetAttribute(DevCfg.Admin.BuildAllAttribute) == true
end

local function refuse(player: Player, reason: string)
	Net.event("Build"):FireClient(player, "Refused", reason)
end

local function newPart(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.CastShadow = true
	p.Parent = model
	return p
end

local function section(parent: Instance, name: string, kind: string, class: string, hp: number): Model
	local s = Instance.new("Model")
	s.Name = name
	s:SetAttribute("Kind", kind)
	s:SetAttribute("Class", class)
	s:SetAttribute("Story", 0)
	s:SetAttribute("MaxHP", hp)
	s:SetAttribute("HP", hp)
	s.Parent = parent
	CollectionService:AddTag(s, D.SectionTag)
	return s
end

-- the bags of a sandbag pile: the first `stage` stand, the rest ghosted; stage 1's scraped ground always shows, its
-- empty sacks only while no bag stands
local function showSandbags(r: Rec, stage: number)
	for _, s in r.model:GetChildren() do
		for _, p in s:GetChildren() do
			if p:IsA("BasePart") then
				local look = p:GetAttribute("Look")
				if look == "Sacks" then
					p.Transparency = if stage == 0 then 0 else 1
				elseif look ~= "Ground" then
					local row = p:GetAttribute("Row") :: number
					local up = row <= stage
					p.Transparency = if up then 0 else C.GhostTransparency
					p.CanCollide = up
					p.CanQuery = up -- (bullets pass through the ghost)
				end
			end
		end
	end
end

-- A piece's library model (Config/Assets `key`, in ReplicatedStorage.Assets, kept by the Library sync: the barbed wire,
-- the sandbag pile, the bridge planks) and each mesh's place from its Origin (piece space: x along, y up from the ground, z across), found
-- once
local kits: { [string]: { model: Model, offsets: { [string]: CFrame } } } = {}
local function libraryKit(key: string): (Model?, { [string]: CFrame })
	local kit = kits[key]
	if kit then
		return kit.model, kit.offsets
	end
	local e = Assets.Entries[key]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, sub in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(sub)
	end
	local m = f and f:FindFirstChild(key)
	local origin = m and m:FindFirstChild("Origin")
	if not (m and origin and origin:IsA("BasePart")) then
		warn("[Build] " .. key .. " is not in the asset library: run the Library sync in the dev place")
		return nil, {}
	end
	local offsets = {}
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d ~= origin then
			offsets[d.Name] = origin.CFrame:ToObjectSpace(d.CFrame)
		end
	end
	kits[key] = { model = m :: Model, offsets = offsets }
	return m :: Model, offsets
end

-- a sandbag pile (Config/Build.Pieces `bags`): its meshes from the library in one section, each bag's with the "Row" of
-- its bag (Rules.pileBag) so it stands and ghosts by stage (showSandbags), stage 1's (`stage1`) with its "Look"; false
-- when the library has no pile
local function layoutPile(r: Rec, ground: number): boolean
	local p = r.piece
	local kit, offsets = libraryKit(p.asset)
	if not kit then
		return false
	end
	local base = CFrame.new(r.frame.Position.X, ground - C.Sandbags.sink, r.frame.Position.Z) * r.frame.Rotation
	local s = section(r.model, "Pile", "Sandbags", "Sandbag", C.Sandbags.hp.max)
	s:SetAttribute("HP", r.work)
	for _, d in kit:GetChildren() do
		local bag = Rules.pileBag(d.Name, p.bags)
		local offset = offsets[d.Name]
		if bag and offset and d:IsA("BasePart") then
			local part = d:Clone()
			part.Anchored = true
			part.Material = Enum.Material.SmoothPlastic
			local jitter = ((bag * 37) % 7 / 6 - 0.5) * 2 * C.Sandbags.shade
			part.Color = if Rules.isPileCord(d.Name)
				then rgb(Palette.Build.SandbagCord)
				else rgb(Palette.Build.Sandbag, jitter)
			part.CFrame = base * offset
			part:SetAttribute("Row", bag)
			part.Parent = s
		elseif offset and d:IsA("BasePart") and (d.Name == p.stage1.ground or d.Name == p.stage1.sacks) then
			-- stage 1: on the ground, blocking nothing (soldiers walk and bullets pass over it)
			local part = d:Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Material = Enum.Material.SmoothPlastic
			local isGround = d.Name == p.stage1.ground
			part.Color = rgb(if isGround then Palette.Build.SandbagPatch else Palette.Build.SandbagSacks)
			part.CFrame = r.frame * offset -- (on the ground at its centre, not sunk with the bags)
			part:SetAttribute("Look", if isGround then "Ground" else "Sacks")
			part.Parent = s
		end
	end
	return true
end

-- which look (Rules.wireLook) a barbed_wire mesh belongs to: Bundle* on the ground, Wreck* broken, the rest standing
local function wireLookOf(name: string): string
	return if string.sub(name, 1, 6) == "Bundle"
		then "Bundle"
		elseif string.sub(name, 1, 5) == "Wreck" then "Broken"
		else "Standing"
end

local function layoutWire(r: Rec, ground: number)
	local base = CFrame.new(r.frame.Position.X, ground, r.frame.Position.Z) * r.frame.Rotation
	local holder = Instance.new("Folder")
	holder.Name = "Wire"
	holder.Parent = r.model
	local kit, offsets = libraryKit("barbed_wire")
	if not kit then
		return
	end
	for _, d in kit:GetChildren() do
		local offset = offsets[d.Name]
		if offset and d:IsA("BasePart") then
			local part = d:Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Material = Enum.Material.SmoothPlastic
			part.Color = rgb(if string.find(d.Name, "Pickets") then Palette.Build.Picket else Palette.Build.Wire)
			part.CFrame = base * offset
			part:SetAttribute("Look", wireLookOf(d.Name))
			part.Parent = holder
		end
	end
end

-- the wire's look (Rules.wireLook): bundled on the ground from the moment it is laid, standing at full work, broken
-- under half HP; it slows and hurts only standing ("Armed"). The grass goes from under it as it is laid.
local function showWire(r: Rec)
	local holder = r.model:FindFirstChild("Wire")
	if not holder then
		return
	end
	local maxHP = C.Structures.wireHP
	local look = Rules.wireLook(r.built, r.work, r.need, r.hp or maxHP, maxHP, C.Wire)
	for _, p in holder:GetChildren() do
		if p:IsA("BasePart") then
			p.Transparency = if p:GetAttribute("Look") == look then 0 else 1
			p.CastShadow = p.Transparency == 0
		end
	end
	r.model:SetAttribute("Look", look)
	r.model:SetAttribute("Armed", look == "Standing")
	if not r.grassed then
		r.grassed = true
		Net.event("GroundDug"):FireAllClients(r.frame.Position, C.Wire.grass)
	end
end

-- a wire shakes and rattles (src/client/WireShake) from `at`: when it takes damage (Destroy swings, blasts; user
-- 2026-10-27: "both", as well as each tick it hurts someone, src/server/Wire)
local function shakeWire(r: Rec, at: Vector3)
	r.model:SetAttribute("RattleFrom", at)
	r.model:SetAttribute("ShakeAt", workspace:GetServerTimeNow())
end

-- The Hesco barrier's library model (ReplicatedStorage.Assets, kept by the Library sync) and where each mesh sits from
-- its Origin (piece space), found once
local hescoKit: Model? = nil
local hescoAt: { [string]: CFrame } = {}
local hescoWarned = false
local function hescoPieces(asset: string): Model?
	if hescoKit then
		return hescoKit
	end
	local e = Assets.Entries[asset]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and e and f:FindFirstChild(e.category)
	for _, sub in string.split(if e then e.folder else "", "/") do
		f = f and f:FindFirstChild(sub)
	end
	local m = f and f:FindFirstChild(asset)
	local origin = m and m:FindFirstChild("Origin")
	if not (m and origin and origin:IsA("BasePart")) then
		if not hescoWarned then
			hescoWarned = true
			warn(`[Build] {asset} is not in the asset library: run the Library sync in the dev place`)
		end
		return nil
	end
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			hescoAt[d.Name] = origin.CFrame:ToObjectSpace(d.CFrame)
		end
	end
	hescoKit = m :: Model
	return hescoKit
end

-- a Hesco barrier's pieces, every stage's laid out once (cloned from the asset library) in a holder per stage
-- ("Stage<s>"), all hidden: a change of stage only shows one and hides another (cloning a stage's meshes at each change
-- was slow to show, user round 5)
local function layHesco(r: Rec): boolean
	if r.stageParts then
		return true
	end
	local kit = hescoPieces(r.piece.asset)
	if not kit then
		return false
	end
	local base = r.base :: CFrame
	local out: { [number]: { BasePart } } = {}
	for s = 0, r.piece.stages do
		local holder = Instance.new("Model")
		holder.Name = "Stage" .. s
		out[s] = {}
		for name, off in hescoAt do
			local kind, n = string.match(name, "^(%a+)(%d)$")
			local src = kit:FindFirstChild(name)
			if kind and tonumber(n) == s and src and src:IsA("BasePart") then
				local part = src:Clone()
				part.Anchored = true
				part.Material = Enum.Material.SmoothPlastic
				part.Color = rgb(Palette.Build.Hesco[kind])
				part.CFrame = base * off
				part.CanTouch = false
				part:SetAttribute("Blocks", table.find(C.Hesco.blocks, kind) ~= nil)
				part.Transparency = 1
				part.CanCollide = false
				part.CanQuery = false
				part.CastShadow = false
				part.Parent = holder
				table.insert(out[s], part)
			end
		end
		holder.Parent = r.model
	end
	r.stageParts = out
	return true
end

-- shows or hides stage `s`'s pieces; only Config/Build.Hesco.blocks (the dirt) collide or are hit
local function showStage(r: Rec, s: number, on: boolean)
	for _, part in (r.stageParts :: any)[s] or {} do
		local blocks = on and part:GetAttribute("Blocks") == true
		part.Transparency = if on then 0 else 1
		part.CastShadow = on
		part.CanCollide = blocks
		part.CanQuery = blocks -- (bullets pass the mesh and liner)
	end
end

-- a Hesco barrier as its HP stands (its work: Config/Build.Hesco.hp): the stage it stands at shown, its HP on the
-- model for the shovel's panel, like a gun's
local function showHesco(r: Rec)
	r.model:SetAttribute("HP", math.ceil(r.work))
	r.model:SetAttribute("MaxHP", r.need)
	local stage = Rules.hescoStage(r.work, r.need, r.piece.stages)
	if r.shown == stage or not layHesco(r) then
		return
	end
	if r.shown then
		showStage(r, r.shown, false)
	end
	showStage(r, stage, true)
	r.shown = stage
end

-- A bridge's planks (Config/Assets bridge_pieces): the layout its seed rolls (Rules.bridgeVariant), maybe turned round,
-- stretched along the trench to its square's `length`, and the unseen plate along the deck that you walk on
local function layoutBridge(r: Rec, length: number, seed: number)
	local kit, offsets = libraryKit("bridge_pieces")
	local p = r.piece
	local v, turned = Rules.bridgeVariant(seed, C.Bridge.variants)
	local cf = r.frame * (if turned then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
	local stretch = length / p.width
	for _, set in { "Frame", "Boards", "More" } do
		for _, tone in { "", "Dark" } do
			local name = `Bridge{v}{set}{tone}`
			local src = kit and kit:FindFirstChild(name)
			local off = offsets[name]
			if src and src:IsA("BasePart") and off then
				local part = src:Clone()
				part.Size = Vector3.new(src.Size.X * stretch, src.Size.Y, src.Size.Z)
				part.CFrame = cf * CFrame.new(off.Position.X * stretch, off.Position.Y, off.Position.Z) * off.Rotation
				part.Color = rgb(if tone == "Dark" then Palette.Build.BridgeDark else Palette.Build.Bridge)
				part.Anchored = true
				part.Material = Enum.Material.SmoothPlastic
				part.CanCollide = false
				part.CanQuery = false -- (bullets pass the planks)
				part.CanTouch = false
				part:SetAttribute("Set", set)
				part.Parent = r.model
			end
		end
	end
	local plate = newPart(
		r.model,
		"Walk",
		Vector3.new(length, C.Bridge.plate, p.depth),
		r.frame * CFrame.new(0, p.height - C.Bridge.plate / 2, 0),
		rgb(Palette.Build.Bridge)
	)
	plate.Transparency = 1
	plate.CastShadow = false
	plate.CanTouch = false
end

-- a bridge as its HP stands (its work; Rules.bridgeStage): the frame and stage 1's boards, then all of them; walkable
-- while it stands. Its HP on the model for the shovel's panel.
local function showBridge(r: Rec)
	r.model:SetAttribute("HP", math.ceil(r.work))
	r.model:SetAttribute("MaxHP", r.need)
	local stage = Rules.bridgeStage(r.work, r.need)
	for _, part in r.model:GetChildren() do
		if part:IsA("BasePart") then
			if part.Name == "Walk" then
				part.CanCollide = stage >= 1
				part.CanQuery = stage >= 1
			else
				part.Transparency = if stage >= 2 or part:GetAttribute("Set") ~= "More" then 0 else 1
			end
		end
	end
end

local function remove(r: Rec, debris: boolean)
	if not recs[r.model] then
		return
	end
	recs[r.model] = nil
	for _, c in r.watch or {} do
		c:Disconnect()
	end
	if debris then
		local pieces = {}
		for _, d in r.model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(pieces, { cf = d.CFrame, size = d.Size, color = d.Color, t = d.Transparency })
			end
		end
		if #pieces > 0 then
			Net.event("SectionBroken"):FireAllClients(pieces, r.frame.Position)
		end
	end
	-- a gun piece: the gun goes, its pit filled back in
	local gun = r.gun
	r.gun = nil
	if gun then
		gun:Destroy()
	end
	if r.pitBase and (r.dug or 0) > 0 then
		Ground.restore(r.pitBase)
		Net.event("GroundDug"):FireAllClients(r.frame.Position, r.piece.depth)
	end
	r.model:Destroy()
end

-- a Hesco barrier worn by `amount` of its HP: its dirt slumps; at 0 it is gone, no rubble (Config/Build.Hesco)
local function wearHesco(r: Rec, amount: number)
	r.work = math.max(r.work - amount, 0)
	r.model:SetAttribute("Work", r.work)
	if r.work <= 0 then
		remove(r, false)
	else
		showHesco(r)
	end
end

-- a gun's building site (Config/Build.Scaffold, Rules/Scaffold) at gun space's origin; Build pivots it onto the floor
local function buildSite(spec: { [string]: any }): Model
	local model = Instance.new("Model")
	model.Name = "Site"
	local colors = Palette.Build.Scaffold :: { [string]: { number } }
	for _, piece in Scaffold.pieces(spec, C.Scaffold.Sizes) do
		local a = Vector3.new(piece.a[1], piece.a[2], piece.a[3])
		local b = Vector3.new(piece.b[1], piece.b[2], piece.b[3])
		local up = Vector3.new(piece.up[1], piece.up[2], piece.up[3])
		local mid = (a + b) / 2
		local p = newPart(
			model,
			piece.color,
			Vector3.new(piece.w, piece.h, (b - a).Magnitude),
			CFrame.lookAt(mid, b, up),
			rgb(colors[piece.color])
		)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	model.WorldPivot = CFrame.new()
	return model
end

-- a gun piece as its work stands: its pit dug to its stage, then its parts on the pit's floor, fitted to the quarter of
-- the work done, or the gun standing there (Rules.gunStands, Rules.pitShare)
showGun = function(r: Rec)
	local p = r.piece
	local gunCfg = ArtilleryCfg.Guns[p.gun]
	local at = r.at :: CFrame
	if not guns or not gunCfg then
		return
	end
	r.standing = Rules.gunStands(r.standing == true, r.work, r.need, C.Guns.standsFrom)
	local share = Rules.pitShare(r.standing == true, r.work, r.need, p.stages)
	local d = gunCfg.dig
	if d and share ~= r.dug then
		local back = -at.LookVector
		local ramp = d.ramp and { dir = back, width = d.ramp.width, length = d.ramp.length }
		r.pitBase = r.pitBase or Ground.pitBase(at.Position, d.radius, d.depth, d.rim, d.rimHeight, ramp, d.wall)
		local base = r.pitBase
		if base then
			if share > 0 then
				local out =
					Ground.pit(at.Position, d.radius, d.depth * share, d.rim, d.rimHeight * share, ramp, d.wall, base)
				Net.event("GroundDug"):FireAllClients(at.Position, out)
			else
				Ground.restore(base)
				Net.event("GroundDug"):FireAllClients(at.Position, p.depth)
			end
		end
		r.dug = share
	end
	local paint = C.Guns.paint[r.team]
	if r.standing then
		if not r.gun then
			if r.parts then
				r.parts:Destroy()
			end
			if r.site then
				r.site:Destroy()
			end
			r.parts, r.site = nil, nil
			local gun = guns.place(p.gun, at.Position, at.LookVector, { paint = paint, dug = d ~= nil })
			r.gun = gun
			if gun then
				gun:SetAttribute("Piece", p.key)
				-- its HP on the holder, for the shovel's panel (src/client/Build)
				local function hp()
					r.model:SetAttribute("HP", gun:GetAttribute("HP"))
				end
				r.model:SetAttribute("MaxHP", gunCfg.hp)
				hp()
				gun:GetAttributeChangedSignal("HP"):Connect(hp)
				-- gone some other way (the dev tools' clear): the piece goes too
				gun.Destroying:Connect(function()
					if r.gun == gun then
						r.gun = nil
						remove(r, false)
					end
				end)
			end
		end
		return
	end
	if r.gun then
		local gun = r.gun
		r.gun = nil
		gun:Destroy()
		r.model:SetAttribute("HP", nil)
		r.model:SetAttribute("MaxHP", nil)
	end
	if not r.parts then
		r.parts = guns.parts(p.gun, paint)
		if r.parts then
			r.parts.Parent = r.model
		end
	end
	local floor = at.Position - Vector3.new(0, if d then d.depth * share else 0, 0)
	local on = CFrame.lookAt(floor, floor + at.LookVector)
	if r.parts then
		local quarters = Rules.stageOf(r.work, r.need, ArtilleryCfg.Assembly.quarters)
		guns.assemble(r.parts, p.gun, on, quarters)
	end
	local spec = C.Scaffold[p.gun]
	if not r.site and spec then
		r.site = buildSite(spec)
		r.site.Parent = r.model
	end
	if r.site then
		r.site:PivotTo(on)
	end
end

-- shows a piece as its work stands now
local function apply(r: Rec)
	r.model:SetAttribute("Work", r.work)
	r.model:SetAttribute("Built", r.built)
	local kind = r.piece.kind
	if kind == "Sandbags" then
		-- (its work is its HP: shown on the shovel's panel like a gun's)
		r.model:SetAttribute("HP", r.work)
		r.model:SetAttribute("MaxHP", r.need)
		showSandbags(r, Rules.pileBags(r.work, C.Sandbags.hp.swing, #r.piece.bags))
	elseif kind == "Wire" then
		showWire(r)
	elseif kind == "Gun" then
		showGun(r)
	elseif kind == "Hesco" then
		showHesco(r)
	elseif kind == "Bridge" then
		showBridge(r)
	end
end

local function count(team: string, owner: number?): number
	local n = 0
	for _, r in recs do
		if r.team == team and (owner == nil or r.owner == owner) then
			n += 1
		end
	end
	return n
end

-- the soldier's character, root and team when they hold the shovel
local function digger(player: Player): (Model?, BasePart?, string?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root or not holdsShovel(character) then
		return nil, nil, nil
	end
	return character, root, teamOf(character)
end

-- Lays a blueprint (Net "Build" "Place")
local function place(player: Player, key: any, at: any)
	local character, root, team = digger(player)
	local piece = Rules.piece(key, C.Pieces)
	if not character or not root or not team or not piece or typeof(at) ~= "CFrame" or piece.kind == "Trench" then
		return
	end
	local frame = Survey.frame(at.Position, at.LookVector)
	-- (a gun: `frame` the gun, `box` the ground it needs; any other piece: the same)
	local gunAt: CFrame? = nil
	if piece.kind == "Gun" then
		local y = Survey.groundAt(frame.Position.X, frame.Position.Z, frame.Position.Y) or frame.Position.Y
		gunAt = CFrame.new(frame.Position.X, y, frame.Position.Z) * frame.Rotation
		frame = Survey.box(piece, gunAt :: CFrame)
	end
	local f = folder()
	-- (a bridge: its trench square decides where it goes, not the ground)
	local bridge = piece.kind == "Bridge"
	local spot, square, length = nil, nil, nil
	if bridge then
		local s, sf, len, m = Survey.bridgeSpot(f, frame.Position)
		spot = Rules.bridgeSpot(s, C.Bridge)
		if sf and len then
			frame, length, square = sf, len, m
		end
	end
	local report = Survey.ground(piece, frame)
	if not bridge then
		frame = CFrame.new(frame.Position.X, report.centre, frame.Position.Z) * frame.Rotation
	end
	local gunPiece = gunAt ~= nil
	local ok, reason = Rules.canPlace({
		piece = piece,
		distance = (root.Position - (if gunAt then gunAt.Position else frame.Position)).Magnitude,
		reach = C.Reach + 2, -- (the client's ghost checks C.Reach; slack for movement since)
		spot = spot,
		slope = if bridge then 0 else report.slope,
		maxSlope = piece.maxSlope or C.Trench.maxSlope,
		ground = bridge or report.ground,
		water = not bridge and report.water,
		overlap = if bridge
			then Survey.onPiece(piece, frame, f)
			else Survey.blocked(piece, frame, report.low, { character }) or Survey.onPiece(piece, frame, f),
		gunGap = gunPiece and Survey.gunGap(piece, (gunAt :: CFrame).Position, f),
		-- (a wire keeps off trenches too: their hole, walls and bank)
		nearTrench = (gunPiece or piece.kind == "Wire") and Survey.nearTrench(piece, frame, f),
		mine = count(team, player.UserId),
		team = count(team, nil),
		perPlayer = C.PerPlayer,
		perTeam = C.PerTeam,
		-- (only engineers build guns: Config/Classes; the admin panel's build anything: everyone)
		allowed = Loadouts.mayBuild(character, piece.kind) or buildsAll(player),
	})
	if not ok then
		refuse(player, reason or "Can't build here")
		return
	end
	local model = Instance.new("Model")
	model.Name = piece.key
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local now = os.clock()
	-- (a sandbag pile's work is its HP: laid at stage 1, Config/Build.Sandbags.hp)
	local bags = piece.kind == "Sandbags"
	local r: Rec = {
		model = model,
		piece = piece,
		team = team,
		owner = player.UserId,
		-- (a sandbag pile's, a Hesco barrier's and a bridge's work is their HP, Config/Build.Sandbags.hp / Hesco.hp /
		-- Bridge.hp)
		work = if bags
			then C.Sandbags.hp.place
			elseif piece.kind == "Hesco" then C.Hesco.hp.place
			elseif bridge then C.Bridge.hp.place
			else 0,
		need = if bags
			then C.Sandbags.hp.max
			elseif piece.kind == "Hesco" then C.Hesco.hp.max
			elseif bridge then C.Bridge.hp.max
			else piece.work,
		built = bridge, -- (a bridge stands, crossable, from the moment it is laid)
		born = now,
		worked = now,
		frame = frame,
		at = gunAt,
	}
	if bags then
		if not layoutPile(r, report.low) then
			model:Destroy()
			refuse(player, "Can't build here") -- (the dev place's asset library lacks the pile: layoutPile warns)
			return
		end
	elseif piece.kind == "Wire" then
		layoutWire(r, report.low)
	elseif piece.kind == "Hesco" then
		r.base = CFrame.new(frame.Position.X, report.low, frame.Position.Z) * frame.Rotation
	elseif bridge and square and length then
		r.square = square
		layoutBridge(r, length, bridgeRoll:NextInteger(0, 2 ^ 20))
	end
	model:SetAttribute("Piece", piece.key)
	model:SetAttribute("Team", team)
	model:SetAttribute("Need", r.need)
	model:SetAttribute("Frame", frame)
	model:SetAttribute(
		"Size",
		if length then Vector3.new(length, piece.height, piece.depth) else Survey.footprint(piece)
	)
	if gunAt then
		model:SetAttribute("At", gunAt)
	end
	recs[model] = r
	model.Parent = f
	apply(r)
	-- a bridge falls in with its square: buried past where its dirt pieces go, or gone
	if square then
		local function check()
			local hp, max = square:GetAttribute("HP"), square:GetAttribute("MaxHP")
			local buried = type(hp) == "number" and type(max) == "number" and hp < max * C.Trench.hp.bare / 100
			if recs[model] and (buried or not square.Parent) then
				remove(r, false)
			end
		end
		r.watch = { square:GetAttributeChangedSignal("HP"):Connect(check), square.AncestryChanged:Connect(check) }
	end
	if bags then
		-- weapons wear its section (Destruction.damage, Build.blast / Build.shot): its bags follow its HP; at 0 the
		-- section breaks and the pile goes with it
		local s = model:FindFirstChild("Pile")
		if s then
			s:GetAttributeChangedSignal("HP"):Connect(function()
				local hp = s:GetAttribute("HP")
				if recs[model] and type(hp) == "number" and hp ~= r.work then
					r.work = math.max(hp, 0)
					apply(r)
				end
			end)
		end
		model.ChildRemoved:Connect(function()
			for _, c in model:GetChildren() do
				if CollectionService:HasTag(c, D.SectionTag) then
					return
				end
			end
			remove(r, false)
		end)
	end
end

-- Plans a trench (Net "Build" "Plan": its start and end on the ground)
local function plan(player: Player, a: any, b: any)
	local character, root, team = digger(player)
	if not character or not root or not team or typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return
	end
	local reason = Trenches.plan(player, team, root, a, b)
	if reason then
		refuse(player, reason)
	end
end

-- A shovel swing (Net "Build" "Work"): at a piece, a trench block or a tree, in the shovel's mode
local function work(player: Player, target: any, mode: any)
	local character, root, team = digger(player)
	if not character or not root or not team or typeof(target) ~= "Instance" then
		return
	end
	if mode ~= "Build" and mode ~= "Destroy" then
		return
	end
	local now = os.clock()
	if Rules.tooSoon(now, lastSwing[player], GAP, C.SwingSlack) then
		return
	end
	-- a trench block
	local blk = Trenches.blockOf(target)
	if blk then
		if Trenches.distance(blk, root.Position) <= C.Trench.swingReach then
			lastSwing[player] = now
			if Trenches.work(blk, team, mode, digShare(player)) then
				Loadouts.award(player, "Trench")
			end
		end
		return
	end
	-- a tree (Destroy only)
	if
		mode == "Destroy"
		and target:IsA("BasePart")
		and (target.Position - root.Position).Magnitude <= C.SwingReach + 4
	then
		if Trees.chop(target, root.Position) then
			lastSwing[player] = now
		end
		return
	end
	-- a piece
	local r = if target:IsA("Model") then recs[target] else nil
	if not r or Survey.distanceTo(target, root.Position) > C.SwingReach then
		return
	end
	local own = team == r.team
	-- a Hesco barrier: swings work its HP (Config/Build.Hesco.hp); its team's Build swings repair it too
	if r.piece.kind == "Hesco" then
		local build = mode == "Build"
		if build and (not own or r.work >= r.need) then
			return
		end
		lastSwing[player] = now
		local h = C.Hesco.hp
		local share = digShare(player)
		local step = if share then Rules.digAmount(1, h.max, share) else nil
		local left, gone = Rules.hescoSwing(r.work, build, h, step)
		if gone then
			remove(r, false)
			return
		end
		r.work = left
		r.worked = now
		if r.work >= r.need and not r.built then
			Loadouts.award(player, "Piece")
			r.built = true
		end
		apply(r)
		return
	end
	if mode == "Build" and r.gun and r.standing then
		-- fixing a standing gun, any team's (Config/Artillery.Repair; user 2026-10-27: "make it so you can fix a
		-- artillery by digging too ... its fine if the cannon looks buried, as long as it gets flattenned out again once
		-- its fixed", "enemie teams should be able to repair and fix enemie trenches and artillery")
		local gun = r.gun
		local g = ArtilleryCfg.Guns[(r.piece :: any).gun or ""]
		local hp = gun:GetAttribute("HP")
		if not guns or not g or type(hp) ~= "number" or hp >= g.hp then
			return
		end
		lastSwing[player] = now
		local what, after = guns.repair(gun, Rules.digAmount(g.hp / g.repair, g.hp, digShare(player)))
		if what then
			-- back in service or whole: a fresh gun in its place, the howitzer's pit dug out again from the ground as
			-- it was (the field gun levels its own ground as it stands), damaged to what it has
			r.gun = nil
			gun:Destroy()
			local d = g.dig
			local at = r.at
			if d and r.pitBase and at then
				local ramp = d.ramp and { dir = -at.LookVector, width = d.ramp.width, length = d.ramp.length }
				local out = Ground.pit(at.Position, d.radius, d.depth, d.rim, d.rimHeight, ramp, d.wall, r.pitBase)
				Net.event("GroundDug"):FireAllClients(at.Position, out)
			end
			showGun(r)
			if r.gun and what == "usable" then
				guns.setHp(r.gun, after)
			end
		end
		return
	end
	if mode == "Destroy" and r.gun and r.standing and guns then
		-- a standing gun loses HP to the shovel as to any damage (Artillery.harm), as many swings as fix it; only a
		-- wreck at 0 is taken apart, swing by swing, below
		local g = ArtilleryCfg.Guns[(r.piece :: any).gun or ""]
		if g and guns.harm(r.gun, Rules.digAmount(g.hp / g.repair, g.hp, digShare(player))) then
			lastSwing[player] = now
			return
		end
	end
	-- a wire that has stood: swings go to its HP (Destroy breaks it, then takes it away; its team's Build stands a
	-- broken one back up)
	if r.piece.kind == "Wire" and r.built then
		local maxHP = C.Structures.wireHP
		local hp = r.hp or maxHP
		if mode == "Build" and (not own or not Rules.wireBroken(hp, maxHP, C.Wire)) then
			return
		end
		lastSwing[player] = now
		local left, gone = Rules.wireSwing(hp, maxHP, mode == "Build", C.Wire)
		if gone then
			remove(r, false)
			return
		end
		r.hp = left
		r.worked = now
		apply(r)
		if mode == "Destroy" then
			shakeWire(r, root.Position)
		end
		return
	end
	if mode == "Build" and (not own or r.work >= r.need) then
		return
	end
	if mode == "Build" and not Loadouts.mayBuild(character, r.piece.kind) and not buildsAll(player) then
		refuse(player, "Engineers only") -- (anyone may take one apart)
		return
	end
	lastSwing[player] = now
	-- a sandbag pile: swings work its HP (Config/Build.Sandbags.hp); its team's Build swings repair it too
	if r.piece.kind == "Sandbags" then
		local h = C.Sandbags.hp
		local build = mode == "Build"
		local step = Rules.digAmount(if build then h.swing else h.destroy, h.max, digShare(player))
		local left, gone = Rules.pileSwing(r.work, build, h, step)
		if gone then
			remove(r, true)
			return
		end
		r.work = left
		r.worked = now
		if r.work >= r.need then
			if not r.paid then
				Loadouts.award(player, "Piece") -- (once per piece)
			end
			r.built, r.paid = true, true
		end
		local s = r.model:FindFirstChild("Pile")
		if s then
			s:SetAttribute("HP", r.work)
		end
		apply(r)
		return
	end
	-- a bridge: swings work its HP (Config/Build.Bridge.hp); its team's Build swings repair it too; at 0 it is gone
	if r.piece.kind == "Bridge" then
		local h = C.Bridge.hp
		local build = mode == "Build"
		local step = Rules.digAmount(if build then h.swing else h.destroy, h.max, digShare(player))
		local left, gone = Rules.trenchSwing(r.work, h.max, step, build)
		if gone then
			remove(r, false)
			return
		end
		r.work = left
		r.worked = now
		if r.work >= r.need and not r.paid then
			Loadouts.award(player, "Piece") -- (once per piece)
			r.paid = true
		end
		apply(r)
		return
	end
	local was = r.work
	local left, gone = Rules.swing(r.work, r.need, mode == "Build", Rules.digAmount(1, r.need, digShare(player)))
	if gone then
		remove(r, r.built and r.piece.kind ~= "Gun") -- (a gun piece leaves no rubble)
		return
	end
	r.work = left
	r.worked = now
	if r.work >= r.need then
		if not r.paid then
			Loadouts.award(player, "Piece") -- (once per piece: built again after Destroy swings pays nothing)
		end
		r.built, r.paid = true, true
	end
	local stages = r.piece.stages or 1
	if
		r.piece.kind == "Gun"
		or r.piece.kind == "Wire" -- (its look changes on every swing: Rules.wireLook)
		or Rules.stageOf(was, r.need, stages) ~= Rules.stageOf(r.work, r.need, stages)
		or r.work >= r.need
	then
		apply(r)
	else
		r.model:SetAttribute("Work", r.work)
	end
end

-- A blast at `position` (src/server/Damage.blast, after the crater) of `kg`, `key` what it is to built things (a
-- Config/Build.Structures key; nil: by its charge): trenches are buried (src/server/Trenches), sandbag piles and wire
-- worn down, each by how far it is from the blast.
function Build.blast(position: Vector3, kg: number, key: string?)
	local S = C.Structures
	local src = Rules.structureSource(key, kg, S)
	Trenches.blast(position, src)
	local cut = {}
	local worn: { { r: Rec, amount: number } } = {} -- (Hesco barriers: worn after the loop, which bursting changes)
	for _, r in recs do
		local frame = r.model:GetAttribute("Frame") :: CFrame
		if r.piece.kind == "Bridge" and r.built then
			-- by how far the blast is from its box: the deck from heap to heap, down to the trench's floor under it
			local size = r.model:GetAttribute("Size") :: Vector3
			local l = frame:PointToObjectSpace(position)
			local dx = math.max(math.abs(l.X) - size.X / 2, 0)
			local dz = math.max(math.abs(l.Z) - size.Z / 2, 0)
			local dy = math.max(l.Y - size.Y, -C.Trench.depth - l.Y, 0)
			local share = Rules.structureHit(math.sqrt(dx * dx + dy * dy + dz * dz), src, S.edge, src.bridge or 0)
			if share > 0 then
				local left, gone = Rules.bridgeHit(r.work, r.need, share)
				r.work = left
				if gone then
					table.insert(cut, r)
				else
					apply(r)
				end
			end
		elseif r.piece.kind == "Wire" then
			local l = frame:PointToObjectSpace(position)
			local dx = math.max(math.abs(l.X) - r.piece.width / 2, 0)
			local dz = math.max(math.abs(l.Z) - r.piece.depth / 2, 0)
			local d = math.sqrt(dx * dx + dz * dz + math.max(l.Y - r.piece.height, 0) ^ 2)
			local hit = S.wireHP * Rules.structureHit(d, src, S.edge, src.wire) / 100
			if hit > 0 then
				r.hp = (r.hp or S.wireHP) - hit
				if (r.hp :: number) <= 0 then
					table.insert(cut, r)
				else
					showWire(r) -- (worn under half it lies broken)
					shakeWire(r, position)
				end
			end
		elseif r.piece.kind == "Sandbags" then
			-- the pile by how far the blast is from it (Destruction leaves class Sandbag to this)
			for _, c in r.model:GetChildren() do
				if CollectionService:HasTag(c, D.SectionTag) and c:IsA("Model") then
					local cf, size = c:GetBoundingBox()
					local l = cf:PointToObjectSpace(position)
					local d = Vector3.new(
						math.max(math.abs(l.X) - size.X / 2, 0),
						math.max(math.abs(l.Y) - size.Y / 2, 0),
						math.max(math.abs(l.Z) - size.Z / 2, 0)
					).Magnitude
					local share = Rules.structureHit(d, src, S.edge)
					if share > 0 then
						Destruction.damage(c, (c:GetAttribute("MaxHP") :: number) * share / 100, position)
					end
				end
			end
		elseif r.piece.kind == "Hesco" then
			-- the whole basket by how far the blast is from its box, Hesco.soak of a sandbag column's share
			local p = r.piece
			local l = frame:PointToObjectSpace(position)
			local d = Vector3.new(
				math.max(math.abs(l.X) - p.width / 2, 0),
				math.max(l.Y - p.height, -l.Y, 0),
				math.max(math.abs(l.Z) - p.depth / 2, 0)
			).Magnitude
			local share = Rules.structureHit(d, src, S.edge) * C.Hesco.soak
			if share > 0 then
				table.insert(worn, { r = r, amount = r.need * share / 100 })
			end
		end
	end
	for _, r in cut do
		remove(r, r.piece.kind ~= "Bridge") -- (a bridge at 0 is simply gone)
	end
	for _, w in worn do
		wearHesco(w.r, w.amount)
	end
end

-- A bullet meeting `part` at `point` (src/server/Firing): a trench square (a piece, or the ground in it) or a sandbag
-- pile loses Structures.bullet
function Build.shot(part: Instance, point: Vector3)
	if Trenches.shot(part, point) then
		return
	end
	local s = part.Parent
	if s and s:IsA("Model") and s:GetAttribute("Class") == "Sandbag" then
		Destruction.damage(s, (s:GetAttribute("MaxHP") :: number) * C.Structures.bullet.hit / 100)
		return
	end
	-- a Hesco barrier's dirt (the only piece of it a bullet meets): `s` its stage's holder ("Stage<s>"), in the
	-- piece's model
	local model = s and s.Parent
	local r = if model and model:IsA("Model") then recs[model] else nil
	if r and r.piece.kind == "Hesco" then
		wearHesco(r, r.need * C.Structures.bullet.hit * C.Hesco.soak / 100)
	end
end

-- the barbed wire that stands (not broken): its box (centre frame and size), its team and model, for src/server/Wire
export type WireBox = { frame: CFrame, size: Vector3, team: string, model: Model }
-- whether `p` is on a Hesco barrier's ground (its footprint and Config/Build.Hesco.ground round it): craters never carve
-- it (src/server/Ground.guard); the barrier takes the blast (Build.blast)
function Build.onHesco(p: Vector3): boolean
	for _, r in recs do
		if r.piece.kind == "Hesco" then
			local l = r.frame:PointToObjectSpace(p)
			if Rules.onFootprint(l.X, l.Z, r.piece.width, r.piece.depth, C.Hesco.ground) then
				return true
			end
		end
	end
	return false
end

function Build.wires(): { WireBox }
	local out = {}
	for _, r in recs do
		if r.piece.kind == "Wire" and r.model:GetAttribute("Armed") == true then
			local p = r.piece
			local frame = r.model:GetAttribute("Frame") :: CFrame
			table.insert(out, {
				frame = frame * CFrame.new(0, p.height / 2, 0),
				size = Vector3.new(p.width, p.height + 3, p.depth),
				team = r.team,
				model = r.model,
			})
		end
	end
	return out
end

-- whether a trench ever touched voxel `key` ("x,y,z" in voxel units): src/server/Ground never refills it
function Build.dug(key: string): boolean
	return Trenches.dug(key)
end

-- whether `p` is within `extra` of a trench's ground (src/server/Ground keeps craters off it)
function Build.nearTrench(p: Vector3, extra: number): boolean
	return Trenches.near(p, extra)
end

-- Removes every piece and trench (dev: the admin panel's undo)
function Build.clear()
	local list = {}
	for _, r in recs do
		table.insert(list, r)
	end
	for _, r in list do
		remove(r, false)
	end
	Trenches.clear()
end

-- a shovel swing's sound (Net "Dug"), passed on to everyone else
local lastSound: { [Player]: number } = {}
local function dug(player: Player, kind: any)
	if kind ~= "Dig" and kind ~= "Toss" and kind ~= "Chip" then
		return
	end
	local character = digger(player)
	local now = os.clock()
	if not character or (lastSound[player] and now - lastSound[player] < ShovelCfg.SoundGap) then
		return
	end
	lastSound[player] = now
	for _, p in Players:GetPlayers() do
		if p ~= player then
			Net.event("Dug"):FireClient(p, character, kind)
		end
	end
end

function Build.start(artillery: Guns)
	guns = artillery
	folder()
	Trenches.start()
	Ground.guard(Build.onHesco)
	Net.event("Dug").OnServerEvent:Connect(dug)
	Net.event("Build").OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any)
		if kind == "Place" then
			place(player, a, b)
		elseif kind == "Plan" then
			plan(player, a, b)
		elseif kind == "Work" then
			work(player, a, b)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		lastSound[player] = nil
	end)
	-- blueprints nobody worked on
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			local stale = {}
			for _, r in recs do
				-- (a bridge is laid at stage 1: untouched while it has no more HP than that and was never whole)
				local fresh = if r.piece.kind == "Bridge"
					then r.work <= C.Bridge.hp.place and not r.paid
					else r.work <= 0 and not r.built
				if fresh and now - r.worked > C.BlueprintLife then
					table.insert(stale, r)
				end
			end
			for _, r in stale do
				remove(r, false)
			end
		end
	end)
end

return Build
