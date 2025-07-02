import 'package:flutter/material.dart';

double getResponsiveFontSize(BuildContext context, double baseSize) {
  final screenWidth = MediaQuery.of(context).size.width;
  // 기준 너비를 375(iPhone SE)로 설정
  const baseWidth = 375.0;
  final scaleFactor = screenWidth / baseWidth;
  // 폰트 크기가 너무 커지거나 작아지는 것을 방지하기 위해 최소/최대값 설정
  return (baseSize * scaleFactor).clamp(baseSize * 0.8, baseSize * 1.5);
}
