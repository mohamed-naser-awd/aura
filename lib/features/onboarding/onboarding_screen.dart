import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers.dart';
import '../../core/router.dart';

/// Onboarding gate: requests runtime permissions and the default-dialer role.
/// Polls status every 0.7s so checkmarks update live and the screen auto-advances
/// to the dialer the moment Aura becomes the default phone app.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _permissions = <Permission>[
    Permission.phone,
    Permission.contacts,
    Permission.sms,
    Permission.notification,
  ];

  Timer? _timer;
  bool _refreshing = false;
  bool _permissionsGranted = false;
  bool _isDefault = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      var allGranted = true;
      for (final p in _permissions) {
        if (!await p.status.isGranted) allGranted = false;
      }
      final isDefault = await ref.read(telecomServiceProvider).isDefaultDialer();
      if (!mounted) return;
      setState(() {
        _permissionsGranted = allGranted;
        _isDefault = isDefault;
      });
      if (isDefault) {
        _timer?.cancel();
        // Refresh the gate provider so the router doesn't bounce us back, then advance.
        ref.invalidate(isDefaultDialerProvider);
        await ref.read(isDefaultDialerProvider.future);
        if (mounted) context.go(Routes.dialer);
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _requestPermissions() async {
    await _permissions.request();
    await _refresh();
  }

  Future<void> _setDefault() async {
    await ref.read(telecomServiceProvider).requestDefaultDialerRole();
    await _refresh();
  }

  Future<void> _continue() async {
    await _refresh();
    if (mounted && !_isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aura is not the default phone app yet')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('Welcome to Aura', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              const Text(
                'Aura needs to be your default phone app to manage ringing, '
                'detect who ended a call, and apply your group rules.',
              ),
              const SizedBox(height: 32),
              _Step(
                number: 1,
                title: 'Grant permissions',
                done: _permissionsGranted,
                action: FilledButton(
                  onPressed: _requestPermissions,
                  child: Text(_permissionsGranted ? 'Granted' : 'Grant'),
                ),
              ),
              const SizedBox(height: 16),
              _Step(
                number: 2,
                title: 'Set Aura as default phone app',
                done: _isDefault,
                action: FilledButton(
                  onPressed: _setDefault,
                  child: Text(_isDefault ? 'Done' : 'Set default'),
                ),
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: _continue,
                  child: const Text("I've done this — continue"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.action,
    required this.done,
  });

  final int number;
  final String title;
  final Widget action;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: done ? Colors.green : null,
          child: done
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : Text('$number'),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        action,
      ],
    );
  }
}
