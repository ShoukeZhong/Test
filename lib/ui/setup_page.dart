import 'package:flutter/material.dart';

import '../anim/pet_painter.dart';
import '../sim/profile.dart';
import '../sim/species.dart';
import '../sim/state.dart';
import '../sim/world.dart';
import 'pet_world_page.dart';
import 'storage.dart';

/// 迎接新生命：選物種、名字、毛色、個性描述。按下後牠就從出生開始以真實時間長大。
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  Species _species = Species.cat;
  int _coat = 0;
  final _name = TextEditingController(text: '小橘');
  final _desc = TextEditingController(text: '很黏人、有點怕生、貪吃');

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _birth() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final (traits, _) = compileTraits(_species, _desc.text);
    final name = _name.text.trim().isEmpty ? (_species == Species.cat ? '小貓' : '小狗') : _name.text.trim();
    final st = PetState.newborn(species: _species, name: name, traits: traits, coat: _coat, nowMs: now);
    final w = World()
      ..food = 0
      ..water = 0.3;
    await Store.save(st, w);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => PetWorldPage(state: st, world: w)));
  }

  @override
  Widget build(BuildContext context) {
    final coats = coatsOf(_species);
    final (traits, matched) = compileTraits(_species, _desc.text);
    final info = infoOf(_species);
    return Scaffold(
      appBar: AppBar(title: const Text('迎接新生命')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('牠會從出生那一刻開始，用真實時間長大、變老，最後離開。'
              '${info.label}的壽命大約 ${info.lifespanMinYears.toStringAsFixed(0)}–${info.lifespanMaxYears.toStringAsFixed(0)} 年。'),
          const SizedBox(height: 16),
          SegmentedButton<Species>(
            segments: const [
              ButtonSegment(value: Species.cat, label: Text('貓')),
              ButtonSegment(value: Species.dog, label: Text('狗')),
            ],
            selected: {_species},
            onSelectionChanged: (v) => setState(() {
              _species = v.first;
              _coat = 0;
            }),
          ),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: '名字'), maxLength: 12),
          const Text('毛色'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < coats.length; i++)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: coats[i].base),
                label: Text(coats[i].name),
                selected: _coat == i,
                onSelected: (_) => setState(() => _coat = i),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: '個性（一句話描述）'),
            maxLines: 2,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(matched.isEmpty ? '沒有認出個性詞，會用預設個性' : '認出：${matched.join('、')}',
              style: Theme.of(context).textTheme.bodySmall),
          Text(
            '活力 ${(traits.activity * 100).round()}　親人 ${(traits.sociability * 100).round()}　膽小 ${(traits.fearfulness * 100).round()}'
            '　衝動 ${(traits.impulsiveness * 100).round()}　貪吃 ${(traits.appetite * 100).round()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _birth, child: const Text('讓牠出生')),
          const SizedBox(height: 24),
          Text('怎麼跟牠相處', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          const Text('・用手指摸牠：頭、臉頰、背。摸太久或摸肚子，貓可能會不耐煩。\n'
              '・在地板上滑動手指，牠會像追逗貓棒一樣追。\n'
              '・把右上角的飼料袋或水壺拖到碗的上方，就會倒出來。\n'
              '・在貓砂盆或地上的便便上來回滑動，就能清掉。\n'
              '・拖起紅色的球再放手，就能丟球。\n'
              '・對著手機說話、拍手，牠聽得到；在前鏡頭前揮手，牠看得到。\n'
              '・聲音和影像只在手機裡即時運算，不錄存、不上傳。\n'
              '・剛出生的頭幾週由媽媽照顧；斷奶後，吃喝拉撒就靠你了。'),
        ],
      ),
    );
  }
}
