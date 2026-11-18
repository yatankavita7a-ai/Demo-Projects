extends RefCounted

# Player-chosen graphics options, saved to user://settings.cfg (separate
# from the game save, so a settings change never touches progress).
#
#   gi      "off" | "low" | "high"   SDFGI global illumination (+ SSR on high)
#   aa      "fxaa" | "taa" | "fsr2"  anti-aliasing / upscaling
#   grain   bool                     film grain and vignette overlay
#
# Purely visual: gameplay never reads these.

const PATH := "user://settings.cfg"
const SECTION := "graphics"
const GI_LEVELS := ["off", "low", "high"]
const GI_LABELS := ["Off (fastest)", "Low", "High"]
const AA_MODES := ["fxaa", "taa", "fsr2"]
const AA_LABELS := ["MSAA + FXAA", "TAA (smoothest)", "FSR 2 upscaling (faster)"]
const FSR_SCALE := 0.77


static func defaults() -> Dictionary:
	var mobile := OS.has_feature("mobile")
	return {"gi": "off" if mobile else "low", "aa": "fxaa", "grain": not mobile}


static func load_settings() -> Dictionary:
	var settings := defaults()
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return settings
	var gi := String(config.get_value(SECTION, "gi", settings["gi"]))
	var aa := String(config.get_value(SECTION, "aa", settings["aa"]))
	settings["gi"] = gi if gi in GI_LEVELS else settings["gi"]
	settings["aa"] = aa if aa in AA_MODES else settings["aa"]
	settings["grain"] = bool(config.get_value(SECTION, "grain", settings["grain"]))
	return settings


static func save_settings(settings: Dictionary) -> bool:
	var config := ConfigFile.new()
	config.load(PATH)  # keep any other sections
	config.set_value(SECTION, "gi", settings.get("gi", "low"))
	config.set_value(SECTION, "aa", settings.get("aa", "fxaa"))
	config.set_value(SECTION, "grain", bool(settings.get("grain", true)))
	return config.save(PATH) == OK


static func apply_viewport(viewport: Viewport, settings: Dictionary) -> void:
	match String(settings.get("aa", "fxaa")):
		"taa":
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			viewport.use_taa = true
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = 1.0
		"fsr2":
			# FSR 2 renders at a lower resolution and does its own temporal AA.
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			viewport.use_taa = false
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			viewport.scaling_3d_scale = FSR_SCALE
		_:
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			viewport.use_taa = false
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = 1.0


# Off keeps the original screen-space lighting (SSAO + SSIL). Low adds SDFGI
# at half resolution in place of SSIL; High runs it at full resolution with
# more cascades, SSIL on top and screen-space reflections.
static func apply_environment(environment: Environment, settings: Dictionary) -> void:
	var gi := String(settings.get("gi", "low"))
	environment.sdfgi_enabled = gi != "off"
	environment.ssil_enabled = gi != "low"
	environment.ssr_enabled = gi == "high"
	if gi == "off":
		return
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_read_sky_light = true
	environment.sdfgi_bounce_feedback = 0.4
	environment.sdfgi_energy = 0.9
	environment.volumetric_fog_gi_inject = 0.6
	if gi == "high":
		environment.sdfgi_cascades = 6
		environment.sdfgi_min_cell_size = 0.2
		RenderingServer.gi_set_use_half_resolution(false)
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_32)
	else:
		environment.sdfgi_cascades = 4
		environment.sdfgi_min_cell_size = 0.3
		RenderingServer.gi_set_use_half_resolution(true)
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_16)
