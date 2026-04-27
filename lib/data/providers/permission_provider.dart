library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/permission_handler_util.dart';

/// Tracks whether storage permission is currently granted.
final StateProvider<bool> storagePermissionProvider =
    StateProvider<bool>((Ref ref) => false);

/// Checks and updates storage permission status.
final FutureProvider<bool> storagePermissionCheckerProvider =
    FutureProvider<bool>((Ref ref) async {
      final bool granted = await PermissionHandlerUtil.hasStoragePermission();
      ref.read(storagePermissionProvider.notifier).state = granted;
      return granted;
    });
