--!strict
-- Client settings. The source of truth is an attribute on the local Player ("Setting_<Key>"), so the
-- menu, any client system, tests, and (later) the server loading a saved profile all share one value.
-- Settings.get(key), Settings.set(key, value), Settings.changed(key, fn).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)

local Settings = {}

local player = Players.LocalPlayer
local PREFIX = "Setting_"

local function valid(key: string, value: any): boolean
	local opt = Cfg.Options[key]
	return opt ~= nil and table.find(opt.values, value) ~= nil
end

-- Defaults, unless something (e.g. a loaded profile) already set the attribute.
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
for key, opt in Cfg.Options do
	if not valid(key, player:GetAttribute(PREFIX .. key)) then
		player:SetAttribute(PREFIX .. key, if touchOnly and opt.defaultTouch then opt.defaultTouch else opt.default)
	end
end

function Settings.get(key: string): string
	return player:GetAttribute(PREFIX .. key) :: string
end

function Settings.set(key: string, value: string)
	assert(valid(key, value), `invalid setting {key}={value}`)
	player:SetAttribute(PREFIX .. key, value)
end

function Settings.changed(key: string, fn: (string) -> ())
	player:GetAttributeChangedSignal(PREFIX .. key):Connect(function()
		local v = player:GetAttribute(PREFIX .. key)
		if valid(key, v) then
			fn(v :: string)
		end
	end)
end

return Settings
