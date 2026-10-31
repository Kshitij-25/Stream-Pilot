import 'package:flutter/material.dart';

import '../connection.dart';
import '../models.dart';
import '../widgets/action_form.dart';

class _Param {
  final String key;
  final String label;
  final String? hint;
  final bool number;
  const _Param(this.key, this.label, {this.hint, this.number = false});
}

class _Trigger {
  final String label;
  final List<_Param> params;
  final String vars;
  const _Trigger(this.label, {this.params = const [], this.vars = ''});
}

const _triggers = <String, _Trigger>{
  'obs.streamStarted': _Trigger('OBS: stream started'),
  'obs.streamStopped': _Trigger('OBS: stream stopped'),
  'obs.recordStarted': _Trigger('OBS: recording started'),
  'obs.recordStopped': _Trigger('OBS: recording stopped'),
  'obs.scene': _Trigger('OBS: scene changed', params: [_Param('scene', 'Only for scene (blank = any)')], vars: '{{scene}}'),
  'obs.connected': _Trigger('OBS: connected'),
  'twitch.follow': _Trigger('Twitch: new follower', vars: '{{user}}'),
  'twitch.sub': _Trigger('Twitch: subscription', vars: '{{user}}'),
  'twitch.gift': _Trigger('Twitch: gifted subs', vars: '{{user}} {{amount}}'),
  'twitch.cheer': _Trigger('Twitch: bits cheered', params: [_Param('minBits', 'Minimum bits', number: true)], vars: '{{user}} {{bits}} {{message}}'),
  'twitch.raid': _Trigger('Twitch: raid', params: [_Param('minViewers', 'Minimum raiders', number: true)], vars: '{{user}} {{viewers}}'),
  'twitch.redeem': _Trigger('Twitch: channel point reward', params: [_Param('reward', 'Reward title (blank = any)')], vars: '{{user}} {{reward}} {{message}}'),
  'twitch.chatCommand': _Trigger('Twitch: chat command', params: [_Param('command', 'Command', hint: '!hello')], vars: '{{user}} {{args}} {{message}}'),
  'twitch.online': _Trigger('Twitch: went live'),
  'twitch.offline': _Trigger('Twitch: went offline'),
  'youtube.superchat': _Trigger('YouTube: Super Chat', params: [_Param('minAmount', 'Minimum amount', number: true)], vars: '{{user}} {{amount}} {{message}}'),
  'youtube.member': _Trigger('YouTube: new member', vars: '{{user}}'),
  'youtube.chatCommand': _Trigger('YouTube: chat command', params: [_Param('command', 'Command', hint: '!hello')], vars: '{{user}} {{args}} {{message}}'),
  'app.foreground': _Trigger('App in focus (auto profile switching)', params: [_Param('process', 'Process name', hint: 'obs64.exe')], vars: '{{process}}'),
  'schedule': _Trigger('Time of day', params: [_Param('time', 'Time (24h HH:MM)', hint: '20:00')]),
  'system.cpu': _Trigger('CPU above', params: [_Param('above', 'Percent', number: true)], vars: '{{cpu}}'),
  'device.connected': _Trigger('A phone connected', vars: '{{device}}'),
};

class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key});

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  List<Json>? _rules;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rules != null || _error != null) return;
    ConnScope.of(context).rpc('automations.get').then((d) {
      if (mounted) setState(() => _rules = [for (final r in d as List) Map<String, dynamic>.from(r as Map)]);
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  Future<void> _save() async {
    try {
      final saved = await ConnScope.of(context).rpc('automations.save', {'rules': _rules}) as List;
      if (mounted) setState(() => _rules = [for (final r in saved) Map<String, dynamic>.from(r as Map)]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _edit(Json? existing) async {
    final result = await Navigator.of(context).push<Json>(MaterialPageRoute(
      builder: (_) => _RuleEditor(rule: existing == null ? {'name': '', 'enabled': true, 'trigger': {'type': 'obs.streamStarted'}, 'cooldown': 0, 'actions': <Json>[]} : jsonCopy(existing)),
    ));
    if (result == null) return;
    setState(() {
      final i = existing == null ? -1 : _rules!.indexWhere((r) => r['id'] == existing['id']);
      if (i >= 0) {
        _rules![i] = result;
      } else {
        _rules!.add(result);
      }
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    return Scaffold(
      appBar: AppBar(title: const Text('Automations')),
      floatingActionButton: rules == null ? null : FloatingActionButton.extended(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('New rule')),
      body: _error != null
          ? Center(child: Text(_error!))
          : rules == null
              ? const Center(child: CircularProgressIndicator())
              : rules.isEmpty
                  ? const Center(child: Text('No rules yet'))
                  : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                      for (final r in rules)
                        ListTile(
                          title: Text('${r['name']}'),
                          subtitle: Text('${_triggers[(r['trigger'] as Map)['type']]?.label ?? (r['trigger'] as Map)['type']} → ${(r['actions'] as List).length} action(s)'),
                          onTap: () => _edit(r),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              tooltip: 'Run now (test)',
                              onPressed: () async {
                                try {
                                  await ConnScope.of(context).rpc('automations.test', {'id': r['id']});
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rule ran. See Action history.')));
                                } catch (e) {
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                                }
                              },
                            ),
                            Switch(
                              value: r['enabled'] == true,
                              onChanged: (v) {
                                setState(() => r['enabled'] = v);
                                _save();
                              },
                            ),
                          ]),
                        ),
                    ]),
    );
  }
}

Json jsonCopy(Json j) => Map<String, dynamic>.from((j.entries.map((e) => MapEntry(e.key, _deep(e.value)))).fold<Map<String, dynamic>>({}, (m, e) => m..[e.key] = e.value));

dynamic _deep(dynamic v) => v is Map
    ? {for (final e in v.entries) e.key as String: _deep(e.value)}
    : v is List
        ? [for (final x in v) _deep(x)]
        : v;

class _RuleEditor extends StatefulWidget {
  final Json rule;
  const _RuleEditor({required this.rule});

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final Json r = widget.rule;
  late final _name = TextEditingController(text: '${r['name']}');
  late final _cool = TextEditingController(text: '${r['cooldown'] ?? 0}');
  final _params = <String, TextEditingController>{};

  Json get trigger => r['trigger'] as Json;

  TextEditingController _p(String key) => _params.putIfAbsent(key, () => TextEditingController(text: '${trigger[key] ?? ''}'));

  @override
  void dispose() {
    _name.dispose();
    _cool.dispose();
    for (final c in _params.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = trigger['type'] as String;
    final def = _triggers[type];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule['id'] == null ? 'New rule' : 'Edit rule'),
        actions: [
          TextButton(
            onPressed: () {
              r['name'] = _name.text.trim().isEmpty ? (def?.label ?? 'Rule') : _name.text.trim();
              r['cooldown'] = int.tryParse(_cool.text) ?? 0;
              Navigator.pop(context, r);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'When'),
          items: [for (final e in _triggers.entries) DropdownMenuItem(value: e.key, child: Text(e.value.label, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() {
            r['trigger'] = {'type': v};
            for (final c in _params.values) {
              c.dispose();
            }
            _params.clear();
          }),
        ),
        for (final p in def?.params ?? const <_Param>[])
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _p(p.key),
              keyboardType: p.number ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(labelText: p.label, hintText: p.hint),
              onChanged: (v) => trigger[p.key] = p.number ? (num.tryParse(v) ?? 0) : v,
            ),
          ),
        if (type == 'schedule')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, children: [
              for (var d = 0; d < 7; d++)
                FilterChip(
                  label: Text(const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d]),
                  selected: ((trigger['days'] ?? const []) as List).contains(d),
                  onSelected: (v) => setState(() {
                    final days = List<int>.from((trigger['days'] ?? const []) as List);
                    v ? days.add(d) : days.remove(d);
                    trigger['days'] = days;
                  }),
                ),
            ]),
          ),
        if (type == 'twitch.chatCommand')
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Moderators only'), value: trigger['modOnly'] == true, onChanged: (v) => setState(() => trigger['modOnly'] = v)),
        const SizedBox(height: 12),
        TextField(controller: _cool, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cooldown (seconds between runs)')),
        const Divider(height: 36),
        Text('Then run', style: Theme.of(context).textTheme.titleMedium),
        if ((def?.vars ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Variables you can use in text fields: ${def!.vars}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ),
        StepList(action: r, listKey: 'actions', onChanged: () => setState(() {})),
        const SizedBox(height: 40),
      ]),
    );
  }
}
