# Infinite Tower: Project Brief

*Status as of 11 November 2026. All of this work is uncommitted on top of commit `edd8c73`.*

## Storyline

The Tower is older than any record. Ten kingdoms were swallowed by it long ago, and what remains of them lives on as its floors: ash fields, golden forests, drowned cities, snowbound valleys, caverns, a black citadel under dead stars. Now it has risen beside **your** world, and it is feeding. Crops fail, rivers thin and the light weakens as the Tower draws out the world's vitality, floor by floor.

You are the **Master**, the only mortal the Tower answers to. From the Summoning Circle at its foot you call **Remnants**: heroes from the consumed kingdoms, each carrying a fragment of a life that no longer exists, and each with their own reason to see the Tower fall.

Every fifth floor holds one of the Tower's **Guardians**, the beings that channel the stolen vitality upward. You can't beat them by strength alone. On the four floors below each one, you gather what remains of its story: its history, how it fights, its weakness, and what can be prepared against it. Each Guardian you defeat stops part of the drain, and your world begins to recover.

At the top waits the **Starless Sovereign**, the Tower's architect and the mouth that feeds on worlds. The first ascent ends at Floor 50, face to face with it. Defeat the Tower's beings, or your world becomes its next floor.

## What is built

**Summoning and heroes**
- 47 original heroes rated 1★ to 7★, across six classes, using the summon rates you set.
- Only 10-pulls are available at first. 5-pulls unlock at Floor 20 and 2-pulls at Floor 40.
- The price per hero rises as you climb: 100, then 120, then 150 gems.
- Summoned heroes stay hidden as face-down cards that flip one at a time, with a REVEAL ALL option.
- Each duplicate is kept as its own copy, and the Hero Collection screen can filter by rarity.

**Economy**
- You start with 3,000 gems.
- Gems come from first floor clears (+150), boss floors (+600) and new clues (+50).

**The tower**
- 50 floors across 10 regions, each with its own look and weather, and a named boss every fifth floor.
- An investigation journal (J) holds clues that weaken each boss.
- A wayfarer ally quest gives supplies and weakens bosses.
- You can keep exploring a floor after finishing it.

**Exploration and gear**
- Every floor has a hidden equipment cache, and rare items are limited to 2 per 10 floors.
- 13 items have working effects, managed in an equipment screen (I).

**The camp (hub), first slice**
- A walkable 3D camp on a **floating island above the clouds** at the Tower's threshold (main menu → CAMP). It starts as crude, broken rock with rubble and timber huts.
- **Sanctuary works** rebuild the island as you climb, each unlocking at a floor, costing materials and giving a perk: Stone Courtyard (floor 1), Garden Terraces (5), Sanctuary Walls (10), Rune Circle (15), Sparring Arena (20), Barrier Dome (30). Plan them at the Architect's Table.
- Buildings turn from timber to white stone once upgraded to level 2.
- Heroes you invite live there and are shown at their posts.
- **Barracks:** houses 4, 6 or 8 heroes depending on level. If your selected hero rests there, they build a vitality bonus for your next climb.
- **Training Grounds:** heroes gain XP while you're away, and each level adds 3% to a hero's stats in the tower.
- **Quarry and Lumber Yard:** miners gather materials.
- **Scout Hall:** expeditions of 2, 4 or 8 hours bring back materials and sometimes common or unusual gear.
- **Materials:** a new resource from first floor clears (+20, boss floors +80) and from the jobs above. Buildings are built and upgraded to level 3 with it.
- **Offline cap:** time away is capped at 12 hours.
- **Coming next:** Cook, Farmer, Alchemist and healing items, Blacksmith, Scholar, Merchant, Hub Manager, and the shop's rotating stock.

**Shop:** the Quartermaster sells 10 items that unlock by floor, each with a purchase limit.

**Skills:** designed in [SKILLS.md](SKILLS.md) but not built yet.

**Combat** (real-time)
- Light and heavy attacks, dodge, guard (which breaks when stamina runs out) and parry.
- Enemies glow during a visible wind-up before each attack.
- Enemies can't see you through walls or terrain.
- Crouching gives stealth, and you can sneak out through the exit on regular floors.

**Menus**
- Main menu and a Settings & Controls screen; the controls are no longer printed on the play screen.
- The pause menu (Esc) has save, settings and resume.

**Saving**
- Saves are written atomically and protected against invalid data.
- An automatic backup is restored if the save is damaged or missing, and the damaged file is kept rather than deleted.
- Saves carry a version number and migrate from old formats, and a warning appears on screen when a save can't be used.

**Graphics**
- High-quality renderer with volumetric fog, light shafts, ambient occlusion and depth haze.
- Photo-scanned CC0 ground, rock, bark and stone textures.
- Generated terrain with shadowed hollows and wet ground.
- Wind-swept grass fields with rolling gust waves, and flower fields.
- Leaf-card broadleaf trees and conifers.
- Weathered ruins, rocks and pebbles, ridged mountains, weather particles, and the Infinite Tower visible on every horizon.

**Quality**
- 407 automated test checks.
- The real save is never touched during testing.

## What is left

- **Characters:** the player and enemies are still placeholder capsules, with no character models or animations.
- **Effects and audio:** there are no combat effects (hit sparks, slashes, camera shake), and no music or sound at all.
- **Heroes in play:** hero skills are designed in [HERO_SKILL_PROPOSAL.md](HERO_SKILL_PROPOSAL.md) and waiting for your approval. Hero levels and awakening, upgrading with or consuming duplicates, and a party or companions are not built.
- **Floors:** the spec asks for 5–10 ways to clear each floor. Only three exist today: fighting, a stealth exit, and the ally on some floors. Puzzles, negotiation, secret passages, settlements, NPCs and factions are missing.
- **Bosses:** most bosses use simple variations on one pattern. Each one still needs unique mechanics (the Twin's two bodies, the Marshal's reinforcements) and a dressed arena.
- **Interface:** there is no map, no quest log, and no real options (graphics, audio, mouse sensitivity). The summon screen has no special effects for 5★ and above.
- **Story:** it isn't told in the game yet; there are no scenes or dialogue.
- **Saves and platform:** there are no multiple save slots and no online backend. Whether the game targets desktop or Android is still undecided.
