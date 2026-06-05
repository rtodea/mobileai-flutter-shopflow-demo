import 'package:flutter/material.dart';

import 'types.dart';

class CSATSurvey extends StatefulWidget {
  final CSATConfig config;

  const CSATSurvey({
    super.key,
    required this.config,
  });

  @override
  State<CSATSurvey> createState() => _CSATSurveyState();
}

class _CSATSurveyState extends State<CSATSurvey> {
  int? _rating;
  final TextEditingController _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('How was your support experience?'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: List.generate(5, (index) {
            final rating = index + 1;
            return ChoiceChip(
              label: Text('$rating'),
              selected: _rating == rating,
              onSelected: (_) => setState(() => _rating = rating),
            );
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _feedbackController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Optional feedback',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _rating == null
              ? null
              : () async {
                  await widget.config.onSubmit?.call(
                    _rating!,
                    _feedbackController.text.trim().isEmpty ? null : _feedbackController.text.trim(),
                  );
                },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
