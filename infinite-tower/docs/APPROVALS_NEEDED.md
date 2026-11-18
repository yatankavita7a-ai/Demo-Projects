# Approvals checklist

*11 November 2026. Tick a box (`[x]`), cross a line out, or reply with the item number. Nothing here has been started.*

## 1. Saving the work (Git)
- [ ] **1.1** Commit all current work. Everything since commit `edd8c73` is uncommitted, including Codex's earlier edits to `AGENTS.md`, `project.godot`, `GachaManager.gd`, `HeroCollection.gd` and `review.py`.
- [ ] **1.2** Choose how to commit:
  - [ ] one checkpoint commit, **or**
  - [ ] several commits grouped by feature
- [ ] **1.3** Choose what happens to the 83 MB of textures in `assets/polyhaven/`:
  - [ ] commit them normally
  - [ ] store them with Git LFS
  - [ ] leave them out of Git

## 2. Project rules
- [ ] **2.1** Update `AGENTS.md` to say "Claude subagent review" instead of the local Qwen reviewer.

## 3. Game content
- [ ] **3.1** Hero skills in [HERO_SKILL_PROPOSAL.md](HERO_SKILL_PROPOSAL.md):
  - [ ] approve as written
  - [ ] approve with changes (list them)
  - [ ] reject
- [ ] **3.2** Storyline in [PROJECT_BRIEF.md](PROJECT_BRIEF.md):
  - [ ] approve
  - [ ] change (say what)
- [ ] **3.3** Shop:
  - [ ] the prices and floor thresholds (floors 1–25) are fine
  - [ ] one purchase per item is fine
  - [ ] "summons limit" meant purchase limits (or tell me what you meant)
  - [ ] also sell: healing items / summon tickets / rotating stock (circle any)

## 4. Main hub (your newest request)
- [ ] **4.1** Hub style:
  - [ ] a 3D camp you walk around, with your heroes visible *(recommended)*
  - [ ] a menu-based base screen
- [ ] **4.2** What heroes do while you're offline (capped by time away):
  - [ ] training earns hero XP and levels *(recommended)*
  - [ ] the workshop slowly produces gems or materials
  - [ ] resting gives a bonus at the start of your next run
  - [ ] scouting expeditions bring back common or unusual gear (never rare)
- [ ] **4.3** What hub building and upgrades cost:
  - [ ] a new resource, "materials", found in the tower *(recommended)*
  - [ ] gems only
- [ ] **4.4** First buildings (each upgradable to level 3):
  - [ ] Barracks (where heroes live) and Training Grounds
  - [ ] Workshop / Storehouse
  - [ ] Summoning Shrine and Market (moves Summon and the Shop into the hub)
  - [ ] Scout Hall (expeditions)

- [ ] **4.5** Hero jobs. Any hero living in the hub can hold one job and works at it while you're offline (capped by time away). Each job has a building you can upgrade. A hero whose class suits the job works faster. Tick the jobs to include:
  - [ ] **Blacksmith** (Forge): upgrades equipment you own (+attack/defense) using materials. *Suits Warriors and Tanks.*
  - [ ] **Cook** (Kitchen): turns ingredients into meals that buff your next tower run (more vitality, faster stamina). *Suits Healers.*
  - [ ] **Fisherman** (Docks): catches fish for the cook, and sometimes finds materials. *Suits Archers.*
  - [ ] **Farmer** (Garden): grows herbs and vegetables for the cook and alchemist. *Suits Healers and Tanks.*
  - [ ] **Alchemist** (Laboratory): brews healing tonics you can drink in the tower. This adds usable items, which don't exist yet. *Suits Mages.*
  - [ ] **Miner / Lumberjack** (Quarry and Lumber Yard): produces the materials used for building. *Suits Tanks and Warriors.*
  - [ ] **Drill Master** (Training Grounds): speeds up the other heroes' training. *Suits Warriors.*
  - [ ] **Scout** (Scout Hall): timed expeditions that bring back gear (never rare) or extra clues. *Suits Assassins and Archers.*
  - [ ] **Scholar** (Library): studies your collected clues, making bosses weaker. *Suits Mages.*
  - [ ] **Merchant** (Market): improves shop prices or adds stock. *Suits any class.*
- [ ] **4.6** Jobs and the tower: can a hero working a hub job still be your selected hero for climbing?
  - [ ] yes, jobs only run while you're away *(recommended)*
  - [ ] no, working heroes are busy until you reassign them

## 5. Order of the next big features
Number them 1 to 5:
- [ ] More ways to clear a floor: puzzles, talking enemies down, secret passages, NPCs
- [ ] Unique boss fights and arenas
- [ ] Heroes in play: levels, awakening, upgrading with duplicates, companions
- [ ] Combat feel: hit sparks, slash trails, camera shake, hit reactions
- [ ] A map, a quest log, real options settings and save slots

## 6. Downloads (I ask again for each exact file)
- [ ] **6.1** Search for free CC0 character models and animations (Quaternius, Kenney or similar)
- [ ] **6.2** Search for free CC0 sound effects and ambient music
- [ ] **6.3** Bundle a free open-license font (for example Cinzel, under 1 MB) so the HUD looks the same on every platform

## 7. Platform
- [ ] **7.1** Target:
  - [ ] desktop (Mac/PC), keeping the current high-end graphics
  - [ ] Android, which needs a mobile renderer, lighter graphics and touch controls
  - [ ] both
