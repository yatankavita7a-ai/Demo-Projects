using UnityEngine;

namespace BossPrototype
{
    /// <summary>
    /// Ground marker sized to an attack's shape. A faint full-size area plus a brighter fill that grows
    /// over the windup; coloured orange / yellow / red by attack type.
    /// </summary>
    public class Telegraph : MonoBehaviour
    {
        AttackShape shape;
        Vector2 size;
        Color color;
        Mesh areaMesh, fillMesh;
        float lastFill = -1f;

        public static Telegraph Create(Transform parent, AttackShape shape, Vector2 size, AttackColor attackColor)
        {
            var go = new GameObject("Telegraph");
            go.transform.SetParent(parent, false);
            var t = go.AddComponent<Telegraph>();
            t.Init(shape, size, Util.AttackColorValue(attackColor));
            return t;
        }

        void Init(AttackShape s, Vector2 sz, Color c)
        {
            shape = s; size = sz; color = c;
            areaMesh = new Mesh { name = "TelegraphArea" };
            fillMesh = new Mesh { name = "TelegraphFill" };
            MakeLayer("Area", areaMesh, 0.02f);
            MakeLayer("Fill", fillMesh, 0.035f);

            var faint = new Color(c.r, c.g, c.b, 0.18f);
            if (shape == AttackShape.Ring)
            {
                // Ring: highlight the band at the outer edge, which is what you roll through.
                ShapeMesh.Annulus(areaMesh, size.x - size.y, size.x, new Color(c.r, c.g, c.b, 0.45f));
            }
            else
            {
                ShapeMesh.Shape(areaMesh, shape, size, 1f, faint);
            }
            SetFill(0f);
        }

        void MakeLayer(string n, Mesh mesh, float y)
        {
            var go = new GameObject(n);
            go.transform.SetParent(transform, false);
            go.transform.localPosition = new Vector3(0f, y, 0f);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = MaterialFactory.Transparent();
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
        }

        public void SetPose(Vector3 origin, Vector3 forward)
        {
            origin.y = 0f;
            transform.position = origin;
            forward.y = 0f;
            if (forward.sqrMagnitude > 0.0001f) transform.rotation = Quaternion.LookRotation(forward);
        }

        public void SetFill(float f)
        {
            f = Mathf.Clamp01(f);
            if (Mathf.Abs(f - lastFill) < 0.004f) return;
            lastFill = f;
            float pulse = f >= 0.999f ? 0.75f : 0.38f + 0.2f * f;
            ShapeMesh.Shape(fillMesh, shape, size, f, new Color(color.r, color.g, color.b, pulse));
        }

        void OnDestroy()
        {
            if (areaMesh != null) Destroy(areaMesh);
            if (fillMesh != null) Destroy(fillMesh);
        }
    }
}
