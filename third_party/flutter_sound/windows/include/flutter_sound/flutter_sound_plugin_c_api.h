#ifndef FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

// Flutter's generated plugin registrant expects this symbol because
// flutter_sound's pubspec declares `windows.pluginClass: FlutterSoundPluginCApi`,
// but the plugin's implementation is named `taudio`. This header + the bridge in
// taudio_plugin_c_api.cpp reconcile the two names.
FLUTTER_PLUGIN_EXPORT void FlutterSoundPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_C_API_H_
