# Boss Arena Prototype (Unity)

A standalone Unity prototype of the boss design in `../docs/BOSS_SYSTEM.md`. It's for comparison and experimentation and doesn't plug into the Godot game.

- Unity 6000.3.28f1, built-in render pipeline, legacy Input Manager.
- The only package beyond the built-in modules is the Test Framework.
- No imported assets: everything is primitives, procedural meshes, materials and sounds.

## Opening it
1. In Unity Hub choose **Add > Add project from disk** and select this folder.
2. Open `Assets/Scenes/BossArena.unity` and press Play.
   - If the scene is missing, run **Boss Prototype > Build Arena Scene**.
   - Pressing Play in any empty scene also works: a bootstrap spawns the arena.
3. If input does nothing and the HUD shows "Legacy input unavailable", go to **Project Settings > Player > Active Input Handling** and set it to *Input Manager (Old)* or *Both*.

Batch rebuild of the scene:

```
Unity -batchmode -nographics -quit -projectPath . -executeMethod ArenaSceneBuilder.Build -logFile build.log
```

To run the EditMode tests: **Window > General > Test Runner > EditMode**. From the command line use `-runTests -testPlatform EditMode` (without `-quit`).

## Controls
| Input | Action |
|---|---|
| WASD | Move. While locked on, you strafe around the boss. |
| Mouse | Orbit the camera. Click to capture the cursor, Esc to release it. |
| Tab / middle mouse | Lock on |
| LMB | Light attack, up to a 3-hit chain. Every 3rd consecutive light hit gives +1 Focus. |
| RMB | Heavy attack |
| Hold RMB (with Focus) | Charged heavy, which spends all Focus |
| Q / Left Shift (hold) | Block. Pressing it within 0.2 s of a hit is a parry. |
| Space | Dodge roll |
| V | Immobilize |
| 1–4 | Swap boss: Cinder Warden, Brass Regent, Drowned Cantor, Pale Huntress |
| R | Restart after death or victory. Ctrl+R restarts at any time. |
| H | Toggle the help panel |

## How it maps to BOSS_SYSTEM.md
| Spec | Where |
|---|---|
| Attack data record: windup/active/recovery, `track_until`, shape, size, damage, posture, colour, lunge, follow-ups, phase | `BossAttack` in `Assets/Scripts/Combat/CombatTypes.cs`. AI fields: range, weight, comboOnly, heldPose, placement, special, ringAfter. |
| Shapes scale with boss size | `BossController.ScaledSize` (size × current scale / default scale) |
| Colour code: orange / yellow / red | `Telegraph` ground markers that fill over the windup, plus a boss body flash and a distinct procedural sound for each colour (`Sfx`) |
| Ring = expanding shockwave | `Shockwave`; roll through its edge |
| Lingering hazards (at least half the arena stays safe) | `FirePool`, with at most 6 at a time |
| Projectiles aim where you were | `BossProjectile`; each bolt aims at your position at the moment it's fired |
| State machine | `BossController`: Idle/Approach → distance-weighted choice → Windup (tracks until `trackUntil`) → Active → Recovery → … |
| Posture, stagger and criticals | Parries, heavies and charged heavies fill posture. It drains after 2 s idle. When full, the boss staggers for 3 s; a heavy during the stagger is a critical worth 10% of max HP plus half the hit's damage. |
| Phase 2 at 50% | 2.5 s roar: the boss can't be damaged and can't hurt you. It unlocks phase-2 attacks and multiplies windups by 0.88. |
| Lock-on framing, pulled back for bosses ≥3× | `OrbitCamera` |
| Dodge: 0.6 s, 3.5 m, i-frames 0.05–0.40 s, 18 stamina; perfect dodge | `PlayerController` + `CombatMath`. A hit that lands 0.05–0.15 s into the roll gives slow motion (timeScale 0.35 for 0.4 s real time) and +1 Focus. A dodge can cancel the late part of your attack. |
| Focus (max 3) and charged heavy | `PlayerController` |
| Immobilize | 2.5 s freeze, 45 s cooldown, then 20 s of boss immunity |
| Stamina | Regenerates 40/s after 0.6 s without spending |
| Feel | `GameFeel` hit-stop and slow-mo, plus `OrbitCamera.Shake` |

Tuning constants live in `Tuning` (`CombatMath.cs`). Movesets live in `BossLibrary.cs`.

### Bosses
- **The Cinder Warden** (4.5×): Ember Arc (cone that leaves fire pools), Delayed Ground Burst (held pose, circle impact, then a ring shockwave), Stomp (circle under its body), the three-hit Warden String, Cinder Grab (red), and Molten Charge (line, phase 2).
- **The Brass Regent** (1.3×): Shielded Charge, Royal Strike I–III (the finisher is yellow), Shield Bash (red), Delayed Overhead, and Regal Onslaught (phase 2: a charge into the yellow finisher).
- **The Drowned Cantor** (4×): Pulse Ring, Resonant Cone (red), Water Bolts, Tidal Slam, and Double Pulse (phase 2).
- **The Pale Huntress** (1.1×): Arrow Volley (markers at your position), Pounce (line into a yellow slam), Backstep into Huntress Shot, Hunting Knife, and Rain of Arrows (phase 2).

To change a boss's size, set `scaleOverride` on the `BossController` in the scene. A value of 0 uses the default size.

## Layout
- `Assets/Scripts/Core/`: bootstrap, arena factory and root, input wrapper, game feel, materials, sounds.
- `Assets/Scripts/Combat/`: data types, maths and tuning, boss library.
- `Assets/Scripts/Boss/`: boss AI, telegraphs, shockwave, fire pool, projectile.
- `Assets/Scripts/Player/`: player and camera.
- `Assets/Scripts/UI/`: IMGUI HUD.
- `Assets/Editor/ArenaSceneBuilder.cs`: builds and saves the scene.
- `Assets/Tests/EditMode/`: NUnit tests for the maths, the boss data and the arena build.
