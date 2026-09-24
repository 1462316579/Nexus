import 'package:flutter/material.dart';
import 'package:miru_app/models/extension.dart';
import 'package:miru_app/utils/i18n.dart';

/// 扩展类型筛选组件 - 可复用，统一扩展仓库和扩展页面的筛选体验
class ExtensionTypeFilter extends StatelessWidget {
  const ExtensionTypeFilter({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
    this.compact = false,
  });

  /// 当前选中的类型，null 表示全部
  final ExtensionType? selectedType;

  /// 类型变更回调
  final ValueChanged<ExtensionType?> onTypeChanged;

  /// 是否紧凑模式（用于移动端底部抽屉）
  final bool compact;

  /// 获取所有扩展类型选项（按顺序）
  static List<ExtensionType> get allTypes => [
        ExtensionType.bangumi,
        ExtensionType.manga,
        ExtensionType.fikushon,
        ExtensionType.music,
      ];

  /// 获取类型的显示文本
  String _getTypeLabel(ExtensionType type) {
    switch (type) {
      case ExtensionType.bangumi:
        return 'extension-type.video'.i18n;
      case ExtensionType.manga:
        return 'extension-type.comic'.i18n;
      case ExtensionType.fikushon:
        return 'extension-type.novel'.i18n;
      case ExtensionType.music:
        return 'extension-type.music'.i18n;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactFilter();
    }
    return _buildSegmentedFilter();
  }

  /// 紧凑模式 - 用于底部抽屉
  Widget _buildCompactFilter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ExtensionType?>(
            segments: [
              ButtonSegment(
                value: null,
                label: Text('common.show-all'.i18n),
              ),
              ...allTypes.map((type) => ButtonSegment(
                    value: type,
                    label: Text(_getTypeLabel(type)),
                  )),
            ],
            selected: <ExtensionType?>{selectedType},
            onSelectionChanged: (Set<ExtensionType?> selection) {
              onTypeChanged(selection.first);
            },
            showSelectedIcon: false,
          ),
        ),
      ],
    );
  }

  /// 分段按钮模式 - 用于桌面端内联显示
  Widget _buildSegmentedFilter() {
    return SegmentedButton<ExtensionType?>(
      segments: [
        ButtonSegment(
          value: null,
          label: Text('common.show-all'.i18n),
        ),
        ...allTypes.map((type) => ButtonSegment(
              value: type,
              label: Text(_getTypeLabel(type)),
            )),
      ],
      selected: <ExtensionType?>{selectedType},
      onSelectionChanged: (Set<ExtensionType?> selection) {
        onTypeChanged(selection.first);
      },
      showSelectedIcon: false,
    );
  }
}