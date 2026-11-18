using UnityEngine;

namespace BossPrototype
{
    public enum PlayerState { Free, Attacking, Rolling, Staggered, Dead }

    /// <summary>
    /// Third-person player: WASD (camera- or lock-relative), light / heavy / charged heavy, block + parry,
    /// dodge roll with i-frames and perfect dodge, Focus, Immobilize, stamina.
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    public class PlayerController : MonoBehaviour
    {
        public static PlayerController Instance { get; private set; }
        public const float Radius = 0.4f;

        public float maxHealth = 150f;
        public float maxStamina = 100f;
        public float runSpeed = 5.5f;

        public float Health { get; private set; }
        public float Stamina { get; private set; }
        public int Focus { get; private set; }
        public float ImmobilizeCooldown { get; private set; }
        public bool LockedOn { get; private set; }
        public PlayerState State { get; private set; }
        public bool IsBlocking { get; private set; }
        public bool IsAlive => State != PlayerState.Dead;
        public bool IsChargingHeavy => heavyHeld && holdTime >= Tuning.ChargeHoldThreshold && Focus > 0;
        public bool IsInvulnerable => State == PlayerState.Rolling && CombatMath.IsRollInvulnerable(rollTime);
        public Vector3 Center => transform.position + Vector3.up * 1f;

        CharacterController cc;
        Transform visual, swordPivot, shield;
        float verticalVelocity;
        float staminaIdle;
        Vector3 pushAccum;

        // Roll
        float rollTime;
        float rolled;
        Vector3 rollDir;
        bool perfectAwarded;

        // Attacks
        PlayerAttackKind attackKind;
        float attackTime;
        bool attackResolved;
        bool queuedLight;
        int lightChain;
        int consecutiveLightHits;
        float lastLightHitTime = -10f;
        int focusSpent;
        bool heavyHeld;
        float holdTime;

        // Block / stagger
        float blockPressedTime = -10f;
        float staggerTimer;

        struct AttackSpec { public float duration, hitTime, damage, posture, range, arc, stamina; }

        static AttackSpec Spec(PlayerAttackKind k, int focus)
        {
            switch (k)
            {
                case PlayerAttackKind.Heavy:
                    return new AttackSpec { duration = 0.85f, hitTime = 0.42f, damage = 30f, posture = 14f, range = 2.4f, arc = 110f, stamina = 24f };
                case PlayerAttackKind.Charged:
                    return new AttackSpec { duration = 1.0f, hitTime = 0.5f, damage = 30f + 30f * focus, posture = 22f * focus, range = 2.9f, arc = 130f, stamina = 10f };
                default:
                    return new AttackSpec { duration = 0.42f, hitTime = 0.14f, damage = 14f, posture = 0f, range = 2.0f, arc = 100f, stamina = 12f };
            }
        }

        void Awake()
        {
            cc = GetComponent<CharacterController>();
            ConfigureController(cc);
            if (Application.isPlaying)
            {
                var old = transform.Find("Visual");
                if (old != null) { old.name = "Visual (old)"; Destroy(old.gameObject); }
            }
            BuildVisual();
            ResetPlayer(transform.position, transform.rotation);
        }

        void OnEnable() { Instance = this; }
        void OnDisable() { if (Instance == this) Instance = null; }

        public static void ConfigureController(CharacterController c)
        {
            c.height = 2f;
            c.radius = Radius;
            c.center = new Vector3(0f, 1f, 0f);
            c.stepOffset = 0.3f;
            c.slopeLimit = 50f;
        }

        public void BuildVisual()
        {
            if (transform.Find("Visual") != null) return;
            visual = new GameObject("Visual").transform;
            visual.SetParent(transform, false);
            var steel = new Color(0.55f, 0.6f, 0.7f);
            Util.Part(PrimitiveType.Capsule, visual, "Body", new Vector3(0f, 1f, 0f), new Vector3(0.8f, 1f, 0.8f), new Color(0.2f, 0.32f, 0.55f));
            Util.Part(PrimitiveType.Cube, visual, "Visor", new Vector3(0f, 1.6f, 0.33f), new Vector3(0.45f, 0.12f, 0.12f), new Color(0.9f, 0.95f, 1f));
            swordPivot = new GameObject("SwordPivot").transform;
            swordPivot.SetParent(visual, false);
            swordPivot.localPosition = new Vector3(0.45f, 1.15f, 0.1f);
            Util.Part(PrimitiveType.Cube, swordPivot, "Blade", new Vector3(0f, 0f, 0.65f), new Vector3(0.07f, 0.07f, 1.2f), steel);
            Util.Part(PrimitiveType.Cube, swordPivot, "Guard", new Vector3(0f, 0f, 0.05f), new Vector3(0.3f, 0.06f, 0.06f), new Color(0.6f, 0.45f, 0.2f));
            shield = Util.Part(PrimitiveType.Cube, visual, "Shield", new Vector3(-0.48f, 1.1f, 0.15f), new Vector3(0.08f, 0.7f, 0.5f), new Color(0.45f, 0.35f, 0.25f)).transform;
        }

        public void ResetPlayer(Vector3 position, Quaternion rotation)
        {
            Health = maxHealth;
            Stamina = maxStamina;
            Focus = 0;
            ImmobilizeCooldown = 0f;
            State = PlayerState.Free;
            IsBlocking = false;
            heavyHeld = false;
            consecutiveLightHits = 0;
            verticalVelocity = 0f;
            pushAccum = Vector3.zero;
            if (cc == null) cc = GetComponent<CharacterController>();
            bool was = cc.enabled;
            cc.enabled = false;
            transform.SetPositionAndRotation(position, rotation);
            cc.enabled = was;
            if (visual != null) visual.localRotation = Quaternion.identity;
        }

        public void ExternalPush(Vector3 delta) { pushAccum += delta; }

        void SpendStamina(float amount)
        {
            Stamina = Mathf.Max(0f, Stamina - amount);
            staminaIdle = 0f;
        }

        // ------------------------------------------------------------------ update
        void Update()
        {
            float dt = Time.deltaTime;
            if (dt <= 0f) return;
            if (visual == null) visual = transform.Find("Visual");

            if (State == PlayerState.Dead)
            {
                visual.localRotation = Quaternion.Slerp(visual.localRotation, Quaternion.Euler(-85f, 0f, 0f), 6f * dt);
                ApplyGravityOnly(dt);
                return;
            }

            if (ImmobilizeCooldown > 0f) ImmobilizeCooldown = Mathf.Max(0f, ImmobilizeCooldown - dt);
            staminaIdle += dt;
            if (staminaIdle >= Tuning.StaminaRegenDelay && State != PlayerState.Rolling && State != PlayerState.Attacking)
                Stamina = Mathf.Min(maxStamina, Stamina + Tuning.StaminaRegenPerSecond * dt);
            if (Time.time - lastLightHitTime > 2.5f) consecutiveLightHits = 0;

            var boss = BossController.Instance;
            bool bossValid = boss != null && boss.IsAlive;
            if (LockedOn && !bossValid) LockedOn = false;
            if (GameInput.LockDown()) LockedOn = !LockedOn && bossValid;

            if (GameInput.ImmobilizeDown()) TryImmobilize(boss);

            Vector2 input = GameInput.Move();
            Vector3 fwd, right;
            if (LockedOn)
            {
                fwd = CombatMath.Flat(boss.transform.position - transform.position).normalized;
                if (fwd.sqrMagnitude < 0.001f) fwd = transform.forward;
            }
            else
            {
                fwd = OrbitCamera.Instance != null ? OrbitCamera.Instance.FlatForward : Vector3.forward;
            }
            right = Vector3.Cross(Vector3.up, fwd);
            Vector3 move = Vector3.ClampMagnitude(fwd * input.y + right * input.x, 1f);

            Vector3 horizontal = Vector3.zero;
            switch (State)
            {
                case PlayerState.Free: horizontal = UpdateFree(dt, move, boss); break;
                case PlayerState.Attacking: horizontal = UpdateAttacking(dt, move, boss); break;
                case PlayerState.Rolling: horizontal = UpdateRolling(dt); break;
                case PlayerState.Staggered:
                    IsBlocking = false;
                    staggerTimer -= dt;
                    if (staggerTimer <= 0f) State = PlayerState.Free;
                    break;
            }

            if (cc.isGrounded && verticalVelocity < 0f) verticalVelocity = -2f;
            verticalVelocity -= 20f * dt;
            Vector3 motion = horizontal + Vector3.up * verticalVelocity * dt + pushAccum;
            pushAccum = Vector3.zero;
            cc.Move(motion);
            ClampToArena();
            AnimateVisual(dt);
        }

        void ApplyGravityOnly(float dt)
        {
            if (cc.isGrounded && verticalVelocity < 0f) verticalVelocity = -2f;
            verticalVelocity -= 20f * dt;
            cc.Move(Vector3.up * verticalVelocity * dt + pushAccum);
            pushAccum = Vector3.zero;
        }

        void ClampToArena()
        {
            Vector3 p = transform.position;
            Vector3 flat = CombatMath.Flat(p);
            float max = ArenaRoot.ArenaRadius - 0.6f;
            if (flat.magnitude > max)
            {
                flat = flat.normalized * max;
                cc.enabled = false;
                transform.position = new Vector3(flat.x, p.y, flat.z);
                cc.enabled = true;
            }
            if (p.y < -10f) ResetPlayer(new Vector3(0f, 0.1f, -12f), Quaternion.identity);
        }

        void FaceToward(Vector3 dir, float dt, float speed = 14f)
        {
            dir.y = 0f;
            if (dir.sqrMagnitude < 0.0001f) return;
            transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(dir), speed * dt);
        }

        void SnapToward(Vector3 dir)
        {
            dir.y = 0f;
            if (dir.sqrMagnitude > 0.0001f) transform.rotation = Quaternion.LookRotation(dir);
        }

        Vector3 UpdateFree(float dt, Vector3 move, BossController boss)
        {
            if (GameInput.BlockDown()) blockPressedTime = Time.time;
            IsBlocking = GameInput.BlockHeld() && !heavyHeld;

            if (GameInput.RollDown() && Stamina > 0f)
            {
                heavyHeld = false;
                StartRoll(move);
                return Vector3.zero;
            }

            if (heavyHeld)
            {
                holdTime += dt;
                if (!GameInput.HeavyHeld() || holdTime >= 1.4f)
                {
                    heavyHeld = false;
                    bool charged = holdTime >= Tuning.ChargeHoldThreshold && Focus > 0;
                    StartAttack(charged ? PlayerAttackKind.Charged : PlayerAttackKind.Heavy, move, boss);
                    return Vector3.zero;
                }
            }
            else if (GameInput.LightDown() && Stamina > 0f)
            {
                lightChain = 1;
                StartAttack(PlayerAttackKind.Light, move, boss);
                return Vector3.zero;
            }
            else if (GameInput.HeavyDown() && Stamina > 0f)
            {
                heavyHeld = true;
                holdTime = 0f;
            }

            float speed = IsBlocking ? 2.4f : heavyHeld ? 1.8f : runSpeed;
            if (LockedOn && boss != null) FaceToward(boss.transform.position - transform.position, dt);
            else if (move.sqrMagnitude > 0.01f) FaceToward(move, dt);
            return move * speed * dt;
        }

        void StartAttack(PlayerAttackKind kind, Vector3 move, BossController boss)
        {
            var spec = Spec(kind, Focus);
            if (kind == PlayerAttackKind.Charged)
            {
                focusSpent = Focus;
                Focus = 0;
                HudOverlay.Flash("CHARGED HEAVY x" + focusSpent, new Color(0.6f, 0.85f, 1f), 0.8f);
            }
            SpendStamina(spec.stamina);
            State = PlayerState.Attacking;
            attackKind = kind;
            attackTime = 0f;
            attackResolved = false;
            queuedLight = false;
            IsBlocking = false;

            if (boss != null && boss.IsAlive && (LockedOn || CombatMath.Flat(boss.transform.position - transform.position).magnitude < boss.Radius + 6f))
                SnapToward(boss.transform.position - transform.position);
            else if (move.sqrMagnitude > 0.01f) SnapToward(move);
        }

        Vector3 UpdateAttacking(float dt, Vector3 move, BossController boss)
        {
            var spec = Spec(attackKind, focusSpent);
            attackTime += dt;
            if (attackKind == PlayerAttackKind.Light && GameInput.LightDown()) queuedLight = true;
            if (GameInput.BlockDown()) blockPressedTime = Time.time;

            if (!attackResolved && attackTime >= spec.hitTime)
            {
                attackResolved = true;
                ResolveAttack(spec, boss);
            }

            // Dodge can cancel the late part of an attack.
            if (attackResolved && GameInput.RollDown() && Stamina > 0f)
            {
                StartRoll(move);
                return Vector3.zero;
            }

            if (attackTime >= spec.duration)
            {
                if (queuedLight && lightChain < 3 && Stamina > 0f)
                {
                    lightChain++;
                    StartAttack(PlayerAttackKind.Light, move, boss);
                }
                else State = PlayerState.Free;
                return Vector3.zero;
            }
            // Small forward step on the swing.
            float step = attackTime < spec.hitTime ? 2.2f : 0f;
            return transform.forward * step * dt;
        }

        void ResolveAttack(AttackSpec spec, BossController boss)
        {
            bool landed = false;
            if (boss != null && boss.IsAlive)
            {
                Vector3 to = CombatMath.Flat(boss.transform.position - transform.position);
                float dist = to.magnitude;
                float surface = dist - boss.Radius;
                float leeway = dist > 0.01f ? Mathf.Asin(Mathf.Clamp01(boss.Radius / dist)) * Mathf.Rad2Deg : 90f;
                float angle = Vector3.Angle(CombatMath.Flat(transform.forward), to);
                if (surface <= spec.range && angle <= spec.arc * 0.5f + leeway)
                {
                    var outcome = boss.ReceivePlayerHit(attackKind, spec.damage, spec.posture);
                    if (outcome != PlayerHitOutcome.Ignored)
                    {
                        landed = true;
                        OnHitLanded(outcome);
                    }
                }
            }
            if (!landed && attackKind == PlayerAttackKind.Light) consecutiveLightHits = 0;
        }

        void OnHitLanded(PlayerHitOutcome outcome)
        {
            if (outcome == PlayerHitOutcome.Critical)
            {
                GameFeel.HitStop(0.16f);
                OrbitCamera.Shake(0.45f, 0.4f);
                Sfx.Play(SfxKind.Critical, 0.9f);
                HudOverlay.Flash("CRITICAL HIT", new Color(1f, 0.85f, 0.3f), 1.2f);
                return;
            }
            Sfx.Play(SfxKind.BossHit, 0.5f);
            switch (attackKind)
            {
                case PlayerAttackKind.Light:
                    GameFeel.HitStop(0.035f);
                    consecutiveLightHits++;
                    lastLightHitTime = Time.time;
                    if (CombatMath.ShouldAwardFocus(consecutiveLightHits)) AddFocus(1, "+1 FOCUS");
                    break;
                case PlayerAttackKind.Heavy:
                    GameFeel.HitStop(0.07f);
                    OrbitCamera.Shake(0.12f, 0.15f);
                    break;
                case PlayerAttackKind.Charged:
                    GameFeel.HitStop(0.12f);
                    OrbitCamera.Shake(0.3f, 0.3f);
                    break;
            }
        }

        void AddFocus(int amount, string message)
        {
            int before = Focus;
            Focus = Mathf.Min(Tuning.MaxFocus, Focus + amount);
            if (Focus > before) HudOverlay.Flash(message, new Color(0.6f, 0.85f, 1f), 0.8f);
        }

        void StartRoll(Vector3 move)
        {
            SpendStamina(Tuning.RollStaminaCost);
            State = PlayerState.Rolling;
            IsBlocking = false;
            rollTime = 0f;
            rolled = 0f;
            perfectAwarded = false;
            rollDir = move.sqrMagnitude > 0.01f ? move.normalized : -CombatMath.Flat(transform.forward).normalized;
            if (move.sqrMagnitude > 0.01f && !LockedOn) SnapToward(rollDir);
            Sfx.Play(SfxKind.Dodge, 0.4f);
        }

        Vector3 UpdateRolling(float dt)
        {
            rollTime += dt;
            float target = CombatMath.RollDisplacement(rollTime);
            float delta = target - rolled;
            rolled = target;
            if (rollTime >= Tuning.RollDuration) State = PlayerState.Free;
            return rollDir * delta;
        }

        void TryImmobilize(BossController boss)
        {
            if (boss == null || !boss.IsAlive) return;
            if (ImmobilizeCooldown > 0f)
            {
                HudOverlay.Flash("Immobilize on cooldown (" + Mathf.CeilToInt(ImmobilizeCooldown) + "s)", Color.gray, 0.8f);
                return;
            }
            if (boss.TryImmobilize())
            {
                ImmobilizeCooldown = Tuning.ImmobilizeCooldown;
                Sfx.Play(SfxKind.Immobilize, 0.7f);
                HudOverlay.Flash("IMMOBILIZED", new Color(1f, 0.85f, 0.3f), 1f);
            }
            else if (boss.ImmobilizeImmunity > 0f)
            {
                HudOverlay.Flash("Boss resists Immobilize (" + Mathf.CeilToInt(boss.ImmobilizeImmunity) + "s)", Color.gray, 1f);
            }
        }

        // ------------------------------------------------------------------ being hit
        public HitResult ReceiveHit(HitInfo hit)
        {
            if (State == PlayerState.Dead) return HitResult.Ignored;
            var boss = BossController.Instance;
            if (boss != null && boss.IsHarmless) return HitResult.Ignored;

            if (IsInvulnerable)
            {
                if (!hit.isHazard && !perfectAwarded && CombatMath.IsPerfectDodge(rollTime))
                {
                    perfectAwarded = true;
                    AddFocus(1, "PERFECT DODGE  +1 FOCUS");
                    GameFeel.SlowMo(Tuning.PerfectDodgeTimeScale, Tuning.PerfectDodgeRealDuration);
                    Sfx.Play(SfxKind.PerfectDodge, 0.6f);
                    return HitResult.PerfectDodge;
                }
                return HitResult.Dodged;
            }

            Vector3 toSource = CombatMath.Flat(hit.sourcePosition - transform.position);
            bool facing = toSource.sqrMagnitude < 0.01f || Vector3.Angle(CombatMath.Flat(transform.forward), toSource) <= 100f;
            if (IsBlocking && facing && hit.color != AttackColor.Unblockable && !hit.isHazard)
            {
                if (CombatMath.IsParry(Time.time - blockPressedTime))
                {
                    if (hit.canParry)
                    {
                        GameFeel.HitStop(0.12f);
                        OrbitCamera.Shake(0.12f, 0.15f);
                        Sfx.Play(SfxKind.Parry, 0.8f);
                        HudOverlay.Flash("PARRY", new Color(1f, 0.95f, 0.6f), 0.7f);
                        Stamina = Mathf.Min(maxStamina, Stamina + 10f);
                        return HitResult.Parried;
                    }
                    Sfx.Play(SfxKind.Block, 0.6f);
                    return HitResult.Blocked;
                }
                if (hit.color == AttackColor.Parryable)
                {
                    // A plain block against a yellow attack gets you staggered.
                    GuardBreak(hit, 0.5f);
                    return HitResult.GuardBroken;
                }
                SpendStamina(hit.postureDamage);
                if (Stamina <= 0f)
                {
                    GuardBreak(hit, 0.6f);
                    return HitResult.GuardBroken;
                }
                TakeDamage(hit.damage * 0.15f);
                Sfx.Play(SfxKind.Block, 0.6f);
                return HitResult.Blocked;
            }

            TakeDamage(hit.damage);
            Sfx.Play(SfxKind.PlayerHit, 0.7f);
            OrbitCamera.Shake(hit.bigImpact ? 0.35f : 0.18f, 0.25f);
            consecutiveLightHits = 0;
            if (State != PlayerState.Dead && hit.damage >= 15f && !hit.isHazard)
            {
                // Hit reaction interrupts the current action.
                State = PlayerState.Staggered;
                staggerTimer = hit.damage >= 40f ? 0.8f : 0.4f;
                heavyHeld = false;
                pushAccum += (toSource.sqrMagnitude > 0.01f ? -toSource.normalized : -transform.forward) * 0.6f;
            }
            return HitResult.Hit;
        }

        void GuardBreak(HitInfo hit, float damageFraction)
        {
            TakeDamage(hit.damage * damageFraction);
            Stamina = 0f;
            staminaIdle = 0f;
            Sfx.Play(SfxKind.PlayerHit, 0.7f);
            HudOverlay.Flash("GUARD BROKEN", new Color(1f, 0.5f, 0.3f), 0.8f);
            if (State != PlayerState.Dead)
            {
                State = PlayerState.Staggered;
                staggerTimer = 0.9f;
                IsBlocking = false;
                heavyHeld = false;
            }
        }

        void TakeDamage(float amount)
        {
            Health = Mathf.Max(0f, Health - amount);
            if (Health <= 0f)
            {
                State = PlayerState.Dead;
                IsBlocking = false;
                heavyHeld = false;
                LockedOn = false;
                GameFeel.SlowMo(0.3f, 0.8f);
            }
        }

        // ------------------------------------------------------------------ animation
        void AnimateVisual(float dt)
        {
            if (swordPivot == null && visual != null) swordPivot = visual.Find("SwordPivot");
            if (shield == null && visual != null) shield = visual.Find("Shield");
            if (swordPivot == null || shield == null) return;

            Quaternion swordTarget = Quaternion.Euler(20f, 0f, 0f);
            float swordSpeed = 14f;
            if (State == PlayerState.Attacking)
            {
                var spec = Spec(attackKind, focusSpent);
                float u = Mathf.Clamp01(attackTime / spec.hitTime);
                swordSpeed = 40f;
                if (attackKind == PlayerAttackKind.Light)
                {
                    float side = lightChain % 2 == 1 ? 1f : -1f;
                    swordTarget = Quaternion.Euler(10f, Mathf.Lerp(-80f, 80f, u) * side, 0f);
                }
                else swordTarget = Quaternion.Euler(Mathf.Lerp(-110f, 50f, u * u), 0f, 0f);
            }
            else if (heavyHeld) swordTarget = Quaternion.Euler(-110f, 0f, 0f);
            swordPivot.localRotation = Quaternion.Slerp(swordPivot.localRotation, swordTarget, swordSpeed * dt);

            Vector3 shieldPos = IsBlocking ? new Vector3(-0.1f, 1.25f, 0.45f) : new Vector3(-0.48f, 1.1f, 0.15f);
            Quaternion shieldRot = IsBlocking ? Quaternion.Euler(0f, 90f, 0f) : Quaternion.identity;
            shield.localPosition = Vector3.Lerp(shield.localPosition, shieldPos, 18f * dt);
            shield.localRotation = Quaternion.Slerp(shield.localRotation, shieldRot, 18f * dt);

            Quaternion bodyRot = Quaternion.identity;
            Vector3 bodyPos = Vector3.zero;
            if (State == PlayerState.Rolling)
            {
                Vector3 localDir = transform.InverseTransformDirection(rollDir);
                Vector3 axis = Vector3.Cross(Vector3.up, localDir);
                float u = Mathf.Clamp01(rollTime / Tuning.RollDuration);
                bodyRot = Quaternion.AngleAxis(u * 360f, axis.sqrMagnitude > 0.001f ? axis.normalized : Vector3.right);
                bodyPos = Vector3.down * 0.4f * Mathf.Sin(u * Mathf.PI);
            }
            else if (State == PlayerState.Staggered) bodyRot = Quaternion.Euler(-15f, 0f, 0f);
            visual.localRotation = State == PlayerState.Rolling ? bodyRot : Quaternion.Slerp(visual.localRotation, bodyRot, 12f * dt);
            visual.localPosition = bodyPos;
        }
    }
}
