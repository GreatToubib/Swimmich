//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

/// Swimmich sort/triage status
class SortStatus {
  /// Instantiate a new enum with the provided [value].
  const SortStatus._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const new_ = SortStatus._(r'new');
  static const reviewLater = SortStatus._(r'review_later');
  static const kept = SortStatus._(r'kept');

  /// List of all possible values in this [enum][SortStatus].
  static const values = <SortStatus>[
    new_,
    reviewLater,
    kept,
  ];

  static SortStatus? fromJson(dynamic value) => SortStatusTypeTransformer().decode(value);

  static List<SortStatus> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SortStatus>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SortStatus.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SortStatus] to String,
/// and [decode] dynamic data back to [SortStatus].
class SortStatusTypeTransformer {
  factory SortStatusTypeTransformer() => _instance ??= const SortStatusTypeTransformer._();

  const SortStatusTypeTransformer._();

  String encode(SortStatus data) => data.value;

  /// Decodes a [dynamic value][data] to a SortStatus.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SortStatus? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'new': return SortStatus.new_;
        case r'review_later': return SortStatus.reviewLater;
        case r'kept': return SortStatus.kept;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [SortStatusTypeTransformer] instance.
  static SortStatusTypeTransformer? _instance;
}
