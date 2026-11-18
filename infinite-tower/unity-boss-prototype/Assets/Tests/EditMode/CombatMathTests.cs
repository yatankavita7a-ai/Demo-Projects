using BossPrototype;
using NUnit.Framework;
using UnityEngine;

namespace BossPrototype.Tests
{
    public class CombatMathTests
    {
        [Test]
        public void ConeContainsPointsInsideAngleAndRadius()
        {
            Assert.IsTrue(CombatMath.PointInCone(Vector3.zero, Vector3.forward, 5f, 90f, new Vector3(0f, 0f, 4f), 0f));
            Assert.IsTrue(CombatMath.PointInCone(Vector3.zero, Vector3.forward, 5f, 90f, new Vector3(2f, 0f, 2.5f), 0f));
            Assert.IsFalse(CombatMath.PointInCone(Vector3.zero, Vector3.forward, 5f, 90f, new Vector3(0f, 0f, -2f), 0f));
            Assert.IsFalse(CombatMath.PointInCone(Vector3.zero, Vector3.forward, 5f, 90f, new Vector3(0f, 0f, 6f), 0f));
        }

        [Test]
        public void RectAndCircleAndRing()
        {
            Assert.IsTrue(CombatMath.PointInRect(Vector3.zero, Vector3.forward, 10f, 2f, new Vector3(0.9f, 0f, 9f), 0f));
            Assert.IsFalse(CombatMath.PointInRect(Vector3.zero, Vector3.forward, 10f, 2f, new Vector3(1.5f, 0f, 5f), 0f));
            Assert.IsFalse(CombatMath.PointInRect(Vector3.zero, Vector3.forward, 10f, 2f, new Vector3(0f, 0f, -1f), 0f));
            Assert.IsTrue(CombatMath.PointInCircle(Vector3.zero, 3f, new Vector3(2f, 5f, 2f), 0f), "height is ignored");
            Assert.IsTrue(CombatMath.PointOnRing(Vector3.zero, 5f, 1f, new Vector3(5.4f, 0f, 0f), 0f));
            Assert.IsFalse(CombatMath.PointOnRing(Vector3.zero, 5f, 1f, new Vector3(2f, 0f, 0f), 0f));
            Assert.IsFalse(CombatMath.IsInShape(AttackShape.Ring, new Vector2(10f, 1f), Vector3.zero, Vector3.forward, Vector3.zero, 0f));
        }

        [Test]
        public void DodgeIFramesAndPerfectDodgeWindow()
        {
            Assert.IsFalse(CombatMath.IsRollInvulnerable(0.04f));
            Assert.IsTrue(CombatMath.IsRollInvulnerable(0.05f));
            Assert.IsTrue(CombatMath.IsRollInvulnerable(0.40f));
            Assert.IsFalse(CombatMath.IsRollInvulnerable(0.41f));
            Assert.IsTrue(CombatMath.IsPerfectDodge(0.10f));
            Assert.IsFalse(CombatMath.IsPerfectDodge(0.20f));
            Assert.AreEqual(Tuning.RollDistance, CombatMath.RollDisplacement(Tuning.RollDuration), 1e-4f);
        }

        [Test]
        public void ParryFocusPhaseAndCritical()
        {
            Assert.IsTrue(CombatMath.IsParry(0.15f));
            Assert.IsFalse(CombatMath.IsParry(0.25f));
            Assert.IsFalse(CombatMath.ShouldAwardFocus(2));
            Assert.IsTrue(CombatMath.ShouldAwardFocus(3));
            Assert.IsTrue(CombatMath.ShouldAwardFocus(6));
            Assert.AreEqual(0.88f, CombatMath.PhaseWindup(1f, 2), 1e-5f);
            Assert.AreEqual(1f, CombatMath.PhaseWindup(1f, 1), 1e-5f);
            Assert.AreEqual(100f, CombatMath.CriticalDamage(1000f, 0f), 1e-3f);
        }

        [Test]
        public void PostureDrainsOnlyAfterDelay()
        {
            Assert.AreEqual(50f, CombatMath.DrainPosture(50f, 1.9f, 1f), 1e-4f);
            Assert.Less(CombatMath.DrainPosture(50f, 2.1f, 1f), 50f);
            Assert.AreEqual(0f, CombatMath.DrainPosture(1f, 5f, 1f), 1e-4f);
        }
    }
}
