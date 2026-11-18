using System.Collections;
using BossPrototype;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace BossPrototype.Tests
{
    /// <summary>Runs every boss's AI for a while against an idle player; any exception or error log fails the test.</summary>
    public class ArenaSmokeTests
    {
        [UnityTest]
        public IEnumerator EveryBossFightsWithoutErrors()
        {
            var root = Object.FindAnyObjectByType<ArenaRoot>();
            if (root == null) root = ArenaFactory.Build(0);
            yield return null;
            Assert.IsNotNull(PlayerController.Instance);
            Assert.IsNotNull(BossController.Instance);

            for (int i = 0; i < BossLibrary.Count; i++)
            {
                root.ResetArena(i);
                var boss = BossController.Instance;
                var player = PlayerController.Instance;
                Assert.AreEqual(BossLibrary.Create(i).scale, boss.Scale, 1e-4f);

                bool sawWindup = false, sawActive = false;
                float t = 0f;
                while (t < 7f)
                {
                    if (boss.State == BossState.Windup) sawWindup = true;
                    if (boss.State == BossState.Active) sawActive = true;
                    t += Time.unscaledDeltaTime;
                    yield return null;
                }
                Assert.IsTrue(sawWindup && sawActive, boss.Def.name + " never attacked");

                // Push into phase 2 and then kill it, exercising roar and death paths.
                boss.ReceivePlayerHit(PlayerAttackKind.Heavy, boss.Def.maxHealth * 0.55f, 0f);
                Assert.AreEqual(2, boss.Phase);
                Assert.AreEqual(BossState.Roar, boss.State);
                Assert.AreEqual(PlayerHitOutcome.Ignored, boss.ReceivePlayerHit(PlayerAttackKind.Light, 10f, 0f), "roar must be invulnerable");
                t = 0f;
                while (t < 4f) { t += Time.unscaledDeltaTime; yield return null; }

                boss.AddPosture(1000f);
                Assert.AreEqual(BossState.Staggered, boss.State);
                float before = boss.Health;
                Assert.AreEqual(PlayerHitOutcome.Critical, boss.ReceivePlayerHit(PlayerAttackKind.Heavy, 30f, 14f));
                Assert.Greater(before - boss.Health, boss.Def.maxHealth * 0.1f - 0.01f);

                Assert.IsTrue(boss.TryImmobilize());
                Assert.IsTrue(boss.IsFrozen);

                boss.ReceivePlayerHit(PlayerAttackKind.Heavy, 100000f, 0f);
                Assert.IsFalse(boss.IsAlive);
                yield return null;
                Assert.IsNotNull(player);
            }
            Object.Destroy(root.gameObject);
            yield return null;
        }
    }
}
