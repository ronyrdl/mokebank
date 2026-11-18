String formatExchangeRate(Object? value) {
  final rate = value?.toString() ?? '—';
  if (!rate.contains('.')) return rate;
  return rate.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
