import 'package:test/test.dart';
import 'package:iesim_core/src/result.dart';

void main() {
  group('Result', () {
    test('Ok 携带值且可模式匹配', () {
      const Result<int> ok = Ok(42);
      final result = switch (ok) {
        Ok(value: final v) => v,
        Err() => 0,
      };
      expect(result, equals(42));
    });

    test('Err 携带失败原因且可模式匹配', () {
      const Result<int> err = Err(StoreError('磁盘写入失败'));
      final message = switch (err) {
        Ok() => '',
        Err(failure: final f) => f.toString(),
      };
      expect(message, contains('磁盘写入失败'));
    });

    test('失败类型为可辨识密封族', () {
      const StoreError e = StoreError('x');
      expect(e, isA<Failure>());
    });
  });
}
