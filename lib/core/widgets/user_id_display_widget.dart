import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_colors.dart';

/// Widget احترافي لعرض رقم تعريف المستخدم (User ID)
/// قابل لإعادة الاستخدام في جميع الشاشات مع إمكانية النسخ
class UserIdDisplayWidget extends StatelessWidget {
  final String userId;
  final String? label;
  final bool showHash;
  final bool showCopyButton;
  final VoidCallback? onCopy;
  final String? fallbackText;
  final TextStyle? textStyle;
  final double iconSize;
  final double spacing;
  final bool compact;

  const UserIdDisplayWidget({
    super.key,
    required this.userId,
    this.label,
    this.showHash = true,
    this.showCopyButton = true,
    this.onCopy,
    this.fallbackText = '------',
    this.textStyle,
    this.iconSize = 16,
    this.spacing = 4,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // TODO: استخدام القيمة الافتراضية إذا كان الـ ID فارغاً
    final displayId = userId.isEmpty ? fallbackText! : userId;
    final hasValidId = userId.isNotEmpty && userId != fallbackText;

    if (compact) {
      return _buildCompactView(context, displayId, hasValidId);
    }

    return _buildFullView(context, displayId, hasValidId);
  }

  /// العرض الكامل مع التسمية وزر النسخ
  Widget _buildFullView(BuildContext context, String displayId, bool hasValidId) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: textStyle ?? const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
        ],
        _buildIdContent(context, displayId, hasValidId),
        if (showCopyButton && hasValidId) ...[
          SizedBox(width: spacing),
          _buildCopyButton(context, displayId),
        ],
      ],
    );
  }

  /// العرض المضغط للشاشات الصغيرة
  Widget _buildCompactView(BuildContext context, String displayId, bool hasValidId) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildIdContent(context, displayId, hasValidId),
        if (showCopyButton && hasValidId) ...[
          SizedBox(width: spacing),
          _buildCopyButton(context, displayId),
        ],
      ],
    );
  }

  /// محتوى عرض الـ ID
  Widget _buildIdContent(BuildContext context, String displayId, bool hasValidId) {
    final prefix = showHash ? '#' : '';
    final formattedId = hasValidId ? '$prefix$displayId' : displayId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasValidId 
            ? AppColors.goldLight.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasValidId 
              ? AppColors.goldLight.withOpacity(0.3)
              : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        formattedId,
        style: textStyle ?? TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: hasValidId ? AppColors.goldLight : Colors.grey,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// زر النسخ
  Widget _buildCopyButton(BuildContext context, String displayId) {
    return InkWell(
      onTap: () => _handleCopy(context, displayId),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.goldLight.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.copy,
          size: iconSize,
          color: AppColors.goldLight,
        ),
      ),
    );
  }

  /// معالجة عملية النسخ
  void _handleCopy(BuildContext context, String textToCopy) {
    // FIX: استخدام Clipboard.setData مع معالجة الأخطاء
    Clipboard.setData(ClipboardData(text: textToCopy)).then((_) {
      // TODO: إظهار رسالة تأكيد عند النسخ الناجح
      _showCopySuccessSnackbar(context);
      
      // استدعاء callback مخصص إذا وجد
      onCopy?.call();
    }).catchError((error) {
      // معالجة خطأ النسخ
      _showCopyErrorSnackbar(context, error);
    });
  }

  /// عرض رسالة نجاح النسخ
  void _showCopySuccessSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('تم نسخ الـ ID بنجاح'),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  /// عرض رسالة خطأ النسخ
  void _showCopyErrorSnackbar(BuildContext context, dynamic error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('فشل نسخ الـ ID'),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(8),
      ),
    );
  }
}

/// Widget مبسط لعرض الـ ID في قوائم المستخدمين
class UserIdListItem extends StatelessWidget {
  final String userId;
  final String userName;
  final VoidCallback? onTap;
  final bool showCopyButton;

  const UserIdListItem({
    super.key,
    required this.userId,
    required this.userName,
    this.onTap,
    this.showCopyButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            userName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        UserIdDisplayWidget(
          userId: userId,
          compact: true,
          showCopyButton: showCopyButton,
          iconSize: 14,
          spacing: 2,
        ),
      ],
    );
  }
}

/// Widget لعرض الـ ID في شريط المعلومات (مثل شاشة الغرفة)
class UserIdBadge extends StatelessWidget {
  final String userId;
  final String? label;
  final Color? backgroundColor;
  final Color? textColor;

  const UserIdBadge({
    super.key,
    required this.userId,
    this.label,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final displayId = userId.isEmpty ? '------' : userId;
    final hasValidId = userId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? (hasValidId 
            ? AppColors.goldLight.withOpacity(0.15)
            : Colors.grey.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasValidId 
              ? AppColors.goldLight.withOpacity(0.4)
              : Colors.grey.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: TextStyle(
                fontSize: 11,
                color: textColor ?? Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '#$displayId',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor ?? (hasValidId 
                  ? AppColors.goldLight 
                  : Colors.grey.shade600),
              fontFamily: 'monospace',
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}