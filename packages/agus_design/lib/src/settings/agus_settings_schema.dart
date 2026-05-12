import 'package:flutter/foundation.dart';

enum AgusSettingType {
  boolean,
  string,
  number,
  select,
  radio,
  array,
  object,
  file,
  folder,
  color,
  json,
}

enum AgusSettingScope { application, user, workspace, resource, language }

extension AgusSettingScopeLabel on AgusSettingScope {
  String get label {
    return switch (this) {
      AgusSettingScope.application => 'Application',
      AgusSettingScope.user => 'User',
      AgusSettingScope.workspace => 'Workspace',
      AgusSettingScope.resource => 'Resource',
      AgusSettingScope.language => 'Language',
    };
  }
}

@immutable
class AgusSettingOption {
  const AgusSettingOption({
    required this.value,
    required this.label,
    this.description,
  });

  final Object value;
  final String label;
  final String? description;
}

@immutable
class AgusSettingSchema {
  const AgusSettingSchema({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.type,
    required this.defaultValue,
    this.options = const <AgusSettingOption>[],
    this.scope = AgusSettingScope.user,
    this.minimum,
    this.maximum,
    this.tags = const <String>[],
    this.jsonOnly = false,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final AgusSettingType type;
  final Object? defaultValue;
  final List<AgusSettingOption> options;
  final AgusSettingScope scope;
  final double? minimum;
  final double? maximum;
  final List<String> tags;
  final bool jsonOnly;

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    final haystack = [
      id,
      title,
      description,
      category,
      ...tags,
      for (final option in options) option.label,
      for (final option in options)
        if (option.description != null) option.description!,
    ].join(' ').toLowerCase();

    return haystack.contains(normalized) ||
        _queryTerms(normalized).every(
          (term) => haystack.contains(term) || _isFuzzyMatch(term, haystack),
        );
  }

  static Iterable<String> _queryTerms(String query) {
    return query.split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
  }

  static bool _isFuzzyMatch(String needle, String haystack) {
    if (needle.length < 2) {
      return haystack.contains(needle);
    }

    var index = 0;
    for (final codeUnit in haystack.codeUnits) {
      if (codeUnit == needle.codeUnitAt(index)) {
        index++;
        if (index == needle.length) {
          return true;
        }
      }
    }

    return false;
  }
}
