import 'package:flutter_test/flutter_test.dart';
import 'package:solray/services/updater.dart';

void main() {
  group('Updater.isNewer', () {
    test('detects newer versions', () {
      expect(Updater.isNewer('1.6.3', '1.6.2'), isTrue);
      expect(Updater.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(Updater.isNewer('1.7.0', '1.6.9'), isTrue);
    });

    test('same or older returns false', () {
      expect(Updater.isNewer('1.6.2', '1.6.2'), isFalse);
      expect(Updater.isNewer('1.6.1', '1.6.2'), isFalse);
      expect(Updater.isNewer('1.5.0', '1.6.2'), isFalse);
    });

    test('handles v prefix and uneven lengths', () {
      expect(Updater.isNewer('v1.7', '1.6.9'), isTrue);
      expect(Updater.isNewer('1.6', '1.6.0'), isFalse);
      expect(Updater.isNewer('V2.0.0', '1.9.9'), isTrue);
    });
  });
}
