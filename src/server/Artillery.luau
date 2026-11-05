--!strict
-- Artillery on the server (docs/MILESTONES.md A2; Config/Artillery, Rules/Artillery): places the guns (the dev menu,
-- and players' shovels: src/server/Build stands them), mans them, lays them and flies their shells.
-- - A gun is a copy of its library model (ReplicatedStorage.Assets.Weapons.Shared.Artillery), anchored, painted
--   (Config/Palette.Artillery), its pivot moved to gun space (found from the Bore disc at rest), standing in the
--   Workspace folder Config/Artillery.Folder. Its attributes: "Gun" (the Config/Artillery.Guns key), "Traverse",
--   "Elevation" (degrees), "FiredAt", "ReadyAt" (server time), "Gunner" (UserId). Every client poses the moving parts
--   from these (src/client/Artillery); the server moves only a turning mount (crewTurns: its gunner stands on it) and,
--   swinging the whole gun, its pivot. The gunner is welded to what they stand on.
-- - E (its ProximityPrompt, in the game's own look: src/client/Prompts) mans it: the gunner stands welded at the crew
--   spot, platform-standing, weapons put away, until they leave (Net "Artillery" "Leave"), die or go.
-- - "Aim" sets the wanted yaw and elevation; the gun works toward them at its rates (Rules/Artillery.lay).
-- - "Fire", loaded: the gunner braces (the howitzer charges up), the gun's `charge` s later the shell leaves the muzzle with the gun's lay, set to miss by a little (Config/Artillery `miss`), flies the plain parabola (stepped
--   casts, so nothing thin is passed through) and goes off where it hits: Damage.blast with its charge and fragments,
--   every client shows it (Net "ArtilleryBlast").
-- - Every blast wears the guns down (Damage.onBlast; Config/Artillery.Hits): a direct hit on a gun takes a lot, one on
--   its pit, mound or the ground round it little. Its HP ("HP") falls through the Config/Artillery.Wreck stages
--   ("Stage"): scorched, leaning and sinking more each stage; at 0 a wreck that stays. Under Config/Artillery.Man
--   `keep` of its HP it is out of service ("Broken": its gunner thrown off, the prompt dimmed, the barrel knocked down,
--   the howitzer's crystal dead) until repairs bring it back to that.
-- - A machine gun (Config/Artillery.Guns `mg`, the MG nest's M2; set up by src/server/Build): no earth under it
--   (it stands on its mount bag); "Trigger" held fires bullets at its rate from its box ("Rounds"), each cast from the
--   muzzle along its lay plus a stray growing with its heat, hurting as a rifle shot does (src/server/Damage, by its
--   `class`), chipping built things (Build.shot) and breaking glass on the way; everyone sees it ("MGShot"). An empty
--   box, or "Reload", swaps it over the gun's `reload` ("ReadyAt"), then it is full again.
-- - A dug-in gun's pit is lined with trench dirt slabs (Config/Artillery.Slabs, the trench kit: src/server/Trenches),
--   laid rough, in the Workspace folder Config/Artillery.PitFolder, gone with the gun.
-- - The ground a gun stands on is never carved by craters (Ground.guard; earth thrown up may land on it). The field gun
--   stands on the terrain, levelled and bared under it, with an unseen hitbox; the howitzer on its earth block.
-- - Its own team's shovel swings fix it (Artillery.repair, from src/server/Build); whole, a fresh gun stands there.
-- - Bot soldiers (src/server/Bots) work the guns through Artillery.manAs / aimAs / aimAtAs / fireAs / triggerAs /
--   reloadAs / leaveAs, with a player's checks (Config/Artillery.Bot). A bot mans any free gun; its "Gunner" is the
--   bot's BotId. Its teammates' E takes the gun over ("Take over the gun"): the bot is set down beside it and the
--   player on it. Artillery.onBotLeft hears every bot leaving a gun, and why.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local DevCfg = require(Shared.Config.DevTools)
local FiringCfg = require(Shared.Config.Firing)
local Palette = require(Shared.Config.Palette)
local PromptCfg = require(Shared.Config.Prompts)
local Rules = require(Shared.Rules.Artillery)
local FrontCfg = require(Shared.Config.Frontline)
local SectorCfg = require(Shared.Config.Sectors)
local Map1 = require(Shared.LiveMap).map -- (the match's map)
local MapTerrain = require(Shared.Rules.MapTerrain)
local SectorRules = require(Shared.Rules.Sectors)
local Net = require(Shared.Net)
local Damage = require(script.Parent.Damage)
local Build = require(script.Parent.Build)
local Destruction = require(script.Parent.Destruction)
local Helmets = require(script.Parent.Helmets)
local Ground = require(script.Parent.Ground)
local Trenches = require(script.Parent.Trenches)
local TrenchCfg = require(Shared.Config.Build).Trench
local BotCfg = require(Shared.Config.Bots)

local Artillery = {}

type State = {
	model: Model,
	key: string,
	gun: Cfg.Gun,
	prompt: ProximityPrompt,
	lay: Rules.Lay,
	want: { yaw: number, elevation: number },
	gunner: Player?,
	bot: Model?, -- a bot soldier manning it (no `gunner` then)
	mannedAt: number,
	conns: { RBXScriptConnection },
	sent: number, -- when the lay was last written out
	aimed: number, -- when the gunner's last aim was taken
	landings: { [string]: Vector3 | false }, -- where each lay asked about comes down (comesDown)
	landingKeys: { string },
	crewAt: number, -- the traverse the mount was last turned to here
	mountRest: { [BasePart]: CFrame }, -- a turning mount's parts at rest, in gun space (crewTurns: posed here too)
	weld: WeldConstraint?, -- the gunner held on the gun
	bracing: boolean, -- a shot on its way (the gunner bracing)
	hp: number,
	stage: number, -- its Config/Artillery.Wreck stage (0: unhurt)
	broken: boolean, -- under Man.keep of its HP (Rules.mannable): nobody can man it
	colors: { [BasePart]: Color3 }, -- as painted
	holes: number, -- shell holes punched in it so far (Wreck.holes)
	upright: CFrame?, -- its pivot before it first leaned
	lean: number, -- which way it leans (radians round its up axis)
	-- the ground it stands on (Artillery.onGround): its pivot as placed and the box under it (x, z in gun space)
	ground: { at: CFrame, lo: { number }, hi: { number } },
	pit: Model?, -- its pit's slabs
	capAt: { yaw: number, at: number, lims: { number } }?, -- its elevation limits along its lay lately (limitsOf)
	-- a machine gun (Config/Artillery.Guns `mg`): its fire held down, its heat (Rules.mgHeat), when its next shot is
	-- due (a fresh pull not yet fired: `pull`), and a box reload under way
	trigger: boolean,
	pull: boolean,
	heat: number,
	nextShot: number,
	reloading: boolean,
	-- a reload's count (a broken-off one's end does nothing) and whether one was broken off, to start over when manned
	reloadOf: number,
	unloaded: boolean,
}

local guns: { [Model]: State } = {}
local random = Random.new()
-- who hears a bot leaving a gun (Artillery.onBotLeft)
local botLeft: { (Model, Model, string) -> () } = {}

-- a gun's traverse of `deg` in gun space: about its `pintle` (Config/Artillery; the origin when it has none)
local function turnAt(gun: Cfg.Gun, deg: number): CFrame
	local p = gun.pintle or { 0, 0 }
	return CFrame.new(p[1], 0, p[2]) * CFrame.Angles(0, math.rad(deg), 0) * CFrame.new(-p[1], 0, -p[2])
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- How far a field gun or howitzer reaches on the live map (Config/Artillery.Reach: no shell past a sector away)
local function reachCap(key: string): number
	return Rules.reachCap(Rules.sectorSpan(Map1.sectors), Cfg.Reach, key)
end

local function folder(): Folder
	local f = workspace:FindFirstChild(Cfg.Folder)
	if not f then
		f = Instance.new("Folder")
		f.Name = Cfg.Folder
		f.Parent = workspace
	end
	return f :: Folder
end

local function library(asset: string): Model
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, sub in { "Weapons", "Shared", "Artillery", asset } do
		f = f and f:FindFirstChild(sub)
	end
	assert(f and f:IsA("Model"), `artillery model {asset} is not in ReplicatedStorage.Assets (run the Library sync)`)
	return f :: Model
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- a mesh's team colour by the role its name ends in (Palette.Artillery.Roles: MountTrim, CarriageFittings, ...)
local function roleColor(name: string, team: string): { number }?
	local art = Palette.Artillery
	for _, role in art.Roles do
		if #name > #role and string.sub(name, -#role) == role then
			return (art.Team[team] :: any)[role]
		end
	end
	return nil
end

-- the team's paint on the painted parts, its accent colours on the accent pieces, the rest by mesh name (the team's own
-- first, as Brown's barrel); the runes and the crystal glow
local function paint(model: Model, team: string)
	local art = Palette.Artillery
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Material = Enum.Material.SmoothPlastic
			d.Color = rgb(
				if table.find(art.Painted, d.Name)
					then art.Paint[team]
					else roleColor(d.Name, team)
						or (art.Team[team] :: any)[d.Name]
						or (art :: any)[d.Name]
						or art.Barrel
			)
			if table.find(art.Glowing, d.Name) then
				d.Material = Enum.Material.Neon
			end
			-- (the howitzer's barrel engravings stay unseen till its charge-up: src/client/ArtilleryCrystal)
			if d.Name == Cfg.Crystal.engraving.part then
				d.Transparency = 1
			end
		end
	end
end

local function part(model: Model, name: string): BasePart
	local p = model:FindFirstChild(name, true)
	assert(p and p:IsA("BasePart"), `artillery model {model.Name} has no part {name}`)
	return p :: BasePart
end

-- gun space on the model as it lies: level, looking from the barrel to its muzzle, the origin found back from the Bore
-- disc (its centre sits `boreCentre` behind the muzzle face)
local function gunSpace(model: Model, gun: Cfg.Gun): CFrame
	local bore = part(model, "Bore")
	local barrel = part(model, "Barrel")
	local f = bore.Position - barrel.Position
	local rot = CFrame.Angles(0, math.rad(Rules.yawOf(f.X, f.Z)), 0)
	local m = gun.muzzle
	local origin = bore.Position - rot:VectorToWorldSpace(Vector3.new(m[1], m[2], m[3] + gun.boreCentre))
	return CFrame.new(origin) * rot
end

-- where the gunner's root stands: the crew spot, on whatever is under it, facing along the gun
local function crewSpot(s: State, character: Model): CFrame?
	-- (on the mount, the spot turns with its traverse)
	local pivot = s.model:GetPivot()
	if s.gun.crewTurns then
		pivot *= turnAt(s.gun, s.lay.traverse)
	end
	local c = s.gun.crew
	local above = pivot:PointToWorldSpace(Vector3.new(c[1], 20, c[2]))
	local leg = character:FindFirstChild("Left Leg") :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not leg or not root then
		return nil
	end
	local floor: number
	if s.gun.crewY then
		floor = pivot:PointToWorldSpace(Vector3.new(c[1], s.gun.crewY, c[2])).Y
	else
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, s.model }
		local hit = workspace:Raycast(above, Vector3.new(0, -60, 0), params)
		if not hit then
			return nil
		end
		floor = hit.Position.Y
	end
	local y = floor + leg.Size.Y + root.Size.Y / 2
	local at = Vector3.new(above.X, y, above.Z)
	-- (upright, along the gun's flat look: a gun laid tilted on a slope, Config/Build.Slope, doesn't lean its gunner)
	local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
	local face = CFrame.lookAt(at, at + (if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)))
	-- (turned to the breech: Config/Artillery `crewYaw`, + right)
	return face * CFrame.Angles(0, -math.rad(s.gun.crewYaw or 0), 0)
end

-- A machine gun's box reload: unable to fire for the gun's `reload`, then full again
local function reloadBox(s: State)
	local mg = s.gun.mg
	if not mg or s.reloading or s.broken or (s.model:GetAttribute("Rounds") :: number? or 0) >= mg.box then
		return
	end
	s.reloading = true
	s.trigger, s.pull = false, false
	s.reloadOf += 1
	local this = s.reloadOf
	s.model:SetAttribute("ReadyAt", now() + s.gun.reload)
	task.delay(s.gun.reload, function()
		if s.reloadOf == this and guns[s.model] then
			s.reloading = false
			s.model:SetAttribute("Rounds", mg.box)
		end
	end)
end

-- A reload broken off by its gunner leaving (user 2026-11-01: "reloading on the machine gun and field cannon should
-- be restarted if cancelled"): it stops here, the gun as it was (the box not swapped, the round not in), and starts
-- over from the beginning once the gun is manned again (restartReload). A gun that keeps its reload (Config
-- `keepsReload`, the howitzer) charges on with nobody on it.
local function cancelReload(s: State)
	if s.gun.keepsReload then
		return
	end
	local ready = s.model:GetAttribute("ReadyAt") :: number?
	if s.reloading or (not s.gun.mg and ready and now() < ready) then
		s.reloadOf += 1
		s.reloading = false
		s.unloaded = true
		s.model:SetAttribute("ReadyAt", now())
	end
end

local function restartReload(s: State)
	if not s.unloaded then
		return
	end
	s.unloaded = false
	if s.gun.mg then
		reloadBox(s)
	else
		s.model:SetAttribute("ReadyAt", now() + s.gun.reload)
	end
end

-- the character on the gun: the gunner's, or the bot's
local function body(s: State): Model?
	return s.bot or (s.gunner and s.gunner.Character)
end

-- the gun off its gunner (a bot's: told why, Artillery.onBotLeft; "Kicked": set down beside the gun); `putOff`: the gun
-- broke or went under them, so a player is set down beside it too (Config/Artillery.PutOff)
local function leave(s: State, why: string?, putOff: boolean?)
	local player = s.gunner
	local bot = s.bot
	s.trigger, s.pull = false, false
	cancelReload(s)
	for _, c in s.conns do
		c:Disconnect()
	end
	s.conns = {}
	s.gunner = nil
	s.bot = nil
	if s.weld then
		s.weld:Destroy()
		s.weld = nil
	end
	s.model:SetAttribute("Gunner", nil)
	s.prompt.Enabled = not s.broken
	s.prompt.ActionText = "Man the gun"
	s.prompt:SetAttribute(PromptCfg.BlockedAttr, if s.broken then "Broken" else nil)
	s.prompt:SetAttribute(PromptCfg.UserAttr, nil)
	s.prompt:SetAttribute(PromptCfg.KitAttr, nil)
	local character = bot or (player and player.Character)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = false
		if bot and why == "Kicked" then
			local spot = crewSpot(s, bot)
			if spot then
				root.CFrame = spot * CFrame.new(-Cfg.Bot.aside, 0, 0)
			end
		elseif putOff and character then
			-- (a moment later: set at once, the player's own client, taking its body back from the weld, put it straight
			-- back where it stood; Studio 2026-11-05)
			local spot = crewSpot(s, character)
			if spot then
				local to = spot * CFrame.new(-Cfg.PutOff.aside, Cfg.PutOff.up, 0)
				local held = root :: BasePart
				task.delay(Cfg.PutOff.after, function()
					if held.Parent and not held.Anchored then
						held.CFrame = to
						held.AssemblyLinearVelocity = Vector3.zero
					end
				end)
			end
		end
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
	if bot then
		for _, fn in botLeft do
			task.spawn(fn, bot, s.model, why or "Left")
		end
	end
end

-- `character` (a player's, or a bot's: `bot`) stood on the gun as its gunner; false when it can't be
local function seat(s: State, character: Model, player: Player?, bot: Model?): boolean
	if s.gunner or s.bot or s.broken then
		return false
	end
	for _, other in guns do
		if (player and other.gunner == player) or (bot and other.bot == bot) then
			return false
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	local spot = crewSpot(s, character)
	if not spot then
		return false
	end
	if player then
		humanoid:UnequipTools()
	end
	-- held on the part of the gun they stand on (user 2026-10-21: "when turning, the player starts twitching on the
	-- gun": the server re-placed an anchored root 20 times a second while every client turns the gun smoothly), so on
	-- every client they ride the gun exactly as it's drawn
	root.CFrame = spot
	local holder = if s.gun.crewTurns then part(s.model, s.gun.mount[1]) else part(s.model, s.gun.base)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "ArtilleryGunner"
	weld.Part0 = root
	weld.Part1 = holder
	weld.Parent = root
	s.weld = weld
	-- the weld broken from outside (a knock throws the gunner off: src/server/Ragdoll): off the gun
	weld.AncestryChanged:Connect(function()
		if s.weld == weld and not weld:IsDescendantOf(game) then
			s.weld = nil
			leave(s, "Knocked")
		end
	end)
	root.Anchored = false
	-- and platform-standing (user 2026-10-22: "the field cannon is unoperable. the character starts tweaking out with
	-- the cannon. it only fixes when you have fly on": the dev Fly platform-stands): held by the weld, the humanoid
	-- still tried to stand and walk on the ground under it, fighting the gun
	humanoid.PlatformStand = true
	s.gunner, s.bot = player, bot
	s.mannedAt = os.clock()
	s.want = { yaw = s.lay.yaw + s.lay.traverse, elevation = s.lay.elevation }
	local id = if player then player.UserId else character:GetAttribute(BotCfg.IdAttribute)
	s.model:SetAttribute("Gunner", id)
	restartReload(s)
	s.prompt:SetAttribute(PromptCfg.UserAttr, id)
	if bot then
		-- (left on for the bot's teammates, who take it over; dimmed for everyone else: Config/Prompts.KitAttr)
		s.prompt.ActionText = Cfg.Bot.takeOver
		s.prompt:SetAttribute(PromptCfg.KitAttr, bot:GetAttribute("Kit"))
	else
		s.prompt.Enabled = false
		-- (still drawn, dimmed, for everyone else: Config/Prompts)
		s.prompt:SetAttribute(PromptCfg.BlockedAttr, "InUse")
	end
	table.insert(
		s.conns,
		humanoid.Died:Connect(function()
			leave(s, "Died")
		end)
	)
	table.insert(
		s.conns,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) then
				leave(s, "Gone")
			end
		end)
	)
	-- no weapon in the hands while on the gun
	if player then
		table.insert(
			s.conns,
			character.ChildAdded:Connect(function(c)
				if c:IsA("Tool") then
					task.defer(function()
						humanoid:UnequipTools()
					end)
				end
			end)
		)
	end
	return true
end

-- A player's E on the gun: mans it, or on a gun a bot of their own kit mans, puts the bot off and takes it over
local function man(s: State, player: Player)
	local character = player.Character
	if not character then
		return
	end
	if s.bot then
		if not Rules.mayTakeOver(character:GetAttribute("Kit"), s.bot:GetAttribute("Kit")) then
			return
		end
		for _, other in guns do
			if other.gunner == player then
				return
			end
		end
		leave(s, "Kicked")
	end
	seat(s, character, player, nil)
end

-- gun `key`'s shell going off at `at` (by `by`): every client's blast first, so it shows even if the damage fails or
-- runs long, then the blast (src/server/Damage)
local function burst(key: string, at: Vector3, by: Model?)
	local gun = Cfg.Guns[key]
	Net.event("ArtilleryBlast"):FireAllClients(at, key)
	Damage.blast(at, gun.kg, by, { fragments = gun.fragments, craterScale = gun.craterScale })
end

-- the shell's flight from `origin` at `velocity`, stepped against the world; goes off where it hits
local function fly(s: State, origin: Vector3, velocity: Vector3, by: Model?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { s.model }
	params.IgnoreWater = false
	params.CollisionGroup = "Default" -- the out-of-bounds walls stop only characters
	local g = s.gun.gravity -- (its own: slow shells, same ranges)
	local t = 0
	local prev = origin
	local key = s.key
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		local x, y, z = Rules.at(t, origin.X, origin.Y, origin.Z, velocity.X, velocity.Y, velocity.Z, g)
		local p = Vector3.new(x, y, z)
		local hit = workspace:Raycast(prev, p - prev, params)
		if hit then
			conn:Disconnect()
			burst(key, hit.Position + hit.Normal * 0.3, by)
		elseif t > Cfg.MaxFlight then
			conn:Disconnect()
		end
		prev = p
	end)
end

-- In a Normal match, why `s`'s gunner can't fire now (user 2026-10-29: "artillery can still only be fired upon
-- non-friendly sectors"): where the shell would land on flat ground lies in a sector the gunner's side holds. Nil when
-- it may fire (or outside a Normal match).
-- (`landsOwn`: whether a point lies in a sector kit `kit`'s side holds)
local function landsOwn(kit: any, x: number, z: number): boolean
	local front = workspace:FindFirstChild(FrontCfg.FolderName)
	if not front then
		return false
	end
	local side = if kit == front:GetAttribute("West")
		then "West"
		elseif kit == front:GetAttribute("East") then "East"
		else nil
	if not side then
		return false
	end
	local id = SectorRules.sectorAt(Map1, MapTerrain, x, z, SectorCfg.Divider.RiverSegments)
	local sector = front:FindFirstChild(id)
	return sector ~= nil and sector:GetAttribute("Owner") == side
end

-- Where a shell from `s` laid `lay` comes down on the ground (the path cast against the terrain every Config/Artillery
-- Arc.step seconds, as the gunner's landing marker; nothing hit within MaxFlight: level with the gun). Kept per lay
-- in `s.landings` (a turning gun asks for a few lays a frame).
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.IgnoreWater = false
-- where a shell from `o` at `v` under `g` first meets the terrain (or, nothing met, level with `baseY`)
local function pathDown(o: Vector3, v: Vector3, g: number, baseY: number): Vector3?
	terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
	local step = Cfg.Arc.step
	local prev, t = o, step
	while t <= Cfg.MaxFlight and prev.Y > Cfg.Arc.floor do
		local x, y, z = Rules.at(t, o.X, o.Y, o.Z, v.X, v.Y, v.Z, g)
		local q = Vector3.new(x, y, z)
		local hit = workspace:Raycast(prev, q - prev, terrainOnly)
		if hit then
			return hit.Position
		end
		prev, t = q, t + step
	end
	local fall = Rules.fall(o.Y - baseY, v.Y, g)
	if fall and fall <= Cfg.MaxFlight then
		local x, y, z = Rules.at(fall, o.X, o.Y, o.Z, v.X, v.Y, v.Z, g)
		return Vector3.new(x, y, z)
	end
	return nil
end

local function comesDown(s: State, lay: Rules.Lay): Vector3?
	local key = string.format("%.2f %.2f %.2f", lay.yaw, lay.traverse, lay.elevation)
	local known = s.landings[key]
	if known ~= nil then
		return known or nil
	end
	local gun = s.gun
	local base = s.model:GetPivot().Position
	local frame = CFrame.new(base) * CFrame.Angles(0, math.rad(lay.yaw), 0)
	local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, lay.traverse, lay.elevation)
	local o = frame:PointToWorldSpace(Vector3.new(mx, my, mz))
	local v = frame:VectorToWorldSpace(Vector3.new(dx, dy, dz)) * gun.speed
	local found = pathDown(o, v, gun.gravity, base.Y)
	if #s.landingKeys >= 32 then
		table.clear(s.landings)
		table.clear(s.landingKeys)
	end
	s.landings[key] = found or false
	table.insert(s.landingKeys, key)
	return found
end

-- whether a shell of `s`'s coming down at `land` falls on a spawn (Config/Artillery.SpawnGuard: either side's spawn
-- zone, or its wave line in a Normal match)
local function nearSpawn(s: State, land: Vector3): boolean
	local G = Cfg.SpawnGuard
	local lines = {}
	local front = workspace:FindFirstChild(FrontCfg.FolderName)
	if front then
		for _, side in { "West", "East" } do
			local c = front:GetAttribute(side .. FrontCfg.LineAttribute)
			if typeof(c) == "Vector3" then
				table.insert(lines, { c.X, c.Z, G.line })
			end
		end
	end
	return Rules.nearSpawn(land.X, land.Z, Map1.spawnZones, lines, s.gun.zone + G.gap)
end

-- Whether a field gun's or howitzer's shell laid `lay` would come down on a spawn
local function onSpawn(s: State, lay: Rules.Lay): boolean
	if s.gun.mg then
		return false
	end
	local land = comesDown(s, lay)
	return land ~= nil and nearSpawn(s, land)
end

-- The turn and speed share for `s`'s next shell to miss (Rules.miss; Config/Artillery `miss`) where it comes down
-- now, its path traced on the terrain: rolled again while it would come down on a spawn or farther off than
-- Miss.stray times the radius (rough ground: a long shot clearing a crest); no miss after Miss.tries.
local function missOf(s: State): (number, number, number)
	local gun = s.gun
	if s.gunner and s.gunner:GetAttribute(DevCfg.Admin.GunAim.exact) == true then
		return 0, 1 -- (the admin panel's "no scatter")
	end
	local land = comesDown(s, s.lay)
	local radius = gun.miss
	local pivot = s.model:GetPivot()
	local function shot(dYaw: number, speed: number): (Vector3, Vector3)
		local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, s.lay.traverse + dYaw, s.lay.elevation)
		return pivot:PointToWorldSpace(Vector3.new(mx, my, mz)),
			pivot:VectorToWorldSpace(Vector3.new(dx, dy, dz)) * gun.speed * speed
	end
	local origin = shot(0, 1)
	local flat = land and Vector3.new(land.X - origin.X, 0, land.Z - origin.Z)
	if not land or not flat or not radius or flat.Magnitude < 1 then
		return 0, 1, 0
	end
	local M = Cfg.Miss
	-- (none of them in `stray`: the one nearest the aim off any spawn, so a shot over rough ground still misses; user
	-- 2026-11-03: "make sure howitzer inaccuracy applies to bots too", whose lobs over crests rolled out of `stray`)
	local best, bestYaw, bestSpeed = math.huge, 0, 1
	for _ = 1, M.tries do
		local right, beyond = Rules.miss(radius, random:NextNumber(), random:NextNumber(), random:NextNumber())
		local dYaw, speed = Rules.missLay(flat.Magnitude, right, beyond)
		local o, v = shot(dYaw, speed)
		local down = pathDown(o, v, gun.gravity, pivot.Position.Y)
		local off = down and Vector3.new(down.X - land.X, 0, down.Z - land.Z).Magnitude
		if down and off and not nearSpawn(s, down) then
			if off <= radius * M.stray then
				return dYaw, speed, off
			elseif off < best then
				best, bestYaw, bestSpeed = off, dYaw, speed
			end
		end
	end
	return bestYaw, bestSpeed, if best < math.huge then best else 0
end

-- the last MISSES shells fired, newest first: the gun's key, a bot's or a player's, how far off its aim it was set to
-- come down (studs; Artillery.misses, the admin readout)
local MISSES = 10
local misses: { { key: string, bot: boolean, off: number } } = {}

local function friendlyTarget(s: State): string?
	local character = body(s)
	if not character then
		return nil
	end
	if onSpawn(s, s.lay) then
		return Cfg.SpawnGuard.why
	end
	local at = s.model:GetPivot().Position
	local x, z = Rules.landing(s.gun, s.lay, at.X, at.Z)
	if x and z and landsOwn(character:GetAttribute("Kit"), x, z) then
		return "Can't fire on your own sector"
	end
	return nil
end

local function fire(s: State)
	local character = body(s)
	local t = now()
	local ready = s.model:GetAttribute("ReadyAt") :: number?
	if not character or s.broken or (ready and t < ready) then
		return
	end
	local gun = s.gun
	local pivot = s.model:GetPivot()
	local dYaw, speed, off = missOf(s)
	table.insert(misses, 1, { key = s.key, bot = s.bot ~= nil, off = off })
	misses[MISSES + 1] = nil
	local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, s.lay.traverse + dYaw, s.lay.elevation)
	local origin = pivot:PointToWorldSpace(Vector3.new(mx, my, mz))
	local velocity = pivot:VectorToWorldSpace(Vector3.new(dx, dy, dz)) * gun.speed * speed
	s.model:SetAttribute("FiredAt", t)
	local quick = s.gunner and s.gunner:GetAttribute(DevCfg.Admin.GunAim.quick) == true
	s.model:SetAttribute("ReadyAt", t + (if quick then DevCfg.Admin.GunAim.quickReload else gun.reload))
	Net.event("ArtilleryShot"):FireAllClients(s.model, origin, velocity)
	fly(s, origin, velocity, character)
end

-- A machine gun's bullet: from the muzzle along the gun's lay plus its stray, cast against the world (glass on the way
-- broken and passed, Config/Firing.Shatter), its wound handed to src/server/Damage
local function bullet(s: State, character: Model)
	local gun = s.gun
	local mg = gun.mg :: any
	local dYaw, dElev = Rules.mgStray(Rules.mgSpread(s.heat, mg.spread), random:NextNumber(), random:NextNumber())
	local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, s.lay.traverse + dYaw, s.lay.elevation + dElev)
	local pivot = s.model:GetPivot()
	local origin = pivot:PointToWorldSpace(Vector3.new(mx, my, mz))
	local line = pivot:VectorToWorldSpace(Vector3.new(dx, dy, dz)).Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { s.model, character }
	local from, panes, result = origin, 0, nil
	while true do
		result = workspace:Raycast(from, line * (mg.range - (from - origin).Magnitude), params)
		if
			not result
			or panes >= FiringCfg.Shatter.panes
			or not Destruction.shot(result.Instance, result.Position, line)
		then
			break
		end
		panes += 1
		from = result.Position + line * 0.01
	end
	local hit = if result then result.Position else origin + line * mg.range
	if result then
		Build.shot(result.Instance, result.Position)
		local mate = Damage.spares(character, result.Instance.Parent)
		local helmet = not mate and Helmets.hit(result.Instance, result.Position, line)
		Damage.shot(character, mg.class, {
			{
				part = result.Instance,
				point = result.Position,
				direction = line,
				distance = (result.Position - origin).Magnitude,
				helmet = helmet,
			},
		})
	end
	Net.event("MGShot"):FireAllClients(s.model, origin, hit, result and result.Normal, result and result.Instance)
end

-- A machine gun at work this frame: its heat settling, and while its fire is held, its shots as they fall due
local function machineGun(s: State, dt: number)
	local mg = s.gun.mg
	if not mg then
		return
	end
	local t = now()
	local shots = 0
	local character = body(s)
	local rounds = s.model:GetAttribute("Rounds") :: number? or 0
	if (s.trigger or s.pull) and character and not s.broken then
		-- (one click, one shot: Rules.mgShot)
		if Rules.mgReady(rounds, s.model:GetAttribute("ReadyAt") :: number?, t) then
			local fires, nextShot = Rules.mgShot(s.nextShot, s.pull, s.trigger, t, Rules.mgInterval(mg.rate), mg.tap)
			if fires then
				s.nextShot, s.pull = nextShot, false
				rounds -= 1
				shots += 1
				s.heat = Rules.mgHeat(s.heat, 1, 0, mg.spread)
				bullet(s, character)
			end
		end
		if shots > 0 then
			s.model:SetAttribute("Rounds", rounds)
			s.model:SetAttribute("FiredAt", t)
		end
		if rounds <= 0 then
			reloadBox(s) -- (an empty box is swapped at once)
		end
	end
	s.heat = Rules.mgHeat(s.heat, 0, dt, mg.spread)
end

local function pitFolder(): Folder
	local f = workspace:FindFirstChild(Cfg.PitFolder)
	if not f then
		f = Instance.new("Folder")
		f.Name = Cfg.PitFolder
		f.Parent = workspace
	end
	return f :: Folder
end

-- The ground's height over the pit's centre (flat ground) `along` the ramp's way out and `across` it, as Ground.pit
-- leaves it (`lean`: studs out per stud up of its walls)
local function surface(d: any, lean: number, along: number, across: number): number
	local r = math.sqrt(along * along + across * across)
	local top = d.radius + d.depth * lean
	local z = 0
	if r <= d.radius then
		z = -d.depth
	elseif r <= top then
		z = -d.depth + (r - d.radius) / lean
	elseif r <= top + d.rim then
		z = d.rimHeight * (1 - math.abs(r - top - d.rim / 2) / (d.rim / 2))
	end
	if d.ramp and along > 0 and along <= d.radius + d.ramp.length then
		local side = math.max(across - d.ramp.width / 2, 0)
		local lane = -d.depth + d.depth * math.clamp((along - d.radius) / d.ramp.length, 0, 1) + side / lean
		z = math.min(z, lane)
	end
	return z
end

-- Lines a gun's pit (centre `at` on the ground, the ramp out along `back`) with rough trench dirt slabs
-- (Config/Artillery.Slabs; the trench kit, src/server/Trenches): uneven rows round its leaning wall, the ramp's sides
-- where they're deep, a few loose floor pieces off the gun's bed. Rolled from where it stands, so the same every time.
local function slabs(at: Vector3, d: any, back: Vector3): Model?
	local kit, offsets = Trenches.pieceKit()
	if not kit then
		return nil
	end
	local S = Cfg.Slabs
	local rng = Random.new(math.floor(at.X) * 7919 + math.floor(at.Z) * 104729)
	local lean = 1 / math.tan(math.rad(d.wall))
	local up = Vector3.yAxis
	local side = back:Cross(up).Unit -- across the ramp
	local holder = Instance.new("Model")
	holder.Name = "Pit"
	local function place(name: string, cf: CFrame, stretch: number, k: number)
		local src = kit:FindFirstChild(name)
		local off = offsets[name]
		if not (src and src:IsA("BasePart") and off) then
			return
		end
		local p = src:Clone()
		p.Size = Vector3.new(src.Size.X * stretch, src.Size.Y * k, src.Size.Z * k)
		p.CFrame = cf * CFrame.new(off.Position.X * stretch, off.Position.Y * k, off.Position.Z * k) * off.Rotation
		p.Color = Trenches.pieceColor(name)
		p.Material = Enum.Material.SmoothPlastic
		local base = not (string.find(name, "Chunks") or string.find(name, "Planks"))
		p.Anchored = true
		p.CanCollide = base
		p.CanQuery = base
		p.CanTouch = false
		p.Parent = holder
	end
	local function jitter(range: number): number
		return rng:NextNumber(-range, range)
	end
	-- a wall slab with its foot's start at `foot`, leaning back out along `out` (flat), `length` along it from there,
	-- `height` up its slope, turned off true by `yaw` and `roll`; `heap`: a trench parapet behind its top
	local function slab(
		foot: Vector3,
		out: Vector3,
		length: number,
		height: number,
		yaw: number,
		roll: number,
		heap: boolean
	)
		local cf = CFrame.fromMatrix(foot, up:Cross(out), up, out) * CFrame.Angles(0, yaw, roll)
		local stretch = length / TrenchCfg.pieces.segment
		local n = S.walls[rng:NextInteger(1, #S.walls)]
		for _, suffix in { "", "Chunks", "Planks", "PlanksDark" } do
			place(`Wall{n}{suffix}`, cf, stretch, height / TrenchCfg.depth)
		end
		if heap then
			place(`Wall{n}Parapet`, cf * CFrame.new(0, height - TrenchCfg.depth, 0), stretch, 1)
		end
	end
	-- round the wall, the ramp's mouth left open
	local a = S.mouth
	while a < 2 * math.pi - S.mouth - S.turn[1] do
		local step = rng:NextNumber(S.turn[1], S.turn[2])
		local m = a + step / 2
		local out = back * math.cos(m) + side * math.sin(m)
		local x = up:Cross(out)
		for row = 0, S.rows - 1 do
			if rng:NextNumber() >= S.gap then
				local h0 = math.max(row * S.rowStep + rng:NextNumber(-S.shift, S.shift * 0.75), 0)
				local r = d.radius + h0 * lean + rng:NextNumber(-S.shift * 0.6, S.shift * 0.4)
				local length = 2 * r * math.tan(step / 2) + rng:NextNumber(S.extra[1], S.extra[2])
				local foot = at + out * r + up * (h0 - d.depth) - x * (length / 2)
				local height = rng:NextNumber(S.height[1], S.height[2])
				local heap = row == S.rows - 1 and rng:NextNumber() < S.parapet
				slab(foot, out, length, height, jitter(S.jitter[1]), jitter(S.jitter[2]), heap)
			end
		end
		a += step
	end
	-- the ramp's sides, where they stand high enough
	if d.ramp then
		local w = d.ramp.width / 2
		local pitch = math.atan(d.depth / d.ramp.length)
		local y = d.radius + 1
		while y < d.radius + d.ramp.length do
			local length = rng:NextNumber(S.rampLength[1], S.rampLength[2])
			local mid = y + length / 2
			local floor = surface(d, lean, mid, 0)
			local height = surface(d, lean, mid, w + S.rampHeight * lean + 2) - floor
			for _, sx in { -1, 1 } do
				if rng:NextNumber() >= S.rampGap and height >= S.rampMin then
					local out = side * sx
					local forward = up:Cross(out):Dot(back) > 0
					local along = if forward then y else y + length
					local foot = at + back * along + out * (w + jitter(0.3)) + up * surface(d, lean, along, 0)
					local roll = if forward then pitch else -pitch
					slab(foot, out, length, math.min(height, S.rampHeight), jitter(S.jitter[1] * 0.5), roll, false)
				end
			end
			y += length * rng:NextNumber(0.85, 1.05)
		end
	end
	-- a few loose floor pieces, none under the bed
	local n = S.floorGrid
	local segment = TrenchCfg.pieces.segment
	for i = 1, n do
		for j = 1, n do
			local u, v = (i - (n + 1) / 2) * S.floorStep, (j - (n + 1) / 2) * S.floorStep
			local r = math.sqrt(u * u + v * v)
			if rng:NextNumber() >= S.floorGap and r > S.floorStep * 1.2 and r < d.radius - S.floorStep / 2 then
				local centre = at + back * u + side * v + up * (0.05 - d.depth)
				local turn = rng:NextNumber(-S.floorTurn, S.floorTurn) + rng:NextInteger(0, 1) * math.pi / 2
				local cf = CFrame.fromMatrix(centre, up:Cross(back), up, back)
					* CFrame.Angles(0, turn, 0)
					* CFrame.new(-segment / 2, 0, 0)
				local f = rng:NextInteger(1, TrenchCfg.pieces.floors)
				place(`Floor{f}`, cf, 1, 1)
				place(`Floor{f}Chunks`, cf, 1, 1)
			end
		end
	end
	holder.Parent = pitFolder()
	return holder
end

-- Digs a gun in at `at` (its Config `dig`; user 2026-10-21: "when you build the howitzer, it will be slightly
-- underground to give it cover (even when spawned, it should naturally destroy the terrain and be more burrowed)"):
-- the pit carved to a level mud floor `depth` under the ground, an earth rim thrown up round it and a ramp down into it
-- behind the gun (`back`, flat; Ground.pit), its walls lined with trench slabs (`slabs`). Returns the floor and the slabs.
local function dig(at: Vector3, d: any, back: Vector3): (Vector3, Model?)
	local ramp = d.ramp and { dir = back, width = d.ramp.width, length = d.ramp.length }
	local out = Ground.pit(at, d.radius, d.depth, d.rim, d.rimHeight, ramp, d.wall)
	Net.event("GroundDug"):FireAllClients(at, out)
	local pit = if d.slabs and d.wall then slabs(at, d, back) else nil
	return at - Vector3.new(0, d.depth, 0), pit
end

-- a copy of a gun's library model, painted (`paint`: a Config/Palette.Artillery.Paint key, nil: Config/Artillery.Paint),
-- its pivot in gun space
local function copyOf(gun: Cfg.Gun, key: string, paintKey: string?): Model
	local model = library(gun.asset):Clone()
	model.Name = key
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- clients pose it whole
	paint(model, if paintKey and Palette.Artillery.Paint[paintKey] then paintKey else Cfg.Paint)
	for name, c in gun.colors or {} do
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name == name then
				d.Color = rgb(c)
			end
		end
	end
	local base = part(model, gun.base)
	model.PrimaryPart = base
	base.PivotOffset = base.CFrame:ToObjectSpace(gunSpace(model, gun))
	return model
end

-- A gun being built (src/server/Build; Config/Artillery.Assembly): a copy of it in `paint`, nothing to stand on, shoot or
-- touch, posed by Artillery.assemble. Not a gun (no "Gun", nobody mans it).
function Artillery.parts(key: string, paintKey: string?): Model?
	local gun = Cfg.Guns[key]
	if not gun then
		return nil
	end
	local model = copyOf(gun, key, paintKey)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	return model
end

-- each built gun's parts at rest in gun space (Artillery.parts copies, before they are posed), the quarter each appears
-- at (Config/Artillery.Assembly; nil: never while built) and the stage of the gun that moves it (1 mount ... 4 breech)
type Built = {
	rest: { [BasePart]: CFrame },
	at: { [BasePart]: number },
	moves: { [BasePart]: number },
	alpha: { [BasePart]: number }, -- its own transparency
}
local built: { [Model]: Built } = setmetatable({}, { __mode = "k" }) :: any

local function builtOf(model: Model, gun: Cfg.Gun): Built
	local got = built[model]
	if got then
		return got
	end
	local pivot = model:GetPivot()
	local b: Built = { rest = {}, at = {}, moves = {}, alpha = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			b.rest[d] = pivot:ToObjectSpace(d.CFrame)
			b.alpha[d] = d.Transparency
			-- its group: the longest name it starts with (BarrelRunes with Barrel)
			local length = 0
			for _, g in gun.assembly do
				for _, name in g.names do
					if #name > length and string.sub(d.Name, 1, #name) == name then
						b.at[d], length = g.at, #name
					end
				end
			end
			for i, names in { gun.mount, gun.cradle, gun.barrel, gun.breech } do
				if table.find(names, d.Name) then
					b.moves[d] = i
				end
			end
		end
	end
	built[model] = b
	return b
end

-- Poses a gun being built (Artillery.parts) standing at `at` with `quarters` of Config/Artillery.Assembly.quarters
-- done: each group in place once its quarter is done, unseen before; the barrel at the gun's lowest lay.
function Artillery.assemble(model: Model, key: string, at: CFrame, quarters: number)
	local gun = Cfg.Guns[key]
	if not gun then
		return
	end
	local b = builtOf(model, gun)
	local t = gun.trunnion
	local trunnion = CFrame.new(t[1], t[2], t[3])
	local lay = trunnion
		* CFrame.Angles(math.rad(math.clamp(0, gun.elevation[1], gun.elevation[2])), 0, 0)
		* trunnion:Inverse()
	for p, rest in b.rest do
		-- (user 2026-10-26: "the runes shouldn't be active until the cannon is built": nothing glows while built)
		local glow = table.find(Palette.Artillery.Glowing, p.Name) ~= nil
		local up = b.at[p] ~= nil and b.at[p] <= quarters
		local laid = if (b.moves[p] or 0) >= 2 then lay * rest else rest
		p.Transparency = if up and not glow then b.alpha[p] else 1
		p.CFrame = at * laid
	end
end

-- The earth block a placed gun stands on (Config/Artillery.Ground): under its footprint in gun space, from the ground
-- (the pivot) down, part of the gun. A gun with `level` stands on the terrain instead, levelled and bared under it
-- (Ground.level), and its hitbox is an unseen box over its `platform`, from Ground.depth under its foot up, that
-- nothing touches, stands on or hits: it only makes the gun's box (blast) reach over the ground round it.
-- Returns the box of ground under it (x, z in gun space: its footprint and pad), which craters never carve.
local function standOn(model: Model, gun: Cfg.Gun): ({ number }, { number })
	local G = Cfg.Ground
	local pivot = model:GetPivot()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local half = d.Size / 2
			for _, c in
				{
					Vector3.new(1, 1, 1),
					Vector3.new(1, 1, -1),
					Vector3.new(1, -1, 1),
					Vector3.new(-1, 1, 1),
					Vector3.new(1, -1, -1),
					Vector3.new(-1, 1, -1),
					Vector3.new(-1, -1, 1),
					Vector3.new(-1, -1, -1),
				}
			do
				local l = pivot:PointToObjectSpace(d.CFrame:PointToWorldSpace(half * c))
				lo, hi = lo:Min(l), hi:Max(l)
			end
		end
	end
	local L, pf = gun.level, gun.platform
	local pad = if L then L.pad else G.pad
	local under, over = { lo.X - pad, lo.Z - pad }, { hi.X + pad, hi.Z + pad }
	if L then
		local reach = Ground.level(pivot, under, over, L.blend, (Enum.Material :: any)[L.material])
		Net.event("GroundDug"):FireAllClients(pivot.Position, reach)
		local out, thick = if pf then pf.pad else L.pad, if pf then pf.thick else 0
		local box = Instance.new("Part")
		box.Name = "Hitbox"
		box.Anchored = true
		box.CanCollide, box.CanQuery, box.CanTouch = false, false, false
		box.Transparency = 1
		box.Size = Vector3.new(hi.X - lo.X + 2 * out, G.depth + thick, hi.Z - lo.Z + 2 * out)
		box.CFrame = pivot * CFrame.new((lo.X + hi.X) / 2, (thick - G.depth) / 2, (lo.Z + hi.Z) / 2)
		box.Parent = model
		return under, over
	end
	local p = Instance.new("Part")
	p.Name = "Ground"
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = true, true, false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Color = rgb((Palette.Terrain :: any)[G.color])
	p.Size = Vector3.new(hi.X - lo.X + 2 * G.pad, G.depth, hi.Z - lo.Z + 2 * G.pad)
	p.CFrame = pivot * CFrame.new((lo.X + hi.X) / 2, -G.depth / 2 - 0.02, (lo.Z + hi.Z) / 2)
	p.Parent = model
	return under, over
end

-- Places a gun (a Config/Artillery.Guns key) at `at`, its muzzle toward `look` (flattened); a gun with `dig` is dug in.
-- `opts`: `paint` (a Config/Palette.Artillery.Paint key: a player-built gun in its team's paint); `dug`: its pit is
-- already carved round `at` (src/server/Build digs a built gun's pit stage by stage), only its slabs laid here; `up`:
-- the gun stands tilted to it (laid on a slope, Config/Build.Slope), its ground levelled to that plane.
function Artillery.place(
	key: string,
	at: Vector3,
	look: Vector3,
	opts: { paint: string?, dug: boolean?, up: Vector3? }?
): Model?
	local gun = Cfg.Guns[key]
	if not gun then
		return nil
	end
	local model = copyOf(gun, key, opts and opts.paint)
	local base = model.PrimaryPart :: BasePart
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local pit: Model? = nil
	if gun.dig and opts and opts.dug then
		local d = gun.dig
		pit = if d.slabs and d.wall then slabs(at, d, -flat.Unit) else nil
		at -= Vector3.new(0, d.depth, 0)
	elseif gun.dig then
		at, pit = dig(at, gun.dig, -flat.Unit)
	end
	local up = opts and opts.up
	if up and up.Y > 0.5 and not gun.dig then
		local along = flat.Unit - up * flat.Unit:Dot(up)
		model:PivotTo(CFrame.lookAt(at, at + along.Unit, up.Unit))
	else
		model:PivotTo(CFrame.lookAt(at, at + flat.Unit))
	end
	-- (a machine gun stands on its nest's mount bag: no earth, a little box of ground kept from craters)
	local under, over
	if gun.nestGround then
		under, over = gun.nestGround.lo, gun.nestGround.hi
	else
		under, over = standOn(model, gun)
	end
	model:SetAttribute("Gun", key)
	model:SetAttribute("Traverse", 0)
	local lims = Rules.capped(gun, reachCap(key))
	-- its `rest` lay, else the lowest it lays (a mortar never lies flat), within its reach (on level ground)
	local low = math.clamp(gun.rest or math.max(gun.elevation[1], 0), lims[1], lims[2])
	model:SetAttribute("Elevation", low)
	model:SetAttribute("HP", gun.hp)
	model:SetAttribute("Stage", 0)
	if gun.mg then
		model:SetAttribute("Rounds", gun.mg.box)
	end
	local colors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			colors[d] = d.Color
		end
	end

	local spot = Instance.new("Attachment")
	spot.Name = "Crew"
	spot.Parent = base
	spot.WorldPosition = model:GetPivot():PointToWorldSpace(Vector3.new(gun.crew[1], 3, gun.crew[2]))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Man the gun"
	prompt.ObjectText = gun.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = gun.prompt
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom -- the game's own look (src/client/Prompts)
	CollectionService:AddTag(prompt, PromptCfg.Tag)
	prompt.Parent = spot
	model.Parent = folder()

	local yaw = Rules.yawOf(flat.X, flat.Z)
	local s: State = {
		model = model,
		key = key,
		gun = gun,
		prompt = prompt,
		lay = { yaw = yaw, traverse = 0, elevation = low },
		want = { yaw = yaw, elevation = low },
		gunner = nil,
		bot = nil,
		mannedAt = 0,
		conns = {},
		sent = 0,
		aimed = 0,
		landings = {},
		landingKeys = {},
		crewAt = 0,
		mountRest = {},
		weld = nil,
		bracing = false,
		hp = gun.hp,
		stage = 0,
		broken = false,
		colors = colors,
		holes = 0,
		upright = nil,
		lean = random:NextNumber(0, 2 * math.pi),
		pit = pit,
		ground = { at = model:GetPivot(), lo = under, hi = over },
		trigger = false,
		pull = false,
		heat = 0,
		nextShot = 0,
		reloading = false,
		reloadOf = 0,
		unloaded = false,
	}
	if gun.crewTurns then
		local pivot = model:GetPivot()
		for _, name in gun.mount do
			local p = model:FindFirstChild(name, true)
			if p and p:IsA("BasePart") then
				s.mountRest[p] = pivot:ToObjectSpace(p.CFrame)
			end
		end
	end
	guns[model] = s
	prompt.Triggered:Connect(function(player)
		man(s, player)
	end)
	model.Destroying:Connect(function()
		if s.gunner or s.bot then
			leave(s, "Gone", true)
		end
		if s.pit then
			s.pit:Destroy()
		end
		guns[model] = nil
	end)
	return model
end

-- Whether `p` stands on a gun's ground (src/server/Ground keeps craters off it; user 2026-10-27: "the ground beneath
-- artilleries are still not indestructible")
function Artillery.onGround(p: Vector3): boolean
	for _, s in guns do
		local g = s.ground
		local l = g.at:PointToObjectSpace(p)
		if Rules.onGround(l.X, l.Z, g.lo, g.hi) then
			return true
		end
	end
	return false
end

-- One repair swing on a gun (src/server/Build: any team's shovel in Build mode; Config/Artillery.Repair) giving back
-- `amount` HP. Returns what it makes it: "whole", "usable" (back in service) or nil, and its HP now. On "whole" or
-- "usable" the caller stands a fresh gun in its place (its ground flattened out again) and gives it that HP
-- (Artillery.setHp). Nil and 0 for a gun that is whole already or not a gun.
function Artillery.repair(model: Model, amount: number): (string?, number)
	local s = guns[model]
	if not s or s.hp >= s.gun.hp then
		return nil, 0
	end
	local what
	s.hp, what = Rules.repaired(s.hp, s.gun.hp, amount, Cfg.Man.keep, s.broken)
	model:SetAttribute("HP", math.round(s.hp * 10) / 10)
	return what, s.hp
end

-- Removes every gun.
function Artillery.clear()
	for model in guns do
		model:Destroy()
	end
end

-- a turning mount (the howitzer's, its gunner standing on it) posed here as well at its traverse, so the server's gunner
-- and its step stand where every client draws them
local function turnMount(s: State)
	s.crewAt = s.lay.traverse
	local frame = s.model:GetPivot() * turnAt(s.gun, s.lay.traverse)
	for p, rest in s.mountRest do
		p.CFrame = frame * rest
	end
end

-- the Damage folder a gun's holes go in (src/client/Artillery carries each with the part named by its "On")
local function damageFolder(model: Model): Folder
	local f = model:FindFirstChild("Damage")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Damage"
		f.Parent = model
	end
	return f :: Folder
end

local function bare(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	parent: Instance,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	return p
end

-- One shell hole punched into the gun where a ray from round it meets one of its `wreckParts`: a dark disc in the
-- surface and a ring of torn metal flaps bent out round it, in that part's own colour gone dark
local function punch(s: State)
	local W = Cfg.Wreck
	local gun = s.gun
	local targets = {}
	for _, name in gun.wreckParts do
		local p = s.model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			table.insert(targets, p)
		end
	end
	if #targets == 0 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = targets
	local cf, size = s.model:GetBoundingBox()
	local reach = size.Magnitude
	for _ = 1, 8 do
		local inside = Vector3.new(
			random:NextNumber(-0.4, 0.4) * size.X,
			random:NextNumber(-0.2, 0.4) * size.Y,
			random:NextNumber(-0.4, 0.4) * size.Z
		)
		local into = cf:PointToWorldSpace(inside)
		local from = into + random:NextUnitVector() * reach
		local hit = workspace:Raycast(from, (into - from).Unit * reach * 1.5, params)
		if hit and hit.Instance:IsA("BasePart") then
			local on = hit.Instance :: BasePart
			local d = random:NextNumber(gun.holeSize[1], gun.holeSize[2])
			local face = CFrame.lookAt(hit.Position, hit.Position + hit.Normal)
			local holes = damageFolder(s.model)
			local dark = on.Color:Lerp(rgb(Palette.Artillery.Scorched), 0.6)
			local disc = face * CFrame.Angles(0, math.rad(90), 0)
			local parts = {
				bare(
					"Hole",
					Vector3.new(W.holeDepth, d, d),
					disc,
					rgb(Palette.Artillery.Hole),
					holes,
					Enum.PartType.Cylinder
				),
			}
			for k = 1, W.petals do
				local a = 2 * math.pi * (k + random:NextNumber(-0.25, 0.25)) / W.petals
				local flap = face
					* CFrame.Angles(0, 0, a)
					* CFrame.new(0, d * 0.45, 0)
					* CFrame.Angles(math.rad(-random:NextNumber(25, 55)), 0, 0)
					* CFrame.new(0, d * 0.15, -0.02)
				table.insert(parts, bare("Flap", Vector3.new(d * 0.3, d * 0.35, W.holeDepth), flap, dark, holes))
			end
			for _, p in parts do
				p:SetAttribute("On", on.Name)
				p:SetAttribute("Offset", on.CFrame:ToObjectSpace(p.CFrame))
			end
			return
		end
	end
end

-- the accent pieces of `roles` (Palette.Artillery.Roles) blown off: each hidden, a loose copy tumbling away
local function blowOff(s: State, roles: { string })
	local D = Cfg.Wreck.debris
	local centre = s.model:GetPivot().Position
	for _, d in s.model:GetDescendants() do
		if not d:IsA("BasePart") or d.Transparency >= 1 then
			continue
		end
		for _, role in roles do
			if #d.Name > #role and string.sub(d.Name, -#role) == role then
				local loose = d:Clone()
				loose.Anchored = false
				loose.CanCollide, loose.CanQuery, loose.CanTouch = true, false, false
				loose.CollisionGroup = "Debris"
				loose.Parent = workspace
				local out = (d.Position - centre) * Vector3.new(1, 0, 1)
				local dir = (if out.Magnitude > 1e-3 then out.Unit else random:NextUnitVector())
					+ Vector3.new(0, 1.2, 0)
				loose.AssemblyLinearVelocity = dir.Unit * random:NextNumber(D.speed[1], D.speed[2])
				loose.AssemblyAngularVelocity = random:NextUnitVector() * D.spin
				Debris:AddItem(loose, D.life)
				d.Transparency = 1
				break
			end
		end
	end
end

-- A gun's look at its Wreck stage: scorched toward Palette.Artillery.Scorched, holed and stripped of its accents
-- (Wreck.holes, Wreck.lose), its glow dead from Wreck.dark, leaning and sunk (Config/Artillery.Wreck).
local function wreck(s: State)
	local W = Cfg.Wreck
	local art = Palette.Artillery
	local stage = s.stage
	local dark = stage >= W.dark
	local scorched, dead = rgb(art.Scorched), rgb(art.Dead)
	for _ = s.holes + 1, W.holes[stage] or 0 do
		punch(s)
	end
	s.holes = math.max(s.holes, W.holes[stage] or 0)
	blowOff(s, (s.gun.lose or W.lose)[stage] or {})
	if dark then
		s.model:SetAttribute("Dead", true)
	end
	for p, c in s.colors do
		if dark and table.find(art.Glowing, p.Name) then
			p.Color = dead
			p.Material = Enum.Material.SmoothPlastic
		else
			p.Color = c:Lerp(scorched, W.scorch[stage] or 0)
		end
	end
	local tilt, sink = W.tilt[stage] or 0, W.sink[stage] or 0
	if tilt > 0 or sink > 0 then
		s.upright = s.upright or s.model:GetPivot()
		local axis = Vector3.new(math.cos(s.lean), 0, math.sin(s.lean))
		s.model:PivotTo(CFrame.new(0, -sink, 0) * (s.upright :: CFrame) * CFrame.fromAxisAngle(axis, math.rad(tilt)))
	end
end

-- In or out of service by its HP (Rules.mannable; user 2026-11-03: "it can still be operated until low HP (50%)"):
-- under Man.keep its gunner is put off, the prompt dimmed and the barrel knocked down; back at it (a repair, the admin
-- HP) it can be manned again. (A gun being built has no state here yet: src/server/Build places it once built.)
local function service(s: State)
	local ok = Rules.mannable(s.hp, s.gun.hp, true, Cfg.Man)
	if ok and s.broken then
		s.broken = false
		s.model:SetAttribute("Broken", nil)
		if not s.gunner and not s.bot then
			s.prompt.Enabled = true
			s.prompt:SetAttribute(PromptCfg.BlockedAttr, nil)
		end
		return
	end
	if ok or s.broken then
		return
	end
	s.broken = true
	s.model:SetAttribute("Broken", true)
	if s.gunner or s.bot then
		leave(s, "Broken", true)
	end
	s.prompt.Enabled = false
	s.prompt:SetAttribute(PromptCfg.BlockedAttr, "Broken")
	-- the barrel knocked down to its lowest lay and round a little
	local gun = s.gun
	local knock = math.min(Cfg.Wreck.knock, gun.traverse)
	s.lay = {
		yaw = s.lay.yaw,
		traverse = if gun.traverse >= 180
			then s.lay.traverse + random:NextNumber(-knock, knock) -- (a ring mount: no stops)
			else math.clamp(s.lay.traverse + random:NextNumber(-knock, knock), -gun.traverse, gun.traverse),
		elevation = gun.elevation[1],
	}
	s.want = { yaw = s.lay.yaw + s.lay.traverse, elevation = s.lay.elevation }
	s.model:SetAttribute("Traverse", math.round(s.lay.traverse * 100) / 100)
	s.model:SetAttribute("Elevation", s.lay.elevation)
	if gun.crewTurns then
		turnMount(s)
	end
end

-- Gives a freshly placed gun `hp`, damaged to its stage (Config/Artillery.Wreck) as blasts would leave it
function Artillery.setHp(model: Model, hp: number)
	local s = guns[model]
	if not s then
		return
	end
	s.hp = math.clamp(hp, 0, s.gun.hp)
	model:SetAttribute("HP", math.round(s.hp * 10) / 10)
	local stage = Rules.wreckStage(s.hp, s.gun.hp, Cfg.Wreck.at)
	if stage ~= s.stage then
		s.stage = stage
		model:SetAttribute("Stage", stage)
		wreck(s)
	end
	service(s)
end

-- `amount` HP off a gun, through its wreck stages
local function hurt(s: State, amount: number)
	if amount <= 0 then
		return
	end
	s.hp = math.max(s.hp - amount, 0)
	s.model:SetAttribute("HP", math.round(s.hp * 10) / 10)
	local stage = Rules.wreckStage(s.hp, s.gun.hp, Cfg.Wreck.at)
	if stage ~= s.stage then
		s.stage = stage
		s.model:SetAttribute("Stage", stage)
		wreck(s)
	end
	service(s)
end

-- A blast at `position` (Damage.onBlast; `structure`: what set it off, a Config/Artillery.Hits key, nil: by its `kg`)
-- wears each gun down by how far it is from the gun's box (Config/Artillery.Hits).
local function blast(position: Vector3, kg: number, structure: string?)
	local H = Cfg.Hits
	local src = Rules.hitSource(structure, kg, H)
	for model, s in guns do
		if s.hp <= 0 then
			continue
		end
		local cf, size = model:GetBoundingBox()
		local function off(c: CFrame, sz: Vector3): number
			local l = c:PointToObjectSpace(position)
			return Vector3.new(
				math.max(math.abs(l.X) - sz.X / 2, 0),
				math.max(math.abs(l.Y) - sz.Y / 2, 0),
				math.max(math.abs(l.Z) - sz.Z / 2, 0)
			).Magnitude
		end
		local d = off(cf, size)
		-- its platform: a flat pad round its foot that counts as the gun (Config `platform`)
		-- (from the top of the earth it stands on, Config/Artillery.Ground)
		local pf = s.gun.platform
		local ground = model:FindFirstChild("Ground")
		if pf and ground and ground:IsA("BasePart") then
			local top = ground.CFrame * CFrame.new(0, (ground.Size.Y + pf.thick) / 2, 0)
			d = math.min(d, off(top, Vector3.new(ground.Size.X + 2 * pf.pad, pf.thick, ground.Size.Z + 2 * pf.pad)))
		end
		hurt(s, Rules.gunHit(d, src, H.direct) / (s.gun.armour or 1))
	end
end

-- A shovel's Destroy swing on a gun (src/server/Build; user 2026-10-27: "when destroying it with a shovel, it reverts
-- it to construction stage. it should just lower hp as it normally would with usual damage"): `amount` HP off it, as a
-- blast takes it. False for a wreck already at 0 (or not a gun).
function Artillery.harm(model: Model, amount: number): boolean
	local s = guns[model]
	if not s or s.hp <= 0 then
		return false
	end
	hurt(s, amount)
	return true
end

local function stateOf(player: Player): State?
	for _, s in guns do
		if s.gunner == player then
			return s
		end
	end
	return nil
end

-- A field gun's or howitzer's shot: the gunner braces first, the shot goes a moment later (user 2026-10-20: "play that
-- first then fire, a slight delay in the shots makes it feel real"); "BraceAt" says when, for the gunner's brace. False
-- and why when it can't (bracing, reloading, broken, or on its side's own sector; a player is told that last).
local function shoot(s: State): (boolean, string?)
	local ready = s.model:GetAttribute("ReadyAt") :: number?
	if s.gun.mg or s.broken then
		return false, nil
	end
	if s.bracing or (ready and now() < ready) then
		return false, "Reloading"
	end
	local why = friendlyTarget(s)
	if why then
		if s.gunner then
			Net.event("Artillery"):FireClient(s.gunner, "Refused", why)
		end
		return false, why
	end
	s.bracing = true
	s.model:SetAttribute("BraceAt", now())
	local who = body(s)
	task.delay(s.gun.charge, function()
		s.bracing = false
		if who and body(s) == who and guns[s.model] then
			-- (aimed again during the brace: checked once more)
			local still = friendlyTarget(s)
			if still then
				if s.gunner then
					Net.event("Artillery"):FireClient(s.gunner, "Refused", still)
				end
				return
			end
			fire(s)
		end
	end)
	return true, nil
end

local function stateOfBot(model: Model): State?
	for _, s in guns do
		if s.bot == model then
			return s
		end
	end
	return nil
end

-- `s`'s elevation limits now (Rules.capped): its shell no farther than reachCap() on the ground that far out along its
-- lay (one terrain ray, cast again once it has turned a degree or a second has passed); a machine gun's own
local capGround = RaycastParams.new()
capGround.FilterType = Enum.RaycastFilterType.Include
local function limitsOf(s: State): { number }
	local gun = s.gun
	if gun.mg then
		return gun.elevation
	end
	local pivot = s.model:GetPivot()
	local mx, my, mz, dx, _, dz = Rules.muzzle(gun, s.lay.traverse, s.lay.elevation)
	local dir = pivot:VectorToWorldSpace(Vector3.new(dx, 0, dz))
	if dir.Magnitude < 1e-3 then
		return Rules.capped(gun, reachCap(s.key))
	end
	local yaw = math.deg(math.atan2(dir.X, dir.Z))
	local c = s.capAt
	local t = now()
	if c and math.abs(Rules.wrap(c.yaw - yaw)) < 1 and t - c.at < 1 then
		return c.lims
	end
	local cap = reachCap(s.key)
	local muzzle = pivot:PointToWorldSpace(Vector3.new(mx, my, mz))
	local out = muzzle + dir.Unit * cap
	capGround.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(out.X, muzzle.Y + 600, out.Z), Vector3.new(0, -1500, 0), capGround)
	local lims = Rules.capped(gun, cap, if hit then hit.Position.Y - muzzle.Y else nil)
	s.capAt = { yaw = yaw, at = t, lims = lims }
	return lims
end

-- The world yaw and the elevation that put `s`'s shot on `point` (Rules.layFor, from its muzzle where that lay puts
-- it); nil when out of its reach (a field gun's or howitzer's past reachCap() flat), or for a machine gun past its
-- stops.
local function layOn(s: State, point: Vector3, arc: string?): (number?, number?)
	local gun = s.gun
	local at = s.model:GetPivot().Position
	local mx, my, mz = Rules.muzzle(gun, s.lay.traverse, s.lay.elevation)
	local origin = s.model:GetPivot():PointToWorldSpace(Vector3.new(mx, my, mz))
	local yaw, elevation = 0, nil
	for _ = 1, 2 do
		local off = point - origin
		yaw = Rules.yawOf(off.X, off.Z)
		local d = Vector3.new(off.X, 0, off.Z).Magnitude
		elevation = if gun.mg or d <= reachCap(s.key) then Rules.layFor(gun, d, off.Y, nil, arc) else nil
		if not elevation then
			return nil, nil
		end
		mx, my, mz = Rules.muzzle(gun, 0, elevation)
		origin = (CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0)):PointToWorldSpace(Vector3.new(mx, my, mz))
	end
	if gun.mg and not Rules.mgTurns(gun, s.lay.yaw, yaw) then
		return nil, nil
	end
	return yaw, elevation
end

-- the lay toward world `yaw` and `elevation` as layOn finds it (the whole gun turned there, the mount centred)
local function layTo(yaw: number, elevation: number): Rules.Lay
	return { yaw = Rules.wrap(yaw), traverse = 0, elevation = elevation }
end

-- What a bot needs to know of a gun (Artillery.list)
export type GunInfo = {
	model: Model,
	key: string, -- its Config/Artillery.Guns key
	mg: boolean, -- a machine gun (triggerAs / reloadAs), else a field gun or howitzer (fireAs)
	free: boolean, -- nobody on it
	player: Player?, -- the player on it
	bot: Model?, -- the bot on it
	broken: boolean,
	loaded: boolean, -- it would fire now (a round in, or rounds in its box, no brace under way)
	readyIn: number, -- seconds until it is
	rounds: number?, -- a machine gun's box
	crew: Vector3, -- where its gunner stands
	reach: number, -- how near `crew` a bot must be to man it (studs)
	-- with a point: the lay that hits it (nil: out of its reach), whether it lies on kit's own side's sector, and
	-- whether that lay comes down on a spawn (Config/Artillery.SpawnGuard: it won't fire there)
	yaw: number?,
	elevation: number?,
	inRange: boolean?,
	friendly: boolean?,
	spawn: boolean?,
}

-- Every gun as a bot sees it (GunInfo); with `point`, whether and how each reaches it, and with `kit` whether that
-- point is the bot's own side's (Normal: "Can't fire on your own sector").
function Artillery.list(point: Vector3?, kit: string?): { GunInfo }
	local out = {}
	local t = now()
	for model, s in guns do
		local ready = model:GetAttribute("ReadyAt") :: number? or 0
		local rounds = if s.gun.mg then model:GetAttribute("Rounds") :: number? or 0 else nil
		local spot = s.prompt.Parent :: Attachment
		local info: GunInfo = {
			model = model,
			key = s.key,
			mg = s.gun.mg ~= nil,
			free = not s.gunner and not s.bot,
			player = s.gunner,
			bot = s.bot,
			broken = s.broken,
			loaded = not s.broken
				and not s.bracing
				and not s.reloading
				and t >= ready
				and (rounds == nil or rounds > 0),
			readyIn = math.max(ready - t, 0),
			rounds = rounds,
			crew = spot.WorldPosition,
			reach = s.gun.prompt * Cfg.Bot.reach,
		}
		if point then
			info.yaw, info.elevation = layOn(s, point)
			info.inRange = info.elevation ~= nil
			info.friendly = kit ~= nil and landsOwn(kit, point.X, point.Z)
			info.spawn = info.elevation ~= nil and onSpawn(s, layTo(info.yaw :: number, info.elevation :: number))
		end
		table.insert(out, info)
	end
	return out
end

-- The gun the bot `model` mans, if any
function Artillery.gunOf(model: Model): Model?
	local s = stateOfBot(model)
	return s and s.model
end

-- The bot soldier `model` (Config/Bots.Tag) mans `gun` (any free gun, not broken, from within Config/Artillery.Bot
-- `reach` of its crew spot, alive, on no other gun): welded on as a player is. False when it can't.
function Artillery.manAs(model: Model, gun: Model): boolean
	local s = guns[gun]
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not s or not root or not CollectionService:HasTag(model, BotCfg.Tag) then
		return false
	end
	local spot = s.prompt.Parent :: Attachment
	if (root.Position - spot.WorldPosition).Magnitude > s.gun.prompt * Cfg.Bot.reach then
		return false
	end
	return seat(s, model, nil, model)
end

-- The bot's gun laid toward world `yaw` and `elevation` (degrees; at the gun's rates). A machine gun stays within its
-- stops. False when it is on no gun.
function Artillery.aimAs(model: Model, yaw: number, elevation: number): boolean
	local s = stateOfBot(model)
	if not s or not Rules.aimOk(yaw, elevation) then
		return false
	end
	local gun = s.gun
	if gun.mg then
		-- (a bot's lay goes straight in on a gun that turns right round: the 360 nest)
		if gun.traverse < 180 then
			yaw, elevation = Rules.mgLay(yaw, elevation, s.lay.yaw, 0, 0, gun)
		end
	end
	local lims = limitsOf(s)
	s.want = { yaw = Rules.wrap(yaw), elevation = math.clamp(elevation, lims[1], lims[2]) }
	return true
end

-- Whether the bot's field gun or howitzer laid on world `point` would land there (user 2026-11-03, bots "still firing into
-- hills"): the shell's path from its muzzle at that lay (Rules.path) cast against the world, soldiers and the gun left
-- out and the first Config/Bots.Build.Crews `arc.near` studs skipped (its own ground and pit), first coming down within
-- `arc.within` studs of the point; and whether it can lay there at all (in its reach). The low arc first, then the
-- lobbed one (user 2026-11-03: the field gun fires over cover; aimAtAs that `arc`). False, false when it is on no gun.
-- (A machine gun: true, true.)
local shotParams = RaycastParams.new()
local function flown(s: State, point: Vector3, arc: string): (boolean, boolean)
	local gun = s.gun
	local yaw, elevation = layOn(s, point, arc)
	if not yaw or not elevation then
		return false, false
	end
	local A = BotCfg.Build.Crews.arc
	local frame = CFrame.new(s.model:GetPivot().Position) * CFrame.Angles(0, math.rad(yaw), 0)
	local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, 0, elevation)
	local origin = frame:PointToWorldSpace(Vector3.new(mx, my, mz))
	local v = frame:VectorToWorldSpace(Vector3.new(dx, dy, dz)) * gun.speed
	local points = Rules.path(
		origin.X,
		origin.Y,
		origin.Z,
		v.X,
		v.Y,
		v.Z,
		gun.gravity,
		A.step,
		Cfg.MaxFlight,
		math.min(origin.Y, point.Y) - 50
	)
	local skip: { Instance } = { s.model }
	if s.pit then
		table.insert(skip, s.pit)
	end
	for _, m in Damage.soldiers() do
		table.insert(skip, m)
	end
	shotParams.FilterDescendantsInstances = skip
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if Vector3.new(b[1] - origin.X, 0, b[3] - origin.Z).Magnitude >= A.near then
			local from = Vector3.new(a[1], a[2], a[3])
			local hit = workspace:Raycast(from, Vector3.new(b[1], b[2], b[3]) - from, shotParams)
			if hit then
				return Vector3.new(hit.Position.X - point.X, 0, hit.Position.Z - point.Z).Magnitude <= A.within, true
			end
		end
	end
	return false, true
end
function Artillery.shotClearAs(model: Model, point: Vector3): (boolean, boolean, string?)
	local s = stateOfBot(model)
	if not s then
		return false, false, nil
	end
	if s.gun.mg then
		return true, true, nil
	end
	local reach = false
	for _, arc in { "low", "high" } do
		local clear, can = flown(s, point, arc)
		reach = reach or can
		if clear then
			return true, true, arc
		end
	end
	return false, reach, nil
end

-- The bot's gun laid to land on world `point` (the low arc where it can, else the high; `arc` "low" or "high": that
-- one). False when it is on no gun or the point is out of its reach or its shell would come down on a spawn (the lay
-- left as it was).
function Artillery.aimAtAs(model: Model, point: Vector3, arc: string?): boolean
	local s = stateOfBot(model)
	if not s then
		return false
	end
	local yaw, elevation = layOn(s, point, arc)
	if not yaw or not elevation or onSpawn(s, layTo(yaw, elevation)) then
		return false
	end
	s.want = { yaw = Rules.wrap(yaw), elevation = elevation }
	return true
end

-- Whether the bot's gun has come round to its aim (within Config/Artillery.Bot `laid`)
function Artillery.laidAs(model: Model): boolean
	local s = stateOfBot(model)
	return s ~= nil and Rules.laid(s.lay, s.want.yaw, s.want.elevation, Cfg.Bot.laid)
end

-- The bot's field gun or howitzer fired (braced, as a player's). False and why when it can't: "Reloading", "Can't fire
-- on your own sector", nil (not on such a gun, or broken).
function Artillery.fireAs(model: Model): (boolean, string?)
	local s = stateOfBot(model)
	if not s then
		return false, nil
	end
	return shoot(s)
end

-- The last shells fired (newest first): each gun's key, whether a bot fired it, and how far off its aim it was set to
-- come down (Config/Artillery `miss`, studs)
function Artillery.misses(): { { key: string, bot: boolean, off: number } }
	return misses
end

-- The bot's machine gun's trigger held or let go (a fresh pull fires at least one shot). False when it is on no MG.
function Artillery.triggerAs(model: Model, held: boolean): boolean
	local s = stateOfBot(model)
	if not s or not s.gun.mg then
		return false
	end
	if held and not s.trigger and not s.reloading then
		s.pull = true
	end
	s.trigger = held
	return true
end

-- The bot's machine gun's box swapped (as the player's "Reload")
function Artillery.reloadAs(model: Model)
	local s = stateOfBot(model)
	if s then
		reloadBox(s)
	end
end

-- The bot off its gun (Artillery.onBotLeft hears "Left")
function Artillery.leaveAs(model: Model)
	local s = stateOfBot(model)
	if s then
		leave(s, "Left")
	end
end

-- Where the shell of the gun `player` mans comes down as it is laid (the admin panel's "GunDummy"), if anywhere
function Artillery.devLanding(player: Player): Vector3?
	for _, s in guns do
		if s.gunner == player and not s.gun.mg then
			return comesDown(s, s.lay)
		end
	end
	return nil
end

-- `fn(model, gun, why)` on every bot leaving a gun: why "Kicked" (a teammate took it over: the bot stands beside it),
-- "Broken", "Died", "Knocked" (thrown off by a blast: src/server/Ragdoll), "Gone" (the bot or the gun removed) or
-- "Left" (Artillery.leaveAs)
-- The admin panel's shelling (src/server/DevTools, Config/DevTools.Blasts.Shells): `count` of gun `key`'s shells
-- landing round `at`, `every` s apart, within `spread` studs, on the ground there (a trench line under fire)
function Artillery.devShells(key: string, at: Vector3)
	local S = DevCfg.Blasts.Shells
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	task.spawn(function()
		for _ = 1, S.count do
			local r, a = math.random() * S.spread, math.random() * math.pi * 2
			local p = at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local hit = workspace:Raycast(p + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
			burst(key, if hit then hit.Position + hit.Normal * 0.3 else p, nil)
			task.wait(S.every)
		end
	end)
end

function Artillery.onBotLeft(fn: (Model, Model, string) -> ())
	table.insert(botLeft, fn)
end

-- A shell of gun `key` (Config/Artillery.Guns) going off at `at`, fired by `by` (also the admin panel's "Shell shock"
-- rows: src/server/DevTools).
function Artillery.land(at: Vector3, key: string, by: Model?)
	burst(key, at, by)
end

function Artillery.start()
	Damage.onBlast(blast)
	Ground.guard(Artillery.onGround)
	Net.event("Artillery").OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any)
		local s = stateOf(player)
		if not s then
			return
		end
		if kind == "Aim" then
			local t = os.clock()
			-- at most Aim.rate a second (a little slack for the network bunching them)
			if Rules.aimOk(a, b) and t - s.aimed >= 0.5 / Cfg.Aim.rate then
				s.aimed = t
				s.want = { yaw = Rules.wrap(a), elevation = b }
			end
		elseif kind == "Trigger" then
			if s.gun.mg then
				-- (a fresh pull fires its one shot even when let go before the next frame: Rules.mgShot)
				if a == true and not s.trigger and not s.reloading then
					s.pull = true
				end
				s.trigger = a == true
			end
		elseif kind == "Reload" then
			reloadBox(s)
		elseif kind == "Fire" and not s.gun.mg then
			shoot(s)
		elseif kind == "Leave" then
			if os.clock() - s.mannedAt >= Cfg.LeaveAfter then
				leave(s)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local s = stateOf(player)
		if s then
			leave(s)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		for model, s in guns do
			if s.gun.mg then
				machineGun(s, dt)
			end
			if not s.gunner and not s.bot then
				continue
			end
			s.lay = Rules.lay(s.lay, s.want.yaw, s.want.elevation, s.gun, dt, limitsOf(s))
			if t - s.sent < 1 / Cfg.Send then
				continue
			end
			s.sent = t
			-- (laid on a spawn: it lays there all the same, the gunner warned while it is; it won't fire)
			model:SetAttribute(Cfg.SpawnGuard.attribute, if not s.gun.mg and onSpawn(s, s.lay) then true else nil)
			model:SetAttribute("Traverse", math.round(s.lay.traverse * 100) / 100)
			model:SetAttribute("Elevation", math.round(s.lay.elevation * 100) / 100)
			local pivot = model:GetPivot()
			local yaw = math.rad(s.lay.yaw)
			local _, current = pivot:ToOrientation()
			local turned = math.abs(Rules.wrap(math.deg(current - yaw))) > 0.01
			if turned then
				model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, yaw, 0))
			end
			-- a turning mount (the howitzer's, its gunner standing on it) is turned here as well, so the server's gunner
			-- and its step stand where every client draws them
			if s.gun.crewTurns and math.abs(s.lay.traverse - s.crewAt) > 0.05 then
				turnMount(s)
			end
		end
	end)
end

return Artillery
