using System.Collections.Generic;
using UnityEngine;

namespace BossPrototype
{
    /// <summary>Builds flat, vertex-coloured ground meshes for telegraphs and shockwaves (local XZ, +Z forward).</summary>
    public static class ShapeMesh
    {
        static readonly List<Vector3> verts = new List<Vector3>();
        static readonly List<Color> cols = new List<Color>();
        static readonly List<int> tris = new List<int>();

        static void Begin() { verts.Clear(); cols.Clear(); tris.Clear(); }

        static void End(Mesh m)
        {
            m.Clear();
            m.SetVertices(verts);
            m.SetColors(cols);
            m.SetTriangles(tris, 0);
            m.RecalculateBounds();
        }

        public static void Fan(Mesh m, float radius, float angleDeg, Color c, int segments = 40)
        {
            Begin();
            verts.Add(Vector3.zero); cols.Add(c);
            float half = angleDeg * 0.5f;
            for (int i = 0; i <= segments; i++)
            {
                float a = Mathf.Lerp(-half, half, (float)i / segments) * Mathf.Deg2Rad;
                verts.Add(new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)) * radius);
                cols.Add(c);
                if (i > 0) { tris.Add(0); tris.Add(i); tris.Add(i + 1); }
            }
            End(m);
        }

        public static void Disc(Mesh m, float radius, Color c) { Fan(m, radius, 360f, c, 48); }

        public static void Annulus(Mesh m, float inner, float outer, Color c, float wallHeight = 0f, int segments = 64)
        {
            Begin();
            inner = Mathf.Max(0f, inner);
            for (int i = 0; i <= segments; i++)
            {
                float a = (float)i / segments * Mathf.PI * 2f;
                var dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a));
                verts.Add(dir * inner); cols.Add(c);
                verts.Add(dir * outer); cols.Add(c);
                if (i > 0)
                {
                    int b = i * 2;
                    tris.Add(b - 2); tris.Add(b + 1); tris.Add(b - 1);
                    tris.Add(b - 2); tris.Add(b); tris.Add(b + 1);
                }
            }
            if (wallHeight > 0f)
            {
                int start = verts.Count;
                float mid = (inner + outer) * 0.5f;
                var top = new Color(c.r, c.g, c.b, 0f);
                for (int i = 0; i <= segments; i++)
                {
                    float a = (float)i / segments * Mathf.PI * 2f;
                    var dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a));
                    verts.Add(dir * mid); cols.Add(c);
                    verts.Add(dir * mid + Vector3.up * wallHeight); cols.Add(top);
                    if (i > 0)
                    {
                        int b = start + i * 2;
                        tris.Add(b - 2); tris.Add(b - 1); tris.Add(b + 1);
                        tris.Add(b - 2); tris.Add(b + 1); tris.Add(b);
                    }
                }
            }
            End(m);
        }

        /// <summary>Rectangle from z = 0 to z = length, centred on x.</summary>
        public static void Rect(Mesh m, float length, float width, Color c)
        {
            Begin();
            float w = width * 0.5f;
            verts.Add(new Vector3(-w, 0f, 0f)); verts.Add(new Vector3(w, 0f, 0f));
            verts.Add(new Vector3(w, 0f, length)); verts.Add(new Vector3(-w, 0f, length));
            for (int i = 0; i < 4; i++) cols.Add(c);
            tris.Add(0); tris.Add(2); tris.Add(1);
            tris.Add(0); tris.Add(3); tris.Add(2);
            End(m);
        }

        /// <summary>Area of an attack shape, scaled by fill (0..1).</summary>
        public static void Shape(Mesh m, AttackShape shape, Vector2 size, float fill, Color c)
        {
            fill = Mathf.Clamp01(fill);
            switch (shape)
            {
                case AttackShape.Cone: Fan(m, size.x * fill, size.y, c); break;
                case AttackShape.Circle: Disc(m, size.x * fill, c); break;
                case AttackShape.Ring: Disc(m, size.x * fill, c); break;
                case AttackShape.Line:
                case AttackShape.Box: Rect(m, size.x * fill, size.y, c); break;
            }
        }
    }
}
