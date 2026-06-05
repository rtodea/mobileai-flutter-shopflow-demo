import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'types.dart';

class TicketStore {
  final String storageKey;

  const TicketStore({this.storageKey = '@mobileai_flutter_support_tickets'});

  Future<List<SupportTicket>> loadTickets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const <SupportTicket>[];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <SupportTicket>[];

    return decoded
        .whereType<Map<String, dynamic>>()
        .map((entry) => SupportTicket(
              id: entry['id']?.toString() ?? '',
              reason: entry['reason']?.toString() ?? '',
              screen: entry['screen']?.toString() ?? '',
              status: entry['status']?.toString() ?? 'open',
              createdAt: entry['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
              wsUrl: entry['wsUrl']?.toString() ?? '',
              unreadCount: (entry['unreadCount'] as num?)?.toInt() ?? 0,
            ))
        .where((ticket) => ticket.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveTickets(List<SupportTicket> tickets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(
        tickets
            .map((ticket) => <String, dynamic>{
                  'id': ticket.id,
                  'reason': ticket.reason,
                  'screen': ticket.screen,
                  'status': ticket.status,
                  'createdAt': ticket.createdAt,
                  'wsUrl': ticket.wsUrl,
                  'unreadCount': ticket.unreadCount,
                })
            .toList(growable: false),
      ),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
