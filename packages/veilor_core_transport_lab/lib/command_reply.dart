import 'dart:convert';

enum ReplyKind { accepted, rejected }

/// Conservative subset of statically observed handler output. Never retains
/// server error text or extra payload. Does not assert that a VPN is connected.
ReplyKind parseCommandReply(List<int> bytes, {required bool reload}) {
  final Object? decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic> || !decoded.containsKey('err')) {
    throw const FormatException('Invalid command reply');
  }
  final error = decoded['err'];
  if (error != null) {
    if (error is! String) throw const FormatException('Invalid error type');
    return ReplyKind.rejected;
  }
  if (reload && (!decoded.containsKey('extra') || decoded['extra'] != null)) {
    throw const FormatException('Unverified success shape');
  }
  return ReplyKind.accepted;
}
