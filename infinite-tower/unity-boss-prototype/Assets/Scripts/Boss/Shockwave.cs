using UnityEngine;

namespace BossPrototype
{
    /// <summary>Expanding ring. Roll through its edge (i-frames) or be outside the band when it passes.</summary>
    public class Shockwave : MonoBehaviour
    {
        float radius;
        float maxRadius;
        float thickness;
        float speed;
        HitInfo hit;
        bool hasHit;
        Mesh mesh;
        Color color;

        public static Shockwave Spawn(Transform parent, Vector3 center, float maxRadius, float thickness, float speed, HitInfo hit, float startRadius = 0.5f)
        {
            var go = new GameObject("Shockwave");
            go.transform.SetParent(parent, false);
            center.y = 0.05f;
            go.transform.position = center;
            var s = go.AddComponent<Shockwave>();
            s.maxRadius = maxRadius;
            s.thickness = Mathf.Max(0.4f, thickness);
            s.speed = Mathf.Max(1f, speed);
            s.hit = hit;
            s.radius = Mathf.Max(0.5f, startRadius);
            s.color = Util.AttackColorValue(hit.color);
            s.mesh = new Mesh { name = "Shockwave" };
            go.AddComponent<MeshFilter>().sharedMesh = s.mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = MaterialFactory.Transparent();
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            return s;
        }

        void Update()
        {
            radius += speed * Time.deltaTime;
            float u = Mathf.Clamp01(radius / maxRadius);
            var c = new Color(color.r, color.g, color.b, Mathf.Lerp(0.85f, 0.35f, u));
            ShapeMesh.Annulus(mesh, radius - thickness * 0.5f, radius + thickness * 0.5f, c, 0.9f);

            var player = PlayerController.Instance;
            var boss = BossController.Instance;
            bool harmless = boss != null && boss.IsHarmless;
            if (!hasHit && !harmless && player != null && player.IsAlive && player.transform.position.y < 1.2f)
            {
                if (CombatMath.PointOnRing(transform.position, radius, thickness, player.transform.position, PlayerController.Radius))
                {
                    hit.sourcePosition = transform.position;
                    player.ReceiveHit(hit);
                    hasHit = true; // hit, blocked or dodged: the ring has passed you either way
                }
            }
            if (radius > maxRadius) Destroy(gameObject);
        }

        void OnDestroy() { if (mesh != null) Destroy(mesh); }
    }
}
