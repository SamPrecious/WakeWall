import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/wakewall_theme.dart';

const _noticeVisibleDuration = Duration(milliseconds: 2800);
const _noticeEnterDuration = Duration(milliseconds: 320);
const _noticeExitDuration = Duration(milliseconds: 260);

// Shows every short app message with the same compact Android-style layout.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showWakeWallNotice(
  BuildContext context, {
  required String message,
  required IconData icon,
  Color? iconColor,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final colors = context.wakeWallColors;
  final messenger = ScaffoldMessenger.of(context);
  final screenWidth = MediaQuery.sizeOf(context).width;
  final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;
  final horizontalMargin = math.max(28.0, (screenWidth - 330) / 2);
  final bottomMargin = math.max(28.0, bottomSafeArea + 24);
  messenger.hideCurrentSnackBar();
  final notice = messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(
        horizontalMargin,
        0,
        horizontalMargin,
        bottomMargin,
      ),
      duration: _noticeVisibleDuration,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      dismissDirection: DismissDirection.down,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor ?? colors.muted, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: colors.tealStrong,
              onPressed: () {
                HapticFeedback.selectionClick();
                (onAction ?? () {})();
              },
            ),
    ),
    snackBarAnimationStyle: const AnimationStyle(
      duration: _noticeEnterDuration,
      reverseDuration: _noticeExitDuration,
    ),
  );
  Timer? timeout;
  if (actionLabel != null) {
    timeout = Timer(_noticeVisibleDuration, () {
      if (context.mounted) {
        messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
      }
    });
  }
  notice.closed.whenComplete(() => timeout?.cancel());
  return notice;
}
