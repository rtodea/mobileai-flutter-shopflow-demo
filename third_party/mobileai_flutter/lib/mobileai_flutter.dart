// Components / widgets
export 'src/widgets/ai_agent.dart';
export 'src/widgets/ai_zone.dart';
export 'src/widgets/ai_approval_dialog.dart';
export 'src/widgets/ai_consent_dialog.dart';
export 'src/widgets/agent_chat_bar.dart';
export 'src/widgets/agent_overlay.dart';
export 'src/widgets/rich_content_renderer.dart';
export 'src/widgets/rich_blocks.dart';
export 'src/widgets/highlight_overlay.dart';

// Core
export 'src/core/types.dart';
export 'src/core/agent_runtime.dart';
export 'src/core/action_registry.dart';
export 'src/core/data_registry.dart';
export 'src/core/block_registry.dart';
export 'src/core/zone_registry.dart';
export 'src/core/action_bridge.dart';
export 'src/core/flutter_platform_adapter.dart';
export 'src/core/verifier.dart';
export 'src/core/default_action_safety_classifier.dart';

// Navigation
export 'src/navigation/flutter_router_adapter.dart';
export 'src/navigation/go_router_adapter.dart';
export 'src/navigation/navigator_router_adapter.dart';

// Providers
export 'src/providers/gemini_provider.dart';
export 'src/providers/openai_provider.dart';
export 'src/providers/provider_factory.dart';

// Hooks / registration widgets
export 'src/hooks/ai_action.dart';
export 'src/hooks/ai_data.dart';
export 'src/hooks/ai_scope.dart';

// Services
export 'src/services/knowledge_base_service.dart';
export 'src/services/conversation_service.dart';
export 'src/services/mobileai_knowledge_retriever.dart';
export 'src/services/voice_service.dart';
export 'src/services/audio_input_service.dart';
export 'src/services/audio_output_service.dart';
export 'src/services/telemetry/index.dart';

// Support
export 'src/support/index.dart';

// Theme
export 'src/theme/rich_ui_theme.dart';

// Tools
export 'src/tools/types.dart';
export 'src/tools/tap_tool.dart';
export 'src/tools/type_tool.dart';
export 'src/tools/scroll_tool.dart';
export 'src/tools/keyboard_tool.dart';
export 'src/tools/long_press_tool.dart';
export 'src/tools/slider_tool.dart';
export 'src/tools/picker_tool.dart';
export 'src/tools/guide_tool.dart';
export 'src/tools/date_picker_tool.dart';
export 'src/tools/knowledge_tool.dart';

// Utilities
export 'src/utils/logger.dart';
