--!strict
-- The narrator's recorded lines (src/client/Speech; generated with the recording, never edited by hand): every line of
-- Config/Cutscenes.Speech recorded one after another in one uploaded audio file, the "sheet" (one upload for the whole
-- narrator). `clips`: each line's exact text -> { start, length } in seconds. A line missing here (its words changed,
-- or a new map) is spoken by Roblox's text-to-speech until it is recorded again.
return table.freeze({
	asset = "rbxassetid://128232469463297",
	volume = 1,
	clips = table.freeze({
		["Cross the meadow at the double."] = { 0.6, 1.637 },
		["Cross the river at the ferry."] = { 2.837, 1.525 },
		["Drive them out of the cascina."] = { 4.962, 1.437 },
		["For Katzmark! Not one step back!"] = { 6.998, 3.391 },
		["For Selvara! The river remembers!"] = { 10.99, 2.146 },
		["For Sowilo! Light the runes!"] = { 13.736, 2.198 },
		["Ford the river by the coaching inn."] = { 16.534, 1.883 },
		["From the watchtower, look east."] = { 19.016, 2.018 },
		["Hold the western rise."] = { 21.634, 1.437 },
		["Katzmark does not rest on a victory. The mages are already marching, rifles slung, while the enemy is still counting its dead."] = {
			23.671,
			7.372,
		},
		["Katzmark holds the valley. Their colours fly from the church tower, and the enemy's last line lies broken in the mud of the river ford."] = {
			31.643,
			8.008,
		},
		["Neither side could break the other. Both armies limp from the field, and both have sworn the next fight will end it."] = {
			40.252,
			6.731,
		},
		["No banner flies over the valley tonight. The guns have fallen silent above the watermill, and the dead lie on both banks of the river."] = {
			47.583,
			7.394,
		},
		["Orders for the Aurel."] = { 55.577, 1.052 },
		["Orders for the valley."] = { 57.229, 1.134 },
		["Selvara holds the valley. Their colours fly from the church tower, and the enemy's last line lies broken in the mud of the river ford."] = {
			58.962,
			7.911,
		},
		["Selvara rides the current of this victory. The brass of their mages is still ringing in the hills, and they mean to strike again before the mud can dry."] = {
			67.473,
			8.921,
		},
		["Sowilo holds the valley. Their colours fly from the church tower, and the enemy's last line lies broken in the mud of the river ford."] = {
			76.994,
			8.135,
		},
		["Sowilo's banners are torn, but they have tasted blood. The crimson rune-casters swear on their scars that the next field will be theirs by nightfall."] = {
			85.729,
			8.297,
		},
		["Take the festival ground under the lanterns."] = { 94.626, 2.316 },
		["Take the oast house. Hold the centre."] = { 97.543, 2.137 },
		["The festival lanterns of the Aurel burn for no one tonight. The meadows are trampled flat, and neither army holds them."] = {
			100.28,
			6.967,
		},
		["The lanterns of the Aurel burn for Katzmark tonight. The enemy has been driven from the festival ground, and the meadows belong to them."] = {
			107.847,
			6.975,
		},
		["The lanterns of the Aurel burn for Selvara tonight. The enemy has been driven from the festival ground, and the meadows belong to them."] = {
			115.422,
			7.58,
		},
		["The lanterns of the Aurel burn for Sowilo tonight. The enemy has been driven from the festival ground, and the meadows belong to them."] = {
			123.601,
			7.023,
		},
		["Then bring down the church tower."] = { 131.224, 1.576 },
		["Through the hedgerows by the barn."] = { 133.4, 1.678 },
	}) :: { [string]: { number } },
})
