import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/core/utils/permission_handler_util.dart';

void main() {
  group('PermissionHandlerUtil.isPublicStoragePath', () {
    test('treats shared Download folders as public', () {
      expect(
        PermissionHandlerUtil.isPublicStoragePath(
          '/storage/emulated/0/Download',
        ),
        isTrue,
      );
    });

    test('treats app-private Android paths as not public', () {
      expect(
        PermissionHandlerUtil.isPublicStoragePath(
          '/storage/emulated/0/Android/data/com.ytdownloader.app/files',
        ),
        isFalse,
      );
      expect(
        PermissionHandlerUtil.isPublicStoragePath(
          '/data/user/0/com.ytdownloader.app/files',
        ),
        isFalse,
      );
    });
  });
}
