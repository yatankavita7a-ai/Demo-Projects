using BossPrototype;
using NUnit.Framework;

namespace BossPrototype.Tests
{
    public class BossLibraryTests
    {
        [Test]
        public void FourBossesWithSpecSizes()
        {
            var all = BossLibrary.All();
            Assert.AreEqual(4, all.Count);
            Assert.AreEqual("The Cinder Warden", all[0].name); Assert.AreEqual(4.5f, all[0].scale);
            Assert.AreEqual("The Brass Regent", all[1].name); Assert.AreEqual(1.3f, all[1].scale);
            Assert.AreEqual("The Drowned Cantor", all[2].name); Assert.AreEqual(4f, all[2].scale);
            Assert.AreEqual("The Pale Huntress", all[3].name); Assert.AreEqual(1.1f, all[3].scale);
        }

        [Test]
        public void AttackDataIsConsistent()
        {
            foreach (var boss in BossLibrary.All())
            {
                bool hasPhase2 = false;
                foreach (var a in boss.attacks)
                {
                    string id = boss.name + "/" + a.name;
                    Assert.LessOrEqual(a.trackUntil, a.windup + 1e-4f, id + " trackUntil > windup");
                    Assert.Greater(a.active, 0f, id);
                    Assert.Greater(a.recovery, 0f, id);
                    foreach (var f in a.followUps)
                        Assert.IsNotNull(boss.Find(f), id + " follow-up missing: " + f);
                    if (a.phase >= 2 && !a.comboOnly) hasPhase2 = true;
                    if (!a.HasHitbox) continue;
                    if (a.comboOnly)
                        Assert.That(a.windup, Is.InRange(0.3f, 0.6f), id + " combo gap");
                    else if (a.heldPose)
                        Assert.That(a.windup, Is.InRange(1.5f, 3f), id + " delayed windup");
                    else
                        Assert.That(a.windup, Is.InRange(0.6f, 1.5f), id + " windup");
                }
                Assert.IsTrue(hasPhase2, boss.name + " needs a phase-2 attack");
            }
        }

        [Test]
        public void CinderWardenHasRequiredMoves()
        {
            var d = BossLibrary.Create(0);
            Assert.AreEqual(AttackSpecial.FirePools, d.Find("Ember Arc").special);
            Assert.Greater(d.Find("Delayed Ground Burst").ringAfter, 0f);
            Assert.AreEqual(AttackShape.Line, d.Find("Molten Charge").shape);
            Assert.AreEqual(2, d.Find("Molten Charge").phase);
            Assert.AreEqual(AttackColor.Unblockable, d.Find("Cinder Grab").color);
        }
    }
}
