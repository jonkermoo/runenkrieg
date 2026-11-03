--!strict
-- The admin panel's slope readout (Config/DevTools.Admin.Slope; Config/Build.Slope): while the Player has the
-- attribute, a label at the cursor's ground with its slope and how each gun piece would lie there (the same survey
-- the build ghost and the server use: BuildSurvey.ground, BuildSurvey.lay), and the first piece's plane shown over its
-- footprint, tilted as it would be laid. Only for this player; nothing goes to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local C = require(Shared.Config.Build)
local Rules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)

local DevSlope = {}

local S = Cfg.Admin.Slope

local shown: { gui: BillboardGui, text: TextLabel, plane: Part, spot: Attachment }? = nil

local function hide()
	if shown then
		shown.gui:Destroy()
		shown.plane:Destroy()
		shown.spot:Destroy()
		shown = nil
	end
end

local function make(): { gui: BillboardGui, text: TextLabel, plane: Part, spot: Attachment }
	local spot = Instance.new("Attachment")
	spot.Name = "DevSlope"
	spot.Parent = workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Name = "DevSlope"
	gui.Adornee = spot
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S.width, S.tall)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = S.size
	text.TextColor3 = Color3.new(1, 1, 0.85)
	text.TextStrokeTransparency = 0.3
	text.TextWrapped = true
	text.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local plane = Instance.new("Part")
	plane.Name = "DevSlopePlane"
	plane.Anchored = true
	plane.CanCollide, plane.CanQuery, plane.CanTouch = false, false, false
	plane.CastShadow = false
	plane.Material = Enum.Material.SmoothPlastic
	plane.Transparency = S.see
	plane.Parent = workspace.CurrentCamera
	return { gui = gui, text = text, plane = plane, spot = spot }
end

-- one piece's line: its lie on the ground at `at`, facing `look`, and its plane (nil when too steep)
local function read(piece: Rules.Piece, at: Vector3, look: Vector3): (string, CFrame?)
	local gun = piece.kind == "Gun"
	local frame = Survey.frame(at, look)
	local box = if gun then Survey.box(piece, frame) else frame
	local report = Survey.ground(piece, box)
	local plane, tilt, cut = Survey.lay(piece, box, report)
	local max = piece.maxSlope or C.Trench.maxSlope
	local steep = report.slope > max
	if not report.ground or report.water then
		return `{piece.name}: {if report.water then "water" else "no ground"}`, nil
	end
	if steep or not plane then
		return `{piece.name}: too steep ({math.round(report.slope)}° > {max}°)`, nil
	end
	return `{piece.name}: earth {math.round(cut)}°, tilt {math.round(tilt)}° (steepest {math.round(report.slope)}°)`,
		plane
end

function DevSlope.start()
	local player = Players.LocalPlayer
	local wait = 0
	RunService.Heartbeat:Connect(function(dt)
		wait -= dt
		if wait > 0 then
			return
		end
		wait = S.every
		local character = player.Character
		if player:GetAttribute(S.attribute) ~= true or player:GetAttribute(Cfg.Attribute) ~= true or not character then
			hide()
			return
		end
		local camera = workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
		if not hit then
			hide()
			return
		end
		local s = shown or make()
		shown = s
		local look = Vector3.new(ray.Direction.X, 0, ray.Direction.Z)
		local lines = {}
		local first: CFrame? = nil
		local firstPiece: Rules.Piece? = nil
		for i, key in S.pieces do
			local piece = Rules.piece(key, C.Pieces)
			if piece then
				local line, plane = read(piece, hit.Position, look)
				table.insert(lines, line)
				if i == 1 then
					first, firstPiece = plane, piece
				end
			end
		end
		s.spot.WorldPosition = hit.Position
		s.text.Text = table.concat(lines, "\n")
		local fp = firstPiece
		if first and fp then
			s.plane.Size = Vector3.new(fp.width, 0.2, fp.depth)
			s.plane.CFrame = first * CFrame.new(0, 0.15, 0)
			s.plane.Color = Color3.fromRGB(120, 200, 120)
			s.plane.Transparency = S.see
		else
			s.plane.Transparency = 1
		end
	end)
end

return DevSlope
