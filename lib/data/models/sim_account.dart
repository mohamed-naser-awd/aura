/// A call-capable SIM/phone account, as reported by the native `SimManager`.
class SimAccount {
  const SimAccount({
    required this.id,
    required this.label,
    required this.isDefault,
    this.carrierName,
    this.slotIndex = -1,
  });

  /// Stable, flattened `PhoneAccountHandle` string used when placing a call.
  final String id;
  final String label;
  final bool isDefault;

  /// Carrier/company name (e.g. "Vodafone"), if available.
  final String? carrierName;

  /// 0-based SIM slot; -1 if unknown.
  final int slotIndex;

  /// Short display, e.g. "Vodafone · SIM 1" (falls back to the label).
  String get display {
    final name = (carrierName != null && carrierName!.isNotEmpty) ? carrierName! : label;
    return slotIndex >= 0 ? '$name · SIM ${slotIndex + 1}' : name;
  }

  factory SimAccount.fromMap(Map<dynamic, dynamic> map) => SimAccount(
        id: map['id'] as String,
        label: map['label'] as String? ?? 'SIM',
        isDefault: map['isDefault'] as bool? ?? false,
        carrierName: map['carrierName'] as String?,
        slotIndex: (map['slotIndex'] as int?) ?? -1,
      );
}

/// How outgoing calls pick a SIM (feature #5).
enum SimSelectionMode { alwaysAsk, fixed }
