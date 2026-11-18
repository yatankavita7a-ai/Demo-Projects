using System.IO;
using BossPrototype;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

/// <summary>
/// Builds Assets/Scenes/BossArena.unity from code and adds it to Build Settings.
/// Menu: Boss Prototype > Build Arena Scene. Batch: -executeMethod ArenaSceneBuilder.Build
/// </summary>
public static class ArenaSceneBuilder
{
    public const string ScenePath = "Assets/Scenes/BossArena.unity";

    [MenuItem("Boss Prototype/Build Arena Scene")]
    public static void Build()
    {
        Directory.CreateDirectory("Assets/Scenes");
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        ArenaFactory.Build(0);
        if (!EditorSceneManager.SaveScene(scene, ScenePath))
            throw new System.Exception("[ArenaSceneBuilder] Failed to save " + ScenePath);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        AssetDatabase.SaveAssets();
        Debug.Log("[ArenaSceneBuilder] Saved " + ScenePath + " and added it to Build Settings.");
    }
}
