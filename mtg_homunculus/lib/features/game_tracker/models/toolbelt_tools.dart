import 'package:flutter/material.dart';
import 'toolbelt_tool.dart';
import '../tools/coin_flip_tool.dart';
import '../tools/die_roller_tool.dart';
import '../tools/initiative_tool.dart';
import '../tools/monarch_tool.dart';
import '../tools/random_player_tool.dart';

const kToolbeltTools = <ToolbeltTool>[
  UtilityTool(icon: Icons.toll_outlined,   label: 'Coin Flip',  action: showCoinFlipDialog),
  UtilityTool(icon: Icons.casino_outlined, label: 'Die Roller', action: showDieRollerDialog),
  MonarchTool(),
  InitiativeTool(),
  RandomPlayerTool(),
];
