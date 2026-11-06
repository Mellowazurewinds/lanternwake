# Lanternwake

Lanternwake is an original, small-scale twilight platformer. Guide a cloaked lantern keeper through three seeded levels, jump across floating stone paths, and reach each glowing exit. Echo lights are optional pickups; drifting storm motes and falls cost lives.

## Play

- At launch, choose Ember Dusk, Blue Hour, or Mint Aurora, then select **Start Voyage**. Use **New Seed** to preview another level layout before starting.
- Run with **A/D** or the **left/right arrows**.
- Jump with **Space**, **W**, or the **up arrow**.
- Reach the glowing gate at the end of each level. Routes include optional high ledges; later levels add moving platforms, crumbling stones, and more storm motes.
- Collect echo lights along the way for a higher pickup count; they are optional and do not end the level.
- Avoid storm motes and stay on the platforms; you have three chances, with respawns at the last platform you reached.
- Click **New World** or press **R** to generate a new seed and switch to a different biome. Ember Dusk has drifting cinders and warm ruin stone, Blue Hour has constellation marks and icy crystals, and Mint Aurora has moving sky ribbons and mossy paths.
- Press **Esc** or click **Pause** to open the menu. Resume, restart the level, pick a new biome, return to the title screen, or quit from there.
- Press **Enter** at a level gate to continue. After winning or losing, press **Enter** to start again.

The scene, traveler, platforms, exits, collectibles, hazards, and scenery are drawn in GDScript. The presentation uses a low-resolution 384x216 render enlarged in crisp, whole-number pixels, with compact color palettes, layered sky bands, biome-specific scenery, framed menus, and readable platform silhouettes. All characters, environments, and artwork are original to Lanternwake. Each seed, biome, and level number creates a repeatable platform route, echo light layout, storm placement, and themed scenery. Endless mode is not part of this version.

Open this folder in Godot 4.4 or later and run `main.tscn` (also configured as the project start scene).
