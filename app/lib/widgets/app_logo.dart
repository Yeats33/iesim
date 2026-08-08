import 'package:flutter/material.dart';

import '../app/theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.teal, AppColors.tealDark],
        ),
        borderRadius: BorderRadius.circular(size * .28),
        boxShadow: [
          BoxShadow(
            color: AppColors.tealDark.withValues(alpha: 0.18),
            blurRadius: size * .36,
            offset: Offset(0, size * .12),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * .12),
        child: CustomPaint(painter: const _IeSimMarkPainter()),
      ),
    );
  }
}

class _IeSimMarkPainter extends CustomPainter {
  const _IeSimMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    final mint = Paint()
      ..color = AppColors.mintStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * .075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final white = Paint()..color = AppColors.paper;
    final teal = Paint()
      ..color = AppColors.tealDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * .045
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(unit * .18, unit * .28, unit * .64, unit * .58),
        Radius.circular(unit * .18),
      ),
      mint,
    );

    canvas.drawArc(
      Rect.fromLTWH(unit * .39, unit * .03, unit * .44, unit * .31),
      1.12 * 3.141592653589793,
      .76 * 3.141592653589793,
      false,
      mint,
    );
    canvas.drawArc(
      Rect.fromLTWH(unit * .50, unit * .15, unit * .25, unit * .17),
      1.12 * 3.141592653589793,
      .76 * 3.141592653589793,
      false,
      mint,
    );

    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(unit * .30, unit * .46, unit * .40, unit * .29),
      Radius.circular(unit * .09),
    );
    canvas.drawRRect(chip, white);
    canvas.drawLine(
      Offset(unit * .30, unit * .59),
      Offset(unit * .70, unit * .59),
      teal,
    );
    canvas.drawLine(
      Offset(unit * .43, unit * .46),
      Offset(unit * .43, unit * .75),
      teal,
    );
    canvas.drawLine(
      Offset(unit * .57, unit * .46),
      Offset(unit * .57, unit * .75),
      teal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(unit * .43, unit * .52, unit * .14, unit * .17),
        Radius.circular(unit * .045),
      ),
      Paint()..color = AppColors.mintStrong,
    );
    canvas.drawCircle(
      Offset(unit * .61, unit * .37),
      unit * .035,
      Paint()..color = AppColors.coral,
    );
  }

  @override
  bool shouldRepaint(covariant _IeSimMarkPainter oldDelegate) => false;
}
