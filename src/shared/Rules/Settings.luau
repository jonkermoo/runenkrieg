--!strict
-- Player settings rules (Config/Settings; src/client/Settings, src/server/Profile). Pure: plain values only.

local SettingsRules = {}

export type Option = {
	kind: string,
	values: { string }?,
	min: number?,
	max: number?,
	step: number?,
	default: any,
	defaultTouch: any?,
	format: string?,
}

-- A slider's value: clamped into its range and rounded to its step (from min).
function SettingsRules.snap(opt: Option, x: number): number
	local lo, hi, step = opt.min :: number, opt.max :: number, opt.step :: number
	local v = lo + math.floor((math.clamp(x, lo, hi) - lo) / step + 0.5) * step
	return math.clamp(math.floor(v * 1e6 + 0.5) / 1e6, lo, hi) -- (no float dust: 1.0000000000000002 is 1)
end

-- A slider's value from a share of its track (0 = min, 1 = max), and back.
function SettingsRules.fromShare(opt: Option, share: number): number
	return SettingsRules.snap(
		opt,
		(opt.min :: number) + math.clamp(share, 0, 1) * ((opt.max :: number) - opt.min :: number)
	)
end

function SettingsRules.share(opt: Option, v: number): number
	return (v - opt.min :: number) / ((opt.max :: number) - opt.min :: number)
end

-- Whether a value is valid for an option. `maxKey`: the longest key name accepted (any letters and digits; the client
-- also checks it names a real key).
function SettingsRules.valid(opt: Option?, value: any, maxKey: number): boolean
	if not opt then
		return false
	end
	if opt.kind == "choice" then
		return type(value) == "string" and table.find(opt.values :: { string }, value) ~= nil
	elseif opt.kind == "slider" then
		return type(value) == "number"
			and value == value -- not NaN
			and value >= opt.min :: number
			and value <= opt.max :: number
			and math.abs(SettingsRules.snap(opt, value) - value) < 1e-6
	elseif opt.kind == "key" then
		return type(value) == "string" and #value > 0 and #value <= maxKey and string.match(value, "^%a%w*$") ~= nil
	end
	return false
end

-- The default for an option on this device.
function SettingsRules.default(opt: Option, touch: boolean): any
	return if touch and opt.defaultTouch ~= nil then opt.defaultTouch else opt.default
end

-- Only the valid entries of an untrusted table (a saved profile, a client's save). Never errors. A slider number
-- outside its range (saved before the range shrank) is clamped into it.
function SettingsRules.clean(options: { [string]: Option }, raw: any, maxKey: number): { [string]: any }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, opt in options do
		local v = raw[key]
		if opt.kind == "slider" and type(v) == "number" and v == v and math.abs(v) ~= math.huge then
			v = SettingsRules.snap(opt, v)
		end
		if SettingsRules.valid(opt, v, maxKey) then
			out[key] = v
		end
	end
	-- no key bound twice: keybinds sharing a key are dropped (they fall back to their defaults)
	local uses: { [any]: number } = {}
	for key, v in out do
		if options[key].kind == "key" then
			uses[v] = (uses[v] or 0) + 1
		end
	end
	for key, v in out do
		if options[key].kind == "key" and uses[v] > 1 then
			out[key] = nil
		end
	end
	return out
end

-- The preset the current values match, or "Custom". `get(key)` reads a value.
function SettingsRules.preset(presets: { [string]: { [string]: any } }, order: { string }, get: (string) -> any): string
	for _, name in order do
		local match = true
		for key, v in presets[name] do
			if get(key) ~= v then
				match = false
				break
			end
		end
		if match then
			return name
		end
	end
	return "Custom"
end

-- Binding `action` (an option key of kind "key") to `key`: the changes to make. Another action already on that key
-- takes the action's old key (a swap), so no key is ever bound twice.
function SettingsRules.rebind(
	options: { [string]: Option },
	get: (string) -> any,
	action: string,
	key: string
): { [string]: string }
	local changes = { [action] = key }
	local old = get(action)
	if old == key then
		return {}
	end
	for other, opt in options do
		if other ~= action and opt.kind == "key" and get(other) == key then
			changes[other] = old
		end
	end
	return changes
end

-- The aimed field of view at a chosen hip field of view: the same narrowing ratio as the defaults.
function SettingsRules.aimFov(fov: number, baseFov: number, baseAimFov: number): number
	return baseAimFov * fov / baseFov
end

-- The look turn per pixel: the base sensitivity times the player's multiplier, the Y axis flipped when inverted.
function SettingsRules.look(base: number, scale: number, invert: boolean): (number, number)
	local s = base * scale
	return s, if invert then -s else s
end

-- A sound group's volume: Master x its own share, both in percent.
function SettingsRules.volume(master: number, own: number): number
	return (master / 100) * (own / 100)
end

-- Debris cap and lifetime at a level: the base values times the level's shares (the cap at least 1).
function SettingsRules.debris(
	level: { live: number, lifetime: number },
	maxLive: number,
	lifetime: number
): (number, number)
	return math.max(1, math.floor(maxLive * level.live + 0.5)), lifetime * level.lifetime
end

-- A slider's shown value.
function SettingsRules.format(opt: Option, v: number): string
	return string.format(opt.format or "%g", v)
end

return SettingsRules
