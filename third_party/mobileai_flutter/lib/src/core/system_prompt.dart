library;

import 'rn_prompt_bundle.g.dart';

String buildSystemPrompt(
  String language, {
  bool hasKnowledge = false,
  bool isCopilot = true,
  String supportStyle = 'warm-concise',
  String? userInstructions,
}) {
  final key = _textPromptKey(
    language: language,
    hasKnowledge: hasKnowledge,
    isCopilot: isCopilot,
    supportStyle: supportStyle,
  );
  final prompt =
      RnPromptBundle.textPrompts[key] ??
      RnPromptBundle.textPrompts[_textPromptKey(
        language: 'en',
        hasKnowledge: hasKnowledge,
        isCopilot: isCopilot,
        supportStyle: 'warm-concise',
      )]!;
  return _appendAppInstructions(
    _appendRuntimeBehaviorGuidance(prompt),
    userInstructions,
  );
}

String buildKnowledgeOnlyPrompt(
  String language, {
  bool hasKnowledge = false,
  String? userInstructions,
}) {
  final key = _knowledgePromptKey(
    language: language,
    hasKnowledge: hasKnowledge,
  );
  final prompt =
      RnPromptBundle.knowledgePrompts[key] ??
      RnPromptBundle.knowledgePrompts[_knowledgePromptKey(
        language: 'en',
        hasKnowledge: hasKnowledge,
      )]!;
  return _appendAppInstructions(prompt, userInstructions);
}

String buildCompanionPrompt(
  String language, {
  bool hasKnowledge = false,
  String? userInstructions,
}) {
  final isArabic = _normalizeLanguage(language) == 'ar';
  final knowledgeToolLine = hasKnowledge
      ? '\n- query_knowledge(question): Search the app knowledge base for policies, FAQs, product details, order rules, or other business information when the answer is not visible on screen.'
      : '';
  final prompt = isArabic
      ? '''
<role>
أنت مساعد مرافق داخل تطبيق Flutter. يمكنك قراءة الشاشة الحالية ومساعدة المستخدم على فهم ما يراه وما يجب فعله بعد ذلك، لكنك لا تتحكم في واجهة التطبيق.
</role>

<capabilities>
- أجب من محتوى الشاشة المرئي عندما يكون كافيا.
- اشرح الحالات المربكة واقترح الخطوة الأكثر أمانا.
- استخدم query_data لمصادر البيانات المسجلة داخل التطبيق.
$knowledgeToolLine
- استخدم أدوات الدعم أو الإبلاغ غير المتعلقة بالواجهة إذا كانت متاحة ومفيدة.
</capabilities>

<limits>
لا يمكنك النقر أو الكتابة أو التمرير أو التنقل أو اختيار عناصر أو إرسال نماذج أو تعديل مناطق الواجهة. إذا طلب منك المستخدم تنفيذ إجراء، ارشده للقيام به بنفسه.
</limits>

<tone>
كن مختصرا وعمليا. لا تحول كل إجابة إلى تعليمات تنقل. اشرح السبب عندما يساعد المستخدم على اتخاذ قرار.
</tone>
'''
      : '''
<role>
You are a screen-aware companion inside a Flutter app. You can read the current screen and help the user understand what they see and what to do next, but you do not control the app UI.
</role>

<capabilities>
- Answer from visible screen content when that is enough.
- Explain confusing UI states and suggest the safest next step.
- Use query_data for app-registered live data sources.
$knowledgeToolLine
- Use available non-UI support, reporting, or diagnostic tools when they help.
</capabilities>

<limits>
You cannot tap, type, scroll, navigate, select controls, submit forms, highlight elements, render blocks, simplify zones, or otherwise operate the app. If the user asks you to perform an action, guide them through doing it themselves.
</limits>

<tone>
Be concise, calm, and practical. Do not reduce every answer to navigation steps. Explain the useful "why" behind a step when it helps the user decide.
</tone>
''';

  return _appendAppInstructions(
    _appendRuntimeBehaviorGuidance(prompt),
    userInstructions,
  );
}

String buildVoiceSystemPrompt(
  String language, {
  bool hasKnowledge = false,
  String supportStyle = 'warm-concise',
  String? userInstructions,
}) {
  final key = _voicePromptKey(
    language: language,
    hasKnowledge: hasKnowledge,
    supportStyle: supportStyle,
  );
  final prompt =
      RnPromptBundle.voicePrompts[key] ??
      RnPromptBundle.voicePrompts[_voicePromptKey(
        language: 'en',
        hasKnowledge: hasKnowledge,
        supportStyle: 'warm-concise',
      )]!;
  final guardedPrompt = _normalizeLanguage(language) == 'ar'
      ? prompt
      : '$prompt\n\n<voice_language_guard>\nSpeak English unless the user explicitly asks you to use another language. If input transcription looks like noise, punctuation, unrelated non-English fragments, or incomplete one-word fragments like "go", "oh", "um", "hi", or "yes", do not act and do not speak; wait silently for the user to finish or repeat a clear English command.\n</voice_language_guard>';
  return _appendAppInstructions(
    _appendRuntimeBehaviorGuidance(guardedPrompt),
    userInstructions,
  );
}

String _textPromptKey({
  required String language,
  required bool hasKnowledge,
  required bool isCopilot,
  required String supportStyle,
}) {
  return '${_normalizeLanguage(language)}|${hasKnowledge ? '1' : '0'}|${isCopilot ? '1' : '0'}|${_normalizeSupportStyle(supportStyle)}';
}

String _voicePromptKey({
  required String language,
  required bool hasKnowledge,
  required String supportStyle,
}) {
  return '${_normalizeLanguage(language)}|${hasKnowledge ? '1' : '0'}|${_normalizeSupportStyle(supportStyle)}';
}

String _knowledgePromptKey({
  required String language,
  required bool hasKnowledge,
}) {
  return '${_normalizeLanguage(language)}|${hasKnowledge ? '1' : '0'}';
}

String _normalizeLanguage(String language) {
  return language.trim().toLowerCase() == 'ar' ? 'ar' : 'en';
}

String _normalizeSupportStyle(String supportStyle) {
  const known = <String>{'warm-concise', 'wow-service', 'neutral-professional'};
  final normalized = supportStyle.trim();
  return known.contains(normalized) ? normalized : 'warm-concise';
}

String _appendAppInstructions(String prompt, String? userInstructions) {
  final instructions = userInstructions?.trim();
  if (instructions == null || instructions.isEmpty) {
    return prompt;
  }
  return '$prompt\n\n<app_instructions>\n$instructions\n</app_instructions>';
}

String _appendRuntimeBehaviorGuidance(String prompt) {
  if (prompt.contains('STALE_TARGET') ||
      prompt.contains('<runtime_behavior>')) {
    return prompt;
  }
  return '$prompt\n\n<runtime_behavior>\nIf a UI action result contains STALE_TARGET, the screen changed after you observed it. Do not retry the old index. Read the current screen state again and choose a target from the latest indexes, or ask the user if the target is no longer clear.\n</runtime_behavior>';
}
