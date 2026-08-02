import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/wakewall_theme.dart';
import 'wakewall_notice.dart';

const wakeWallPrivacyPolicyUrl =
    'https://samprecious.github.io/wakewall-privacy/';

typedef PrivacyPolicyLauncher = Future<bool> Function(Uri uri);

Future<bool> _openPrivacyPolicyExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

// Quiet Settings footer that opens WakeWall's policy in the user's browser.
class PrivacyPolicyAction extends StatelessWidget {
  const PrivacyPolicyAction({
    this.launcher = _openPrivacyPolicyExternally,
    super.key,
  });

  final PrivacyPolicyLauncher launcher;

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    var opened = false;
    try {
      opened = await launcher(Uri.parse(wakeWallPrivacyPolicyUrl));
    } catch (_) {
      // Browser availability is reported through WakeWall's normal notice.
    }
    if (!opened && context.mounted) {
      showWakeWallNotice(
        context,
        message: 'WakeWall couldn\'t open the privacy policy.',
        icon: Icons.error_outline_rounded,
        iconColor: context.wakeWallColors.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Semantics(
      key: const ValueKey('privacy-policy-action'),
      container: true,
      link: true,
      label: 'Privacy Policy',
      value: 'How WakeWall handles your data',
      hint: 'Opens in your browser',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _open(context),
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 22, color: colors.muted),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Privacy Policy',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'How WakeWall handles your data',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
