import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../models/task_model.dart';

/// نافذة مكافأة المهمة المطابقة بالكامل لـ dialog_task_coin.xml
class TaskRewardDialog extends StatelessWidget {
  final TaskModel task;

  const TaskRewardDialog({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // خلفية نافذة المكافأة bg_get_task_coin
              Image.asset(
                R.bgGetTaskCoin,
                fit: BoxFit.fill,
                width: double.infinity,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 60),
                  // تهانينا (congratulations)
                  const Text(
                    'تهانينا',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD6BF),
                      shadows: [
                        Shadow(
                          color: Color(0xFF944307),
                          offset: Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // قيمة المكافأة مع أيقونة mini_coins
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        R.miniCoins,
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+${task.coinsReward > 0 ? task.coinsReward : task.expReward}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFECB15),
                          shadows: [
                            Shadow(
                              color: Color(0xFF614C00),
                              offset: Offset(0, 2),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // زر التأكيد (confirm)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 45),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE301),
                        borderRadius: BorderRadius.circular(60),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFDE301).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'تأكيد',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
