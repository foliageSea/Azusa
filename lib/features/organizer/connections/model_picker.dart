import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../shared/localization.dart';

Future<String?> showModelPicker(
  BuildContext context,
  List<String> models, {
  required String selected,
}) => showFDialog<String>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  builder: (context, style, animation) => FDialog(
    key: const ValueKey('ai-model-picker'),
    animation: animation,
    semanticsLabel: context.l10n.selectModel,
    builder: (context, style) =>
        _ModelPicker(models: models, selected: selected),
  ),
);

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.selected});

  final List<String> models;
  final String selected;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final models = widget.models
        .where((model) => model.toLowerCase().contains(query))
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.selectModel, style: context.theme.typography.body.lg),
          const SizedBox(height: 16),
          FTextField(
            key: const ValueKey('ai-model-search'),
            hint: l.searchModels,
            autocorrect: false,
            enableSuggestions: false,
            control: .managed(
              onChange: (value) =>
                  setState(() => query = value.text.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SizedBox(
              height: 320,
              child: models.isEmpty
                  ? Center(child: Text(l.noMatchingModels))
                  : ListView.builder(
                      itemCount: models.length,
                      itemBuilder: (context, index) {
                        final model = models[index];
                        return FButton(
                          variant: .ghost,
                          onPress: () => Navigator.of(context).pop(model),
                          suffix: model == widget.selected
                              ? const Icon(FLucideIcons.check)
                              : null,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(model, overflow: TextOverflow.ellipsis),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
          FButton(
            variant: .outline,
            onPress: () => Navigator.of(context).pop(),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }
}
