import 'dart:convert';

/// A carrier entry from the public operator-icons MCC catalog.
class OperatorCatalogEntry {
  const OperatorCatalogEntry({
    required this.mnc,
    required this.operatorName,
    required this.brand,
    required this.icon,
    required this.iconScope,
    this.plmn,
    this.gids = const [],
  });

  final String mnc;
  final String operatorName;
  final String brand;
  final String icon;
  final String iconScope;
  final String? plmn;
  final List<OperatorCatalogGid> gids;

  String get displayName => brand.isEmpty ? operatorName : brand;
}

/// Optional MVNO/profile discriminators nested below an MCC/MNC entry.
class OperatorCatalogGid {
  const OperatorCatalogGid({
    this.gid1,
    this.gid2,
    this.profileNames = const [],
    this.serviceProviderNames = const [],
    this.icon,
    this.iconScope,
  });

  final String? gid1;
  final String? gid2;
  final List<String> profileNames;
  final List<String> serviceProviderNames;
  final String? icon;
  final String? iconScope;
}

class OperatorCatalogMatch {
  const OperatorCatalogMatch({
    required this.entry,
    required this.score,
    required this.icon,
    required this.iconScope,
    required this.resolvedDisplayName,
    this.gid,
  });

  final OperatorCatalogEntry entry;
  final OperatorCatalogGid? gid;
  final int score;
  final String icon;
  final String iconScope;
  final String resolvedDisplayName;

  String get displayName => resolvedDisplayName;
  String get operatorName => entry.operatorName;
  String get brand => entry.brand;
}

/// Small, dependency-free decoder for operator-icons' per-MCC TOML files.
///
/// The matching order follows NekokoLPA2: MCC selects a catalog, MNC is
/// mandatory, then profile/service-provider names and GID1/GID2 increase the
/// score. This also honors the catalog's optional GID-specific icon override.
class OperatorCatalog {
  OperatorCatalog({
    required this.mcc,
    required this.country,
    required this.iso,
    required Iterable<OperatorCatalogEntry> operators,
  }) : operators = List.unmodifiable(operators);

  final String mcc;
  final String country;
  final String iso;
  final List<OperatorCatalogEntry> operators;

  factory OperatorCatalog.decode(String source, {String? expectedMcc}) {
    var mcc = '';
    var country = '';
    var iso = '';
    final entries = <OperatorCatalogEntry>[];
    _MutableOperator? currentOperator;
    _MutableGid? currentGid;

    void finishOperator() {
      final value = currentOperator?.build();
      if (value != null) entries.add(value);
      currentOperator = null;
      currentGid = null;
    }

    for (final rawLine in const LineSplitter().convert(source)) {
      final line = _stripTomlComment(rawLine).trim();
      if (line.isEmpty) continue;
      if (line == '[[operators]]') {
        finishOperator();
        currentOperator = _MutableOperator();
        continue;
      }
      if (line == '[[operators.gids]]') {
        final operator = currentOperator;
        if (operator == null) continue;
        currentGid = _MutableGid();
        operator.gids.add(currentGid!);
        continue;
      }

      final separator = line.indexOf('=');
      if (separator < 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      final gid = currentGid;
      if (gid != null) {
        switch (key) {
          case 'gid1':
            gid.gid1 = _parseTomlString(value);
          case 'gid2':
            gid.gid2 = _parseTomlString(value);
          case 'profile_names':
            gid.profileNames = _parseTomlStringList(value);
          case 'profile_provider_names':
            gid.serviceProviderNames = _parseTomlStringList(value);
          case 'icon':
            gid.icon = _parseTomlString(value);
          case 'icon_scope':
            gid.iconScope = _parseTomlString(value);
        }
        continue;
      }

      final operator = currentOperator;
      if (operator != null) {
        switch (key) {
          case 'mnc':
            operator.mnc = _parseTomlString(value);
          case 'plmn':
            operator.plmn = _parseTomlString(value);
          case 'operator':
            operator.operatorName = _parseTomlString(value);
          case 'brand':
            operator.brand = _parseTomlString(value);
          case 'icon':
            operator.icon = _parseTomlString(value);
          case 'icon_scope':
            operator.iconScope = _parseTomlString(value);
        }
        continue;
      }

      switch (key) {
        case 'mcc':
          mcc = _parseTomlString(value) ?? '';
        case 'country':
          country = _parseTomlString(value) ?? '';
        case 'iso':
          iso = _parseTomlString(value) ?? '';
      }
    }
    finishOperator();

    if (!RegExp(r'^\d{3}$').hasMatch(mcc)) {
      throw const FormatException('operator-icons 目录缺少有效 MCC');
    }
    if (expectedMcc != null && mcc != expectedMcc) {
      throw FormatException('operator-icons 目录 MCC 不匹配：$mcc');
    }
    return OperatorCatalog(
      mcc: mcc,
      country: country,
      iso: iso,
      operators: entries,
    );
  }

  OperatorCatalogMatch? resolve({
    required String mnc,
    String? gid1,
    String? gid2,
    String? profileName,
    String? serviceProviderName,
  }) {
    final candidates = _mncCandidates(mnc);
    OperatorCatalogMatch? best;
    for (final entry in operators) {
      if (!candidates.contains(entry.mnc)) continue;
      var score = 100;
      if (_entryMatchesName(entry, profileName, serviceProviderName)) {
        score += 20;
      }

      OperatorCatalogGid? matchedGid;
      if (_normalizeOptional(gid1) != null ||
          _normalizeOptional(gid2) != null) {
        var bestGidStrength = -1;
        for (final gid in entry.gids) {
          final strength = _gidMatchStrength(
            gid,
            gid1: gid1,
            gid2: gid2,
            profileName: profileName,
            serviceProviderName: serviceProviderName,
          );
          if (strength > bestGidStrength) {
            matchedGid = gid;
            bestGidStrength = strength;
          }
        }
        if (bestGidStrength >= 0) score += 30;
      }

      final icon = _nonEmpty(matchedGid?.icon) ?? entry.icon;
      final scope = _nonEmpty(matchedGid?.iconScope) ?? entry.iconScope;
      final match = OperatorCatalogMatch(
        entry: entry,
        gid: matchedGid,
        score: score,
        icon: icon,
        iconScope: scope,
        resolvedDisplayName: _resolvedDisplayName(
          entry,
          matchedGid,
          profileName,
          serviceProviderName,
        ),
      );
      if (best == null || match.score > best.score) best = match;
    }
    return best;
  }
}

class _MutableOperator {
  String? mnc;
  String? plmn;
  String? operatorName;
  String? brand;
  String? icon;
  String? iconScope;
  final List<_MutableGid> gids = [];

  OperatorCatalogEntry? build() {
    final normalizedMnc = _nonEmpty(mnc);
    final normalizedOperator = _nonEmpty(operatorName);
    if (normalizedMnc == null ||
        !RegExp(r'^\d{1,3}$').hasMatch(normalizedMnc) ||
        normalizedOperator == null) {
      return null;
    }
    return OperatorCatalogEntry(
      mnc: normalizedMnc,
      plmn: _nonEmpty(plmn),
      operatorName: normalizedOperator,
      brand: _nonEmpty(brand) ?? '',
      icon: _nonEmpty(icon) ?? '',
      iconScope: _nonEmpty(iconScope) ?? '',
      gids: List.unmodifiable(gids.map((item) => item.build())),
    );
  }
}

class _MutableGid {
  String? gid1;
  String? gid2;
  List<String> profileNames = const [];
  List<String> serviceProviderNames = const [];
  String? icon;
  String? iconScope;

  OperatorCatalogGid build() => OperatorCatalogGid(
    gid1: _nonEmpty(gid1),
    gid2: _nonEmpty(gid2),
    profileNames: List.unmodifiable(profileNames),
    serviceProviderNames: List.unmodifiable(serviceProviderNames),
    icon: _nonEmpty(icon),
    iconScope: _nonEmpty(iconScope),
  );
}

bool _entryMatchesName(
  OperatorCatalogEntry entry,
  String? profileName,
  String? serviceProviderName,
) =>
    _matchesName(profileName, entry.operatorName) ||
    _matchesName(profileName, entry.brand) ||
    _matchesName(serviceProviderName, entry.operatorName) ||
    _matchesName(serviceProviderName, entry.brand) ||
    entry.gids.any(
      (gid) => _gidMatchesName(gid, profileName, serviceProviderName),
    );

int _gidMatchStrength(
  OperatorCatalogGid gid, {
  required String? gid1,
  required String? gid2,
  required String? profileName,
  required String? serviceProviderName,
}) {
  final expectedGid1 = _normalizeOptional(gid.gid1);
  final expectedGid2 = _normalizeOptional(gid.gid2);
  final actualGid1 = _normalizeOptional(gid1);
  final actualGid2 = _normalizeOptional(gid2);
  final idsMatch =
      (expectedGid1 == null || expectedGid1 == actualGid1) &&
      (expectedGid2 == null || expectedGid2 == actualGid2);
  final namesMatch = _gidMatchesName(gid, profileName, serviceProviderName);
  if (!idsMatch && !namesMatch) return -1;
  return (namesMatch ? 4 : 0) +
      (expectedGid1 == null ? 0 : 1) +
      (expectedGid2 == null ? 0 : 1);
}

bool _gidMatchesName(
  OperatorCatalogGid gid,
  String? profileName,
  String? serviceProviderName,
) =>
    gid.profileNames.any((name) => _matchesName(profileName, name)) ||
    gid.serviceProviderNames.any(
      (name) => _matchesName(serviceProviderName, name),
    );

String _resolvedDisplayName(
  OperatorCatalogEntry entry,
  OperatorCatalogGid? gid,
  String? profileName,
  String? serviceProviderName,
) {
  if (gid == null) return entry.displayName;
  for (final name in gid.serviceProviderNames) {
    if (_matchesName(serviceProviderName, name) ||
        _matchesName(profileName, name)) {
      return name;
    }
  }
  final profileMatched = gid.profileNames.any(
    (name) => _matchesName(profileName, name),
  );
  if (profileMatched && gid.serviceProviderNames.isNotEmpty) {
    return gid.serviceProviderNames.first;
  }
  return entry.displayName;
}

Set<String> _mncCandidates(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || !RegExp(r'^\d+$').hasMatch(trimmed)) return const {};
  return {
    trimmed,
    if (trimmed.length < 2) trimmed.padLeft(2, '0'),
    if (trimmed.length < 3) trimmed.padLeft(3, '0'),
  };
}

String? _normalizeOptional(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

bool _matchesName(String? candidate, String? expected) {
  final left = _normalizeOptional(candidate);
  final right = _normalizeOptional(expected);
  if (left == null || right == null) return false;
  return left == right || left.contains(right) || right.contains(left);
}

String? _nonEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String _stripTomlComment(String line) {
  var inString = false;
  var escaped = false;
  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (escaped) {
      escaped = false;
    } else if (char == r'\') {
      escaped = true;
    } else if (char == '"') {
      inString = !inString;
    } else if (!inString && char == '#') {
      return line.substring(0, index);
    }
  }
  return line;
}

String? _parseTomlString(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 2 || !trimmed.startsWith('"')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is String ? decoded : null;
  } catch (_) {
    return trimmed.substring(1, trimmed.length - 1);
  }
}

List<String> _parseTomlStringList(String value) => RegExp(r'"(?:\\.|[^"\\])*"')
    .allMatches(value)
    .map((match) => _parseTomlString(match.group(0)!))
    .whereType<String>()
    .toList(growable: false);
