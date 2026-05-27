import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../models/player.dart';

/// Shows a dialog listing [players] for the user to pick one.
///
/// Returns the selected player's id, an empty string if the user chose
/// "Clear", or null if the dialog was dismissed.
Future<String?> showPlayerPickerDialog(
  BuildContext context,
  List<Player> players, {
  String title = 'Choose a player',
  bool includeClear = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppTheme.dialogBg,
      shape: AppTheme.dialogShape,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < players.length; i++)
              ListTile(
                leading: CircleAvatar(backgroundColor: players[i].color, radius: 12),
                title: Text(
                  _playerLabel(players, i),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, players[i].id),
              ),
            if (includeClear) ...[
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.clear, color: Colors.white38, size: 20),
                title: const Text(
                  'Clear',
                  style: TextStyle(color: Colors.white38),
                ),
                onTap: () => Navigator.pop(context, ''),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

String _playerLabel(List<Player> players, int index) {
  final p = players[index];
  final base = switch (p.seatPosition) {
    SeatPosition.topEdge    => 'Top',
    SeatPosition.bottomEdge => 'Bottom',
    SeatPosition.leftSide   => 'Left',
    SeatPosition.rightSide  => 'Right',
  };
  final samePos = players.where((q) => q.seatPosition == p.seatPosition).toList();
  if (samePos.length == 1) return base;
  return '$base ${samePos.indexOf(p) + 1}';
}
