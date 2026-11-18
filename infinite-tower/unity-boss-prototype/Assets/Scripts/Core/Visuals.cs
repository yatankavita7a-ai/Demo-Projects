using System.Collections.Generic;
using UnityEngine;

namespace BossPrototype
{
    /// <summary>Procedural materials (built-in render pipeline). No asset files needed.</summary>
    public static class MaterialFactory
    {
        static readonly Dictionary<Color, Material> litCache = new Dictionary<Color, Material>();
        static Material transparent;

        static Shader LitShader()
        {
            Shader s = Shader.Find("Standard");
            if (s == null) s = Shader.Find("Legacy Shaders/Diffuse");
            if (s == null) s = Shader.Find("Unlit/Color");
            return s;
        }

        /// <summary>Shared lit material for a colour.</summary>
        public static Material Lit(Color c)
        {
            if (litCache.TryGetValue(c, out Material m) && m != null) return m;
            m = NewLit(c);
            litCache[c] = m;
            return m;
        }

        /// <summary>Unshared lit material (for per-object flashing).</summary>
        public static Material NewLit(Color c)
        {
            var m = new Material(LitShader()) { color = c };
            if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", 0.25f);
            return m;
        }

        /// <summary>Unlit, alpha-blended, vertex-coloured, double-sided (Sprites/Default is always available).</summary>
        public static Material Transparent()
        {
            if (transparent != null) return transparent;
            Shader s = Shader.Find("Sprites/Default");
            if (s == null) s = Shader.Find("Unlit/Transparent");
            transparent = new Material(s) { color = Color.white };
            transparent.renderQueue = 3000;
            return transparent;
        }
    }

    public static class Util
    {
        public static void SafeDestroy(Object o)
        {
            if (o == null) return;
            if (Application.isPlaying) Object.Destroy(o);
            else Object.DestroyImmediate(o);
        }

        public static void StripCollider(GameObject go)
        {
            var c = go.GetComponent<Collider>();
            if (c != null) SafeDestroy(c);
        }

        /// <summary>Primitive child without a collider.</summary>
        public static GameObject Part(PrimitiveType type, Transform parent, string name, Vector3 localPos, Vector3 localScale, Color color, bool keepCollider = false)
        {
            var go = GameObject.CreatePrimitive(type);
            go.name = name;
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            go.transform.localScale = localScale;
            if (!keepCollider) StripCollider(go);
            Tint.Add(go, color);
            return go;
        }

        public static Color AttackColorValue(AttackColor c)
        {
            switch (c)
            {
                case AttackColor.Parryable: return new Color(1f, 0.88f, 0.15f);
                case AttackColor.Unblockable: return new Color(1f, 0.12f, 0.1f);
                default: return new Color(1f, 0.52f, 0.08f);
            }
        }
    }
}
