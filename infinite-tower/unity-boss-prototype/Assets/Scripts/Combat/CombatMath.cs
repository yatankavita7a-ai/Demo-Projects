using UnityEngine;

namespace BossPrototype
{
    /// <summary>Tuning numbers taken from BOSS_SYSTEM.md.</summary>
    public static class Tuning
    {
        // Dodge roll
        public const float RollDuration = 0.6f;
        public const float RollDistance = 3.5f;
        public const float RollIFrameStart = 0.05f;
        public const float RollIFrameEnd = 0.40f;
        public const float RollStaminaCost = 18f;
        public const float PerfectDodgeWindow = 0.15f;
        public const float PerfectDodgeTimeScale = 0.35f;
        public const float PerfectDodgeRealDuration = 0.4f;

        // Block / parry
        public const float ParryWindow = 0.2f;

        // Focus
        public const int MaxFocus = 3;
        public const int LightHitsPerFocus = 3;
        public const float ChargeHoldThreshold = 0.45f;

        // Immobilize
        public const float ImmobilizeDuration = 2.5f;
        public const float ImmobilizeCooldown = 45f;
        public const float ImmobilizeBossImmunity = 20f;

        // Stamina
        public const float StaminaRegenPerSecond = 40f;
        public const float StaminaRegenDelay = 0.6f;

        // Posture / stagger
        public const float PostureDrainDelay = 2f;
        public const float PostureDrainPerSecond = 18f;
        public const float StaggerDuration = 3f;
        public const float CriticalFractionOfMaxHealth = 0.10f;
        public const float StaggerDamageMultiplier = 1.5f;

        // Phases
        public const float Phase2HealthFraction = 0.5f;
        public const float RoarDuration = 2.5f;
        public const float Phase2WindupMultiplier = 0.88f;

        // Camera
        public const float LargeBossScale = 3f;
    }

    /// <summary>Pure, engine-light combat helpers (covered by EditMode tests).</summary>
    public static class CombatMath
    {
        public static Vector3 Flat(Vector3 v) { v.y = 0f; return v; }

        public static bool PointInCircle(Vector3 center, float radius, Vector3 point, float pad)
        {
            return Flat(point - center).magnitude <= radius + pad;
        }

        public static bool PointInCone(Vector3 origin, Vector3 forward, float radius, float angleDeg, Vector3 point, float pad)
        {
            Vector3 d = Flat(point - origin);
            float dist = d.magnitude;
            if (dist > radius + pad) return false;
            if (dist <= pad + 0.01f) return true;
            float leeway = Mathf.Asin(Mathf.Clamp01(pad / dist)) * Mathf.Rad2Deg;
            return Vector3.Angle(Flat(forward), d) <= angleDeg * 0.5f + leeway;
        }

        /// <summary>Rectangle starting at origin, extending 'length' along forward, 'width' wide.</summary>
        public static bool PointInRect(Vector3 origin, Vector3 forward, float length, float width, Vector3 point, float pad)
        {
            Vector3 f = Flat(forward).normalized;
            if (f.sqrMagnitude < 0.0001f) f = Vector3.forward;
            Vector3 r = Vector3.Cross(Vector3.up, f);
            Vector3 d = Flat(point - origin);
            float z = Vector3.Dot(d, f);
            float x = Vector3.Dot(d, r);
            return z >= -pad && z <= length + pad && Mathf.Abs(x) <= width * 0.5f + pad;
        }

        public static bool PointOnRing(Vector3 center, float radius, float thickness, Vector3 point, float pad)
        {
            float dist = Flat(point - center).magnitude;
            return Mathf.Abs(dist - radius) <= thickness * 0.5f + pad;
        }

        /// <summary>Static hit test for a shape. Rings are resolved by the expanding shockwave instead.</summary>
        public static bool IsInShape(AttackShape shape, Vector2 size, Vector3 origin, Vector3 forward, Vector3 point, float pad)
        {
            switch (shape)
            {
                case AttackShape.Cone: return PointInCone(origin, forward, size.x, size.y, point, pad);
                case AttackShape.Circle: return PointInCircle(origin, size.x, point, pad);
                case AttackShape.Line:
                case AttackShape.Box: return PointInRect(origin, forward, size.x, size.y, point, pad);
                default: return false;
            }
        }

        public static bool IsRollInvulnerable(float rollTime)
        {
            return rollTime >= Tuning.RollIFrameStart && rollTime <= Tuning.RollIFrameEnd;
        }

        /// <summary>A hit that lands within 0.15 s of starting the roll (and inside the i-frames) is a perfect dodge.</summary>
        public static bool IsPerfectDodge(float rollTime)
        {
            return IsRollInvulnerable(rollTime) && rollTime <= Tuning.PerfectDodgeWindow;
        }

        public static bool IsParry(float timeSinceBlockPressed)
        {
            return timeSinceBlockPressed >= 0f && timeSinceBlockPressed <= Tuning.ParryWindow;
        }

        public static bool ShouldAwardFocus(int consecutiveLightHits)
        {
            return consecutiveLightHits > 0 && consecutiveLightHits % Tuning.LightHitsPerFocus == 0;
        }

        public static float PhaseWindup(float windup, int phase)
        {
            return phase >= 2 ? windup * Tuning.Phase2WindupMultiplier : windup;
        }

        public static float CriticalDamage(float maxHealth, float baseDamage)
        {
            return maxHealth * Tuning.CriticalFractionOfMaxHealth + baseDamage * 0.5f;
        }

        public static float DrainPosture(float posture, float timeSinceFill, float dt)
        {
            if (timeSinceFill < Tuning.PostureDrainDelay) return posture;
            return Mathf.Max(0f, posture - Tuning.PostureDrainPerSecond * dt);
        }

        /// <summary>Ease-out displacement of the dodge roll at time t.</summary>
        public static float RollDisplacement(float t)
        {
            float u = Mathf.Clamp01(t / Tuning.RollDuration);
            return Tuning.RollDistance * (1f - (1f - u) * (1f - u));
        }

        /// <summary>Weight of an attack given the distance to the player (distances already scaled).</summary>
        public static float DistanceWeight(BossAttack a, float distance, float shapeScale)
        {
            bool inRange = distance >= a.minRange * shapeScale && distance <= a.maxRange * shapeScale;
            return a.weight * (inRange ? 1f : 0.06f);
        }

        public static bool InRange(BossAttack a, float distance, float shapeScale)
        {
            return distance >= a.minRange * shapeScale && distance <= a.maxRange * shapeScale;
        }

        public static bool IsLargeBoss(float bossScale) { return bossScale >= Tuning.LargeBossScale; }
    }
}
