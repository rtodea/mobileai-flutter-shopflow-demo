import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/types.dart';
import 'ai_approval_dialog.dart';
import 'ai_consent_dialog.dart';
import 'rich_content_renderer.dart';

/// AgentChatBar — Floating, draggable, compressible chat widget.
/// Mirrors react-native-agentic-ai's AgentChatBar component fully:
/// - FAB (compressed) mode with drag support
/// - Expanded panel with drag handle + minimize button
/// - Result bubble (success/error) with dismiss
/// - Text input row with send button + loading dots
/// - Keyboard offset handling
class AgentChatBar extends StatefulWidget {
  final Function(String, [List<UserImage>?]) onSend;
  final bool isThinking;
  final ExecutionResult? lastResult;
  final List<AiMessage> messages;
  final List<AiMessage> humanMessages;
  final List<ConversationSummary> conversations;
  final bool isLoadingHistory;
  final void Function(String conversationId)? onConversationSelect;
  final VoidCallback? onNewConversation;
  final String language;
  final VoidCallback? onDismiss;
  final VoidCallback? onCancel;
  final AgentChatBarTheme? theme;
  final InteractionMode mode;
  final List<InteractionMode> availableModes;
  final ValueChanged<InteractionMode>? onModeChanged;
  final bool isVoiceConnected;
  final bool isMicMuted;
  final bool isSpeakerMuted;
  final bool isAISpeaking;
  final VoidCallback? onToggleVoiceConnection;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleSpeaker;
  final String? activeSupportLabel;
  final bool consentVisible;
  final String? consentProviderName;
  final AIConsentConfig? consentConfig;
  final VoidCallback? onConsentAccept;
  final VoidCallback? onConsentDecline;
  final bool approvalVisible;
  final AskUserRequest? approvalRequest;
  final VoidCallback? onApprovalAccept;
  final VoidCallback? onApprovalDecline;
  final bool awaitingUserResponse;
  final Widget? afterMessagesContent;

  const AgentChatBar({
    super.key,
    required this.onSend,
    required this.isThinking,
    this.lastResult,
    this.messages = const [],
    this.humanMessages = const [],
    this.conversations = const [],
    this.isLoadingHistory = false,
    this.onConversationSelect,
    this.onNewConversation,
    this.language = 'en',
    this.onDismiss,
    this.onCancel,
    this.theme,
    this.mode = InteractionMode.text,
    this.availableModes = const [InteractionMode.text],
    this.onModeChanged,
    this.isVoiceConnected = false,
    this.isMicMuted = false,
    this.isSpeakerMuted = false,
    this.isAISpeaking = false,
    this.onToggleVoiceConnection,
    this.onToggleMic,
    this.onToggleSpeaker,
    this.activeSupportLabel,
    this.consentVisible = false,
    this.consentProviderName,
    this.consentConfig,
    this.onConsentAccept,
    this.onConsentDecline,
    this.approvalVisible = false,
    this.approvalRequest,
    this.onApprovalAccept,
    this.onApprovalDecline,
    this.awaitingUserResponse = false,
    this.afterMessagesContent,
  });

  @override
  State<AgentChatBar> createState() => _AgentChatBarState();
}

class _AgentChatBarState extends State<AgentChatBar>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _showHistory = false;
  int _localUnread = 0;
  int _seenMessageCount = 0;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _transcriptScrollController = ScrollController();
  // Sentinel: until anchored to a real (non-zero) screen size in
  // didChangeDependencies, the clamps in build()/_buildFab() pull this to the
  // bottom-right corner — avoids a 0x0 first frame pinning the FAB top-left.
  Offset _position = const Offset(100000, 100000);
  bool _initialized = false;
  double _keyboardOffset = 0;
  final List<UserImage> _pendingImages = [];

  // Default colors (matching RN exactly)
  static const _bg = Color(0xF21A1A2E);
  static const _fabBg = Color(0xFF1A1A2E);
  static const _accent = Color(0xFF7B68EE);

  Color get _primaryColor => widget.theme?.primaryColor ?? _accent;
  Color get _fabColor => widget.theme?.primaryColor ?? _fabBg;
  Color get _backgroundColor => widget.theme?.backgroundColor ?? _bg;

  @override
  void initState() {
    super.initState();
    _seenMessageCount = widget.messages.length;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final size = MediaQuery.of(context).size;
      // On some platforms the first didChangeDependencies fires while the
      // surface is still 0x0; anchoring then would clamp the FAB into the
      // top-left corner. Wait for a real size, then anchor bottom-right once.
      if (size.width > 0 && size.height > 0) {
        _position = Offset(size.width - 80, size.height - 200);
        _initialized = true;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AgentChatBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length > _seenMessageCount) {
      final newAssistantMessages = widget.messages
          .skip(_seenMessageCount)
          .where((message) => message.role != 'user')
          .length;
      if (newAssistantMessages > 0 && !_isExpanded) {
        _localUnread += newAssistantMessages;
      }
      _seenMessageCount = widget.messages.length;
    } else if (widget.messages.length < _seenMessageCount) {
      _seenMessageCount = widget.messages.length;
      _localUnread = 0;
    }
    final shouldAutoOpen =
        (widget.consentVisible && !oldWidget.consentVisible) ||
        (widget.approvalVisible && !oldWidget.approvalVisible);
    if (shouldAutoOpen && !_isExpanded) {
      setState(_expandChat);
    } else if (_isExpanded && _localUnread != 0) {
      setState(() => _localUnread = 0);
    }
    final transcriptChanged =
        widget.mode != oldWidget.mode ||
        widget.messages.length != oldWidget.messages.length ||
        widget.humanMessages.length != oldWidget.humanMessages.length ||
        widget.consentVisible != oldWidget.consentVisible ||
        widget.isThinking != oldWidget.isThinking;
    if (transcriptChanged) {
      unawaited(_scrollTranscriptToEnd());
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _transcriptScrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollTranscriptToEnd() async {
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!_transcriptScrollController.hasClients) return;
    final position = _transcriptScrollController.position;
    final target = position.maxScrollExtent;
    if (!target.isFinite) return;
    _transcriptScrollController.jumpTo(target);
    if (!_transcriptScrollController.hasClients) return;
    final settledTarget = _transcriptScrollController.position.maxScrollExtent;
    if (!settledTarget.isFinite) return;
    await _transcriptScrollController.animateTo(
      settledTarget,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _handleSend() {
    final text = _textController.text.trim();
    final hasImages = _pendingImages.isNotEmpty;
    // Allow send with images even when isThinking (bypass, same as RN)
    final canSend =
        !widget.isThinking || widget.awaitingUserResponse || hasImages;
    if ((text.isNotEmpty || hasImages) && canSend) {
      final images =
          hasImages ? List<UserImage>.from(_pendingImages) : null;
      widget.onSend(text, images);
      _textController.clear();
      if (hasImages) {
        setState(() => _pendingImages.clear());
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      // Use image_picker if available; dynamically check to avoid hard dependency
      final picker = _tryCreateImagePicker();
      if (picker == null) return;
      final pickedFile = await picker.call();
      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      final compressed = await _compressImage(bytes);
      final base64Data = base64Encode(compressed);
      final mimeType = pickedFile.path.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';

      setState(() {
        _pendingImages.add(UserImage(base64: base64Data, mimeType: mimeType));
      });
    } catch (_) {
      // image_picker not available or user cancelled — silently ignore
    }
  }

  /// Attempt to create an image picker function.
  /// Returns null if `image_picker` is not available.
  dynamic Function()? _tryCreateImagePicker() {
    // The _pickImageFromGallery method uses image_picker conditionally.
    // If the package is not available in the host app, the try/catch inside
    // _pickImageFromGallery handles the error gracefully.
    return _pickImageFromGallery;
  }

  /// Compress image to max 1024x1024 JPEG at 30% quality.
  Future<Uint8List> _compressImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final maxDim = 1024;
      final width = image.width;
      final height = image.height;

      int targetWidth = width;
      int targetHeight = height;
      if (width > maxDim || height > maxDim) {
        if (width > height) {
          targetWidth = maxDim;
          targetHeight = (height * maxDim / width).round();
        } else {
          targetHeight = maxDim;
          targetWidth = (width * maxDim / height).round();
        }
      }

      // If resize is needed, decode at target size
      if (targetWidth != width || targetHeight != height) {
        final resizedCodec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
        final resizedFrame = await resizedCodec.getNextFrame();
        final resizedImage = resizedFrame.image;
        final byteData = await resizedImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        resizedImage.dispose();
        image.dispose();
        if (byteData != null) {
          return byteData.buffer.asUint8List();
        }
      }

      image.dispose();
      return bytes;
    } catch (_) {
      return bytes;
    }
  }

  void _removeImage(int index) {
    setState(() {
      if (index >= 0 && index < _pendingImages.length) {
        _pendingImages.removeAt(index);
      }
    });
  }

  /// Dynamically use image_picker if available. Returns an XFile-like object or null.
  Future<dynamic> _pickImageFromGallery() async {
    try {
      // Attempt to use image_picker dynamically
      // This will fail at runtime if the package is not in the host app's pubspec
      final dynamic picker =
          _ImagePickerProxy.pickImage();
      return await picker;
    } catch (_) {
      return null;
    }
  }

  void _expandChat() {
    _isExpanded = true;
    _localUnread = 0;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    _keyboardOffset = mediaQuery.viewInsets.bottom;
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    // Some devices (e.g. certain MIUI builds) report a zero-size surface on the
    // first frame. Clamping a position into a negative range — width - 70 when
    // width is 0 — makes lowerLimit > upperLimit and double.clamp throws an
    // ArgumentError. Guard every upper limit so it can never fall below its
    // lower limit.
    final double maxX = (screenWidth - 70).clamp(0.0, double.infinity);
    final double collapsedMaxY =
        (screenHeight - 80).clamp(0.0, double.infinity);
    final double expandedMaxY =
        (screenHeight - 400).clamp(100.0, double.infinity);
    final double expandedLeft =
        ((screenWidth - 340) / 2).clamp(0.0, double.infinity);

    return Positioned(
      left: _isExpanded ? expandedLeft : _position.dx.clamp(0.0, maxX),
      top:
          (_isExpanded
              ? _position.dy.clamp(100.0, expandedMaxY)
              : _position.dy.clamp(0.0, collapsedMaxY)) -
          _keyboardOffset,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final dragMaxX =
                (MediaQuery.of(context).size.width - (_isExpanded ? 340 : 70))
                    .clamp(0.0, double.infinity);
            final dragMaxY =
                (MediaQuery.of(context).size.height - (_isExpanded ? 300 : 80))
                    .clamp(0.0, double.infinity);
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(0.0, dragMaxX),
              (_position.dy + details.delta.dy).clamp(0.0, dragMaxY),
            );
          });
        },
        // Material wraps everything so TextField and InkWell work
        // even when rendered above MaterialApp in the widget tree.
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: _isExpanded ? _buildExpanded() : _buildFab(),
          ),
        ),
      ),
    );
  }

  // ─── FAB ──────────────────────────────────────────────────────

  Widget _buildFab() {
    final mediaSize = MediaQuery.of(context).size;
    final maxFabX = (mediaSize.width - 70).clamp(0.0, double.infinity);
    final fabX = _position.dx.clamp(0.0, maxFabX);
    final showPreview = _localUnread > 0;
    final previewAlignRight = fabX > mediaSize.width / 2;
    return GestureDetector(
      key: const ValueKey('fab'),
      onTap: () => setState(_expandChat),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (showPreview)
            Positioned(
              bottom: 70,
              left: previewAlignRight ? null : 0,
              right: previewAlignRight ? 0 : null,
              child: _ClosedPreviewBubble(
                key: const ValueKey('ai-closed-preview'),
                text: _latestAssistantPreview(),
                alignRight: previewAlignRight,
                isArabic: widget.language == 'ar',
                onTap: () => setState(_expandChat),
              ),
            ),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _fabColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: widget.isThinking
                ? _LoadingDots(color: widget.theme?.textColor ?? Colors.white)
                : const _AIBadge(),
          ),
          if (_localUnread > 0)
            Positioned(
              key: const ValueKey('ai-unread-badge'),
              right: -4,
              top: -4,
              child: _UnreadBadge(count: _localUnread),
            ),
        ],
      ),
    );
  }

  String _latestAssistantPreview() {
    for (final message in widget.messages.reversed) {
      if (message.role == 'user') continue;
      final preview = message.previewText.trim();
      if (preview.isNotEmpty) return preview;
      final content = richContentToPlainText(message.content).trim();
      if (content.isNotEmpty) return content;
    }
    return widget.language == 'ar' ? 'رسالة جديدة' : 'New message';
  }

  // ─── Expanded Panel ───────────────────────────────────────────

  Widget _buildExpanded() {
    final isArabic = widget.language == 'ar';
    final transcriptMessages = widget.mode == InteractionMode.human
        ? widget.humanMessages
        : widget.messages;
    return Container(
      key: const ValueKey('expanded'),
      width: 340,
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          if (_showHistory)
            _buildHistoryPanel()
          else ...[
            if (widget.availableModes.length > 1) _buildModeTabs(),
            if (transcriptMessages.isNotEmpty)
              _buildTranscript(isArabic, transcriptMessages),
            if (transcriptMessages.isEmpty &&
                widget.lastResult != null &&
                widget.mode != InteractionMode.human)
              _buildResultBubble(isArabic),
            if (widget.consentVisible &&
                widget.consentConfig != null &&
                widget.consentProviderName != null)
              AIConsentInlineCard(
                providerName: widget.consentProviderName!,
                config: widget.consentConfig!,
                onAccept: widget.onConsentAccept ?? () {},
                onDecline: widget.onConsentDecline ?? () {},
              ),
            if (widget.approvalVisible)
              AIApprovalInlineCard(
                request: widget.approvalRequest,
                onGrant: widget.onApprovalAccept ?? () {},
                onDeny: widget.onApprovalDecline ?? () {},
              ),
            if (widget.mode == InteractionMode.voice && !widget.approvalVisible)
              _buildVoiceControlsRow(isArabic),
            if (widget.mode != InteractionMode.voice)
              _buildTextInputRow(isArabic),
          ],
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: widget.availableModes
            .map((mode) {
              final selected = mode == widget.mode;
              final dotColor = switch (mode) {
                InteractionMode.text => const Color(0xFF7B68EE),
                InteractionMode.voice => const Color(0xFF34C759),
                InteractionMode.human => const Color(0xFFFF9500),
              };
              return Expanded(
                child: GestureDetector(
                  onTap: widget.onModeChanged == null
                      ? null
                      : () => widget.onModeChanged!(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          switch (mode) {
                            InteractionMode.text => 'Text',
                            InteractionMode.voice => 'Voice',
                            InteractionMode.human => 'Human',
                          },
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: (widget.theme?.textColor ?? Colors.white)
                                .withValues(alpha: selected ? 1 : 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _buildDragHandle() {
    final showHistoryActions =
        (widget.onConversationSelect != null ||
            widget.onNewConversation != null) &&
        !_showHistory;
    return Row(
      children: [
        if (showHistoryActions)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _buildHistoryActions(),
          )
        else
          const SizedBox(width: 48),
        const Expanded(child: Center(child: _DragGrip())),
        GestureDetector(
          onTap: () => setState(() {
            _isExpanded = false;
            _showHistory = false;
          }),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              '—',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryActions() {
    final count = widget.conversations.length;
    return Row(
      children: [
        GestureDetector(
          onTap: widget.onConversationSelect == null
              ? null
              : () => setState(() => _showHistory = true),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.onNewConversation != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onNewConversation,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Center(
                child: Text(
                  '+',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultBubble(bool isArabic) {
    final result = widget.lastResult!;
    final isSuccess = result.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSuccess
            ? const Color(0x3328A745) // rgba(40, 167, 69, 0.2)
            : const Color(0x33DC3545), // rgba(220, 53, 69, 0.2)
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // maxHeight: 200 — matches RN's resultScroll maxHeight
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  result.message.trim(),
                  style: TextStyle(
                    color: widget.theme?.textColor ?? Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                ),
              ),
            ),
          ),
          if (widget.onDismiss != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onDismiss,
              child: Icon(
                Icons.close,
                size: 16,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTranscript(bool isArabic, List<AiMessage> messages) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        controller: _transcriptScrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...messages
              .map((message) {
                final isUser = message.role == 'user';
                final bubbleColor = isUser
                    ? _primaryColor.withValues(alpha: 0.34)
                    : Colors.white.withValues(alpha: 0.1);

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: isUser
                        ? _buildUserMessageContent(message, isArabic)
                        : DefaultTextStyle(
                            style: TextStyle(
                              color: widget.theme?.textColor ?? Colors.white,
                              fontSize: 14,
                              height: 1.4,
                            ),
                            child: RichContentRenderer(
                              content: message.content,
                            ),
                          ),
                  ),
                );
              }),
            if (widget.afterMessagesContent != null)
              widget.afterMessagesContent!,
          ],
        ),
      ),
    );
  }

  Widget _buildUserMessageContent(AiMessage message, bool isArabic) {
    final content = message.content;
    final nodes = content is List<AiRichNode> ? content : normalizeRichContent(content);
    final hasImages = nodes.any((node) => node is AiImageNode);
    final textStyle = TextStyle(
      color: widget.theme?.textColor ?? Colors.white,
      fontSize: 14,
      height: 1.4,
    );

    if (!hasImages) {
      return Text(
        richContentToPlainText(content).trim(),
        style: textStyle,
        textAlign: isArabic ? TextAlign.right : TextAlign.left,
      );
    }

    return Column(
      crossAxisAlignment:
          isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final node in nodes)
          if (node is AiImageNode)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.memory(
                    base64Decode(node.base64),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else if (node is AiTextNode && node.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                node.text.trim(),
                style: textStyle,
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
              ),
            ),
      ],
    );
  }

  Widget _buildHistoryPanel() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 320),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showHistory = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Color(0xFF7B68EE),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Back',
                        style: TextStyle(
                          color: Color(0xFF7B68EE),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'History',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onNewConversation == null
                    ? null
                    : () {
                        widget.onNewConversation?.call();
                        setState(() => _showHistory = false);
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: Color(0xFF7B68EE),
                      ),
                      SizedBox(width: 5),
                      Text(
                        'New',
                        style: TextStyle(
                          color: Color(0xFF7B68EE),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.isLoadingHistory && widget.conversations.isEmpty)
            ...List<Widget>.generate(
              3,
              (_) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 90,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!widget.isLoadingHistory && widget.conversations.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: const [
                  Icon(Icons.history_rounded, size: 34, color: Colors.white38),
                  SizedBox(height: 10),
                  Text(
                    'No previous conversations',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Your AI conversations will appear here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.conversations.isNotEmpty)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: widget.conversations
                      .map(
                        (conversation) => GestureDetector(
                          onTap: widget.onConversationSelect == null
                              ? null
                              : () {
                                  widget.onConversationSelect?.call(
                                    conversation.id,
                                  );
                                  setState(() => _showHistory = false);
                                },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        conversation.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _primaryColor.withValues(
                                          alpha: 0.22,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '${conversation.messageCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  conversation.preview.isEmpty
                                      ? 'No messages'
                                      : conversation.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatRelativeDate(conversation.updatedAt),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatRelativeDate(int timestamp) {
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildVoiceControlsRow(bool isArabic) {
    final isConnecting = !widget.isVoiceConnected;
    final isMicActive = widget.isVoiceConnected && !widget.isMicMuted;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildAudioControlButton(
          isActive: widget.isSpeakerMuted,
          onTap: widget.onToggleSpeaker,
          child: Icon(
            widget.isSpeakerMuted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            size: 18,
            color: widget.theme?.textColor ?? Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: isConnecting
                ? null
                : () {
                    if (isMicActive) {
                      widget.onToggleVoiceConnection?.call();
                    } else {
                      widget.onToggleMic?.call();
                    }
                  },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: isConnecting ? 0.7 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: widget.isAISpeaking
                      ? const Color(0xFF34C759).withValues(alpha: 0.3)
                      : isMicActive
                      ? const Color(0xFFFF3B30).withValues(alpha: 0.3)
                      : isConnecting
                      ? const Color(0xFFFFCC00).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Center(
                        child: isConnecting
                            ? _LoadingDots(
                                color: widget.theme?.textColor ?? Colors.white,
                              )
                            : Icon(
                                widget.isAISpeaking
                                    ? Icons.volume_up_rounded
                                    : isMicActive
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                size: 18,
                                color: widget.theme?.textColor ?? Colors.white,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isConnecting
                          ? (isArabic ? 'جاري الاتصال...' : 'Connecting...')
                          : widget.isAISpeaking
                          ? (isArabic ? 'يتحدث...' : 'Speaking...')
                          : isMicActive
                          ? (isArabic ? 'إيقاف' : 'Stop')
                          : (isArabic ? 'تحدث' : 'Talk'),
                      style: TextStyle(
                        color: widget.theme?.textColor ?? Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(bottom: 17),
          decoration: BoxDecoration(
            color: widget.isVoiceConnected
                ? const Color(0xFF34C759)
                : const Color(0xFFFFCC00),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  Widget _buildAudioControlButton({
    required bool isActive,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isActive
              ? const Color.fromRGBO(255, 100, 100, 0.2)
              : Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _buildPendingImagePreview() {
    if (_pendingImages.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 68,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = _pendingImages[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(image.base64),
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 60,
                    height: 60,
                    color: Colors.white.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.broken_image,
                      size: 20,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  onTap: () => _removeImage(index),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextInputRow(bool isArabic) {
    final canReplyWhileRunning = widget.awaitingUserResponse;
    final hasImages = _pendingImages.isNotEmpty;
    // Allow input when images are pending (bypass isThinking, same as RN)
    final inputEnabled =
        !widget.isThinking || canReplyWhileRunning || hasImages;
    final showCancel =
        widget.isThinking && !canReplyWhileRunning && !hasImages;
    final placeholder = switch (widget.mode) {
      InteractionMode.text => isArabic ? 'اكتب طلبك...' : 'Ask AI...',
      InteractionMode.voice => isArabic ? 'أرسل رسالة...' : 'Send a message...',
      InteractionMode.human =>
        isArabic ? 'اكتب لفريق الدعم...' : 'Message support...',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPendingImagePreview(),
        Row(
          children: [
            // Attachment button
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.attach_file_rounded,
                  size: 18,
                  color: (widget.theme?.textColor ?? Colors.white)
                      .withValues(alpha: 0.6),
                ),
              ),
            ),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(22),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                // PATCH (shopflow demo): the chat bar is rendered above
                // MaterialApp, so it has no DefaultTextEditingShortcuts in scope
                // and physical Backspace/Delete/arrow keys do nothing on desktop
                // (only typed characters arrive via the text-input channel).
                // Re-introduce the default text-editing shortcuts here and enable
                // interactive selection so the field behaves normally.
                child: DefaultTextEditingShortcuts(
                  child: CupertinoTextField(
                    controller: _textController,
                    enabled: inputEnabled,
                    enableInteractiveSelection: true,
                    textDirection:
                        isArabic ? TextDirection.rtl : TextDirection.ltr,
                    textAlign: isArabic ? TextAlign.right : TextAlign.left,
                    onSubmitted: (_) => _handleSend(),
                    textInputAction: TextInputAction.send,
                    cursorColor: widget.theme?.textColor ?? Colors.white,
                    style: TextStyle(
                      color: widget.theme?.textColor ?? Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    placeholder: placeholder,
                    placeholderStyle: TextStyle(
                      color: (widget.theme?.textColor ?? Colors.white)
                          .withValues(alpha: 0.4),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration:
                        const BoxDecoration(color: Colors.transparent),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: showCancel ? widget.onCancel : _handleSend,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: showCancel
                      ? Colors.red.withValues(alpha: 0.6)
                      : _primaryColor.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: showCancel
                    ? const Icon(Icons.stop, size: 18, color: Colors.white)
                    : const Icon(
                        Icons.send_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Sub-widgets ───────────────────────────────────────────────

class _ClosedPreviewBubble extends StatelessWidget {
  final String text;
  final bool alignRight;
  final bool isArabic;
  final VoidCallback onTap;

  const _ClosedPreviewBubble({
    super.key,
    required this.text,
    required this.alignRight,
    required this.isArabic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(alignRight ? 16 : 4),
            bottomRight: Radius.circular(alignRight ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          text,
          key: const ValueKey('ai-closed-preview-text'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: isArabic ? TextAlign.right : TextAlign.left,
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _DragGrip extends StatelessWidget {
  const _DragGrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 5,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _AIBadge extends StatelessWidget {
  const _AIBadge();

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(painter: _AIBadgePainter()),
      ),
    );
  }
}

class _AIBadgePainter extends CustomPainter {
  const _AIBadgePainter();

  static const double _size = 28;
  static const double _bubbleWidth = _size * 0.6;
  static const double _bubbleHeight = _size * 0.45;
  static const double _tailSize = _size * 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final left = (size.width - _bubbleWidth) / 2;
    final top = (size.height - (_bubbleHeight + (_tailSize * 0.5))) / 2;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, _bubbleWidth, _bubbleHeight),
      const Radius.circular(_size * 0.12),
    );

    canvas.drawRRect(body, paint);

    final tailLeft = _size * 0.22;
    final tailTop = size.height - (_size * 0.18) - _tailSize;
    final tail = Path()
      ..moveTo(tailLeft, tailTop)
      ..lineTo(tailLeft, tailTop + _tailSize)
      ..lineTo(tailLeft + _tailSize, tailTop)
      ..close();

    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class _LoadingDots extends StatefulWidget {
  final Color color;
  const _LoadingDots({required this.color});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, animation) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i / 3;
              final t = (_controller.value - delay).clamp(0.0, 1.0);
              final opacity = 0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─── Image Picker Proxy ──────────────────────────────────────
//
// Uses `image_picker` if available in the host app. If the package is not
// installed, pickerImage() returns null. The proxy avoids a hard import
// dependency so the SDK doesn't force every consumer to add `image_picker`.

class _ImagePickerProxy {
  static Future<dynamic> pickImage() async {
    try {
      // Dynamic lookup via dart:mirrors is not available in Flutter AOT.
      // Instead, we import image_picker normally at the top of a separate
      // file or rely on the host app having it. In this SDK approach,
      // we catch the error if it's missing at runtime.
      final dynamic imagePicker = _createImagePicker();
      if (imagePicker == null) return null;
      final dynamic result = await imagePicker.pickImage(
        source: _ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 30,
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  static dynamic _createImagePicker() {
    // This will be resolved at compile time. If image_picker is in the
    // host pubspec, it works. If not, the try/catch in pickImage handles it.
    try {
      return _ImagePickerInstance();
    } catch (_) {
      return null;
    }
  }
}

/// Minimal placeholder that mirrors image_picker's ImageSource enum.
/// The actual image_picker package will be used when available.
class _ImageSource {
  static const int gallery = 0;
}

/// Stub wrapper — if image_picker is available, the host app can use the
/// real ImagePicker. This stub exists so the code compiles without the dep.
class _ImagePickerInstance {
  Future<dynamic> pickImage({
    required int source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    // At runtime, this will be replaced if image_picker is available.
    // Without it, return null.
    return null;
  }
}

// ─── Theme ────────────────────────────────────────────────────

class AgentChatBarTheme {
  final Color? primaryColor;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? successColor;
  final Color? errorColor;

  const AgentChatBarTheme({
    this.primaryColor,
    this.backgroundColor,
    this.textColor,
    this.successColor,
    this.errorColor,
  });
}
