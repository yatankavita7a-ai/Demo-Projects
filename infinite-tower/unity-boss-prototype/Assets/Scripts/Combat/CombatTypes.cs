using System.Collections.Generic;
using UnityEngine;

namespace BossPrototype
{
    /// <summary>Hit-area shape of a boss attack (BOSS_SYSTEM.md "Boss attack data").</summary>
    public enum AttackShape { Cone, Circle, Ring, Line, Box }

    /// <summary>God of War colour code: orange = normal, yellow = parryable, red = unblockable.</summary>
    public enum AttackColor { Normal, Parryable, Unblockable }

    /// <summary>Where the shape is anchored: in front of the boss, or on the player's (locked) position.</summary>
    public enum AttackPlacement { AtBoss, AtTarget }

    public enum AttackSpecial { None, FirePools, Projectiles, Backstep }

    public enum PlayerAttackKind { Light, Heavy, Charged }

    public enum PlayerHitOutcome { Ignored, Hit, Critical }

    public enum HitResult { Ignored, Hit, Blocked, GuardBroken, Parried, Dodged, PerfectDodge }

    /// <summary>
    /// One boss attack as a data record. Distances are metres at the boss's default scale;
    /// they are multiplied by (current scale / default scale) at runtime so shapes scale with the boss.
    /// </summary>
    [System.Serializable]
    public class BossAttack
    {
        public string name = "Attack";

        // Timings (seconds). Phase 2 multiplies windup and trackUntil by Tuning.Phase2WindupMultiplier.
        public float windup = 1f;
        public float active = 0.2f;
        public float recovery = 1f;
        /// <summary>The boss stops turning to follow the player this many seconds into the windup.</summary>
        public float trackUntil = 0.6f;

        /// <summary>
        /// Shape and size. size meaning per shape:
        /// Cone: x = radius, y = full angle (deg). Circle: x = radius.
        /// Ring: x = max radius, y = band thickness. Line / Box: x = length (forward), y = width.
        /// </summary>
        public AttackShape shape = AttackShape.Cone;
        public Vector2 size = new Vector2(3f, 90f);
        /// <summary>Forward offset of the shape origin from the boss centre.</summary>
        public float offset;

        public float damage = 20f;
        /// <summary>Stamina drained from a player who blocks this attack.</summary>
        public float postureDamage = 20f;
        public AttackColor color = AttackColor.Normal;

        /// <summary>Lunge / charge distance during the active window (negative = backstep).</summary>
        public float lunge;
        /// <summary>Follow-up attack names (combo strings). The first valid one is chained.</summary>
        public string[] followUps = new string[0];
        /// <summary>The phase the attack becomes available in.</summary>
        public int phase = 1;

        // AI selection.
        public float minRange;
        public float maxRange = 999f;
        public float weight = 1f;
        /// <summary>Only reachable as a combo follow-up.</summary>
        public bool comboOnly;
        /// <summary>Delayed attack: the raised pose is held for most of the windup.</summary>
        public bool heldPose;

        public AttackPlacement placement = AttackPlacement.AtBoss;
        /// <summary>Number of markers (AtTarget) or projectiles.</summary>
        public int count = 1;
        /// <summary>Random spread of AtTarget markers around the player.</summary>
        public float scatter;
        public AttackSpecial special = AttackSpecial.None;

        /// <summary>If &gt; 0, the impact spawns an expanding shockwave ring of this radius.</summary>
        public float ringAfter;
        public float ringSpeed = 10f;
        public float projectileSpeed = 16f;
        /// <summary>Camera shake on impact.</summary>
        public bool bigImpact;

        public bool HasHitbox => damage > 0f && special != AttackSpecial.Backstep;
    }

    public class BossDefinition
    {
        public string name;
        public string epithet;
        /// <summary>Size relative to the player (player = 1).</summary>
        public float scale = 1f;
        public float maxHealth = 800f;
        public float maxPosture = 100f;
        public float moveSpeed = 4f;
        public float turnSpeed = 220f;
        public Color bodyColor = Color.gray;
        public Color accentColor = Color.white;
        public List<BossAttack> attacks = new List<BossAttack>();

        public BossAttack Find(string attackName)
        {
            for (int i = 0; i < attacks.Count; i++)
                if (attacks[i].name == attackName) return attacks[i];
            return null;
        }
    }

    /// <summary>A hit sent to the player by an attack or hazard.</summary>
    public struct HitInfo
    {
        public float damage;
        public float postureDamage;
        public AttackColor color;
        public bool canParry;
        /// <summary>Lingering ground hazard: cannot be blocked, never a perfect dodge.</summary>
        public bool isHazard;
        public bool bigImpact;
        public Vector3 sourcePosition;
        public string source;
    }
}
