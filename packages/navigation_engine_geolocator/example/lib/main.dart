import 'dart:async';

import 'package:flutter/material.dart';
import 'package:navigation_engine/navigation_engine.dart';
import 'package:navigation_engine_geolocator/navigation_engine_geolocator.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'navigation_engine_geolocator example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1A73E8)),
      home: const FixesScreen(),
    ),
  );
}

/// Shows the latest device GPS fix, or the latest error.
class FixesScreen extends StatefulWidget {
  const FixesScreen({super.key});

  @override
  State<FixesScreen> createState() => _FixesScreenState();
}

class _FixesScreenState extends State<FixesScreen> {
  // A NavigationSession would take it as `NavigationSession(fixes: _source)`
  // and start and stop it itself.
  final _source = GeolocatorFixSource();
  late final StreamSubscription<NavFix> _subscription;
  NavFix? _fix;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _subscription = _source.fixes.listen(
      (fix) => setState(() {
        _fix = fix;
        _error = null;
      }),
      onError: (Object error) => setState(() => _error = error),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _source.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_source.isRunning) {
        _source.stop();
      } else {
        _error = null;
        _source.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fix = _fix;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Device GPS')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.titleMedium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              if (error != null)
                Text(
                  '$error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (fix == null)
                const Text('No fix yet')
              else ...[
                Text(
                  '${fix.position.lat.toStringAsFixed(6)}, '
                  '${fix.position.lng.toStringAsFixed(6)}',
                ),
                Text('± ${fix.accuracy.toStringAsFixed(1)} m'),
                Text('Speed: ${_or(fix.speed, 'm/s')}'),
                Text('Heading: ${_or(fix.heading, '°')}'),
                Text('At ${TimeOfDay.fromDateTime(fix.time).format(context)}'),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggle,
        icon: Icon(_source.isRunning ? Icons.stop : Icons.my_location),
        label: Text(_source.isRunning ? 'Stop' : 'Start'),
      ),
    );
  }

  static String _or(double? value, String unit) =>
      value == null ? 'unknown' : '${value.toStringAsFixed(1)} $unit';
}
