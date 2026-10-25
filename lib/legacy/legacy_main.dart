import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/tasko_store.dart';
import 'data/task_query.dart';
import 'models.dart';
import 'ui/task_detail_screen.dart';
import 'ui/task_routes.dart';
import 'theme.dart';
import 'ui/core_screens.dart';
import 'ui/secondary_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  SupabaseClient? client;
  String? startupError;
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      await Supabase.initialize(url: url, publishableKey: key);
      client = Supabase.instance.client;
    } catch (_) {
      startupError = 'Не удалось подключиться к базе. Проверьте локальный Supabase и перезапустите приложение.';
    }
  }
  final store = TaskoStore(client: client);
  try {
    await store.initialize();
    if (const bool.fromEnvironment('TASKO_DEMO')) {
      await store.enterDemo();
    }
  } catch (_) {
    startupError =
        'Не удалось загрузить данные. Проверьте подключение и повторите вход.';
  }
  runApp(TaskoApp(store: store, startupError: startupError));
}

class TaskoApp extends StatelessWidget {
  final TaskoStore store;
  final String? startupError;
  const TaskoApp({super.key, required this.store, this.startupError});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      key: ValueKey(store.isAuthenticated),
      title: 'Tasko',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: taskoTheme(Brightness.light),
      darkTheme: taskoTheme(Brightness.dark),
      themeMode: switch (store.theme) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      },
      home: store.isAuthenticated
          ? TaskoShell(store: store)
          : AuthScreen(store: store),
      builder: (context, child) => startupError == null
          ? child!
          : Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        startupError!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
                Expanded(child: child!),
              ],
            ),
    ),
  );
}

class TaskoShell extends StatefulWidget {
  final TaskoStore store;
  const TaskoShell({super.key, required this.store});
  @override
  State<TaskoShell> createState() => _TaskoShellState();
}

class _TaskoShellState extends State<TaskoShell> {
  int selected = 0;
  String? selectedProjectId, selectedTaskId;
  static const labels = ['Сводка', 'Задачи', 'Проекты', 'Команда', 'Входящие'];
  static const icons = [
    Symbols.space_dashboard_sharp,
    Symbols.checklist_sharp,
    Symbols.folder_sharp,
    Symbols.group_sharp,
    Symbols.inbox_sharp,
  ];
  void open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  void select(int index) => setState(() {
    selected = index;
    selectedProjectId = null;
    selectedTaskId = null;
  });
  Future<void> search() async {
    final task = await showSearch<TaskoTask?>(
      context: context,
      delegate: _TaskSearch(widget.store),
    );
    if (!mounted || task == null) return;
    if (MediaQuery.sizeOf(context).width >= 1200) {
      setState(() {
        selected = 1;
        selectedProjectId = null;
        selectedTaskId = task.id;
      });
    } else {
      await showTaskDetails(context, widget.store, task: task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final width = MediaQuery.sizeOf(context).width;
    final expanded = width > 840;
    final rail = width >= 600 && !expanded;
    final sideBySide = width >= 1200;
    Widget page = switch (selected) {
      0 => DashboardScreen(
        store: store,
        onProjects: () => select(2),
        onProfile: () => open(ProfileScreen(store: store)),
        onCalendar: () => open(CalendarScreen(store: store)),
        onReports: () => open(ReportsScreen(store: store)),
      ),
      1 => TasksScreen(
        store: store,
        onTaskSelected: sideBySide
            ? (id) => setState(() => selectedTaskId = id)
            : null,
      ),
      2 =>
        selectedProjectId != null &&
                store.projects.any((p) => p.id == selectedProjectId)
            ? BoardScreen(
                store: store,
                projectId: selectedProjectId!,
                onBack: () => setState(() => selectedProjectId = null),
              )
            : ProjectsScreen(
                store: store,
                onOpenProject: (id) => setState(() => selectedProjectId = id),
              ),
      3 => TeamScreen(store: store),
      _ => InboxScreen(store: store),
    };
    if (sideBySide && selected == 1 && selectedTaskId != null) {
      page = Row(
        children: [
          Expanded(child: page),
          const VerticalDivider(width: 1),
          SizedBox(
            width: width > 1200 ? 440 : 380,
            child: TaskDetailScreen(
              store: store,
              taskId: selectedTaskId!,
              embedded: true,
              onClose: () => setState(() => selectedTaskId = null),
              onTaskCopied: (id) => setState(() => selectedTaskId = id),
              onEdit: (context, task) =>
                  showTaskEditor(context, store, task: task),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (expanded) ...[
              _drawer(context, store),
              const VerticalDivider(width: 1),
            ] else if (rail) ...[
              NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: select,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (var i = 0; i < 5; i++)
                    NavigationRailDestination(
                      icon: Icon(icons[i], weight: 300),
                      selectedIcon: Icon(icons[i], weight: 300, fill: 1),
                      label: Text(labels[i]),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Column(
                children: [
                  if (store.error != null)
                    MaterialBanner(
                      content: Text(store.error!),
                      actions: [
                        TextButton(
                          onPressed: store.busy
                              ? null
                              : () async {
                                  try {
                                    await store.refresh();
                                  } catch (_) {}
                                },
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  if (store.busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(child: page),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: width >= 600
          ? null
          : Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: select,
                destinations: [
                  for (var i = 0; i < 5; i++)
                    NavigationDestination(
                      icon: Icon(icons[i], weight: 300),
                      selectedIcon: Icon(icons[i], weight: 300, fill: 1),
                      label: labels[i],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _drawer(BuildContext context, TaskoStore store) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 256,
      child: Material(
        color: colors.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Tasko', style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    store.isDemo ? 'Демонстрация' : 'Моё пространство',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: search,
                    icon: const Icon(Symbols.search_sharp, size: 20),
                    label: const Text('Поиск задач'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final index in [0, 1, 4, 3])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: selected == index
                            ? colors.secondaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: ListTile(
                          dense: true,
                          minTileHeight: 48,
                          leading: Icon(
                            icons[index],
                            weight: 300,
                            fill: selected == index ? 1 : 0,
                          ),
                          title: Text(
                            index == 1 ? 'Мои задачи' : labels[index],
                            style: text.titleSmall,
                          ),
                          trailing: index == 1
                              ? Text(
                                  '${store.tasks.where((t) => t.status != TaskStatus.done).length}',
                                  style: text.bodySmall,
                                )
                              : null,
                          onTap: () => select(index),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => select(2),
                          child: const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Проекты'),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Создать проект',
                        onPressed: () => showProjectEditor(context, store),
                        icon: const Icon(Symbols.add_sharp),
                      ),
                    ],
                  ),
                  for (final project in store.projects.where(
                    (p) => !p.archived,
                  ))
                    Material(
                      color: selected == 2 && selectedProjectId == project.id
                          ? colors.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      child: ListTile(
                        dense: true,
                        minTileHeight: 48,
                        leading: Text(project.key, style: monoStyle(context)),
                        title: Text(
                          project.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                        onTap: () => setState(() {
                          selected = 2;
                          selectedProjectId = project.id;
                          selectedTaskId = null;
                        }),
                      ),
                    ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Symbols.calendar_month_sharp),
                    title: const Text('Календарь'),
                    onTap: () => open(CalendarScreen(store: store)),
                  ),
                  ListTile(
                    leading: const Icon(Symbols.bar_chart_sharp),
                    title: const Text('Отчёты'),
                    onTap: () => open(ReportsScreen(store: store)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                radius: 16,
                child: Text(store.profile.initials, style: text.labelMedium),
              ),
              title: Text(store.profile.name, style: text.bodyMedium),
              trailing: const Icon(Symbols.settings_sharp, size: 20),
              onTap: () => open(SettingsScreen(store: store)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _TaskSearch extends SearchDelegate<TaskoTask?> {
  final TaskoStore store;
  _TaskSearch(this.store) : super(searchFieldLabel: 'Поиск задач');
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      tooltip: 'Очистить поиск',
      onPressed: () => query = '',
      icon: const Icon(Symbols.close_sharp),
    ),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: 'Назад',
    onPressed: () => close(context, null),
    icon: const Icon(Symbols.arrow_back_sharp),
  );
  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
  Widget _results(BuildContext context) {
    final tasks = TaskQuery(
      text: query,
      showCompleted: true,
      includeArchived: true,
    ).apply(store.tasks, store.projects, DateTime.now());
    return tasks.isEmpty
        ? const Center(child: Text('Задачи не найдены'))
        : ListView(
            children: [
              for (final task in tasks)
                ListTile(
                  title: Text(task.title),
                  subtitle: Text(
                    '${taskKey(task, store.projects.where((p) => p.id == task.projectId).firstOrNull)} · ${task.issueType.label} · ${task.status.label}',
                  ),
                  onTap: () => close(context, task),
                ),
            ],
          );
  }
}
