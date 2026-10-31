import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:local_auth/local_auth.dart';

import '../../theme/cardy_palette.dart';

/// Locks Cardy behind the device's biometric or screen-lock authentication
/// on launch and whenever the app returns from the background.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _locked = true;
  bool _authenticating = false;
  bool _checkingAvailability = true;
  bool _backgrounded = false;
  bool _deviceSupportsLock = true;
  DateTime? _unlockedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlockWithAuth());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
      _lockInBackground();
      return;
    }
    if (state != AppLifecycleState.resumed || !_backgrounded) return;
    _backgrounded = false;
    if (_locked && !_authenticating) _unlockWithAuth();
  }

  void _lockInBackground() {
    if (!mounted || _locked || _authenticating || !_deviceSupportsLock) return;
    final justUnlocked = _unlockedAt != null &&
        DateTime.now().difference(_unlockedAt!) < const Duration(seconds: 2);
    if (justUnlocked) return;
    setState(() => _locked = true);
  }

  Future<void> _unlockWithAuth() async {
    if (_authenticating || !_locked) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    var authenticated = false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        _deviceSupportsLock = false;
        _checkingAvailability = false;
        if (mounted) {
          setState(() {
            _locked = false;
            _authenticating = false;
          });
        }
        return;
      }
      authenticated = await _auth.authenticate(
        localizedReason: 'Unlock Cardy to view your saved cards',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (error) {
      _error = 'Could not start authentication. $error';
    }
    _checkingAvailability = false;
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      if (authenticated) {
        _locked = false;
        _unlockedAt = DateTime.now();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: _locked, child: widget.child),
          if (_locked)
            _LockScreen(
              authenticating: _authenticating,
              checking: _checkingAvailability,
              error: _error,
              onUnlock: _unlockWithAuth,
            ),
        ],
      );
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.authenticating,
    required this.checking,
    required this.error,
    required this.onUnlock,
  });

  final bool authenticating;
  final bool checking;
  final String? error;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: appBackground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: softSurface,
                      border: Border.all(color: panelBorder),
                    ),
                    alignment: Alignment.center,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedLock,
                      size: 34,
                      color: brandAccentDeep,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Cardy is locked',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Authenticate with your fingerprint, face or screen lock to view your saved cards.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, height: 1.4),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: authenticating || checking ? null : onUnlock,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: isCardyDarkMode
                            ? const Color(0xFF111111)
                            : Colors.white,
                      ),
                      icon: authenticating || checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const HugeIcon(
                              icon: HugeIcons.strokeRoundedFingerPrint),
                      label: Text(
                        authenticating ? 'Authenticating…' : 'Unlock Cardy',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
