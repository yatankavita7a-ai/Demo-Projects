using UnityEngine;

namespace BossPrototype
{
    /// <summary>Lingering hazard: a ground decal that ignites after a short warning and burns for a while.</summary>
    public class FirePool : MonoBehaviour
    {
        public const int MaxActive = 6;
        public static int ActiveCount;

        const float WarnTime = 0.6f;
        const float TickInterval = 0.5f;

        float radius;
        float lifetime;
        float tickDamage;
        float age;
        float tickTimer;
        Mesh mesh;
        Light glow;

        public static FirePool Spawn(Transform parent, Vector3 pos, float radius, float lifetime, float tickDamage)
        {
            if (ActiveCount >= MaxActive) return null; // keep at least half the arena safe
            var go = new GameObject("FirePool");
            go.transform.SetParent(parent, false);
            pos.y = 0.04f;
            go.transform.position = pos;
            var f = go.AddComponent<FirePool>();
            f.radius = radius;
            f.lifetime = lifetime;
            f.tickDamage = tickDamage;
            f.mesh = new Mesh { name = "FirePool" };
            go.AddComponent<MeshFilter>().sharedMesh = f.mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = MaterialFactory.Transparent();
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            return f;
        }

        void OnEnable() { ActiveCount++; }
        void OnDisable() { ActiveCount = Mathf.Max(0, ActiveCount - 1); }

        void Update()
        {
            age += Time.deltaTime;
            bool burning = age >= WarnTime;
            float fade = Mathf.Clamp01((lifetime - age) / 0.8f);
            Color c;
            if (!burning) c = new Color(0.5f, 0.15f, 0.05f, 0.35f * (age / WarnTime));
            else
            {
                float flicker = 0.75f + 0.25f * Mathf.Sin(age * 23f + transform.position.x);
                c = new Color(1f, 0.38f * flicker + 0.1f, 0.05f, 0.7f * fade);
            }
            ShapeMesh.Disc(mesh, radius, c);

            if (burning && glow == null)
            {
                var lgo = new GameObject("Glow");
                lgo.transform.SetParent(transform, false);
                lgo.transform.localPosition = Vector3.up * 1f;
                glow = lgo.AddComponent<Light>();
                glow.type = LightType.Point;
                glow.color = new Color(1f, 0.45f, 0.1f);
                glow.range = radius * 3f;
            }
            if (glow != null) glow.intensity = 2.2f * fade * (0.8f + 0.2f * Mathf.Sin(age * 17f));

            if (burning)
            {
                tickTimer -= Time.deltaTime;
                var player = PlayerController.Instance;
                var boss = BossController.Instance;
                if (tickTimer <= 0f && player != null && player.IsAlive && (boss == null || !boss.IsHarmless)
                    && CombatMath.PointInCircle(transform.position, radius, player.transform.position, PlayerController.Radius))
                {
                    tickTimer = TickInterval;
                    player.ReceiveHit(new HitInfo
                    {
                        damage = tickDamage,
                        color = AttackColor.Unblockable,
                        isHazard = true,
                        sourcePosition = transform.position,
                        source = "Fire pool",
                    });
                }
            }
            if (age >= lifetime) Destroy(gameObject);
        }

        void OnDestroy() { if (mesh != null) Destroy(mesh); }
    }
}
