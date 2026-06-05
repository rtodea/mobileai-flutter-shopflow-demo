import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class NotificationPreferencesState {
  final bool pushNotificationsEnabled;
  final bool emailDigestEnabled;
  final bool smsBackupEnabled;
  final bool inAppBannersEnabled;
  final String digestMode;
  final String presetBundle;
  final bool quietHoursEnabled;
  final String quietHoursScope;
  final bool criticalAlertsBypass;
  final String recurrence;
  final String calendarName;
  final bool previewSummary;
  final String reminderStyle;
  final DateTime effectiveFrom;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final Set<String> mutedTopics;

  NotificationPreferencesState({
    required this.pushNotificationsEnabled,
    required this.emailDigestEnabled,
    required this.smsBackupEnabled,
    required this.inAppBannersEnabled,
    required this.digestMode,
    required this.presetBundle,
    required this.quietHoursEnabled,
    required this.quietHoursScope,
    required this.criticalAlertsBypass,
    required this.recurrence,
    required this.calendarName,
    required this.previewSummary,
    required this.reminderStyle,
    required this.effectiveFrom,
    required this.startTime,
    required this.endTime,
    required this.mutedTopics,
  });

  factory NotificationPreferencesState.initial() {
    return NotificationPreferencesState(
      pushNotificationsEnabled: true,
      emailDigestEnabled: true,
      smsBackupEnabled: false,
      inAppBannersEnabled: true,
      digestMode: 'Smart Digest',
      presetBundle: 'Balanced',
      quietHoursEnabled: true,
      quietHoursScope: 'Marketing and deals',
      criticalAlertsBypass: true,
      recurrence: 'Weekdays',
      calendarName: 'Primary',
      previewSummary: true,
      reminderStyle: 'Push first',
      effectiveFrom: DateTime(2026, 4, 25),
      startTime: const TimeOfDay(hour: 22, minute: 0),
      endTime: const TimeOfDay(hour: 7, minute: 0),
      mutedTopics: const <String>{
        'Flash deals',
        'Style picks',
        'Back in stock',
      },
    );
  }

  NotificationPreferencesState copyWith({
    bool? pushNotificationsEnabled,
    bool? emailDigestEnabled,
    bool? smsBackupEnabled,
    bool? inAppBannersEnabled,
    String? digestMode,
    String? presetBundle,
    bool? quietHoursEnabled,
    String? quietHoursScope,
    bool? criticalAlertsBypass,
    String? recurrence,
    String? calendarName,
    bool? previewSummary,
    String? reminderStyle,
    DateTime? effectiveFrom,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    Set<String>? mutedTopics,
  }) {
    return NotificationPreferencesState(
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      emailDigestEnabled: emailDigestEnabled ?? this.emailDigestEnabled,
      smsBackupEnabled: smsBackupEnabled ?? this.smsBackupEnabled,
      inAppBannersEnabled: inAppBannersEnabled ?? this.inAppBannersEnabled,
      digestMode: digestMode ?? this.digestMode,
      presetBundle: presetBundle ?? this.presetBundle,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursScope: quietHoursScope ?? this.quietHoursScope,
      criticalAlertsBypass:
          criticalAlertsBypass ?? this.criticalAlertsBypass,
      recurrence: recurrence ?? this.recurrence,
      calendarName: calendarName ?? this.calendarName,
      previewSummary: previewSummary ?? this.previewSummary,
      reminderStyle: reminderStyle ?? this.reminderStyle,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      mutedTopics: mutedTopics ?? this.mutedTopics,
    );
  }
}

class NotificationPreferencesNotifier
    extends Notifier<NotificationPreferencesState> {
  @override
  NotificationPreferencesState build() {
    return NotificationPreferencesState.initial();
  }

  void setPushNotificationsEnabled(bool value) {
    state = state.copyWith(pushNotificationsEnabled: value);
  }

  void setEmailDigestEnabled(bool value) {
    state = state.copyWith(emailDigestEnabled: value);
  }

  void setSmsBackupEnabled(bool value) {
    state = state.copyWith(smsBackupEnabled: value);
  }

  void setInAppBannersEnabled(bool value) {
    state = state.copyWith(inAppBannersEnabled: value);
  }

  void setDigestMode(String value) {
    state = state.copyWith(digestMode: value);
  }

  void setPresetBundle(String value) {
    state = state.copyWith(presetBundle: value);
  }

  void setQuietHoursEnabled(bool value) {
    state = state.copyWith(quietHoursEnabled: value);
  }

  void setQuietHoursScope(String value) {
    state = state.copyWith(quietHoursScope: value);
  }

  void setCriticalAlertsBypass(bool value) {
    state = state.copyWith(criticalAlertsBypass: value);
  }

  void setRecurrence(String value) {
    state = state.copyWith(recurrence: value);
  }

  void setCalendarName(String value) {
    state = state.copyWith(calendarName: value);
  }

  void setPreviewSummary(bool value) {
    state = state.copyWith(previewSummary: value);
  }

  void setReminderStyle(String value) {
    state = state.copyWith(reminderStyle: value);
  }

  void setEffectiveFrom(DateTime value) {
    state = state.copyWith(effectiveFrom: value);
  }

  void setStartTime(TimeOfDay value) {
    state = state.copyWith(startTime: value);
  }

  void setEndTime(TimeOfDay value) {
    state = state.copyWith(endTime: value);
  }

  void toggleMutedTopic(String topic) {
    final nextTopics = Set<String>.from(state.mutedTopics);
    if (nextTopics.contains(topic)) {
      nextTopics.remove(topic);
    } else {
      nextTopics.add(topic);
    }
    state = state.copyWith(mutedTopics: nextTopics);
  }
}

final notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesNotifier, NotificationPreferencesState>(
      NotificationPreferencesNotifier.new,
    );
