--!strict
-- Someone else's shot as this player hears it (Config/Audio.Heard, Rules/ShotAudio; the shooter hears their own shot
-- from src/client/GunFx). Everything comes from where the shot was fired, late by the distance (sound at 960 studs/s):
-- close by the shot's own sound, farther off crossfading into a far report (Config/Firing.Sounds.Far, a weapon's own in
-- Config/Weapons `sounds`), duller with distance; a bullet passing close cracks (rifles) or whizzes (pellets) beside
-- the listener before the report arrives; walls and hillsides around the listener send back echoes from where they
-- stand, growing in with the shot's distance (none beside the gun). All of it at the weapon's own pitch, the shot in its
-- own tone (Config/Weapons `report`). The listener is the camera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Audio)
local Firing = require(Shared.Config.Firing)
local W = require(Shared.Config.Weapons)
local R = require(Shared.Rules.ShotAudio)
local ScreenBlur = require(script.Parent.ScreenBlur)
local SoundFx = require(script.Parent.SoundFx)

local H = A.Heard

local ShotAudio = {}

-- a weapon's sound `name` (its own over Config/Firing's), as SoundFx entries on falloff `profile`, made once
local entries: { [string]: { { [string]: any } } } = {}
local function sounds(weapon: string, name: string, profile: string): { { [string]: any } }
	local key = `{weapon}:{name}`
	local list = entries[key]
	if not list then
		local w = W[weapon]
		local c = (w and w.sounds and w.sounds[name]) or (Firing.Sounds :: any)[name]
		list = {}
		for _, e in (if c == nil then {} elseif c.id then { c } else c) :: { any } do
			local copy = table.clone(e)
			copy.profile = profile
			table.insert(list, copy)
		end
		entries[key] = list
	end
	return list
end

local function any(list: { { [string]: any } }): { [string]: any }?
	return if #list > 0 then list[math.random(#list)] else nil
end

local function point(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

-- reflections around the listener: level rays out to the echo range, { to the wall, wall to the listener } each
local function walls(listener: Vector3, origin: Vector3, ignore: { Instance }): ({ { number } }, { Vector3 })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local paths, at = {}, {}
	for i = 1, H.echo.rays do
		local a = (i - 1) / H.echo.rays * math.pi * 2
		local r = workspace:Raycast(listener, Vector3.new(math.cos(a), 0, math.sin(a)) * H.echo.range, params)
		if r then
			table.insert(paths, { (r.Position - origin).Magnitude, (r.Position - listener).Magnitude })
			table.insert(at, r.Position)
		end
	end
	return paths, at
end

-- `shooter` fired `weapon` from `origin`; `hits`: where each bullet or pellet ended.
function ShotAudio.heard(shooter: Model, weapon: string, origin: Vector3, hits: { Vector3 })
	if shooter:GetAttribute("Muted") == true then
		return -- a muted soldier (the animation showcase's dummies)
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local listener = camera.CFrame.Position
	local d = (listener - origin).Magnitude
	local late = R.delay(d, H.speed)
	local shotShare, farShare = R.mix(d, H.near, H.far)
	local lo, mid, hi = R.air(d, H.air)
	local w = W[weapon]
	local report = w and w.report
	local pitch = if report then report.pitch else 1
	local tone = if report then report.eq else { 0, 0, 0 }
	if shotShare > H.min then
		SoundFx.play(any(sounds(weapon, "Shot", "Gunshot")), origin, nil, {
			volume = shotShare,
			eq = { lo + tone[1], mid + tone[2], hi + tone[3] },
			delay = late,
			pitch = pitch,
		})
	end
	local far = sounds(weapon, "Far", "Report")
	if farShare > H.min then
		SoundFx.play(any(far), origin, nil, { volume = farShare, eq = { lo, mid, hi }, delay = late, pitch = pitch })
	end

	-- the bullet (or the nearest pellet) going by
	local bullet = if w and w.pellets then H.pass.pellet else H.pass.bullet
	local best: R.Pass? = nil
	for _, hit in hits do
		local p = R.pass(point(origin), point(hit), point(listener), H.pass.radius, H.pass.clear)
		if p and (not best or p.off < best.off) then
			best = p
		end
	end
	if best then
		ScreenBlur.pass(best.off, best.along / bullet) -- blurs the screen as it goes by (src/client/ScreenBlur)
	end
	local pass = any(sounds(weapon, "Pass", "Gunshot"))
	if best and pass then
		local at = Vector3.new(best.point[1], best.point[2], best.point[3])
		SoundFx.play(pass, at, nil, {
			volume = R.passGain(best.off, H.pass.radius, H.pass.edge),
			delay = math.max(0, R.passTime(best.along, best.off, bullet, H.speed) - (pass.lead or 0)),
		})
	end

	-- echoes off what stands around the listener, only once the shot is some way off
	local grow = R.grow(d, H.echo.from, H.echo.full)
	if grow * H.echo.gain <= H.min then
		return
	end
	local ignore: { Instance } = { shooter }
	local own = Players.LocalPlayer.Character
	if own then
		table.insert(ignore, own)
	end
	local paths, at = walls(listener, origin, ignore)
	for _, e in R.echoes(d, paths, H.speed, H.echo.count, H.echo.extra, H.echo.gain, A.Profiles.Report.ref) do
		local el, em, eh = R.air(paths[e.index][1] + paths[e.index][2], H.air)
		SoundFx.play(
			any(far),
			at[e.index],
			nil,
			{ volume = e.gain * grow, eq = { el, em, eh + H.echo.dull }, delay = e.delay, pitch = pitch }
		)
	end
end

-- Loads every weapon's far reports and passes now, so the first one starts on time.
function ShotAudio.preload()
	local all = {}
	for name in W do
		for _, s in { "Far", "Pass" } do
			table.insert(all, sounds(name, s, if s == "Far" then "Report" else "Gunshot"))
		end
	end
	SoundFx.preload(table.unpack(all))
end

return ShotAudio
