using System.Collections.Generic;
using UnityEngine;

namespace BossPrototype
{
    public enum BossState { Idle, Approach, Windup, Active, Recovery, ParryReel, Staggered, Roar, Dead }

    /// <summary>
    /// Data-driven boss: Idle/Approach -> choose attack weighted by distance -> Windup (tracks until trackUntil)
    /// -> Active -> Recovery (punish window) -> repeat. Posture, stagger, criticals, phase 2 roar, immobilize.
    /// </summary>
    public class BossController : MonoBehaviour
    {
        public static BossController Instance { get; private set; }

        [Tooltip("0 Cinder Warden, 1 Brass Regent, 2 Drowned Cantor, 3 Pale Huntress")]
        public int bossIndex;
        [Tooltip("Size relative to the player. 0 = use the boss definition's default.")]
        public float scaleOverride;

        public BossDefinition Def { get; private set; }
        public float Scale { get; private set; } = 1f;
        /// <summary>Multiplier for attack distances (current scale / default scale).</summary>
        public float ShapeScale => Def != null && Def.scale > 0f ? Scale / Def.scale : 1f;
        public float Health { get; private set; }
        public float Posture { get; private set; }
        public int Phase { get; private set; } = 1;
        public BossState State { get; private set; }
        public BossAttack CurrentAttack { get; private set; }
        public float StateTime { get; private set; }
        public float FreezeTimer { get; private set; }
        public float ImmobilizeImmunity { get; private set; }

        public bool IsAlive => State != BossState.Dead;
        public bool IsFrozen => FreezeTimer > 0f;
        public bool IsStaggered => State == BossState.Staggered;
        /// <summary>During the roar (and after death) the boss can't be hurt and can't hurt you.</summary>
        public bool IsHarmless => State == BossState.Roar || State == BossState.Dead;
        public float Radius => 0.5f * Scale;
        public float Height => 2f * Scale;
        public Vector3 ChestPosition => transform.position + Vector3.up * Height * 0.62f;

        // Attack execution
        float windupTime, trackTime;
        readonly List<Vector3> origins = new List<Vector3>();
        readonly List<Vector3> scatterOffsets = new List<Vector3>();
        readonly List<Telegraph> telegraphs = new List<Telegraph>();
        Vector3 attackForward = Vector3.forward;
        Vector3 activeStart, activeEnd;
        bool attackHasHit;
        int projectilesFired;
        BossAttack lastAttack;
        float idleDuration;
        float postureIdle;
        float flashTimer;

        // Visuals
        Transform visualRoot, armPivot, head;
        Renderer bodyRenderer, headRenderer, weaponRenderer;
        Material bodyMat, headMat, weaponMat;
        float pose; // -0.6 swing .. 1 raised

        void Awake()
        {
            if (Def == null) Setup(bossIndex, scaleOverride);
        }

        void OnEnable() { Instance = this; }
        void OnDisable() { if (Instance == this) Instance = null; ClearTelegraphs(); }

        /// <summary>Configure from the library and rebuild visuals. Works in edit mode (preview) and play mode.</summary>
        public void Setup(int index, float scale = 0f)
        {
            bossIndex = Mathf.Clamp(index, 0, BossLibrary.Count - 1);
            scaleOverride = scale;
            Def = BossLibrary.Create(bossIndex);
            Scale = scale > 0f ? scale : Def.scale;
            Health = Def.maxHealth;
            Posture = 0f;
            Phase = 1;
            FreezeTimer = 0f;
            ImmobilizeImmunity = 0f;
            CurrentAttack = null;
            lastAttack = null;
            ClearTelegraphs();
            SetState(BossState.Idle);
            idleDuration = 1.5f;
            gameObject.name = "Boss - " + Def.name;
            BuildVisuals();
        }

        // ------------------------------------------------------------------ visuals
        void BuildVisuals()
        {
            var old = transform.Find("Visual");
            if (old != null) { old.name = "Visual (old)"; Util.SafeDestroy(old.gameObject); }
            var body = GetComponent<CapsuleCollider>();
            if (body == null) body = gameObject.AddComponent<CapsuleCollider>();
            body.height = Height;
            body.radius = Radius * 0.9f;
            body.center = new Vector3(0f, Height * 0.5f, 0f);

            visualRoot = new GameObject("Visual").transform;
            visualRoot.SetParent(transform, false);
            float s = Scale;
            var bodyGo = Util.Part(PrimitiveType.Capsule, visualRoot, "Body", new Vector3(0f, s, 0f), new Vector3(s, s, s), Def.bodyColor);
            var headGo = Util.Part(PrimitiveType.Sphere, visualRoot, "Head", new Vector3(0f, s * 1.95f, s * 0.12f), Vector3.one * s * 0.55f, Def.accentColor * 0.8f);
            head = headGo.transform;
            Util.Part(PrimitiveType.Cube, head, "Eyes", new Vector3(0f, 0.05f, 0.45f), new Vector3(0.7f, 0.12f, 0.15f), Def.accentColor);
            Util.Part(PrimitiveType.Cube, visualRoot, "Shoulders", new Vector3(0f, s * 1.55f, 0f), new Vector3(s * 1.5f, s * 0.3f, s * 0.6f), Def.bodyColor * 1.2f);

            armPivot = new GameObject("ArmPivot").transform;
            armPivot.SetParent(visualRoot, false);
            armPivot.localPosition = new Vector3(s * 0.7f, s * 1.5f, 0f);
            Util.Part(PrimitiveType.Cube, armPivot, "Arm", new Vector3(0f, -s * 0.45f, 0f), new Vector3(s * 0.25f, s * 0.9f, s * 0.25f), Def.bodyColor * 1.1f);
            var weaponGo = Util.Part(PrimitiveType.Cube, armPivot, "Weapon", new Vector3(0f, -s * 0.9f, s * 0.7f), new Vector3(s * 0.12f, s * 0.12f, s * 1.5f), Def.accentColor);
            Util.Part(PrimitiveType.Cube, visualRoot, "OffArm", new Vector3(-s * 0.7f, s * 1.05f, 0f), new Vector3(s * 0.25f, s * 0.9f, s * 0.25f), Def.bodyColor * 1.1f);

            bodyRenderer = bodyGo.GetComponent<Renderer>();
            headRenderer = headGo.GetComponent<Renderer>();
            weaponRenderer = weaponGo.GetComponent<Renderer>();
            if (Application.isPlaying)
            {
                // Per-instance materials so the boss can flash yellow/red.
                bodyMat = MaterialFactory.NewLit(Def.bodyColor);
                headMat = MaterialFactory.NewLit(Def.accentColor * 0.8f);
                weaponMat = MaterialFactory.NewLit(Def.accentColor);
                bodyRenderer.sharedMaterial = bodyMat;
                headRenderer.sharedMaterial = headMat;
                weaponRenderer.sharedMaterial = weaponMat;
            }
        }

        void UpdateVisuals(float dt)
        {
            if (visualRoot == null) return;
            float target = 0f;
            float crouch = 1f;
            float tilt = 0f;
            switch (State)
            {
                case BossState.Windup:
                    if (CurrentAttack != null)
                    {
                        float u = windupTime > 0f ? StateTime / windupTime : 1f;
                        target = CurrentAttack.heldPose ? Mathf.Clamp01(u / 0.35f) : u;
                        if (CurrentAttack.shape == AttackShape.Line && CurrentAttack.lunge > 0f) crouch = Mathf.Lerp(1f, 0.82f, u);
                        if (CurrentAttack.special == AttackSpecial.Backstep) crouch = 0.85f;
                    }
                    break;
                case BossState.Active: target = -0.6f; break;
                case BossState.Recovery: target = -0.3f; break;
                case BossState.Staggered: target = -0.5f; crouch = 0.8f; tilt = 22f; break;
                case BossState.ParryReel: target = 0.6f; tilt = -14f; break;
                case BossState.Roar: target = 1f; tilt = -10f + Mathf.Sin(StateTime * 30f) * 2f; break;
                case BossState.Dead: tilt = Mathf.Min(85f, StateTime * 60f); crouch = 0.9f; break;
            }
            float speed = State == BossState.Active ? 30f : 8f;
            if (!IsFrozen) pose = Mathf.MoveTowards(pose, target, speed * dt);
            armPivot.localRotation = Quaternion.Euler(-pose * 150f, 0f, 0f);
            visualRoot.localScale = new Vector3(1f, Mathf.Lerp(visualRoot.localScale.y, crouch, 10f * dt), 1f);
            visualRoot.localRotation = Quaternion.Slerp(visualRoot.localRotation, Quaternion.Euler(tilt, 0f, 0f), 8f * dt);

            if (bodyMat == null) return;
            // Colour flash: yellow = parryable, red = unblockable, gold = immobilized, white = hit.
            Color body = Def.bodyColor;
            Color weapon = Def.accentColor;
            if (State == BossState.Windup && CurrentAttack != null && CurrentAttack.HasHitbox)
            {
                float pulse = 0.5f + 0.5f * Mathf.Sin(Time.time * 18f);
                Color ac = Util.AttackColorValue(CurrentAttack.color);
                if (CurrentAttack.color != AttackColor.Normal) body = Color.Lerp(body, ac, 0.45f + 0.4f * pulse);
                weapon = Color.Lerp(weapon, ac, 0.6f + 0.4f * pulse);
            }
            if (IsFrozen) body = Color.Lerp(body, new Color(1f, 0.85f, 0.3f), 0.6f);
            if (flashTimer > 0f) { flashTimer -= dt; body = Color.Lerp(body, Color.white, 0.7f); }
            bodyMat.color = body;
            weaponMat.color = weapon;
            headMat.color = State == BossState.Staggered ? Color.Lerp(Def.accentColor, Color.white, 0.5f) : Def.accentColor * 0.8f;
        }

        // ------------------------------------------------------------------ main loop
        void Update()
        {
            if (Def == null) return;
            float dt = Time.deltaTime;
            UpdateVisuals(dt);

            if (State == BossState.Dead)
            {
                StateTime += dt;
                return;
            }

            if (FreezeTimer > 0f)
            {
                FreezeTimer -= dt;
                if (FreezeTimer <= 0f)
                {
                    FreezeTimer = 0f;
                    ImmobilizeImmunity = Tuning.ImmobilizeBossImmunity;
                }
                return; // everything (including telegraph fill) pauses
            }
            if (ImmobilizeImmunity > 0f) ImmobilizeImmunity = Mathf.Max(0f, ImmobilizeImmunity - dt);

            // Posture drains after 2 s without being filled (not while staggered).
            postureIdle += dt;
            if (State != BossState.Staggered) Posture = CombatMath.DrainPosture(Posture, postureIdle, dt);

            StateTime += dt;
            var player = PlayerController.Instance;
            Vector3 toPlayer = player != null ? CombatMath.Flat(player.transform.position - transform.position) : Vector3.forward * 10f;
            float dist = toPlayer.magnitude;
            bool playerAlive = player != null && player.IsAlive;

            switch (State)
            {
                case BossState.Idle:
                    if (playerAlive) Face(toPlayer, dt);
                    if (StateTime >= idleDuration && playerAlive)
                    {
                        if (AnyInRange(dist)) BeginAttack(ChooseAttack(dist));
                        else SetState(BossState.Approach);
                    }
                    break;

                case BossState.Approach:
                    if (!playerAlive) { SetState(BossState.Idle); break; }
                    Face(toPlayer, dt);
                    if (dist > Radius + 1.2f)
                        transform.position += toPlayer.normalized * Def.moveSpeed * Mathf.Sqrt(ShapeScale) * dt;
                    if (AnyInRange(dist) || StateTime > 3.5f) BeginAttack(ChooseAttack(dist));
                    break;

                case BossState.Windup: UpdateWindup(dt, toPlayer); break;
                case BossState.Active: UpdateActive(); break;

                case BossState.Recovery:
                    if (StateTime >= CurrentAttack.recovery) EndAttack();
                    break;

                case BossState.ParryReel:
                    if (StateTime >= 1.4f) EndAttack();
                    break;

                case BossState.Staggered:
                    if (StateTime >= Tuning.StaggerDuration)
                    {
                        Posture = 0f;
                        EndAttack();
                    }
                    break;

                case BossState.Roar:
                    if (StateTime >= Tuning.RoarDuration) { idleDuration = 0.3f; SetState(BossState.Idle); }
                    break;
            }

            ClampToArena();
            PushPlayer(player);
        }

        void SetState(BossState s)
        {
            State = s;
            StateTime = 0f;
        }

        void Face(Vector3 dir, float dt, float multiplier = 1f)
        {
            dir.y = 0f;
            if (dir.sqrMagnitude < 0.0001f) return;
            transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(dir), Def.turnSpeed * multiplier * dt);
        }

        // ------------------------------------------------------------------ attack selection
        bool AnyInRange(float dist)
        {
            foreach (var a in Def.attacks)
                if (Selectable(a) && CombatMath.InRange(a, dist, ShapeScale)) return true;
            return false;
        }

        bool Selectable(BossAttack a) { return !a.comboOnly && a.phase <= Phase && a.weight > 0f; }

        BossAttack ChooseAttack(float dist)
        {
            float total = 0f;
            var weights = new List<float>(Def.attacks.Count);
            foreach (var a in Def.attacks)
            {
                float w = Selectable(a) ? CombatMath.DistanceWeight(a, dist, ShapeScale) : 0f;
                if (a == lastAttack) w *= 0.35f;
                if (a.phase >= 2 && Phase >= 2) w *= 1.3f; // favour the new behaviour
                weights.Add(w);
                total += w;
            }
            float r = Random.value * total;
            for (int i = 0; i < weights.Count; i++)
            {
                r -= weights[i];
                if (r <= 0f && weights[i] > 0f) return Def.attacks[i];
            }
            foreach (var a in Def.attacks) if (Selectable(a)) return a;
            return Def.attacks[0];
        }

        // ------------------------------------------------------------------ attack execution
        void BeginAttack(BossAttack a)
        {
            ClearTelegraphs();
            CurrentAttack = a;
            lastAttack = a;
            windupTime = CombatMath.PhaseWindup(a.windup, Phase);
            trackTime = CombatMath.PhaseWindup(a.trackUntil, Phase);
            attackHasHit = false;
            projectilesFired = 0;
            SetState(BossState.Windup);

            scatterOffsets.Clear();
            int markers = a.placement == AttackPlacement.AtTarget ? Mathf.Max(1, a.count) : 1;
            for (int i = 0; i < markers; i++)
            {
                Vector2 rnd = i == 0 ? Vector2.zero : Random.insideUnitCircle * a.scatter * ShapeScale;
                scatterOffsets.Add(new Vector3(rnd.x, 0f, rnd.y));
            }
            attackForward = transform.forward;
            ComputeOrigins();

            if (a.HasHitbox)
            {
                Vector2 size = ScaledSize(a);
                for (int i = 0; i < origins.Count; i++)
                {
                    var t = Telegraph.Create(HazardParent(), a.shape, size, a.color);
                    t.SetPose(origins[i], attackForward);
                    telegraphs.Add(t);
                }
                Sfx.Play(a.color == AttackColor.Unblockable ? SfxKind.WindupRed : a.color == AttackColor.Parryable ? SfxKind.WindupYellow : SfxKind.WindupNormal);
                if (a.color != AttackColor.Normal)
                    HudOverlay.Flash(a.color == AttackColor.Unblockable ? "UNBLOCKABLE" : "PARRYABLE", Util.AttackColorValue(a.color), 0.7f);
            }
        }

        Vector2 ScaledSize(BossAttack a)
        {
            float k = ShapeScale;
            switch (a.shape)
            {
                case AttackShape.Cone: return new Vector2(a.size.x * k, a.size.y);
                case AttackShape.Ring: return new Vector2(a.size.x * k, Mathf.Max(0.8f, a.size.y * Mathf.Sqrt(k)));
                case AttackShape.Line:
                    if (a.special == AttackSpecial.Projectiles) return new Vector2(a.size.x, a.size.y);
                    return new Vector2(a.size.x * k, a.size.y * k);
                default: return new Vector2(a.size.x * k, a.size.y * k);
            }
        }

        void ComputeOrigins()
        {
            origins.Clear();
            var a = CurrentAttack;
            var player = PlayerController.Instance;
            if (a.placement == AttackPlacement.AtTarget && player != null)
            {
                foreach (var off in scatterOffsets) origins.Add(CombatMath.Flat(player.transform.position) + off);
                return;
            }
            Vector3 basePos = CombatMath.Flat(transform.position);
            if (a.shape == AttackShape.Line || a.shape == AttackShape.Ring)
            {
                origins.Add(basePos + attackForward * a.offset * ShapeScale);
            }
            else
            {
                // The marker sits where the blow will land, including the lunge.
                float lunge = a.special == AttackSpecial.Backstep ? 0f : a.lunge;
                origins.Add(basePos + attackForward * (a.offset + lunge) * ShapeScale);
            }
        }

        void UpdateWindup(float dt, Vector3 toPlayer)
        {
            var a = CurrentAttack;
            if (StateTime <= trackTime)
            {
                Face(toPlayer, dt, 1.5f);
                attackForward = CombatMath.Flat(transform.forward).normalized;
                ComputeOrigins();
                if (a.special == AttackSpecial.Projectiles && toPlayer.sqrMagnitude > 0.01f) attackForward = toPlayer.normalized;
            }
            float fill = windupTime > 0f ? StateTime / windupTime : 1f;
            for (int i = 0; i < telegraphs.Count && i < origins.Count; i++)
            {
                telegraphs[i].SetPose(origins[i], attackForward);
                telegraphs[i].SetFill(fill);
            }
            if (StateTime >= windupTime) EnterActive();
        }

        void EnterActive()
        {
            var a = CurrentAttack;
            SetState(BossState.Active);
            activeStart = transform.position;
            float lunge = a.lunge * ShapeScale;
            activeEnd = activeStart + attackForward * lunge;
            ClearTelegraphs();

            if (a.HasHitbox && a.special != AttackSpecial.Projectiles)
            {
                Sfx.Play(SfxKind.Impact, a.bigImpact ? 0.9f : 0.5f);
                if (a.bigImpact || Scale >= Tuning.LargeBossScale)
                {
                    float d = PlayerController.Instance != null ? Vector3.Distance(PlayerController.Instance.transform.position, origins[0]) : 10f;
                    OrbitCamera.Shake(Mathf.Lerp(0.5f, 0.1f, Mathf.Clamp01(d / 25f)) * (a.bigImpact ? 1f : 0.5f), 0.35f);
                }
            }

            var hit = MakeHit(a);
            if (a.shape == AttackShape.Ring)
            {
                Vector2 size = ScaledSize(a);
                Shockwave.Spawn(HazardParent(), origins[0], size.x, size.y, a.ringSpeed * Mathf.Sqrt(ShapeScale), hit);
                attackHasHit = true;
            }
            if (a.ringAfter > 0f)
            {
                // Delayed ground burst: the impact is followed by an expanding shockwave to roll through.
                Shockwave.Spawn(HazardParent(), origins[0], a.ringAfter * ShapeScale, 1.2f * Mathf.Sqrt(ShapeScale), a.ringSpeed * Mathf.Sqrt(ShapeScale), hit, ScaledSize(a).x);
            }
            if (a.special == AttackSpecial.FirePools)
            {
                Vector2 size = ScaledSize(a);
                for (int i = 0; i < a.count; i++)
                {
                    float ang = Random.Range(-size.y * 0.4f, size.y * 0.4f);
                    float r = Random.Range(size.x * 0.35f, size.x * 0.9f);
                    Vector3 dir = Quaternion.Euler(0f, ang, 0f) * attackForward;
                    FirePool.Spawn(HazardParent(), origins[0] + dir * r, 1.8f * Mathf.Sqrt(ShapeScale), 8f, 6f);
                }
            }
        }

        HitInfo MakeHit(BossAttack a)
        {
            return new HitInfo
            {
                damage = a.damage,
                postureDamage = a.postureDamage,
                color = a.color,
                canParry = a.color != AttackColor.Unblockable,
                bigImpact = a.bigImpact,
                sourcePosition = transform.position,
                source = a.name,
            };
        }

        void UpdateActive()
        {
            var a = CurrentAttack;
            float u = a.active > 0f ? Mathf.Clamp01(StateTime / a.active) : 1f;
            float eased = 1f - (1f - u) * (1f - u);
            if (Mathf.Abs(a.lunge) > 0.001f)
            {
                Vector3 p = Vector3.Lerp(activeStart, activeEnd, eased);
                transform.position = new Vector3(p.x, transform.position.y, p.z);
            }

            var player = PlayerController.Instance;
            if (a.special == AttackSpecial.Projectiles)
            {
                int count = Mathf.Max(1, a.count);
                float interval = a.active / count;
                while (projectilesFired < count && StateTime >= projectilesFired * interval)
                {
                    if (player != null)
                    {
                        Vector3 from = transform.position + transform.forward * Radius + Vector3.up * Height * 0.7f;
                        BossProjectile.Spawn(HazardParent(), from, player.Center, a.projectileSpeed, MakeHit(a), Util.AttackColorValue(a.color));
                        Sfx.Play(SfxKind.WindupNormal, 0.3f);
                    }
                    projectilesFired++;
                }
            }
            else if (a.HasHitbox && !attackHasHit && player != null && player.IsAlive)
            {
                bool inside = false;
                Vector2 size = ScaledSize(a);
                if (a.shape == AttackShape.Line && a.lunge > 0f)
                {
                    // Charge: the lane swept so far, plus the body.
                    float travelled = CombatMath.Flat(transform.position - activeStart).magnitude + Radius;
                    inside = CombatMath.PointInRect(CombatMath.Flat(activeStart) - attackForward * Radius, attackForward, travelled + Radius, size.y, player.transform.position, PlayerController.Radius);
                }
                else
                {
                    foreach (var o in origins)
                        if (CombatMath.IsInShape(a.shape, size, o, attackForward, player.transform.position, PlayerController.Radius)) { inside = true; break; }
                }
                if (inside) ResolveHitOnPlayer(a, player);
            }

            if (State == BossState.Active && StateTime >= a.active) EnterRecovery();
        }

        void ResolveHitOnPlayer(BossAttack a, PlayerController player)
        {
            attackHasHit = true;
            var hit = MakeHit(a);
            var result = player.ReceiveHit(hit);
            if (result == HitResult.Parried)
            {
                AddPosture(a.color == AttackColor.Parryable ? 35f : 15f);
                if (State == BossState.Staggered) return;
                if (a.color == AttackColor.Parryable)
                {
                    ClearTelegraphs();
                    SetState(BossState.ParryReel); // hard stagger: combo is cancelled
                    HudOverlay.Flash("DEFLECTED!", Util.AttackColorValue(AttackColor.Parryable), 1f);
                }
            }
        }

        void EnterRecovery()
        {
            var a = CurrentAttack;
            // Combo strings: chain directly into the next hit's (short) windup.
            if (a.followUps != null && a.followUps.Length > 0)
            {
                foreach (var name in a.followUps)
                {
                    var next = Def.Find(name);
                    if (next != null && next.phase <= Phase)
                    {
                        BeginAttack(next);
                        return;
                    }
                }
            }
            SetState(BossState.Recovery);
        }

        void EndAttack()
        {
            CurrentAttack = null;
            ClearTelegraphs();
            idleDuration = Phase >= 2 ? Random.Range(0.3f, 0.6f) : Random.Range(0.5f, 1.0f);
            SetState(BossState.Idle);
        }

        void ClearTelegraphs()
        {
            foreach (var t in telegraphs) if (t != null) Util.SafeDestroy(t.gameObject);
            telegraphs.Clear();
        }

        Transform HazardParent()
        {
            return ArenaRoot.Instance != null ? ArenaRoot.Instance.Hazards : null;
        }

        void ClampToArena()
        {
            Vector3 p = transform.position;
            Vector3 flat = CombatMath.Flat(p);
            float max = ArenaRoot.ArenaRadius - Radius - 0.5f;
            if (flat.magnitude > max)
            {
                flat = flat.normalized * max;
                transform.position = new Vector3(flat.x, p.y, flat.z);
            }
        }

        void PushPlayer(PlayerController player)
        {
            if (player == null || !player.IsAlive) return;
            Vector3 d = CombatMath.Flat(player.transform.position - transform.position);
            float min = Radius + PlayerController.Radius + 0.05f;
            if (d.magnitude < min)
            {
                Vector3 dir = d.sqrMagnitude > 0.0001f ? d.normalized : -transform.forward;
                player.ExternalPush(dir * (min - d.magnitude));
            }
        }

        // ------------------------------------------------------------------ taking damage
        public void AddPosture(float amount)
        {
            if (State == BossState.Dead || State == BossState.Roar || State == BossState.Staggered) return;
            Posture = Mathf.Min(Def.maxPosture, Posture + amount);
            postureIdle = 0f;
            if (Posture >= Def.maxPosture)
            {
                CurrentAttack = null;
                ClearTelegraphs();
                SetState(BossState.Staggered);
                Sfx.Play(SfxKind.Critical, 0.5f);
                HudOverlay.Flash("POSTURE BROKEN - HEAVY ATTACK FOR A CRITICAL", new Color(1f, 0.85f, 0.4f), 1.6f);
            }
        }

        /// <summary>Called by the player's attacks.</summary>
        public PlayerHitOutcome ReceivePlayerHit(PlayerAttackKind kind, float damage, float posture)
        {
            if (IsHarmless) return PlayerHitOutcome.Ignored;
            var outcome = PlayerHitOutcome.Hit;
            if (State == BossState.Staggered)
            {
                if (kind != PlayerAttackKind.Light)
                {
                    damage = CombatMath.CriticalDamage(Def.maxHealth, damage);
                    outcome = PlayerHitOutcome.Critical;
                    StateTime = Mathf.Max(StateTime, Tuning.StaggerDuration - 0.6f); // gets up shortly after the critical
                    Posture = 0f;
                }
                else damage *= Tuning.StaggerDamageMultiplier;
                posture = 0f;
            }
            Health = Mathf.Max(0f, Health - damage);
            flashTimer = 0.08f;
            if (posture > 0f) AddPosture(posture);

            if (Health <= 0f)
            {
                CurrentAttack = null;
                ClearTelegraphs();
                SetState(BossState.Dead);
                FreezeTimer = 0f;
                Sfx.Play(SfxKind.Roar, 0.6f);
                HudOverlay.Flash("BOSS DEFEATED", new Color(1f, 0.85f, 0.4f), 4f);
            }
            else if (Phase == 1 && Health <= Def.maxHealth * Tuning.Phase2HealthFraction)
            {
                Phase = 2;
                CurrentAttack = null;
                ClearTelegraphs();
                FreezeTimer = 0f;
                SetState(BossState.Roar);
                Sfx.Play(SfxKind.Roar, 0.9f);
                OrbitCamera.Shake(0.4f, 1.2f);
                HudOverlay.Flash(Def.name.ToUpperInvariant() + " ENRAGES", Def.accentColor, 2f);
            }
            return outcome;
        }

        /// <summary>Immobilize (V). Fails while immune (20 s after a freeze ends).</summary>
        public bool TryImmobilize()
        {
            if (IsHarmless || IsFrozen || ImmobilizeImmunity > 0f) return false;
            FreezeTimer = Tuning.ImmobilizeDuration;
            return true;
        }
    }
}
