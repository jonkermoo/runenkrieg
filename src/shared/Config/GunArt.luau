--!strict
-- Each gun's body drawn flat for the HUD's gun card (src/client/AmmoHud; user 2026-11-12: "make sure it looks like the
-- guns in game too, just 2d"): a side view from the gun's right (+X), the muzzle to the right, rendered from the gun's
-- own meshes as Armory.build scales them (every visible part but the ones the card draws live: bolt, bore, rounds,
-- cases, clips, shells), each part its own flat colour with an ink outline, and uploaded as one Image each. `z` and `y` are the
-- image's edges in gun space (studs, the Gun part's frame): its left edge at z[2] (the butt), its right at z[1] (the
-- muzzle), its top at y[2], its bottom at y[1].
-- To redraw them: tools/gunart (local tooling, README.md there).
local GunArt: { [string]: { image: number, z: { number }, y: { number } } } = {
	pistol_c96 = { image = 104331262967979, z = { -1.5702, 0.5772 }, y = { -0.9879, 0.5522 } },
	pistol_nagant = { image = 91524033338898, z = { -0.986, 0.7206 }, y = { -0.8659, 0.35 } },
	pistol_webley = { image = 104005851333113, z = { -1.2905, 0.7695 }, y = { -0.893, 0.5426 } },
	rifle_g98 = { image = 80428728470528, z = { -3.9354, 1.4816 }, y = { -1.0813, 0.3496 } },
	rifle_m91 = { image = 114248350348323, z = { -3.9935, 1.5732 }, y = { -1.0956, 0.3389 } },
	rifle_mondragon = { image = 95944109511928, z = { -3.3806, 1.4142 }, y = { -0.9765, 0.3776 } },
	rifle_remington8 = { image = 102596252156194, z = { -2.9502, 1.5996 }, y = { -1.0043, 0.3695 } },
	rifle_smle = { image = 81605645050239, z = { -3.4338, 1.4705 }, y = { -1.018, 0.4282 } },
	rifle_winchester1907 = { image = 104708660696588, z = { -2.7092, 1.7044 }, y = { -1.1623, 0.3155 } },
	shotgun_m1897 = { image = 82791832511407, z = { -2.7866, 1.5463 }, y = { -1.0043, 0.3078 } },
}

return table.freeze(GunArt)
