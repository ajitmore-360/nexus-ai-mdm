import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Labelled text input styled for the admin dark theme.
class AdminFormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? suffixText;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const AdminFormField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.suffixText,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            fontSize: 11,
            color: AppColors.mutedText,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: AppTextStyles.inputText,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.inputHint,
            suffixText: suffixText,
            suffixStyle:
                AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
            suffix: suffix,
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Labelled dropdown styled for the admin dark theme.
/// Uses a themed [DropdownButton] inside a styled [Container] to avoid
/// the deprecated [DropdownButtonFormField.value] parameter on Flutter ≥ 3.33.
class AdminDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final void Function(T?) onChanged;

  const AdminDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 11,
              color: AppColors.mutedText,
              letterSpacing: 0.8,
            ),
          ),
        if (label.isNotEmpty) const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: DropdownButton<T>(
            value: value,
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: AppColors.elevatedCard,
            style: AppTextStyles.inputText,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.secondaryText, size: 20),
            items: items
                .map((item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text('$item', style: AppTextStyles.inputText),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// Gradient-filled primary action button used across admin pages.
class AdminGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;

  const AdminGradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Text(label,
                style: AppTextStyles.buttonMedium.copyWith(color: Colors.white)),
      ),
    );
  }
}

/// Status chip (Active/Connected = green, Invited/Pending = amber, else coral).
class AdminStatusChip extends StatelessWidget {
  final String status;
  const AdminStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg, text, border;
    if (s == 'active' || s == 'connected') {
      bg = const Color(0x1A10F090);
      text = AppColors.success;
      border = AppColors.success.withValues(alpha: 0.3);
    } else if (s == 'invited' || s == 'pending' || s == 'config needed') {
      bg = const Color(0x1AFFB800);
      text = AppColors.warning;
      border = AppColors.warning.withValues(alpha: 0.3);
    } else if (s == 'inactive' || s == 'error' || s == 'not connected') {
      bg = const Color(0x1AFF3366);
      text = AppColors.error;
      border = AppColors.error.withValues(alpha: 0.3);
    } else {
      bg = AppColors.mutedText.withValues(alpha: 0.1);
      text = AppColors.mutedText;
      border = AppColors.mutedText.withValues(alpha: 0.2);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(status,
          style: AppTextStyles.chipLabel.copyWith(color: text, fontSize: 11)),
    );
  }
}

/// Role chip: Admin=violet, Steward=cyan, Analyst=amber, Viewer=muted.
class AdminRoleChip extends StatelessWidget {
  final String role;
  const AdminRoleChip({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final r = role.toLowerCase();
    Color color;
    if (r == 'admin') {
      color = AppColors.primary;
    } else if (r == 'steward') {
      color = AppColors.cyan;
    } else if (r == 'analyst') {
      color = AppColors.warning;
    } else {
      color = AppColors.mutedText;
    }
    final label = role.isNotEmpty ? role[0].toUpperCase() + role.substring(1) : role;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: AppTextStyles.chipLabel.copyWith(color: color, fontSize: 11)),
    );
  }
}

/// Plan chip: Enterprise=violet, Pro=cyan, else muted.
class AdminPlanChip extends StatelessWidget {
  final String plan;
  const AdminPlanChip({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final p = plan.toLowerCase();
    Color color;
    if (p == 'enterprise') {
      color = AppColors.aiPurple;
    } else if (p == 'pro') {
      color = AppColors.cyan;
    } else {
      color = AppColors.secondaryText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(plan,
          style: AppTextStyles.chipLabel.copyWith(color: color, fontSize: 11)),
    );
  }
}

/// Section header: small uppercase label, 11px, muted.
class AdminSectionHeader extends StatelessWidget {
  final String label;
  const AdminSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 11,
          color: AppColors.mutedText,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Table column header text.
class AdminTableHeader extends StatelessWidget {
  final String label;
  const AdminTableHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.tableHeader.copyWith(
        fontSize: 11,
        color: AppColors.mutedText,
        letterSpacing: 1.0,
      ),
    );
  }
}
