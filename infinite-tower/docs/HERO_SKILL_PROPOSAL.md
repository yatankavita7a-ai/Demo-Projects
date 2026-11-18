# Infinite Tower — Hero Skill Proposal

This document proposes one active and one passive skill for each of the 47 heroes in `data/HeroDatabase.gd`. These are design proposals only; no skill content or battle effects have been added to the game. Exact values, cooldowns, progression unlocks, and interactions should be tuned after approval and playtesting.

The proposals target the planned third-person action combat. Skills should support readable choices and exploration, while keeping low-rarity heroes useful through clear specializations rather than raw power. Duplicate hero instances will retain independent progression and awakening state.

## Original heroes

| Hero | Active skill proposal | Passive skill proposal |
|---|---|---|
| Aurelia | **Dawnward Arc** — a forward sword sweep that briefly guards Aurelia during its wind-up. | **Lasting Oath** — a well-timed block steadies her, improving stamina recovery for a short time. |
| Kael | **Ashen Comet** — launch a focused ember bolt that bursts against a target or nearby surface. | **Cinder Study** — repeated hits on one enemy increase Kael's damage against that enemy for a short period. |
| Sylva | **Briarline Shot** — fire a binding arrow that briefly slows a target. | **Canopy Step** — moving through foliage or ruin cover reduces enemy detection. |
| Draven | **Iron Verdict** — a heavy overhead strike that deals extra poise damage to guarding enemies. | **Veteran's Measure** — taking a hit while attacking reduces the recovery time of Draven's next heavy strike. |
| Nyra | **Veilstep** — dash through a target and strike from behind if the path is clear. | **Patient Knife** — attacks from outside an enemy's awareness deal increased opening damage. |
| Orion | **Starfall Mark** — mark a target; the next charged attack against it calls down a small arcane impact. | **Astral Reading** — marked enemies show clearer wind-up cues. |
| Lyra | **Mending Chord** — restore a modest amount of health and interrupt nearby lesser enemies. | **Steady Hymn** — healing an ally or herself also restores a small amount of stamina. |
| Ragnar | **Gatebreaker** — brace, then drive forward with a shield-led impact that staggers enemies. | **Stonewall** — blocking a heavy attack reduces the stamina cost of the next block. |
| Vex | **Dustneedle** — throw a quick blade that interrupts an enemy preparing an attack. | **Fleeting Target** — a successful dodge briefly reduces enemy tracking. |
| Seraphina | **Gilded Benediction** — create a short-lived ward that reduces incoming damage while standing within it. | **Merciful Return** — defeating an enemy restores a small amount of health, with a short internal limit. |

## One-star heroes

| Hero | Active skill proposal | Passive skill proposal |
|---|---|---|
| Brutus | **Shoulder Rush** — charge a short distance and stagger the first enemy hit. | **Hard Knuckles** — light attacks deal more poise damage to already-staggered foes. |
| Aldric | **Measured Cut** — a deliberate slash with a longer wind-up and strong guard pressure. | **Keep Formation** — blocking without moving improves Aldric's next attack stability. |
| Toren | **Quarry Slam** — strike the ground to disrupt nearby enemies and expose their footing. | **Sure Footing** — stagger and knockback effects on Toren are reduced. |
| Cedric | **Turning Guard** — turn into an incoming attack and answer with a quick counter if timed well. | **Watchful Guard** — successful blocks briefly widen the parry timing window. |
| Garron | **Rallying Cry** — interrupt nearby lesser enemies and draw their attention. | **Old Campaigner** — health recovery items restore a little more health. |
| Elric | **Spark Lance** — a narrow electric strike that interrupts one target. | **Charged Focus** — landing a spell on an attacking enemy briefly improves spell recovery. |
| Zephyr | **Windstep** — a quick lateral burst that can pass through a narrow enemy attack. | **Light as Air** — dodges consume slightly less stamina when moving laterally. |
| Merek | **Runic Snare** — place a small rune that briefly roots the first enemy to cross it. | **Patient Scribe** — standing still briefly improves the reach of Merek's next spell. |
| Isolde | **Frost Needle** — a precise ice shard that slows a target after repeated hits. | **Cold Resolve** — slowed enemies deal slightly less poise damage to Isolde. |
| Theron | **Echo Bolt** — fire a bolt that repeats at reduced strength if it hits a marked target. | **Resonant Casting** — consecutive spell hits on one target briefly improve Theron's focus. |
| Faye | **Snare Arrow** — pin a target's movement briefly if the arrow hits its legs. | **Fieldcraft** — nearby hidden caches become easier to notice while Faye is unthreatened. |
| Rowan | **Covering Volley** — loose a short volley while stepping backward. | **Trail Sense** — footprints and disturbed ground remain visible from farther away. |
| Eryn | **Splitshot** — fire two lighter arrows at separate nearby targets. | **Quick Nock** — a clean dodge briefly speeds up Eryn's next ranged attack. |
| Caelum | **Gale Arrow** — a charged arrow pushes a target away from a ledge or hazard. | **High Ground** — ranged attacks from higher ground gain improved stagger. |
| Liora | **Sunthread Shot** — a bright arrow marks a target and briefly reveals it through visual cover. | **Clear Sight** — marked enemies' attack wind-ups are easier to read. |
| Kairo | **Shadow Feint** — leave a brief decoy and make a short evasive step. | **Silent Approach** — enemies notice Kairo from a shorter distance while crouched or walking. |
| Zane | **Twin Fang** — two quick close-range cuts, with the second stronger after a dodge. | **Predator's Rhythm** — a successful back attack reduces the next light-attack recovery. |
| Riven | **Crosscut** — dash through an enemy and cut across its exposed side. | **Open Wound** — repeated hits on one enemy improve Riven's damage against it modestly. |
| Sable | **Smoke Veil** — release a small smoke cloud that breaks lesser enemies' lock briefly. | **Unseen Return** — leaving enemy awareness improves the next opening attack. |
| Dusk | **Night Needle** — throw a blade that deals extra poise damage to an enemy facing away. | **Dimlight Hunter** — detection range is reduced in dark areas. |
| Elara | **Kindling Touch** — restore a small amount of health to herself and nearby allies, if present. | **Gentle Hands** — healing effects are more efficient when the recipient is at low health. |
| Mira | **Clearwater Pulse** — a short pulse that removes a movement slow and restores a little stamina. | **Calm Presence** — after avoiding damage for a short time, Mira recovers health slowly out of combat. |
| Solene | **Dawn Bell** — a focused chime that interrupts an enemy and briefly steadies the player. | **First Light** — the first healing action after entering a floor is more effective. |
| Aveline | **Safeguard** — place a brief protective mark on herself or a nearby ally. | **Shared Burden** — blocking an attack for an ally reduces Aveline's next healing cooldown. |
| Nessa | **Tide of Mercy** — send a short wave that heals slightly and pushes enemies back. | **Patient Recovery** — healing received is more effective while not sprinting or attacking. |
| Borin | **Rampart Stance** — plant his feet and absorb a frontal hit before answering with a shove. | **Deep Roots** — guarding drains stamina more slowly while stationary. |
| Thrain | **Anvil Drop** — a heavy downward strike that briefly slows a target. | **Iron Breath** — stamina recovery begins sooner after blocking. |
| Doran | **Stonehook** — hook and pull a nearby lesser enemy off balance. | **Hold the Line** — enemies staggered by Doran remain vulnerable slightly longer. |
| Haldor | **Bastion Turn** — rotate behind a broad guard and knock back nearby attackers. | **Shield Habit** — successive successful blocks cost less stamina, up to a modest cap. |
| Orgrim | **Mountain's Answer** — absorb a hit and release a short-range shockwave. | **Unmoved** — health cannot be interrupted by a single small hit while using a healing item. |

## Six-star heroes

| Hero | Active skill proposal | Passive skill proposal |
|---|---|---|
| Valtherion | **Oath of the First King** — a sweeping greatblade attack that gains reach after a successful parry. | **Crown Unbroken** — parries briefly strengthen Valtherion's resistance to interruption. |
| Eclipsa | **Eclipse Well** — create a short-lived gravity field that pulls lesser enemies toward its center. | **Twin Phase** — alternating light and heavy attacks improves the next spell's impact. |
| Kaizora | **Hundredfold Shade** — chain several short dashes between nearby targets, stopping at the last one. | **Perfect Angle** — attacks from an enemy's flank deal extra poise damage. |
| Sylphira | **Verdant Refrain** — create a healing field that also slows enemies entering it. | **Living Current** — healing while at high health converts part of the excess into a brief ward. |
| Dreadmoor | **Sepulchral Grasp** — seize a target with spectral chains, interrupting and pulling it closer. | **Graveweight** — nearby enemies recover from stagger more slowly. |

## Seven-star heroes

| Hero | Active skill proposal | Passive skill proposal |
|---|---|---|
| Aetherion | **Heavenfall** — leap and strike the ground, creating a broad shockwave whose center staggers bosses. | **Worldbearer** — a perfectly timed dodge empowers the next heavy attack without removing its stamina cost. |
| Nyxara | **Eventide Convergence** — gather nearby marked enemies into a dark rift, then release a controlled burst. | **Abyssal Calculation** — observing an enemy's full attack pattern briefly exposes its next opening. |

## Shared implementation principles for review

- Skills should be readable in third-person combat and have clear startup, effect, and recovery cues.
- Passives should support each hero's role without making any rarity mandatory for progression.
- Exploration passives must reveal clues or improve discovery without automatically collecting or generating loot.
- Boss-control effects should be reduced or converted to poise damage against bosses.
- Healing should not create an infinite sustain loop; all healing passives need clear limits and out-of-combat rules.
- Exact cooldowns, stamina costs, level unlocks, upgrade materials, and awakening changes remain undecided pending review.
