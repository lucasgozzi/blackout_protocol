import 'package:flutter/material.dart';

class BoardConstants {
  static const double tileSize    = 40.0;  // smaller tiles = bigger map fits
  static const double pieceSize   = 130.0;
  static const double boardPadding = 8.0;

  // Zone overlay colors
  static const zoneStreet     = Color(0xFF1A1A28);
  static const zoneIndoor     = Color(0xFF141420);
  static const zoneExtraction = Color(0xFF0A1A0A);
  static const zoneWall       = Color(0xFF080810);

  static const tileDefault    = Color(0xFF141420);
  static const tileBorder     = Color(0xFF2A2A3E);
  static const tileWall       = Color(0xFF080810);
  static const tileDoor       = Color(0xFF1A143A);

  // Highlights
  static const highlightReachable = Color(0x5500AAFF);
  static const highlightAttack    = Color(0x55FF4444);
  static const highlightSelected  = Color(0x5500FF88);
  static const highlightObjective = Color(0x55FFAA00);
  static const highlightDoor      = Color(0x556644AA);

  // Zone border colors by type
  static const streetBorder     = Color(0xFF2A2A40);
  static const indoorBorder      = Color(0xFF1E1E30);
  static const extractionBorder  = Color(0xFF1A3A1A);

  // Piece colors
  static const playerBlue    = Color(0xFF00FF88);
  static const playerYellow  = Color(0xFFFFDD00);
  static const playerOrange  = Color(0xFFFF8800);
  static const playerRed     = Color(0xFFFF2222);
  static const enemyColor    = Color(0xFFFF4444);
  static const enemyBoss     = Color(0xFFFF0088);
}
