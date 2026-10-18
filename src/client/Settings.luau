--!strict
-- Client settings. The source of truth is an attribute on the local Player ("Setting_<Key>"), so the menu, any client
-- system and tests share one value. The server sets the saved ones when the profile loads (src/server/Profile);
-- a change here is sent back to be saved (Net "SaveSettings", Config/Settings.SendDelay after the last change).
-- Settings.get(key), Settings.set(key, value), Settings.changed(key, fn), Settings.key(action) for a keybind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Settings)
local Net = require(Shared.Net)
local R = require(Shared.Rules.Settings)

local Settings = {}

local player = Players.LocalPlayer
local PREFIX = "Setting_"

-- A key option's value must also name a real key or mouse button.
function Settings.input(name: string): (Enum.KeyCode | Enum.UserInputType)?
	-- indexing an enum with a name it lacks throws
	local ok, key = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok then
		return key
	end
	local okType, kind = pcall(function()
		return (Enum.UserInputType :: any)[name]
	end)
	return if okType and string.match(name, "^MouseButton") then kind else nil
end

local function valid(key: string, value: any): boolean
	local opt = (Cfg.Options :: any)[key]
	return R.valid(opt, value, Cfg.MaxKeyName) and (opt.kind ~= "key" or Settings.input(value) ~= nil)
end

-- Defaults, unless the profile already set the attribute.
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
for key, opt in Cfg.Options :: any do
	if not valid(key, player:GetAttribute(PREFIX .. key)) then
		player:SetAttribute(PREFIX .. key, R.default(opt, touchOnly))
	end
end

function Settings.get(key: string): any
	return player:GetAttribute(PREFIX .. key)
end

local sendAt = 0
local function send()
	local at = os.clock() + Cfg.SendDelay
	sendAt = at
	task.delay(Cfg.SendDelay, function()
		if sendAt ~= at then
			return -- changed again since: the later one sends
		end
		local all = {}
		for key in Cfg.Options do
			all[key] = Settings.get(key)
		end
		Net.event("SaveSettings"):FireServer(all)
	end)
end

function Settings.set(key: string, value: any)
	assert(valid(key, value), `invalid setting {key}={value}`)
	if player:GetAttribute(PREFIX .. key) ~= value then
		player:SetAttribute(PREFIX .. key, value)
		send()
	end
end

-- Calls fn(value) whenever the setting changes (from the menu or the loaded profile).
function Settings.changed(key: string, fn: (any) -> ())
	player:GetAttributeChangedSignal(PREFIX .. key):Connect(function()
		local v = player:GetAttribute(PREFIX .. key)
		if valid(key, v) then
			fn(v)
		end
	end)
end

-- A keybind's input ("Key_Fire" -> Enum.UserInputType.MouseButton1).
function Settings.key(action: string): Enum.KeyCode | Enum.UserInputType
	return Settings.input(Settings.get(action)) :: any
end

-- Whether an input is the one bound to an action.
function Settings.pressed(action: string, input: InputObject): boolean
	local k = Settings.key(action)
	return input.KeyCode == k or input.UserInputType == k
end

return Settings
