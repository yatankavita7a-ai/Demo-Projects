# Boss combat system

*Design, 11 November 2026. It is drawn from research into Elden Ring and the Souls games, God of War (2018 and Ragnarök) and Black Myth: Wukong. The sources are listed at the bottom.*

## Principles we follow
- **Every attack is readable.** Each one has a distinct wind-up pose, sound and ground marker.
  - Wind-ups mostly last 0.6–1.5 s; delayed attacks are the exception.
  - No two attacks share the same wind-up.
- **Fair but hard.** Attacks hit hard, but every one can be avoided.
  - Big committal attacks leave a punish window long enough for a full player combo.
- **Colour code (God of War):**
  - Orange marker: a normal attack. Dodge it, block it or parry it.
  - Yellow flash: parryable. A timed parry staggers the boss hard, while a plain block gets staggered.
  - Red marker: unblockable. You must dodge.
- **Phases add new behaviour, not just more HP.** At 50% health the boss roars, can't be damaged and can't hurt you during the roar, then unlocks new attacks.
  - Wind-ups get at most 12% faster.

## Boss attack data
Each attack is a data record with these fields:
- `windup`, `active` and `recovery` timings.
- `track_until`: the boss stops turning to follow you this many seconds into the wind-up.
- `shape`: cone, circle, ring (an expanding shockwave), line (a charge or beam) or box (a low sweep).
- Size, damage and posture damage.
- Colour: normal, yellow or red.
- Movement: lunge or charge distance.
- Combo follow-ups, and the phase the attack becomes available in.

Shapes scale with the boss's size.

| Archetype | Telegraph | How to answer |
|---|---|---|
| Swipe (cone) | Arm drawn back and a cone marker | Dodge sideways or behind, or parry |
| Overhead slam + shockwave | Weapon raised, circle marker, then an expanding ring | Dodge the impact, then roll through the ring's edge |
| Delayed swing | The pose is held for 0.5–1.5 s | Dodge when the swing starts, not when the wind-up starts |
| Combo string (2–4 hits) | First hit has a full wind-up, then 0.3–0.5 s gaps | Dodge each hit; the finisher is the heaviest |
| Charge (line) | Crouch and roar, line marker; direction locks when the charge starts | Sidestep late |
| Grab (red) | Red marker and a distinct sound | Must dodge; it deals heavy damage |
| Low sweep (box) | Low swing | Jump over it, or roll |
| Projectiles | Charge-up glow | Strafe; they aim where you were when fired |
| Lingering hazards | Ground decals, then fire, roots or poison pools | Move away; at least half the arena always stays safe |
| Stomp (large bosses) | Foot raised, circle under the body | Don't camp between its legs |

## Posture, stagger and critical hits
- Parries, heavy hits and charged heavies fill the boss's **posture bar**.
- The bar drains after 2 s without being filled.
- When it's full, the boss staggers for 3 s and takes extra damage. A heavy attack during the stagger lands a **critical hit** worth about 10% of the boss's maximum health.

## Player mechanics
- **Movement:** jog at 4.6 m/s; hold Shift while moving to sprint at ×1.5.
- **Lock-on** (middle mouse or Tab): the camera frames the boss's chest.
  - When locked on to big bosses, the camera pulls back to a wide, Wukong-style frame.
  - Movement strafes around the target.
- **Camera:** a God of War–style over-the-shoulder camera by default, with a Classic option.
- **Dodge roll:** 2.8 m in 0.6 s, invulnerable from 0.05 to 0.40 s, costing 18 stamina.
  - It can cancel the late part of an attack.
- **Backstep** (Shift with no direction): 0.35 s, 1.3 m.
- **Plunge attacks:** attack during a jump to strike on landing.
- **Spectral steed** (R): rides at 12 m/s, with a double jump and a side dash. A big hit throws you off, and the steed can't be summoned again for 10 s.
- **Perfect dodge:** dodging within 0.15 s of a hit triggers brief slow motion and earns 1 Focus point (Wukong). It leaves an afterimage behind.
- **Focus:** up to 3 points.
  - Earned from every third consecutive light hit and from perfect dodges.
  - **Charged heavy:** hold the heavy attack button to spend all Focus for big damage and posture damage.
- **Immobilize** (V): freezes the target briefly (2.5 s on bosses) on a 45 s cooldown, so you can make your own opening.
- **Stamina:** recovers at about 40 per second after a 0.6 s pause.
- **Feel:** a short hit-stop on hits and parries, weapon trails, and camera shake on big boss impacts.

## Boss sizes and movesets

| Floor | # | Boss | Size | Signature attacks |
|---|---|---|---|---|
| 5 | 0 | The Cinder Warden | 4.5× | Ember arc that leaves fire pools, delayed ground burst with a shockwave, stomp, charge (phase 2) |
| 10 | — | **The Dead Tide** (no guardian) | — | Survive an endless zombie horde for 10:00. See *Special floors* below |
| — | 1 | Mother of Briars *(no longer guards a floor)* | 3× | Root snares at your position followed by eruptions, thorn sweep, vine grab (red), briar hazards (phase 2) |
| 15 | 2 | The Brass Regent | 1.3× | Shielded charge, three-strike royal combo with a yellow finisher, shield bash (red), delayed overhead |
| 20 | 10 | **Vharzul, the Unburnt Wyrm** | 5× | Sweeping fire breath (red cone), tail sweep (box), wing-gust ring, charge; flies to rain fire and breathe from above, then lands with a slam. Invincible without Dragonbane. See *Special floors* below |
| — | 3 | The Drowned Cantor *(no longer guards a floor; the Sovereign still borrows its moves)* | 4× | Rising-water pulse rings, resonant cone (red), water bolts, double pulse (phase 2) |
| 25 | 4 | The Pale Huntress | 1.1× | Arrow volley, pounce (charge into a yellow slam), backstep |
| 30 | 5 | The Maw Below | 5× | Burrowing lunge, darkness hazard field, stomp, tail sweep |
| 35 | 6 | The Hollow Knight | 1.2× | Feinting delayed swings, four-hit combo, shield bash (red); many yellow attacks |
| 40 | 7 | The Sepulchre Twin | 2× | Beam (red line), pinning grab, cross combo |
| 45 | 8 | The Red Marshal | 1.5× | Artillery lanes (line hazards), banner call that summons soldiers, charge |
| 50 | 9 | The Starless Sovereign | 4× | Stance shifts that mix earlier bosses' attacks; two phases |

Clues and allies keep their existing effects: they weaken the boss. A known weakness can also open extra punish time.

## Special floors
*Added 12 November 2026. Inspired by the GameRant piece on enemy design: every encounter has a reason to be in the world (a lore line on the floor's title card), uses scale as spectacle, avoids repetition, and signals danger with sound. Data lives in `scripts/systems/SpecialFloors.gd`.*

### Floor 10: The Dead Tide
*"The kingdoms the Tower drained did not rest. Their people still walk, and they remember you are alive."*
- **Goal:** there is no guardian. Survive for **10:00** of real gameplay time. Paused time does not count; slow motion does not slow the clock.
- **HUD:** the boss bar area shows "SURVIVE THE DEAD TIDE · FELLED n", a big countdown and a draining green bar.
- **Spawning:** groups arrive from 26–36 m away, behind the camera, so they come from out of view. A hard cap of **40** live zombies holds at all times. Zombies that fall more than 75 m behind, drop out of the world, or stay stuck for 10 s are removed.
- **Escalation:** every **2:00** (five tiers), spawns come faster and in bigger groups, the live cap rises (14 → 40), and zombies get more health (×1.0 → ×1.75) and speed (×1.0 → ×1.2). The mix shifts from shamblers to runners and brutes.
- **Surges:** at **4:00** and **8:00** a brute pack (3, then 4 brutes, plus 5 shamblers) breaks through from one direction, with a bell toll and a camera shake.
- **Zombie types:** all reuse existing monster models, desaturated to a sickly grey-green (`shaders/zombie_rot.gdshader`).

  | Type | Model | Behaviour |
  |---|---|---|
  | Shambler | Orc | Slow (1.7 m/s), sluggish walk |
  | Runner | Tribal | Fast (5 m/s), fragile, quick wind-up |
  | Bloated | Blob Orc | Slow; on death it bursts into a 6 s poison pool (`BossHazard`) |
  | Brute | Yeti | 4× health, 1.6× size, heavy hits; light hits do half damage and it does not flinch |

- **Clues and allies:** the floor 6–9 clues now describe the Tide. Each clue found and each Wayfarer ally thins it (longer spawn gaps, and each clue lowers the cap by one).
- **Clearing:** reaching 0:00 collapses the remaining dead and clears the floor. Dying uses the normal defeat and retry flow.
- **Debug:** in debug builds, F9 skips one minute; `DeadTideDirector.fast_forward(seconds)` is the test hook.

### Floor 20: Vharzul, the Unburnt Wyrm
*"The Tower could not burn the last dragon, so it chained it. Vharzul guards the gate that drinks its own sky."*
- **Size and model:** 5× the player, using the Flying/Dragon model with ash-gold scales. Moveset index 10 in `BossMoves`.
- **Ground attacks:** sweeping fire breath (a red cone; the whole arc is marked, then a narrow flame swings across it), tail sweep (a box you can jump), wing gust (an expanding ring) and charge.
- **Flight:** takes off (it is untouchable while airborne and the player can walk beneath it), makes three air attacks (fire rain pools, a sweeping breath from above), then glides over the player and drops in a landing slam with a shockwave.
- **Phase two:** an inferno sweep into a tail whip, and a ring-shaped fire storm.
- **Invincible by default:** without Dragonbane, every hit clangs off with a spark and a HUD hint, and does no damage, posture or burn.
- **Dragonbane:** three pieces are hidden in glowing shrines west of the path:
  - Scalebreaker Shard on floor 16.
  - Emberward Charm on floor 17 or 18, chosen by the world seed.
  - Wyrm's Eye on floor 19.

  The inventory (I) lists the pieces and where they are, and offers **Forge Dragonbane** once all three are owned. Carrying the forged blade lets hits land. A glowing weak point under its throat takes **double damage and posture**, and so does any hit while it is staggered. Pieces and blade are saved in the tower state (`dragonbane: {pieces, forged}`), validated and saved atomically.
- **Without Dragonbane:** entering floor 20 shows a warning, the piece locations and a choice:
  - (a) **Return** to the lowest floor that still hides a piece. The pause menu also offers a retreat to floor 19.
  - (b) **The Chain Rite** (very hard). Four Tower chains bind Vharzul to pillars around the arena.
    - Stand in a pillar's circle for **8 s** to light it. Progress drains at 0.5/s while you are outside the circle.
    - During the rite, Vharzul attacks at full aggression: wind-ups ×0.8 and shorter pauses.
    - When all four pillars are lit, the chains drag it down for **8 s**. During that window it takes normal damage, cannot be immobilized and builds no posture.
    - It then breaks free and the pillars reset. Each cycle its wind-ups are 5% faster (down to ×0.6) and its attacks hit 15% harder.
    - Reaching half health still triggers the roar, which breaks the chains.

## Two implementations
- **Godot:** built into the game itself.
- **Unity:** a standalone boss-arena prototype in `unity-boss-prototype/`, next to the Godot project, using the same design. It's for comparison and experimentation; it can't plug into the Godot game.

## Sources
- Birkhead, "Boss Design – Tips From A Combat Designer" (Game Developer)
- Stout, "Enemy Attacks and Telegraphing" (Game Developer)
- Cooper, "How do enemy attacks work with the camera?" (Signals and Light)
- God of War ring colours: Digital Trends combat guide; Gamepressure guide to Ragnarök
- Game Informer, God of War combat designer on the Valkyries
- Sekiro posture: Samurai Gamers
- Black Myth: Wukong: Maxroll stances guide; Gamepressure combat system; Gamer Guides on Immobilize; Destructoid on Focus points
- Video reference: "How to make a BOSS in Unity!" (Brackeys), https://youtu.be/AD4JIXQDw0s
