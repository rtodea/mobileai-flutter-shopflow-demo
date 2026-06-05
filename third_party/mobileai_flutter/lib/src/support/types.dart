// Support Mode — types and configuration for customer support features.
//
// Transforms the AI agent into a customer support assistant with:
// - Custom greeting message
// - Quick reply suggestions
// - Human escalation capability
// - CSAT (Customer Satisfaction) collection after conversation

// ─── Support Style Persona ───────────────────────────────────────

/// Preset support personalities.
enum SupportStyleEnum {
  warmConcise,
  professional,
  empathetic,
  friendly,
  technical,
}

/// Support style type for backward compatibility.
typedef SupportStyle = String;

// ─── Quick Replies ────────────────────────────────────────────────

class QuickReply {
  final String label;
  final String? message;
  final String? icon;

  const QuickReply({
    required this.label,
    this.message,
    this.icon,
  });

  QuickReply copyWith({String? label, String? message, String? icon}) {
    return QuickReply(
      label: label ?? this.label,
      message: message ?? this.message,
      icon: icon ?? this.icon,
    );
  }

  @override
  String toString() => 'QuickReply(label: $label)';
}

// ─── Escalation ───────────────────────────────────────────────────

/// Escalation provider type.
enum EscalationProvider { mobileai, custom }

/// Configuration for human escalation.
class EscalationConfig {
  /// Where to route the escalation.
  /// - 'mobileai' (default when analyticsKey is set): ticket goes to MobileAI
  ///   dashboard inbox via POST /api/v1/escalations + WebSocket reply delivery.
  /// - 'custom': fires the onEscalate callback — wire to Intercom, Zendesk, etc.
  final EscalationProvider? provider;

  /// Callback when user requests human support (required when provider='custom').
  /// Use this to open a live chat widget, send email, etc.
  final Future<String> Function(EscalationContext context)? onEscalate;

  /// Label for the escalate button. Default: "Talk to a human"
  final String? buttonLabel;

  /// Message shown to user when escalated. Default: "Connecting you to a human agent..."
  final String? escalationMessage;

  const EscalationConfig({
    this.provider,
    this.onEscalate,
    this.buttonLabel,
    this.escalationMessage,
  });

  EscalationConfig copyWith({
    EscalationProvider? provider,
    Future<String> Function(EscalationContext context)? onEscalate,
    String? buttonLabel,
    String? escalationMessage,
  }) {
    return EscalationConfig(
      provider: provider ?? this.provider,
      onEscalate: onEscalate ?? this.onEscalate,
      buttonLabel: buttonLabel ?? this.buttonLabel,
      escalationMessage: escalationMessage ?? this.escalationMessage,
    );
  }
}

/// Context passed to escalation callback.
class EscalationContext {
  /// Summary of the conversation so far
  final String conversationSummary;

  /// Current screen the user is on
  final String currentScreen;

  /// User's original question/issue
  final String originalQuery;

  /// Number of AI steps taken before escalation
  final int stepsBeforeEscalation;

  const EscalationContext({
    required this.conversationSummary,
    required this.currentScreen,
    required this.originalQuery,
    required this.stepsBeforeEscalation,
  });

  @override
  String toString() =>
      'EscalationContext(screen: $currentScreen, steps: $stepsBeforeEscalation)';
}

// ─── CSAT (Customer Satisfaction) ────────────────────────────────

enum CSATSurveyType { csat, ces }
enum CSATRatingType { stars, emoji, thumbs }

class CSATConfig {
  /// Enable CSAT survey after conversation. Default: true if support mode enabled
  final bool enabled;

  /// Which survey to show. 'csat' = Customer Satisfaction, 'ces' = Customer Effort Score.
  final CSATSurveyType? surveyType;

  /// Question text. Default varies by surveyType
  final String? question;

  /// Rating type. Default: 'emoji'
  final CSATRatingType? ratingType;

  /// Callback when user submits rating
  final Future<void> Function(int rating, String? feedback)? onSubmit;

  /// Show after N seconds of inactivity. Default: 10
  final int? showAfterIdleSeconds;

  const CSATConfig({
    this.enabled = true,
    this.surveyType,
    this.question,
    this.ratingType,
    this.onSubmit,
    this.showAfterIdleSeconds,
  });

  CSATConfig copyWith({
    bool? enabled,
    CSATSurveyType? surveyType,
    String? question,
    CSATRatingType? ratingType,
    Future<void> Function(int rating, String? feedback)? onSubmit,
    int? showAfterIdleSeconds,
  }) {
    return CSATConfig(
      enabled: enabled ?? this.enabled,
      surveyType: surveyType ?? this.surveyType,
      question: question ?? this.question,
      ratingType: ratingType ?? this.ratingType,
      onSubmit: onSubmit ?? this.onSubmit,
      showAfterIdleSeconds: showAfterIdleSeconds ?? this.showAfterIdleSeconds,
    );
  }
}

class CSATRating {
  /// Numeric score (1-5 for stars/emoji, 0-1 for thumbs)
  final int score;

  /// Optional text feedback
  final String? feedback;

  /// Conversation metadata
  final CSATMetadata metadata;

  const CSATRating({
    required this.score,
    this.feedback,
    required this.metadata,
  });

  @override
  String toString() => 'CSATRating(score: $score, feedback: $feedback)';
}

class CSATMetadata {
  final int conversationDuration;
  final int stepsCount;
  final bool wasEscalated;
  final String screen;
  final String? ticketId;

  const CSATMetadata({
    required this.conversationDuration,
    required this.stepsCount,
    required this.wasEscalated,
    required this.screen,
    this.ticketId,
  });
}

// ─── Business Hours ──────────────────────────────────────────────

class BusinessHoursConfig {
  final String timezone;
  final Map<int, BusinessHoursDay?> schedule;

  /// Message shown outside business hours
  final String? offlineMessage;

  const BusinessHoursConfig({
    required this.timezone,
    this.schedule = const {},
    this.offlineMessage,
  });
}

class BusinessHoursDay {
  final String start;
  final String end;

  const BusinessHoursDay({required this.start, required this.end});
}

// ─── Support Ticket ──────────────────────────────────────────────

class SupportTicket {
  final String id;
  final String reason;
  final String screen;
  final String status;
  final List<ChatMessage> history;
  final String createdAt;
  final String wsUrl;
  final int unreadCount;

  const SupportTicket({
    required this.id,
    required this.reason,
    required this.screen,
    this.status = 'open',
    this.history = const [],
    required this.createdAt,
    required this.wsUrl,
    this.unreadCount = 0,
  });

  SupportTicket copyWith({
    String? id,
    String? reason,
    String? screen,
    String? status,
    List<ChatMessage>? history,
    String? createdAt,
    String? wsUrl,
    int? unreadCount,
  }) {
    return SupportTicket(
      id: id ?? this.id,
      reason: reason ?? this.reason,
      screen: screen ?? this.screen,
      status: status ?? this.status,
      history: history ?? this.history,
      createdAt: createdAt ?? this.createdAt,
      wsUrl: wsUrl ?? this.wsUrl,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class ChatMessage {
  final String role;
  final String content;
  final String? timestamp;

  const ChatMessage({
    required this.role,
    required this.content,
    this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {'role': role, 'content': content, if (timestamp != null) 'timestamp': timestamp};
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: json['timestamp']?.toString(),
    );
  }
}

// ─── Reported Issues ─────────────────────────────────────────────

enum ReportedIssueCustomerStatusEnum {
  acknowledged,
  investigating,
  answered,
  resolved,
  escalated,
}

/// Reported issue status type for flexibility.
typedef ReportedIssueCustomerStatus = String;

class ReportedIssueStatusUpdate {
  final String id;
  final ReportedIssueCustomerStatus status;
  final String message;
  final String source; // 'ai', 'operator', 'system'
  final String timestamp;

  const ReportedIssueStatusUpdate({
    required this.id,
    required this.status,
    required this.message,
    required this.source,
    required this.timestamp,
  });

  factory ReportedIssueStatusUpdate.fromJson(Map<String, dynamic> json) {
    return ReportedIssueStatusUpdate(
      id: json['id'] as String,
      status: json['status'] as String,
      message: json['message'] as String,
      source: json['source'] as String,
      timestamp: json['timestamp'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'message': message,
      'source': source,
      'timestamp': timestamp,
    };
  }
}

class ReportedIssue {
  final String id;
  final String issueType;
  final String complaintSummary;
  final String verificationStatus;
  final String severity;
  final double? confidence;
  final String screen;
  final String? evidenceSummary;
  final String? aiSummary;
  final String? recommendedAction;
  final List<String>? sourceScreens;
  final List<String>? screenFlow;
  final ReportedIssueCustomerStatus customerStatus;
  final List<ReportedIssueStatusUpdate> statusHistory;
  final String createdAt;
  final String updatedAt;
  final String? linkedEscalationTicketId;

  const ReportedIssue({
    required this.id,
    required this.issueType,
    required this.complaintSummary,
    required this.verificationStatus,
    required this.severity,
    this.confidence,
    required this.screen,
    this.evidenceSummary,
    this.aiSummary,
    this.recommendedAction,
    this.sourceScreens,
    this.screenFlow,
    required this.customerStatus,
    this.statusHistory = const [],
    required this.createdAt,
    required this.updatedAt,
    this.linkedEscalationTicketId,
  });

  factory ReportedIssue.fromJson(Map<String, dynamic> json) {
    return ReportedIssue(
      id: json['id'] as String,
      issueType: json['issueType'] as String,
      complaintSummary: json['complaintSummary'] as String,
      verificationStatus: json['verificationStatus'] as String,
      severity: json['severity'] as String,
      confidence: (json['confidence'] as num?)?.toDouble(),
      screen: json['screen'] as String,
      evidenceSummary: json['evidenceSummary']?.toString(),
      aiSummary: json['aiSummary']?.toString(),
      recommendedAction: json['recommendedAction']?.toString(),
      sourceScreens: (json['sourceScreens'] as List?)?.cast<String>(),
      screenFlow: (json['screenFlow'] as List?)?.cast<String>(),
      customerStatus: json['customerStatus'] as String,
      statusHistory: (json['statusHistory'] as List?)
              ?.map((e) => ReportedIssueStatusUpdate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      linkedEscalationTicketId: json['linkedEscalationTicketId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'issueType': issueType,
      'complaintSummary': complaintSummary,
      'verificationStatus': verificationStatus,
      'severity': severity,
      if (confidence != null) 'confidence': confidence,
      'screen': screen,
      if (evidenceSummary != null) 'evidenceSummary': evidenceSummary,
      if (aiSummary != null) 'aiSummary': aiSummary,
      if (recommendedAction != null) 'recommendedAction': recommendedAction,
      if (sourceScreens != null) 'sourceScreens': sourceScreens,
      if (screenFlow != null) 'screenFlow': screenFlow,
      'customerStatus': customerStatus,
      'statusHistory': statusHistory.map((e) => e.toJson()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (linkedEscalationTicketId != null) 'linkedEscalationTicketId': linkedEscalationTicketId,
    };
  }
}

// ─── Support Mode Config ─────────────────────────────────────────

class SupportModeConfig {
  final bool enabled;
  final SupportStyle supportStyle;
  final String? greetingMessage;
  final String? agentName;
  final String? avatarUrl;
  final List<QuickReply> quickReplies;
  final EscalationConfig? escalation;
  final CSATConfig? csat;
  final BusinessHoursConfig? businessHours;
  final String? systemContext;
  final List<String> autoEscalateTopics;
  final String? tone;
  final String? signOff;

  /// Consumer-defined "WOW actions" — special tools the AI can use
  final List<WowAction> wowActions;

  /// Callback to restore a previous ticket
  final Future<SupportTicket?> Function()? onRestoreTicket;

  /// Callback to restore transcript for a ticket
  final Future<List<String>> Function(SupportTicket ticket)? onRestoreTranscript;

  /// Callback to send a message to the human agent
  final Future<void> Function(SupportTicket ticket, String message)? onSendHumanMessage;

  /// Build WebSocket URL for a ticket
  final String? Function(SupportTicket ticket)? socketUrlBuilder;

  const SupportModeConfig({
    this.enabled = false,
    this.supportStyle = 'warm-concise',
    this.greetingMessage,
    this.agentName,
    this.avatarUrl,
    this.quickReplies = const [],
    this.escalation,
    this.csat,
    this.businessHours,
    this.systemContext,
    this.autoEscalateTopics = const [],
    this.tone,
    this.signOff,
    this.wowActions = const [],
    this.onRestoreTicket,
    this.onRestoreTranscript,
    this.onSendHumanMessage,
    this.socketUrlBuilder,
  });

  SupportModeConfig copyWith({
    bool? enabled,
    SupportStyle? supportStyle,
    String? greetingMessage,
    String? agentName,
    String? avatarUrl,
    List<QuickReply>? quickReplies,
    EscalationConfig? escalation,
    CSATConfig? csat,
    BusinessHoursConfig? businessHours,
    String? systemContext,
    List<String>? autoEscalateTopics,
    String? tone,
    String? signOff,
    List<WowAction>? wowActions,
    Future<SupportTicket?> Function()? onRestoreTicket,
    Future<List<String>> Function(SupportTicket ticket)? onRestoreTranscript,
    Future<void> Function(SupportTicket ticket, String message)? onSendHumanMessage,
    String? Function(SupportTicket ticket)? socketUrlBuilder,
  }) {
    return SupportModeConfig(
      enabled: enabled ?? this.enabled,
      supportStyle: supportStyle ?? this.supportStyle,
      greetingMessage: greetingMessage ?? this.greetingMessage,
      agentName: agentName ?? this.agentName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      quickReplies: quickReplies ?? this.quickReplies,
      escalation: escalation ?? this.escalation,
      csat: csat ?? this.csat,
      businessHours: businessHours ?? this.businessHours,
      systemContext: systemContext ?? this.systemContext,
      autoEscalateTopics: autoEscalateTopics ?? this.autoEscalateTopics,
      tone: tone ?? this.tone,
      signOff: signOff ?? this.signOff,
      wowActions: wowActions ?? this.wowActions,
      onRestoreTicket: onRestoreTicket ?? this.onRestoreTicket,
      onRestoreTranscript: onRestoreTranscript ?? this.onRestoreTranscript,
      onSendHumanMessage: onSendHumanMessage ?? this.onSendHumanMessage,
      socketUrlBuilder: socketUrlBuilder ?? this.socketUrlBuilder,
    );
  }
}

/// A "WOW action" — special tool the AI can use to surprise/delight users.
class WowAction {
  final String name;
  final String description;
  final String triggerHint;
  final Future<Object?> Function(Map<String, dynamic> args) handler;

  const WowAction({
    required this.name,
    required this.description,
    required this.triggerHint,
    required this.handler,
  });
}
