#include "include/taudio/taudio_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "taudio_plugin.h"

void TaudioPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  taudio::TaudioPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

// Bridge: flutter_sound's pubspec declares pluginClass FlutterSoundPluginCApi,
// so Flutter's generated registrant calls this symbol. Forward it to taudio.
#include "include/flutter_sound/flutter_sound_plugin_c_api.h"

void FlutterSoundPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  taudio::TaudioPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
