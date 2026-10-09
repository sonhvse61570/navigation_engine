/// How much the navigation speaks, as the sound button offers it.
enum AudioGuidance {
  /// Turn-by-turn directions and alerts.
  sound,

  /// Alerts only (traffic, crashes, works), no turn-by-turn directions.
  alertsOnly,

  /// Nothing.
  muted,
}
