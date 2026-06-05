import '../core/types.dart';
import '../utils/logger.dart';

const int _defaultMaxTokens = 2000;
const int _charsPerToken = 4;
const int _defaultPriority = 5;

class KnowledgeBaseService {
  late final KnowledgeRetriever _retriever;
  late final int _maxChars;

  KnowledgeBaseService(dynamic config, [int? maxTokens]) {
    _maxChars = (maxTokens ?? _defaultMaxTokens) * _charsPerToken;

    if (config is List<KnowledgeEntry>) {
      _retriever = _StaticKeywordRetriever(config);
      Logger.info('KnowledgeBase initialized with ${config.length} static entries (budget: ${maxTokens ?? _defaultMaxTokens} tokens)');
    } else if (config is KnowledgeRetriever) {
      _retriever = config;
      Logger.info('KnowledgeBase initialized with custom retriever');
    } else {
      throw ArgumentError('config must be either List<KnowledgeEntry> or KnowledgeRetriever');
    }
  }

  Future<String> retrieve(String query, String screenName) async {
    try {
      final entries = await _retriever.retrieve(query, screenName);

      if (entries.isEmpty) {
        return 'No relevant knowledge found for this query. Answer based on what is visible on screen.';
      }

      final selected = _applyTokenBudget(entries);
      
      Logger.info('Retrieved ${selected.length}/${entries.length} entries for "$query"');
      
      return _formatEntries(selected);
    } catch (e) {
      Logger.error('Knowledge retrieval failed: $e');
      return 'Knowledge retrieval failed. Answer based on what is visible on screen.';
    }
  }

  List<KnowledgeEntry> _applyTokenBudget(List<KnowledgeEntry> entries) {
    final selected = <KnowledgeEntry>[];
    int totalChars = 0;

    for (final entry in entries) {
      final entryChars = entry.title.length + entry.content.length + 10;
      if (totalChars + entryChars > _maxChars && selected.isNotEmpty) break;
      
      selected.add(entry);
      totalChars += entryChars;
    }

    return selected;
  }

  String _formatEntries(List<KnowledgeEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('--- DOMAIN KNOWLEDGE ---');
    for (final entry in entries) {
      buffer.writeln('Title: ${entry.title}');
      buffer.writeln(entry.content);
      buffer.writeln('------------------------');
    }
    return buffer.toString();
  }
}

class _StaticKeywordRetriever implements KnowledgeRetriever {
  final List<KnowledgeEntry> entries;

  _StaticKeywordRetriever(this.entries);

  @override
  Future<List<KnowledgeEntry>> retrieve(String query, String screenName) async {
    final queryWords = _tokenize(query);
    if (queryWords.isEmpty) return [];

    final scored = <_ScoredEntry>[];

    for (final entry in entries) {
      if (!_isScreenMatch(entry, screenName)) continue;

      final searchableText = '${entry.title} ${entry.tags?.join(' ') ?? ''} ${entry.content}';
      final searchableWords = _tokenize(searchableText);

      int matchCount = 0;
      for (final w in queryWords) {
        if (searchableWords.any((s) => s.contains(w) || w.contains(s))) {
          matchCount++;
        }
      }

      if (matchCount > 0) {
        final score = matchCount * (entry.priority ?? _defaultPriority);
        scored.add(_ScoredEntry(entry, score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.entry).toList();
  }

  bool _isScreenMatch(KnowledgeEntry entry, String screenName) {
    if (entry.screens == null || entry.screens!.isEmpty) return true;
    final lowerScreenName = screenName.toLowerCase();
    return entry.screens!.any((s) => s.toLowerCase() == lowerScreenName);
  }

  List<String> _tokenize(String text) {
    final regExp = RegExp(r'[^a-z0-9\u0600-\u06FF\s]+');
    return text
        .toLowerCase()
        .replaceAll(regExp, ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();
  }
}

class _ScoredEntry {
  final KnowledgeEntry entry;
  final int score;
  _ScoredEntry(this.entry, this.score);
}
