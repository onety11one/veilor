// Historical implementation, e3c19f1eb1225dbd48a4862f0983b82d0af8de69.
// Test oracle only. GPL-3.0-or-later; see NOTICE.md.
// ignore_for_file: strict_raw_type, inference_failure_on_collection_literal
abstract final class DeepCopyUtils {
  static dynamic mapCopy(dynamic obj) {
    if (obj is! Map) {
      return obj;
    }
    var mapCopied = {};
    obj.forEach((key, value) {
      mapCopied[key] = mapCopy(value);
    });
    return mapCopied;
  }
}
