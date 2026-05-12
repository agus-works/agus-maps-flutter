import 'package:agus_design/agus_design.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings schema matches searchable metadata', () {
    const schema = AgusSettingSchema(
      id: 'workbench.activityBar.visible',
      title: 'Workbench: Activity Bar Visible',
      description: 'Controls Activity Bar visibility.',
      category: 'Workbench',
      type: AgusSettingType.boolean,
      defaultValue: true,
      tags: ['layout'],
      options: [
        AgusSettingOption(
          value: true,
          label: 'Visible',
          description: 'Show the side activity strip.',
        ),
      ],
    );

    expect(schema.matchesQuery('activity'), isTrue);
    expect(schema.matchesQuery('layout'), isTrue);
    expect(schema.matchesQuery('side strip'), isTrue);
    expect(schema.matchesQuery('wrkb actv'), isTrue);
    expect(schema.matchesQuery('terminal'), isFalse);
  });
}
