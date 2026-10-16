import 'package:flutter_test/flutter_test.dart';
import 'package:qiyou/app_state.dart';
import 'package:qiyou/data/device_bridge.dart';
import 'package:qiyou/data/miyoushe_client.dart';
import 'package:qiyou/data/record_browser_session.dart';
import 'package:qiyou/domain/models.dart';

class SessionTestStore extends DeviceBridge {
  SessionTestStore(this.rejectWrite);
  final bool rejectWrite;
  @override
  Future<void> write(String value) async {
    if (rejectWrite) throw StateError('synthetic store failure');
  }
}

void main() {
  for (final rejectWrite in [false, true]) {
    test(
        'Browser session retains login and commits after storage: reject=$rejectWrite',
        () async {
      final state = AppState(bridge: SessionTestStore(rejectWrite));
      addTearDown(state.dispose);
      final entry = state.entries.first;
      final original = Account(
          id: entry.accountId,
          cookie: 'account_id=1; cookie_token=test-original',
          deviceId: 'old-device',
          roles: [entry.role]);
      state.demo = false;
      state.accounts = [original];
      final session = RecordBrowserSession.fromCookies({
        'DEVICEFP': 'official-fingerprint',
        '_MHYUUID': 'official-device-id',
        'cookie_token': 'must-not-replace-auth'
      }, 'Windows browser')!;
      if (rejectWrite) {
        await expectLater(state.installRecordBrowserSession(entry, session),
            throwsStateError);
        expect(state.accounts.single, same(original));
      } else {
        await state.installRecordBrowserSession(entry, session);
        final updated = state.accounts.single;
        expect(updated.id, original.id);
        expect(MiyousheClient.parseCookie(updated.cookie)['cookie_token'],
            'test-original');
        expect(updated.deviceId, 'official-device-id');
        expect(
            updated.recordHeaders['x-rpc-device_fp'], 'official-fingerprint');
      }
      expect(state.busy, isFalse);
    });
  }
}
