import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

/// Reusable 2-line expandable text widget with ".. more" / "less" action toggle.
class ExpandableText extends StatefulWidget {
  final String text;
  final int maxLines;
  final TextStyle style;
  final Color linkColor;

  const ExpandableText({
    super.key,
    required this.text,
    this.maxLines = 2,
    required this.style,
    this.linkColor = AppColors.primaryAccent,
  });

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _isExpanded ? null : widget.maxLines,
          overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: widget.style,
        ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(
              _isExpanded ? 'less' : '.. more',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: widget.linkColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
