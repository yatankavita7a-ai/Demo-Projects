using BossPrototype;
using NUnit.Framework;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace BossPrototype.Tests
{
    public class ArenaBuildTests
    {
        [Test]
        public void FactoryBuildsPlayerBossAndCamera()
        {
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            ArenaFactory.Build(0);
            var player = Object.FindAnyObjectByType<PlayerController>();
            var boss = Object.FindAnyObjectByType<BossController>();
            Assert.IsNotNull(player);
            Assert.IsNotNull(boss);
            Assert.IsNotNull(Object.FindAnyObjectByType<OrbitCamera>());
            Assert.IsNotNull(Object.FindAnyObjectByType<HudOverlay>());
            Assert.AreEqual(4.5f, boss.Scale, 1e-4f);
            Assert.IsNotNull(boss.transform.Find("Visual"));
            Assert.IsNotNull(player.transform.Find("Visual"));
            for (int i = 0; i < BossLibrary.Count; i++)
            {
                boss.Setup(i);
                Assert.AreEqual(BossLibrary.Create(i).scale, boss.Scale, 1e-4f);
            }
        }
    }
}
