import 'dart:convert';

import 'lpa_activation.dart';

class ProfileCatalogEntry {
  const ProfileCatalogEntry({
    required this.plmn,
    required this.serviceProviderName,
    required this.rsp,
    this.profileNames = const [],
    this.referenceSizeBytes,
    this.eumSizes = const {},
  });

  final String plmn;
  final String serviceProviderName;
  final String rsp;
  final List<String> profileNames;
  final int? referenceSizeBytes;
  final Map<String, int> eumSizes;

  String? get mcc =>
      RegExp(r'^\d{5,6}$').hasMatch(plmn) ? plmn.substring(0, 3) : null;

  String? get mnc =>
      RegExp(r'^\d{5,6}$').hasMatch(plmn) ? plmn.substring(3) : null;

  int? sizeForEum(String? eumId) => eumId == null
      ? referenceSizeBytes
      : eumSizes[eumId] ?? referenceSizeBytes;

  int? get minimumSizeBytes {
    final values = <int>[?referenceSizeBytes, ...eumSizes.values];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a < b ? a : b);
  }

  int? get maximumSizeBytes {
    final values = <int>[?referenceSizeBytes, ...eumSizes.values];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
  }

  static ProfileCatalogEntry? fromJson(dynamic value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final rsp = map['rsp'];
    final provider = map['serviceProviderName'];
    if (rsp is! String || rsp.trim().isEmpty) return null;
    if (provider is! String || provider.trim().isEmpty) return null;
    final rawNames = map['names'];
    final rawEumSizes = map['eum_sizes'];
    return ProfileCatalogEntry(
      plmn: map['plmn'] is String ? (map['plmn'] as String).trim() : '',
      serviceProviderName: provider.trim(),
      rsp: rsp.trim().toLowerCase(),
      profileNames: rawNames is List
          ? rawNames
                .whereType<String>()
                .map((name) => name.trim())
                .where((name) => name.isNotEmpty)
                .toList(growable: false)
          : const [],
      referenceSizeBytes: _positiveInt(map['reference_size']),
      eumSizes: rawEumSizes is Map
          ? Map.unmodifiable({
              for (final entry in rawEumSizes.entries)
                if (entry.key is String && _positiveInt(entry.value) != null)
                  (entry.key as String).trim(): _positiveInt(entry.value)!,
            })
          : const {},
    );
  }
}

class ProfileCatalogMatch {
  ProfileCatalogMatch({
    required this.smdpAddress,
    required List<ProfileCatalogEntry> candidates,
    this.referenceEum,
  }) : candidates = List.unmodifiable(candidates);

  final String smdpAddress;
  final List<ProfileCatalogEntry> candidates;
  final String? referenceEum;

  bool get found => candidates.isNotEmpty;

  List<String> get providerNames {
    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate.serviceProviderName))
          candidate.serviceProviderName,
    ];
  }

  String? get unambiguousProvider {
    final names = providerNames;
    return names.length == 1 ? names.single : null;
  }
}

/// Decoder and exact SM-DP+ matcher for EUICC profile catalog data.
class ProfileCatalog {
  ProfileCatalog(Iterable<ProfileCatalogEntry> entries, {this.referenceEum})
    : _entries = List.unmodifiable(entries);

  factory ProfileCatalog.decode(String source) {
    final root = jsonDecode(source);
    if (root is! Map || root['results'] is! List) {
      throw const FormatException('Profile 数据源格式无效');
    }
    final rawReferenceEum = root['reference_eum'];
    return ProfileCatalog(
      (root['results'] as List)
          .map(ProfileCatalogEntry.fromJson)
          .whereType<ProfileCatalogEntry>(),
      referenceEum:
          rawReferenceEum is String && rawReferenceEum.trim().isNotEmpty
          ? rawReferenceEum.trim()
          : null,
    );
  }

  final List<ProfileCatalogEntry> _entries;
  final String? referenceEum;

  ProfileCatalogMatch match(LpaActivation activation) {
    final host = activation.smdpAddress.toLowerCase().split(':').first;
    final seen = <String>{};
    final candidates = <ProfileCatalogEntry>[];
    for (final entry in _entries) {
      final rsp = entry.rsp.split(':').first;
      if (rsp != host) continue;
      final eumFingerprint = entry.eumSizes.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final key =
          '${entry.plmn}\u0000${entry.serviceProviderName}\u0000${entry.rsp}'
          '\u0000${entry.profileNames.join('|')}'
          '\u0000${entry.referenceSizeBytes}'
          '\u0000${eumFingerprint.map((item) => '${item.key}:${item.value}').join('|')}';
      if (seen.add(key)) candidates.add(entry);
    }
    candidates.sort((a, b) {
      final provider = a.serviceProviderName.compareTo(b.serviceProviderName);
      return provider != 0 ? provider : a.plmn.compareTo(b.plmn);
    });
    return ProfileCatalogMatch(
      smdpAddress: activation.smdpAddress,
      candidates: candidates,
      referenceEum: referenceEum,
    );
  }
}

int? _positiveInt(Object? value) => value is int && value > 0 ? value : null;
