import 'package:flutter_test/flutter_test.dart';
import 'package:stream_deck/models.dart';

DeckConfig sample() => DeckConfig.fromJson({
      'cols': 3,
      'rows': 2,
      'rootPage': 'home',
      'pages': {
        'home': {
          'id': 'home',
          'name': 'Home',
          'buttons': [
            {'id': 'a', 'label': 'A', 'icon': 'x', 'color': '#ff0000', 'action': {'type': 'folder', 'page': 'sub'}},
            null,
            {'id': 'c', 'label': 'C', 'icon': 'x', 'color': '#00ff00', 'action': {'type': 'back'}},
            null,
            {'id': 'e', 'label': 'E', 'icon': 'x', 'color': '#0000ff', 'action': {'type': 'back'}},
            null,
          ],
        },
        'sub': {'id': 'sub', 'name': 'Sub', 'buttons': []},
      },
    });

void main() {
  test('custom image, active look and screens survive a JSON round-trip', () {
    final cfg = sample();
    cfg.pages['home']!.pinned = true;
    cfg.pages['home']!.icon = '🔴';
    cfg.pages['home']!.buttons[1] = DeckButton(
      id: 'x', label: 'L', icon: 'mi:mic', image: 'aGk=', iconOn: '🔇', labelOn: 'Muted', colorOn: '#b71c1c',
      action: {'type': 'toggle', 'on': {'type': 'hotkey', 'keys': 'f1'}, 'off': {'type': 'hotkey', 'keys': 'f2'}},
    );
    final again = DeckConfig.fromJson(cfg.toJson());
    final b = again.pages['home']!.buttons[1]!;
    expect(b.image, 'aGk=');
    expect(b.hasActiveLook, true);
    expect(b.action['on']['keys'], 'f1');
    expect(again.screens.map((p) => p.id), ['home']);
    expect(again.pages['sub']!.pinned, false);
  });

  test('screens falls back to the start page when none is pinned', () {
    expect(sample().screens.map((p) => p.id), ['home']);
  });

  test('describeAction covers the new macro types', () {
    expect(describeAction({'type': 'multi', 'repeat': 3, 'actions': [{}, {}]}), 'Macro (2 steps ×3)');
    expect(describeAction({'type': 'volume', 'op': 'set', 'value': 40}), 'Set volume to… 40');
    expect(describeAction(defaultAction('toggle')).startsWith('Toggle'), true);
    expect(describeAction({'type': 'widget', 'kind': 'cpu'}), 'Widget: CPU usage');
  });

  test('config round-trips through JSON', () {
    final cfg = sample();
    final again = DeckConfig.fromJson(cfg.toJson());
    expect(again.pages['home']!.buttons[2]!.id, 'c');
    expect(again.pages['sub']!.buttons.length, 6);
  });

  test('resize keeps buttons at their row/col and rescues overflow', () {
    final cfg = sample()..resize(4, 2);
    final b = cfg.pages['home']!.buttons;
    expect(b.length, 8);
    expect(b[0]!.id, 'a');
    expect(b[2]!.id, 'c');
    expect(b[5]!.id, 'e'); // row 1, col 1 stays row 1, col 1

    cfg.resize(1, 2); // c (col 2) falls off and takes a free slot
    final small = cfg.pages['home']!.buttons.whereType<DeckButton>().map((x) => x.id).toSet();
    expect(small, {'a', 'c'}); // only two slots exist; overflow refills free slots in order, e is dropped
  });

  test('deleting a page clears folder buttons that pointed to it', () {
    final cfg = sample()..deletePage('sub');
    expect(cfg.pages.containsKey('sub'), false);
    expect(cfg.pages['home']!.buttons[0], isNull);
  });

  test('colors parse and format', () {
    expect(colorToHex(parseColor('#1565c0')), '#1565c0');
    expect(parseColor('garbage').toARGB32(), 0xFF37474F);
  });
}
