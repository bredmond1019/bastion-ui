/// `BastielLockup` — the gem icon + wordmark brand lockup for the app bar
/// (`ticket-brand-header-lockup` task 1), ported from
/// `../bastion-web/components/shell/wordmark.tsx`.
///
/// Web source (read in full while porting): a `Row`-equivalent flex with the
/// icon at `h-8 w-8` (32px), a `gap-2.5` (10px) gap, then the wordmark at
/// `h-[1.375rem] w-auto` (22px tall, width auto from its natural aspect
/// ratio). `select-none` has no Flutter equivalent (text selection is opt-in
/// here, not opt-out).
///
/// **The accessibility contract is part of the port, not decoration.** The
/// web comment is explicit: the lockup carries exactly **one** accessible
/// name. The icon is decorative — wrapped in [ExcludeSemantics] — and the
/// wordmark image owns the name via `Semantics(label: 'bastiel', image:
/// true)`, mirroring the web's `alt=""` (icon) / `alt="bastiel"` (wordmark)
/// split. Do not give both a label.
library;

import 'package:flutter/material.dart';

/// Source dimensions of `assets/brand/bastiel-text.png`, used to derive the
/// rendered width from the fixed 22dp render height while preserving the
/// source aspect ratio (344x64 -> ~118.25dp wide at 22dp tall).
const double _wordmarkSourceWidth = 344;
const double _wordmarkSourceHeight = 64;
const double _wordmarkRenderHeight = 22;
const double _wordmarkRenderWidth =
    _wordmarkRenderHeight * _wordmarkSourceWidth / _wordmarkSourceHeight;

/// The bastiel gem icon + wordmark lockup.
///
/// Renders the icon at 32x32, a 10dp gap, then the wordmark at 22dp tall
/// (width auto from its source aspect ratio). Exposes exactly one
/// accessible name: `"bastiel"`.
class BastielLockup extends StatelessWidget {
  const BastielLockup({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ExcludeSemantics(
          child: Image(
            image: AssetImage('assets/brand/bastiel-icon.png'),
            width: 32,
            height: 32,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          label: 'bastiel',
          image: true,
          child: const Image(
            image: AssetImage('assets/brand/bastiel-text.png'),
            height: _wordmarkRenderHeight,
            width: _wordmarkRenderWidth,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}
