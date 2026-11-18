using UnityEngine;

namespace BossPrototype
{
    /// <summary>Straight-flying bolt aimed at where the player was when it was fired.</summary>
    public class BossProjectile : MonoBehaviour
    {
        Vector3 velocity;
        float life = 4f;
        HitInfo hit;
        bool dodged;
        const float HitRadius = 0.45f;

        public static BossProjectile Spawn(Transform parent, Vector3 from, Vector3 target, float speed, HitInfo hit, Color color)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            go.name = "BossProjectile";
            Util.StripCollider(go);
            go.transform.SetParent(parent, false);
            go.transform.position = from;
            go.transform.localScale = Vector3.one * 0.55f;
            var r = go.GetComponent<Renderer>();
            r.sharedMaterial = MaterialFactory.Lit(color);
            var p = go.AddComponent<BossProjectile>();
            Vector3 dir = target - from;
            dir.y *= 0.5f;
            if (dir.sqrMagnitude < 0.01f) dir = Vector3.forward;
            p.velocity = dir.normalized * speed;
            p.hit = hit;
            return p;
        }

        void Update()
        {
            float dt = Time.deltaTime;
            transform.position += velocity * dt;
            if (transform.position.y < 0.4f) transform.position = new Vector3(transform.position.x, 0.4f, transform.position.z);
            life -= dt;

            var player = PlayerController.Instance;
            var boss = BossController.Instance;
            if (!dodged && player != null && player.IsAlive && (boss == null || !boss.IsHarmless))
            {
                Vector3 d = player.Center - transform.position;
                if (Mathf.Abs(d.y) < 1.2f && CombatMath.Flat(d).magnitude <= HitRadius + PlayerController.Radius)
                {
                    hit.sourcePosition = transform.position - velocity.normalized;
                    var result = player.ReceiveHit(hit);
                    if (result == HitResult.Dodged || result == HitResult.PerfectDodge) dodged = true;
                    else
                    {
                        Destroy(gameObject);
                        return;
                    }
                }
            }
            if (life <= 0f || transform.position.magnitude > 80f) Destroy(gameObject);
        }
    }
}
