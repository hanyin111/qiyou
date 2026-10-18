import '../domain/models.dart';

abstract interface class CommunityClient {
  Future<Account> connect(String input, {String? existingDeviceId});
  Future<DailyNote> daily(Account account, Role role);
  Future<SignStatus> signInfo(Account account, Role role);
  Future<SignStatus> sign(Account account, Role role);
  void close();
}

// Community renewal is separate from initial SDK login and game write actions.
abstract interface class RenewableCommunityClient implements CommunityClient {
  Future<Account> renew(Account account);
}
