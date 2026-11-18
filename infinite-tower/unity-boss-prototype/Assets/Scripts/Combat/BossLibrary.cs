using System.Collections.Generic;
using UnityEngine;

namespace BossPrototype
{
    /// <summary>
    /// Data-driven boss movesets (BOSS_SYSTEM.md "Boss sizes and movesets").
    /// Index 0..3 = keys 1..4: Cinder Warden, Brass Regent, Drowned Cantor, Pale Huntress.
    /// </summary>
    public static class BossLibrary
    {
        public const int Count = 4;

        public static BossDefinition Create(int index)
        {
            switch (Mathf.Clamp(index, 0, Count - 1))
            {
                case 1: return BrassRegent();
                case 2: return DrownedCantor();
                case 3: return PaleHuntress();
                default: return CinderWarden();
            }
        }

        public static List<BossDefinition> All()
        {
            var list = new List<BossDefinition>();
            for (int i = 0; i < Count; i++) list.Add(Create(i));
            return list;
        }

        static readonly string[] None = new string[0];

        // ------------------------------------------------------------------ 0
        static BossDefinition CinderWarden()
        {
            var d = new BossDefinition
            {
                name = "The Cinder Warden",
                epithet = "Keeper of the Ash Gate",
                scale = 4.5f,
                maxHealth = 1100f,
                maxPosture = 100f,
                moveSpeed = 4.2f,
                turnSpeed = 150f,
                bodyColor = new Color(0.22f, 0.16f, 0.14f),
                accentColor = new Color(1f, 0.45f, 0.1f),
            };
            d.attacks.Add(new BossAttack
            {
                name = "Ember Arc", shape = AttackShape.Cone, size = new Vector2(10f, 110f),
                windup = 1.0f, trackUntil = 0.6f, active = 0.25f, recovery = 1.2f,
                damage = 28f, postureDamage = 30f, lunge = 1.5f,
                special = AttackSpecial.FirePools, count = 3,
                minRange = 0f, maxRange = 11f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Delayed Ground Burst", shape = AttackShape.Circle, size = new Vector2(4.5f, 0f), offset = 5.5f,
                windup = 1.9f, trackUntil = 1.0f, active = 0.2f, recovery = 1.7f, heldPose = true,
                damage = 34f, postureDamage = 40f, ringAfter = 17f, ringSpeed = 10f, bigImpact = true,
                minRange = 3f, maxRange = 14f, weight = 2f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Stomp", shape = AttackShape.Circle, size = new Vector2(5.5f, 0f), offset = 0f,
                windup = 0.9f, trackUntil = 0f, active = 0.15f, recovery = 0.9f,
                damage = 26f, postureDamage = 30f, bigImpact = true,
                minRange = 0f, maxRange = 5.5f, weight = 4f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Warden String I", shape = AttackShape.Cone, size = new Vector2(8.5f, 90f),
                windup = 0.9f, trackUntil = 0.55f, active = 0.2f, recovery = 0.8f,
                damage = 22f, postureDamage = 25f, lunge = 2f,
                followUps = new[] { "Warden String II" },
                minRange = 0f, maxRange = 9f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Warden String II", shape = AttackShape.Cone, size = new Vector2(8.5f, 90f),
                windup = 0.4f, trackUntil = 0.2f, active = 0.2f, recovery = 0.8f,
                damage = 22f, postureDamage = 25f, lunge = 1.5f, comboOnly = true,
                followUps = new[] { "Warden String III" },
            });
            d.attacks.Add(new BossAttack
            {
                name = "Warden String III", shape = AttackShape.Circle, size = new Vector2(4.2f, 0f), offset = 4.5f,
                windup = 0.5f, trackUntil = 0.25f, active = 0.2f, recovery = 1.8f,
                damage = 36f, postureDamage = 45f, lunge = 1f, comboOnly = true, bigImpact = true,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Cinder Grab", shape = AttackShape.Cone, size = new Vector2(6.5f, 60f),
                windup = 1.1f, trackUntil = 0.8f, active = 0.25f, recovery = 1.4f,
                damage = 55f, postureDamage = 0f, color = AttackColor.Unblockable, lunge = 2f,
                minRange = 0f, maxRange = 7f, weight = 1.5f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Molten Charge", shape = AttackShape.Line, size = new Vector2(24f, 4.5f),
                windup = 1.2f, trackUntil = 0.95f, active = 0.8f, recovery = 1.6f,
                damage = 32f, postureDamage = 35f, lunge = 21f, phase = 2, bigImpact = true,
                minRange = 8f, maxRange = 30f, weight = 3f,
            });
            return d;
        }

        // ------------------------------------------------------------------ 1
        static BossDefinition BrassRegent()
        {
            var d = new BossDefinition
            {
                name = "The Brass Regent",
                epithet = "Crowned in Gears",
                scale = 1.3f,
                maxHealth = 750f,
                maxPosture = 90f,
                moveSpeed = 3.6f,
                turnSpeed = 300f,
                bodyColor = new Color(0.55f, 0.42f, 0.18f),
                accentColor = new Color(0.95f, 0.8f, 0.35f),
            };
            d.attacks.Add(new BossAttack
            {
                name = "Shielded Charge", shape = AttackShape.Line, size = new Vector2(12f, 2f),
                windup = 0.9f, trackUntil = 0.7f, active = 0.5f, recovery = 1.0f,
                damage = 22f, postureDamage = 30f, lunge = 11f,
                minRange = 5f, maxRange = 16f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Royal Strike I", shape = AttackShape.Cone, size = new Vector2(3f, 90f),
                windup = 0.7f, trackUntil = 0.45f, active = 0.15f, recovery = 0.7f,
                damage = 16f, postureDamage = 18f, lunge = 1.2f,
                followUps = new[] { "Royal Strike II" },
                minRange = 0f, maxRange = 4f, weight = 4f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Royal Strike II", shape = AttackShape.Cone, size = new Vector2(3f, 90f),
                windup = 0.35f, trackUntil = 0.15f, active = 0.15f, recovery = 0.7f,
                damage = 16f, postureDamage = 18f, lunge = 1f, comboOnly = true,
                followUps = new[] { "Royal Strike III" },
            });
            d.attacks.Add(new BossAttack
            {
                name = "Royal Strike III", shape = AttackShape.Cone, size = new Vector2(3.6f, 60f),
                windup = 0.55f, trackUntil = 0.3f, active = 0.2f, recovery = 1.5f,
                damage = 28f, postureDamage = 35f, color = AttackColor.Parryable, lunge = 1.4f, comboOnly = true,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Shield Bash", shape = AttackShape.Box, size = new Vector2(2.6f, 2.4f),
                windup = 0.8f, trackUntil = 0.55f, active = 0.2f, recovery = 1.1f,
                damage = 40f, postureDamage = 0f, color = AttackColor.Unblockable, lunge = 1f,
                minRange = 0f, maxRange = 3.5f, weight = 2f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Delayed Overhead", shape = AttackShape.Box, size = new Vector2(4f, 1.4f),
                windup = 1.6f, trackUntil = 1.1f, active = 0.2f, recovery = 1.4f, heldPose = true,
                damage = 32f, postureDamage = 40f, lunge = 0.8f,
                minRange = 0f, maxRange = 5f, weight = 2f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Regal Onslaught", shape = AttackShape.Line, size = new Vector2(12f, 2f),
                windup = 0.9f, trackUntil = 0.7f, active = 0.5f, recovery = 0.6f,
                damage = 22f, postureDamage = 30f, lunge = 11f, phase = 2,
                followUps = new[] { "Royal Strike III" },
                minRange = 4f, maxRange = 16f, weight = 3f,
            });
            return d;
        }

        // ------------------------------------------------------------------ 2
        static BossDefinition DrownedCantor()
        {
            var d = new BossDefinition
            {
                name = "The Drowned Cantor",
                epithet = "Choir of the Sunken Nave",
                scale = 4f,
                maxHealth = 950f,
                maxPosture = 100f,
                moveSpeed = 2.6f,
                turnSpeed = 120f,
                bodyColor = new Color(0.12f, 0.26f, 0.32f),
                accentColor = new Color(0.35f, 0.85f, 1f),
            };
            d.attacks.Add(new BossAttack
            {
                name = "Pulse Ring", shape = AttackShape.Ring, size = new Vector2(18f, 1.4f),
                windup = 1.2f, trackUntil = 0f, active = 0.3f, recovery = 1.0f,
                damage = 24f, postureDamage = 25f, ringSpeed = 9f, bigImpact = true,
                minRange = 0f, maxRange = 18f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Resonant Cone", shape = AttackShape.Cone, size = new Vector2(12f, 50f),
                windup = 1.3f, trackUntil = 0.9f, active = 0.4f, recovery = 1.4f,
                damage = 48f, postureDamage = 0f, color = AttackColor.Unblockable,
                minRange = 0f, maxRange = 13f, weight = 2f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Water Bolts", shape = AttackShape.Line, size = new Vector2(22f, 1f),
                windup = 0.9f, trackUntil = 0.9f, active = 1.2f, recovery = 0.8f,
                damage = 18f, postureDamage = 20f, special = AttackSpecial.Projectiles, count = 3, projectileSpeed = 16f,
                minRange = 6f, maxRange = 45f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Tidal Slam", shape = AttackShape.Circle, size = new Vector2(5f, 0f), offset = 0f,
                windup = 1.0f, trackUntil = 0f, active = 0.15f, recovery = 1.0f,
                damage = 26f, postureDamage = 30f, bigImpact = true,
                minRange = 0f, maxRange = 6f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Double Pulse", shape = AttackShape.Ring, size = new Vector2(18f, 1.4f),
                windup = 1.1f, trackUntil = 0f, active = 0.3f, recovery = 0.4f,
                damage = 24f, postureDamage = 25f, ringSpeed = 9f, phase = 2, bigImpact = true,
                followUps = new[] { "Double Pulse Echo" },
                minRange = 0f, maxRange = 18f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Double Pulse Echo", shape = AttackShape.Ring, size = new Vector2(18f, 1.4f),
                windup = 0.5f, trackUntil = 0f, active = 0.3f, recovery = 1.4f,
                damage = 24f, postureDamage = 25f, ringSpeed = 11f, phase = 2, comboOnly = true,
            });
            return d;
        }

        // ------------------------------------------------------------------ 3
        static BossDefinition PaleHuntress()
        {
            var d = new BossDefinition
            {
                name = "The Pale Huntress",
                epithet = "Arrow of the White Wood",
                scale = 1.1f,
                maxHealth = 650f,
                maxPosture = 80f,
                moveSpeed = 4.8f,
                turnSpeed = 360f,
                bodyColor = new Color(0.8f, 0.82f, 0.85f),
                accentColor = new Color(0.6f, 0.9f, 0.7f),
            };
            d.attacks.Add(new BossAttack
            {
                name = "Arrow Volley", shape = AttackShape.Circle, size = new Vector2(1.8f, 0f),
                placement = AttackPlacement.AtTarget, count = 4, scatter = 3.5f,
                windup = 1.1f, trackUntil = 0.75f, active = 0.2f, recovery = 0.7f,
                damage = 18f, postureDamage = 20f,
                minRange = 5f, maxRange = 40f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Pounce", shape = AttackShape.Line, size = new Vector2(10f, 1.8f),
                windup = 0.8f, trackUntil = 0.6f, active = 0.35f, recovery = 0.6f,
                damage = 14f, postureDamage = 15f, lunge = 9.5f,
                followUps = new[] { "Pounce Slam" },
                minRange = 4f, maxRange = 14f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Pounce Slam", shape = AttackShape.Circle, size = new Vector2(2.6f, 0f), offset = 0.8f,
                windup = 0.45f, trackUntil = 0.2f, active = 0.2f, recovery = 1.5f,
                damage = 30f, postureDamage = 35f, color = AttackColor.Parryable, comboOnly = true,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Backstep", shape = AttackShape.Circle, size = Vector2.zero,
                windup = 0.2f, trackUntil = 0.2f, active = 0.35f, recovery = 0.2f,
                damage = 0f, postureDamage = 0f, lunge = -7f, special = AttackSpecial.Backstep,
                followUps = new[] { "Huntress Shot" },
                minRange = 0f, maxRange = 3.5f, weight = 3f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Huntress Shot", shape = AttackShape.Line, size = new Vector2(25f, 0.8f),
                windup = 0.45f, trackUntil = 0.45f, active = 0.5f, recovery = 0.9f,
                damage = 16f, postureDamage = 15f, special = AttackSpecial.Projectiles, count = 2, projectileSpeed = 24f,
                comboOnly = true,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Hunting Knife", shape = AttackShape.Cone, size = new Vector2(2.6f, 100f),
                windup = 0.6f, trackUntil = 0.4f, active = 0.15f, recovery = 0.8f,
                damage = 16f, postureDamage = 18f, lunge = 0.8f,
                minRange = 0f, maxRange = 3f, weight = 2f,
            });
            d.attacks.Add(new BossAttack
            {
                name = "Rain of Arrows", shape = AttackShape.Circle, size = new Vector2(2f, 0f),
                placement = AttackPlacement.AtTarget, count = 7, scatter = 6f,
                windup = 1.4f, trackUntil = 0.9f, active = 0.2f, recovery = 1.0f,
                damage = 20f, postureDamage = 20f, phase = 2,
                minRange = 3f, maxRange = 40f, weight = 3f,
            });
            return d;
        }
    }
}
