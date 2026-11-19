/// Category management: the buckets expenses are filed under, and a monthly limit for each.
///
/// Lists the active categories with their colour, icon, both names and limit; archived ones sit in
/// a collapsible section where they can be restored. Tapping a category opens the editor (name,
/// Amharic name, colour, icon, monthly limit). Deleting asks first, and the server decides the
/// outcome: a category nothing uses is deleted, one with expenses is archived so history stays
/// readable — the snackbar says which happened.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';
import '../../../platform/settings.dart';
import '../../../shared/category_visuals.dart';
import '../../../shared/month_data.dart';
import '../../../shared_kernel/money.dart';
import '../../expenses/presentation/expense_providers.dart' show categoriesProvider;

/// Every category, archived included, for this screen.
final allCategoriesProvider = FutureProvider<List<CategoryDto>>((ref) async {
  return ref.watch(categoriesApiProvider).list(includeArchived: true);
});

void _refreshCategories(WidgetRef ref) {
  ref.invalidate(allCategoriesProvider);
  ref.invalidate(categoriesProvider);
  invalidateMonthData(ref);
}

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  bool _showArchived = false;

  Future<void> _restore(CategoryDto category, AppSettings settings) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(categoriesApiProvider).restore(category.id);
      _refreshCategories(ref);
      messenger?.showSnackBar(SnackBar(content: Text(settings.say('ተመልሷል', 'Restored'))));
    } on ApiException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(allCategoriesProvider);
    final budgets = {
      for (final b in ref.watch(budgetsProvider).valueOrNull ?? const <BudgetDto>[])
        if (b.categoryId != null) b.categoryId!: b.amount,
    };

    return Scaffold(
      appBar: AppBar(title: Text(settings.say('ምድቦች', 'Categories'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('category-add'),
        icon: const Icon(Icons.add_rounded),
        label: Text(settings.say('ምድብ ጨምር', 'Add category')),
        onPressed: () => showCategoryEditor(context),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is ApiException
                    ? error.message
                    : settings.say('ምድቦችን መጫን አልተቻለም', 'Could not load categories'),
              ),
              TextButton(
                onPressed: () => ref.invalidate(allCategoriesProvider),
                child: Text(settings.say('እንደገና ሞክር', 'Retry')),
              ),
            ],
          ),
        ),
        data: (list) {
          final active = list.where((c) => !c.isArchived).toList();
          final archived = list.where((c) => c.isArchived).toList();
          return RefreshIndicator(
            onRefresh: () async => _refreshCategories(ref),
            child: ListView(
              key: const Key('categories-list'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                for (final category in active)
                  _CategoryTile(
                    category: category,
                    budget: budgets[category.id],
                    settings: settings,
                    onTap: () => showCategoryEditor(
                      context,
                      category: category,
                      budget: budgets[category.id],
                    ),
                  ),
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    key: const Key('categories-show-archived'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      settings.say('የተቀመጡ (${archived.length})', 'Archived (${archived.length})'),
                    ),
                    trailing: Icon(
                      _showArchived ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    ),
                    onTap: () => setState(() => _showArchived = !_showArchived),
                  ),
                  if (_showArchived)
                    for (final category in archived)
                      _CategoryTile(
                        category: category,
                        budget: null,
                        settings: settings,
                        trailing: TextButton(
                          key: Key('category-restore-${category.id}'),
                          onPressed: () => _restore(category, settings),
                          child: Text(settings.say('መልስ', 'Restore')),
                        ),
                      ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.budget,
    required this.settings,
    this.onTap,
    this.trailing,
  });

  final CategoryDto category;
  final Money? budget;
  final AppSettings settings;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = categoryColor(category.color);
    final other = settings.isAmharic ? category.name : category.nameAm;
    final details = [
      if (other != null && other.isNotEmpty) other,
      if (budget != null)
        settings.say(
          'ገደብ ${Money(budget!.minorUnits, settings.currency).formatRounded()}',
          'Limit ${Money(budget!.minorUnits, settings.currency).formatRounded()}',
        ),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        key: Key('category-${category.id}'),
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: category.isArchived ? 0.06 : 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(categoryIcon(category.icon), color: color, size: 20),
        ),
        title: Text(
          settings.isAmharic ? (category.nameAm ?? category.name) : category.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: category.isArchived ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

/// Open the editor. With [category] it edits (and offers delete); without, it creates.
Future<void> showCategoryEditor(BuildContext context, {CategoryDto? category, Money? budget}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CategoryEditorSheet(category: category, budget: budget),
    );

class CategoryEditorSheet extends ConsumerStatefulWidget {
  const CategoryEditorSheet({super.key, this.category, this.budget});

  final CategoryDto? category;
  final Money? budget;

  @override
  ConsumerState<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<CategoryEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.category?.name ?? '');
  late final TextEditingController _nameAm = TextEditingController(
    text: widget.category?.nameAm ?? '',
  );
  late final TextEditingController _budget = TextEditingController(
    text: widget.budget == null ? '' : widget.budget!.majorUnits.round().toString(),
  );
  late String _color = (widget.category?.color ?? categoryPalette.first).toUpperCase();
  // A new category starts with a neutral icon; an existing one keeps what it has (even none).
  late String? _icon = widget.category == null ? 'more_horiz' : widget.category!.icon;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.category != null;

  @override
  void dispose() {
    _name.dispose();
    _nameAm.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final settings = ref.read(settingsProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    final categories = ref.read(categoriesApiProvider);
    final budgets = ref.read(budgetsApiProvider);
    final nameAm = _nameAm.text.trim();
    try {
      final category = widget.category;
      final saved = category == null
          ? await categories.create(
              name: _name.text.trim(),
              nameAm: nameAm.isEmpty ? null : nameAm,
              color: _color,
              icon: _icon,
            )
          : await categories.update(
              category.id,
              name: _name.text.trim() != category.name ? _name.text.trim() : null,
              nameAm: nameAm != (category.nameAm ?? '') ? nameAm : null,
              color: _color != category.color.toUpperCase() ? _color : null,
              icon: _icon != category.icon ? _icon : null,
            );
      final limit = double.tryParse(_budget.text.trim());
      if (limit != null && limit > 0) {
        final minor = Money.fromMajor(limit, settings.currency).minorUnits;
        if (minor != widget.budget?.minorUnits) await budgets.setForCategory(saved.id, minor);
      } else if (widget.budget != null) {
        await budgets.clearForCategory(saved.id);
      }
      _refreshCategories(ref);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final settings = ref.read(settingsProvider);
    final category = widget.category!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(settings.say('${category.name} ልሰርዝ?', 'Delete ${category.name}?')),
        content: Text(
          settings.say(
            'ወጪዎች ካሉበት ታሪኩ እንዲቆይ ይቀመጣል እንጂ አይሰረዝም።',
            'If expenses use it, it is archived instead so their history stays readable.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(settings.say('ተመለስ', 'Cancel')),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(settings.say('ሰርዝ', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      final archived = await ref.read(categoriesApiProvider).remove(category.id);
      _refreshCategories(ref);
      if (mounted) Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            archived == null
                ? settings.say('ተሰርዟል', 'Deleted')
                : settings.say('ወጪዎች ስላሉበት ተቀምጧል', 'Archived, because expenses use it'),
          ),
        ),
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + viewInsets),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editing
                    ? settings.say('ምድብ አስተካክል', 'Edit category')
                    : settings.say('አዲስ ምድብ', 'New category'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('category-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: settings.say('ስም (በእንግሊዝኛ)', 'Name'),
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? settings.say('ስም ያስፈልጋል', 'A name is required')
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('category-name-am'),
                controller: _nameAm,
                decoration: InputDecoration(
                  labelText: settings.say('ስም በአማርኛ (አማራጭ)', 'Amharic name (optional)'),
                  prefixIcon: const Icon(Icons.translate_rounded),
                ),
              ),
              const SizedBox(height: 18),
              Text(settings.say('ቀለም', 'Colour'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final hex in categoryPalette)
                    Semantics(
                      button: true,
                      selected: _color == hex,
                      label: hex,
                      child: InkWell(
                        key: Key('category-color-$hex'),
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _color = hex),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: categoryColor(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == hex ? scheme.onSurface : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: _color == hex
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(settings.say('ምልክት', 'Icon'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in categoryIconNames)
                    IconButton(
                      key: Key('category-icon-$name'),
                      tooltip: name,
                      isSelected: _icon == name,
                      style: IconButton.styleFrom(
                        backgroundColor: _icon == name
                            ? categoryColor(_color).withValues(alpha: 0.18)
                            : null,
                      ),
                      icon: Icon(
                        categoryIcon(name),
                        color: _icon == name ? categoryColor(_color) : scheme.onSurfaceVariant,
                      ),
                      onPressed: () => setState(() => _icon = name),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const Key('category-budget'),
                controller: _budget,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: settings.say('የወር ገደብ (አማራጭ)', 'Monthly limit (optional)'),
                  helperText: settings.say(
                    'ማጠቃለያው 80% ሲደርስ ያስጠነቅቃል',
                    'The summary warns you at 80%',
                  ),
                  prefixIcon: const Icon(Icons.savings_outlined),
                  suffixText: settings.currency,
                ),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return null;
                  final value = num.tryParse(text);
                  return (value == null || value <= 0)
                      ? settings.say('ትክክለኛ መጠን ያስገቡ', 'Enter a valid amount')
                      : null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('category-error'),
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('category-save'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(settings.say('አስቀምጥ', 'Save')),
              ),
              if (_editing) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('category-delete'),
                  onPressed: _saving ? null : _delete,
                  icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
                  label: Text(
                    settings.say('ሰርዝ', 'Delete category'),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
