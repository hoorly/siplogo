String formatPhoneNumber(String rawNumber) {
  final buffer = StringBuffer();
  final len = rawNumber.length;

  // Форматируем посимвольно согласно маске: X (XXX) X-XXX-XXX
  for (int i = 0; i < len; i++) {
    // Если передается что-то не цифрами, отдаем без форматирования
    if (!'0123456789'.contains(rawNumber[i]) || i > 10) {
      return rawNumber;
    }
    if (i == 1) buffer.write(' (');
    if (i == 4) buffer.write(') ');
    if (i == i && i == 5) buffer.write('-');
    if (i == 8) buffer.write('-');
    buffer.write(rawNumber[i]);
  }

  return buffer.toString();
}
