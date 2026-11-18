using UnityEngine;

namespace BossPrototype
{
    /// <summary>
    /// Builds the whole arena from primitives. Used by the editor scene builder (edit mode) and by the
    /// runtime bootstrap (play mode in an empty scene). Colours are applied at runtime via Tint.
    /// </summary>
    public static class ArenaFactory
    {
        public static ArenaRoot Build(int bossIndex = 0)
        {
            var rootGo = new GameObject("BossArena");
            var hazards = new GameObject("Hazards").transform;
            hazards.SetParent(rootGo.transform, false);
            var root = rootGo.AddComponent<ArenaRoot>();
            root.Hazards = hazards;
            root.currentBoss = bossIndex;
            rootGo.AddComponent<GameFeel>();
            rootGo.AddComponent<HudOverlay>();

            BuildEnvironment(rootGo.transform);
            BuildLights(rootGo.transform);

            var playerGo = new GameObject("Player");
            playerGo.transform.SetParent(rootGo.transform, false);
            playerGo.transform.position = ArenaRoot.PlayerSpawn;
            var cc = playerGo.AddComponent<CharacterController>();
            PlayerController.ConfigureController(cc);
            var player = playerGo.AddComponent<PlayerController>();
            player.BuildVisual();
            player.ResetPlayer(ArenaRoot.PlayerSpawn, Quaternion.identity);

            CreateBoss(rootGo.transform, bossIndex);

            var camGo = new GameObject("Main Camera");
            camGo.tag = "MainCamera";
            camGo.transform.SetParent(rootGo.transform, false);
            camGo.transform.position = ArenaRoot.PlayerSpawn + new Vector3(0f, 3.5f, -6f);
            camGo.transform.rotation = Quaternion.Euler(15f, 0f, 0f);
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.09f, 0.07f, 0.09f);
            cam.fieldOfView = 60f;
            cam.nearClipPlane = 0.1f;
            cam.farClipPlane = 300f;
            camGo.AddComponent<AudioListener>();
            camGo.AddComponent<OrbitCamera>();
            return root;
        }

        public static BossController CreateBoss(Transform parent, int bossIndex)
        {
            var go = new GameObject("Boss");
            go.transform.SetParent(parent, false);
            go.transform.SetPositionAndRotation(ArenaRoot.BossSpawn, Quaternion.LookRotation(Vector3.back));
            var boss = go.AddComponent<BossController>();
            boss.Setup(bossIndex);
            return boss;
        }

        static void BuildEnvironment(Transform root)
        {
            var env = new GameObject("Environment").transform;
            env.SetParent(root, false);
            float r = ArenaRoot.ArenaRadius;

            var floor = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            floor.name = "Floor";
            floor.transform.SetParent(env, false);
            floor.transform.localPosition = new Vector3(0f, -0.25f, 0f);
            floor.transform.localScale = new Vector3(r * 2f, 0.25f, r * 2f);
            Util.StripCollider(floor);
            var box = floor.AddComponent<BoxCollider>();
            box.size = new Vector3(1f, 2f, 1f);
            Tint.Add(floor, new Color(0.25f, 0.23f, 0.24f));

            var outer = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            outer.name = "OuterGround";
            outer.transform.SetParent(env, false);
            outer.transform.localPosition = new Vector3(0f, -0.6f, 0f);
            outer.transform.localScale = new Vector3(r * 5f, 0.25f, r * 5f);
            Util.StripCollider(outer);
            Tint.Add(outer, new Color(0.12f, 0.1f, 0.11f));

            // Decorative inner rings (not hazards).
            Util.Part(PrimitiveType.Cylinder, env, "RuneRing", new Vector3(0f, 0.005f, 0f), new Vector3(r * 1.2f, 0.005f, r * 1.2f), new Color(0.3f, 0.27f, 0.27f));
            Util.Part(PrimitiveType.Cylinder, env, "RuneCore", new Vector3(0f, 0.01f, 0f), new Vector3(6f, 0.005f, 6f), new Color(0.35f, 0.2f, 0.15f));

            const int pillars = 16;
            for (int i = 0; i < pillars; i++)
            {
                float a = i * Mathf.PI * 2f / pillars;
                var pos = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)) * (r + 1.5f);
                float hgt = 5f + (i % 3) * 2f;
                Util.Part(PrimitiveType.Cube, env, "Pillar" + i, pos + Vector3.up * hgt * 0.5f, new Vector3(2f, hgt, 2f), new Color(0.33f, 0.3f, 0.3f), true);
                if (i % 4 == 0)
                {
                    var brazier = Util.Part(PrimitiveType.Sphere, env, "Ember" + i, pos + Vector3.up * (hgt + 0.6f), Vector3.one * 0.9f, new Color(1f, 0.5f, 0.15f));
                    var l = new GameObject("EmberLight").AddComponent<Light>();
                    l.transform.SetParent(brazier.transform, false);
                    l.type = LightType.Point;
                    l.color = new Color(1f, 0.55f, 0.25f);
                    l.range = 18f;
                    l.intensity = 1.6f;
                }
            }
        }

        static void BuildLights(Transform root)
        {
            var sun = new GameObject("Directional Light").AddComponent<Light>();
            sun.transform.SetParent(root, false);
            sun.type = LightType.Directional;
            sun.transform.rotation = Quaternion.Euler(52f, -35f, 0f);
            sun.color = new Color(1f, 0.9f, 0.8f);
            sun.intensity = 1.05f;
            sun.shadows = LightShadows.Soft;

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.34f, 0.31f, 0.36f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogColor = new Color(0.09f, 0.07f, 0.09f);
            RenderSettings.fogStartDistance = 45f;
            RenderSettings.fogEndDistance = 140f;
        }
    }
}
