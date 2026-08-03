import 'package:flutter_test/flutter_test.dart';
import 'package:olivia/services/serial_listener.dart';

void main() {
  group('SerialPortListener.parseSensorLine', () {
    test('parses a comma-separated telemetry payload', () {
      final parsed = SerialPortListener.parseSensorLine(
        'korban_1,standby,-6.595,106.816,1200,2,ON,LOW',
      );

      expect(parsed, isNotNull);
      expect(parsed!['node_id'], 'korban_1');
      expect(parsed['status_sys'], 'standby');
      expect(parsed['latitude'], -6.595);
      expect(parsed['longitude'], 106.816);
      expect(parsed['sound_value'], 1200);
      expect(parsed['vibration_count'], 2);
      expect(parsed['vibration_status'], 'ON');
      expect(parsed['sound_status'], 'LOW');
    });

    test('accepts the current 8-field packet format with zero GPS values', () {
      final parsed = SerialPortListener.parseSensorLine(
        'korban_1,mendeteksi,0,0,3200,4,KORBAN_GEDOK_RAPID,SUARA_TERIAKAN',
      );

      expect(parsed, isNotNull);
      expect(parsed!['node_id'], 'korban_1');
      expect(parsed['status_sys'], 'mendeteksi');
      expect(parsed['latitude'], 0.0);
      expect(parsed['longitude'], 0.0);
      expect(parsed['sound_value'], 3200);
      expect(parsed['vibration_count'], 4);
      expect(parsed['vibration_status'], 'KORBAN_GEDOK_RAPID');
      expect(parsed['sound_status'], 'SUARA_TERIAKAN');
    });

    test('ignores SYSTEM packets and keeps future payload compatibility', () {
      expect(
        SerialPortListener.parseSensorLine('SYSTEM:LISTENING_FOR_DATA...'),
        isNull,
      );

      final parsed = SerialPortListener.parseSensorLine(
        'korban_1,custom_status,-6.200000,106.800000,1200,0,aman,aman,extra_field',
      );

      expect(parsed, isNotNull);
      expect(parsed!['node_id'], 'korban_1');
      expect(parsed['status_sys'], 'custom_status');
    });
  });

  group('SerialPortListener.normalizeStatusForUi', () {
    test('maps standby and mendeteksi to readable UI labels', () {
      expect(
        SerialPortListener.normalizeStatusForUi('standby'),
        'Safe / Normal / Standby',
      );
      expect(
        SerialPortListener.normalizeStatusForUi('mendeteksi'),
        'Alert / Danger',
      );
      expect(
        SerialPortListener.normalizeStatusForUi('custom_status'),
        'custom_status',
      );
    });
  });
}
