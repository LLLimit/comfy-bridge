import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/workflow_definition.dart';

typedef WorkflowSubmit = Future<void> Function(
  Map<String, dynamic> values,
  Map<String, XFile> assets,
);

class DynamicWorkflowForm extends StatefulWidget {
  const DynamicWorkflowForm({
    super.key,
    required this.workflow,
    required this.submitting,
    required this.onSubmit,
  });

  final WorkflowDefinition workflow;
  final bool submitting;
  final WorkflowSubmit onSubmit;

  @override
  State<DynamicWorkflowForm> createState() => _DynamicWorkflowFormState();
}

class _DynamicWorkflowFormState extends State<DynamicWorkflowForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, dynamic> _values = {};
  final Map<String, XFile> _assets = {};
  bool _advancedOpen = false;
  bool _imagesOpen = false;
  bool _audiosOpen = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant DynamicWorkflowForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workflow.id != widget.workflow.id ||
        oldWidget.workflow.revision != widget.workflow.revision) {
      _reset();
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _reset() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    _values.clear();
    _assets.clear();
    _advancedOpen = false;
    _imagesOpen = false;
    _audiosOpen = false;
    for (final input in widget.workflow.inputs) {
      _values[input.key] = input.defaultValue;
      if ({'text', 'textarea', 'number', 'seed'}.contains(input.widget)) {
        _textControllers[input.key] = TextEditingController(
          text: input.defaultValue?.toString() ?? '',
        );
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final regular = widget.workflow.inputs
        .where((item) => !item.advanced)
        .toList();
    final parameters = regular
        .where((item) => item.valueType != 'asset')
        .toList();
    final images = regular
        .where((item) => item.widget == 'imagePicker')
        .toList();
    final audios = regular
        .where((item) => item.widget == 'audioPicker')
        .toList();
    final advanced = widget.workflow.inputs
        .where((item) => item.advanced)
        .toList();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final input in parameters) ...[
            _buildInput(input),
            const SizedBox(height: 18),
          ],
          if (images.isNotEmpty) ...[
            _assetSection(
              title: '参考图片',
              icon: Icons.photo_library_outlined,
              inputs: images,
              expanded: _imagesOpen,
              onExpansionChanged: (value) => _imagesOpen = value,
            ),
            const SizedBox(height: 12),
          ],
          if (audios.isNotEmpty) ...[
            _assetSection(
              title: '参考音频',
              icon: Icons.audio_file_outlined,
              inputs: audios,
              expanded: _audiosOpen,
              onExpansionChanged: (value) => _audiosOpen = value,
            ),
            const SizedBox(height: 12),
          ],
          if (advanced.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                initiallyExpanded: _advancedOpen,
                onExpansionChanged: (value) => _advancedOpen = value,
                title: const Text('高级设置'),
                subtitle: Text('${advanced.length} 个参数'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                children: [
                  for (final input in advanced) ...[
                    _buildInput(input),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: widget.submitting ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: widget.submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              widget.submitting ? '正在提交…' : widget.workflow.submitLabel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _assetSection({
    required String title,
    required IconData icon,
    required List<WorkflowInput> inputs,
    required bool expanded,
    required ValueChanged<bool> onExpansionChanged,
  }) {
    final selected = inputs
        .where((input) => _assets.containsKey(input.key))
        .length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('已添加 $selected / ${inputs.length}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        children: [
          for (final input in inputs) ...[
            _buildInput(input),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  Widget _buildInput(WorkflowInput input) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                input.label,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (!input.required)
              Text(
                '可选',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
          ],
        ),
        if (input.description != null) ...[
          const SizedBox(height: 4),
          Text(
            input.description!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
        const SizedBox(height: 10),
        switch (input.widget) {
          'textarea' => _textField(input, maxLines: 5),
          'text' => _textField(input),
          'number' => _numberField(input),
          'seed' => _seedField(input),
          'slider' => _slider(input),
          'switch' => _switch(input),
          'select' => _select(input),
          'chips' => _chips(input),
          'imagePicker' => _imagePicker(input),
          'audioPicker' => _audioPicker(input),
          _ => Text('暂不支持的字段类型：${input.widget}'),
        },
      ],
    );
  }

  Widget _textField(WorkflowInput input, {int maxLines = 1}) {
    return TextFormField(
      controller: _textControllers[input.key],
      maxLines: maxLines,
      minLines: maxLines == 1 ? 1 : 3,
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      decoration: InputDecoration(hintText: input.label),
      validator: (value) {
        if (input.required && (value == null || value.trim().isEmpty)) {
          return '请填写${input.label}';
        }
        final maxLength = input.constraints['maxLength'] as int?;
        if (maxLength != null && (value?.length ?? 0) > maxLength) {
          return '最多输入 $maxLength 个字符';
        }
        return null;
      },
      onChanged: (value) => _values[input.key] = value,
    );
  }

  Widget _numberField(WorkflowInput input) {
    return TextFormField(
      controller: _textControllers[input.key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      validator: (value) {
        if (input.required && (value == null || value.isEmpty)) return '请输入数值';
        if (value != null && value.isNotEmpty && num.tryParse(value) == null) {
          return '请输入有效数值';
        }
        return null;
      },
      onChanged: (value) {
        _values[input.key] = input.valueType == 'integer'
            ? int.tryParse(value)
            : double.tryParse(value);
      },
    );
  }

  Widget _seedField(WorkflowInput input) {
    return TextFormField(
      controller: _textControllers[input.key],
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: '留空为随机',
        suffixIcon: IconButton(
          tooltip: '随机 Seed',
          onPressed: () {
            final value =
                DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFFFFFFFFFF;
            _textControllers[input.key]!.text = '$value';
            _values[input.key] = value;
          },
          icon: const Icon(Icons.casino_outlined),
        ),
      ),
      onChanged: (value) => _values[input.key] = int.tryParse(value),
    );
  }

  Widget _slider(WorkflowInput input) {
    final minimum = (input.constraints['min'] as num? ?? 0).toDouble();
    final maximum = (input.constraints['max'] as num? ?? 100).toDouble();
    final step = (input.constraints['step'] as num? ?? 1).toDouble();
    final raw = (_values[input.key] as num? ?? minimum).toDouble();
    final value = raw.clamp(minimum, maximum);
    final displayValue = step < 1
        ? value.toStringAsFixed(1)
        : value.round().toString();
    final divisions = ((maximum - minimum) / step).round();
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${minimum.round()}'),
            Text(
              displayValue,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text('${maximum.round()}'),
          ],
        ),
        Slider(
          value: value,
          min: minimum,
          max: maximum,
          divisions: divisions > 0 ? divisions : null,
          onChanged: (next) => setState(() {
            _values[input.key] = input.valueType == 'integer'
                ? next.round()
                : next;
          }),
        ),
      ],
    );
  }

  Widget _switch(WorkflowInput input) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _values[input.key] as bool? ?? false,
      onChanged: (value) => setState(() => _values[input.key] = value),
      title: Text((_values[input.key] as bool? ?? false) ? '已开启' : '已关闭'),
    );
  }

  Widget _select(WorkflowInput input) {
    return DropdownButtonFormField<Object>(
      initialValue: _values[input.key],
      items: [
        for (final option in input.options)
          DropdownMenuItem(value: option.value, child: Text(option.label)),
      ],
      onChanged: (value) => setState(() => _values[input.key] = value),
    );
  }

  Widget _chips(WorkflowInput input) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final option in input.options)
          ChoiceChip(
            label: Text(option.label),
            selected: _values[input.key] == option.value,
            onSelected: (_) =>
                setState(() => _values[input.key] = option.value),
          ),
      ],
    );
  }

  Widget _imagePicker(WorkflowInput input) {
    final asset = _assets[input.key];
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final selected = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
        );
        if (selected != null && mounted) {
          setState(() => _assets[input.key] = selected.xFile);
        }
      },
      child: Container(
        height: 116,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: asset == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 32),
                    SizedBox(height: 8),
                    Text('从相册选择图片'),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.image_outlined, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          asset.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: '移除',
                        onPressed: () =>
                            setState(() => _assets.remove(input.key)),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _audioPicker(WorkflowInput input) {
    final asset = _assets[input.key];
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final selected = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['mp3', 'wav', 'm4a', 'flac', 'ogg'],
        );
        if (selected != null && mounted) {
          setState(() => _assets[input.key] = selected.xFile);
        }
      },
      child: Container(
        height: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: asset == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.audio_file_outlined, size: 32),
                    SizedBox(height: 8),
                    Text('选择音频文件'),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.graphic_eq, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          asset.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: '移除',
                        onPressed: () =>
                            setState(() => _assets.remove(input.key)),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    for (final input in widget.workflow.inputs) {
      if (input.valueType == 'asset' &&
          input.required &&
          !_assets.containsKey(input.key)) {
        setState(() {
          if (input.widget == 'imagePicker') _imagesOpen = true;
          if (input.widget == 'audioPicker') _audiosOpen = true;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('请选择${input.label}')));
        return;
      }
    }
    await widget.onSubmit(
      Map<String, dynamic>.from(_values),
      Map.from(_assets),
    );
  }
}
