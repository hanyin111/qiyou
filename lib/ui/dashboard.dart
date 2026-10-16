import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/miyoushe_client.dart';
import '../domain/models.dart';
import 'design.dart';
import 'dialogs.dart';
import 'official_login.dart';
import 'note_verification.dart';

class Overview extends StatelessWidget {
  const Overview(
      {super.key,
      required this.state,
      required this.toast,
      required this.goPage});
  final AppState state;
  final ValueChanged<String> toast;
  final ValueChanged<int> goPage;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('游戏',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600))),
          IconButton(
              tooltip: '刷新',
              onPressed: state.busy
                  ? null
                  : () async {
                      await state.refresh();
                      toast(state.demo ? '演示数据已刷新' : '同步结束');
                    },
              icon: Icon(Icons.refresh_rounded,
                  size: 21, color: context.palette.secondary)),
          SizedBox(width: 9),
          FilledButton.icon(
              onPressed: state.busy || state.visibleEntries.isEmpty
                  ? null
                  : () async => toast(await state.signAll()),
              icon: Icon(
                  state.signedCount == state.entries.length
                      ? Icons.check_rounded
                      : Icons.task_alt_rounded,
                  size: 17),
              label: Text(state.busy
                  ? '处理中'
                  : state.signedCount == state.entries.length
                      ? '今日已签'
                      : '一键签到')),
        ]),
        SizedBox(height: 20),
        if (state.demo) ...[
          Row(children: [
            Expanded(
                child: Text('示例数据',
                    style: TextStyle(
                        fontSize: 12, color: context.palette.secondary))),
            TextButton(
                onPressed: () => goPage(2),
                child: Text('连接账号', style: TextStyle(fontSize: 12)))
          ]),
          SizedBox(height: 6)
        ],
        if (state.entries.length > 3) ...[
          GameFilters(state),
          SizedBox(height: 16)
        ],
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1060
              ? 3
              : constraints.maxWidth >= 680
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final entry in state.visibleEntries)
              SizedBox(
                  width: width,
                  child: GameCard(entry: entry, state: state, toast: toast))
          ]);
        }),
        if (state.activities.isNotEmpty) ...[
          SizedBox(height: 17),
          Text(state.activities.first.text,
              style: TextStyle(fontSize: 11, color: context.palette.secondary))
        ],
      ]);
}

class GameFilters extends StatelessWidget {
  const GameFilters(this.state, {super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final game in <Game?>[
          null,
          ...Game.values.where((g) =>
              state.entries.any((e) => e.role.game == g) ||
              state.tasks.any((t) => t.game == g))
        ])
          Padding(
              padding: EdgeInsets.only(right: 8),
              child: ChoiceChip(
                  label: Text(game?.shortTitle ?? '全部'),
                  selected: state.filter == game,
                  showCheckmark: false,
                  selectedColor: context.palette.text,
                  backgroundColor: context.palette.surface,
                  labelStyle: TextStyle(
                      fontSize: 12,
                      color: state.filter == game
                          ? context.palette.surface
                          : context.palette.secondary),
                  padding: EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                  side: BorderSide(
                      color: state.filter == game
                          ? context.palette.text
                          : context.palette.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                  onSelected: (_) => state.setFilter(game))),
        if (!state.demo && state.accounts.length > 1)
          DropdownButton<String?>(
              value: state.accountFilter,
              underline: SizedBox(),
              hint: Text('全部账号'),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('全部账号')),
                for (final account in state.accounts)
                  DropdownMenuItem(
                      value: account.id, child: Text(account.title)),
              ],
              onChanged: state.setAccountFilter),
      ]));
}

class GameCard extends StatelessWidget {
  const GameCard(
      {super.key,
      required this.entry,
      required this.state,
      required this.toast});
  final GameEntry entry;
  final AppState state;
  final ValueChanged<String> toast;
  @override
  Widget build(BuildContext context) {
    final game = entry.role.game;
    final note = entry.note;
    return Surface(
        padding: EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GameMark(game, size: 44),
            SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(game.shortTitle,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 3),
                  Text('${entry.role.nickname} · ${entry.role.serverName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: context.palette.secondary)),
                ])),
            Tooltip(
                message: '查看${game.shortTitle}详情',
                child: InkWell(
                    onTap: () => showGameDetails(context, state, entry, toast),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (entry.signStatus.isDone)
                            Icon(Icons.check_rounded,
                                color: context.palette.accent, size: 13),
                          Text(
                              entry.signStatus == SignStatus.pending
                                  ? '未签'
                                  : entry.signStatus.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: entry.signStatus.isDone
                                      ? context.palette.accent
                                      : context.palette.secondary)),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              color: context.palette.secondary, size: 15),
                        ])))),
          ]),
          SizedBox(height: 19),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${note?.energy ?? '—'}',
                style: TextStyle(
                    fontSize: 31,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.8)),
            SizedBox(width: 5),
            Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text('/ ${note?.capacity ?? '—'}',
                    style: TextStyle(
                        fontSize: 13, color: context.palette.secondary))),
            Spacer(),
            Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text(_recovery(note),
                    style: TextStyle(
                        fontSize: 10, color: context.palette.secondary))),
          ]),
          SizedBox(height: 10),
          ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  minHeight: 4,
                  value: note?.ratio ?? 0,
                  backgroundColor: context.palette.selected,
                  color: context.palette.accent)),
          SizedBox(height: 11),
          Wrap(spacing: 20, runSpacing: 6, children: [
            for (final metric in note?.metrics ?? [Metric('日常', '等待同步')])
              Text('${metric.label}  ${metric.value}',
                  style: TextStyle(
                      fontSize: 10,
                      color: metric.complete
                          ? context.palette.accent
                          : context.palette.secondary))
          ]),
          if (entry.error != null) ...[
            SizedBox(height: 12),
            Text(entry.error!,
                style: TextStyle(
                    fontSize: 11, color: context.palette.error, height: 1.7)),
            if (!state.demo &&
                supportsOfficialLogin &&
                entry.noteError != null &&
                (entry.role.game.community == Community.miyoushe ||
                    !entry.noteNeedsVerification))
              TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          if (entry.noteNeedsVerification) {
                            await openNoteVerification(context, state, entry);
                          } else {
                            try {
                              await state.refreshNote(entry);
                            } on MiyousheException {
                              // The card displays the updated failure.
                            }
                          }
                        },
                  child:
                      Text(entry.noteNeedsVerification ? '完成安全验证' : '重试体力查询')),
          ],
        ]));
  }

  String _recovery(DailyNote? note) {
    final time = note?.remainingAt(DateTime.now());
    if (time == null) return note == null ? '回满时间待同步' : '回满时间暂未提供';
    if (time.inSeconds <= 0) return '预计已回满';
    final minutes = (time.inSeconds / 60).ceil();
    return minutes >= 60
        ? '${minutes ~/ 60}h ${minutes % 60}m 回满'
        : '${minutes}m 回满';
  }
}

class TaskPanel extends StatelessWidget {
  const TaskPanel({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final tasks = state.visibleTasks;
    return Surface(
        padding: EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('手动清单',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            Text('${state.doneTasks}/${state.tasks.length}',
                style:
                    TextStyle(fontSize: 12, color: context.palette.secondary)),
            IconButton(
                tooltip: '添加待办',
                onPressed: () => showAddTask(context, state),
                icon: Icon(Icons.add_rounded,
                    size: 20, color: context.palette.accent))
          ]),
          if (tasks.isEmpty)
            Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Text('暂无待办，点 + 添加。',
                    style: TextStyle(
                        fontSize: 12, color: context.palette.secondary))),
          for (var i = 0; i < tasks.length; i++) ...[
            InkWell(
                onTap: state.busy ? null : () => state.toggleTask(tasks[i]),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      SizedBox(
                          width: 24,
                          height: 28,
                          child: Checkbox(
                              value: tasks[i].done,
                              onChanged: state.busy
                                  ? null
                                  : (_) => state.toggleTask(tasks[i]),
                              activeColor: context.palette.accent,
                              side: BorderSide(color: context.palette.line),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5)))),
                      SizedBox(width: 10),
                      Expanded(
                          child: Text(tasks[i].title,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: tasks[i].done
                                      ? context.palette.secondary
                                      : context.palette.text,
                                  decoration: tasks[i].done
                                      ? TextDecoration.lineThrough
                                      : null))),
                      SizedBox(width: 8),
                      GameMark(tasks[i].game, size: 24),
                    ]))),
            if (i < tasks.length - 1) Divider(height: 1),
          ],
        ]));
  }
}
