import 'dart:async';
import 'dart:math';

import 'package:bilancio_familiare_app/bloc/category/category_bloc.dart';
import 'package:bilancio_familiare_app/bloc/entry/entry_bloc.dart';
import 'package:bilancio_familiare_app/cards/app_button.dart';
import 'package:bilancio_familiare_app/cards/custom_app_bar.dart';
import 'package:bilancio_familiare_app/cards/entry_item_dialog.dart';
import 'package:bilancio_familiare_app/database/models/category.dart';
import 'package:bilancio_familiare_app/database/models/entry.dart';
import 'package:bilancio_familiare_app/database/models/entry_item.dart';
import 'package:bilancio_familiare_app/helpers/currency_input_formatter.dart';
import 'package:bilancio_familiare_app/helpers/format_helper.dart';
import 'package:bilancio_familiare_app/models/enums.dart';
import 'package:bilancio_familiare_app/router/app_router_paths.dart';
import 'package:bilancio_familiare_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EntryDetailsPage extends StatefulWidget {
  const EntryDetailsPage({super.key});

  @override
  State<EntryDetailsPage> createState() => _EntryDetailsPageState();
}

class _EntryDetailsPageState extends State<EntryDetailsPage> {
  final _formKey = GlobalKey<FormState>();

  late EntryBloc? _entryBloc;

  late TextEditingController _numericController;
  late TextEditingController _descriptionController;
  late TextEditingController _dateController;

  late FocusNode _descriptionFocus;
  late FocusNode _priceFocus;

  Timer? _descriptionDebounce;
  int _descriptionRequest = 0;
  List<DescriptionSuggestion> _descriptionSuggestions = [];

  List<Category> _categories = [];

  /// Voci della spesa in modifica: quando non sono vuote il prezzo è la loro
  /// somma e il campo diventa di sola lettura.
  List<EntryItem> _items = [];

  double get _itemsTotal =>
      _items.fold<double>(0, (sum, item) => sum + item.price);

  int? _entryId;
  bool _initialized = false;
  bool _saving = false;
  String? _saveRequestId;

  String _newSaveRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  int? _selectedCategoryId;
  Category? get _selectedCategory => _categoryById(_selectedCategoryId);

  Category? _categoryById(int? id) =>
      _categories.where((category) => category.id == id).firstOrNull;

  // Validation for numeric input
  String? _validateNumericInput(String? value) {
    if (value != null && value.isNotEmpty) {
      final number = FormatHelper.formatStringToCurrency(value);
      if (number == null) {
        return 'Inserisci un numero valido';
      }
    }
    return null;
  }

  // Validation for string input
  String? _validateStringInput(String? value) {
    if (value == null || value.isEmpty) {
      return 'Inserisci una descrizione valida';
    }
    return null;
  }

  void _clearDescriptionSuggestions() {
    _descriptionDebounce?.cancel();
    _descriptionRequest++;
    if (_descriptionSuggestions.isNotEmpty) {
      setState(() => _descriptionSuggestions = []);
    }
  }

  void _onDescriptionFocusChanged() {
    if (!_descriptionFocus.hasFocus) {
      _clearDescriptionSuggestions();
    }
  }

  void _onDescriptionChanged(String value) {
    _clearDescriptionSuggestions();
    final text = value.trim();
    final categoryId = _selectedCategoryId;
    if (_entryId != null || categoryId == null || text.length < 2) {
      return;
    }

    final request = _descriptionRequest;
    _descriptionDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final suggestions =
            await _entryBloc!.findDescriptionSuggestions(text, categoryId);
        if (mounted && request == _descriptionRequest) {
          setState(() => _descriptionSuggestions = suggestions);
        }
      } catch (_) {
        // Suggestions are optional. The description can still be typed.
      }
    });
  }

  void _selectDescription(DescriptionSuggestion suggestion) {
    _clearDescriptionSuggestions();
    final description = suggestion.description;
    _descriptionController.value = TextEditingValue(
      text: description,
      selection: TextSelection.collapsed(offset: description.length),
    );
    if (suggestion.categoryId != _selectedCategoryId &&
        _categoryById(suggestion.categoryId) != null) {
      context.read<CategoryBloc>().add(ChangeCategory(suggestion.categoryId));
    }
  }

  Widget _buildDescriptionSuggestions() {
    return TextFieldTapRegion(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: ListTile.divideTiles(
            color: AppColors.outline,
            tiles: _descriptionSuggestions.map(_buildDescriptionSuggestion),
          ).toList(),
        ),
      ),
    );
  }

  Widget _buildDescriptionSuggestion(DescriptionSuggestion suggestion) {
    final category = _categoryById(suggestion.categoryId);
    return ListTile(
      dense: true,
      minTileHeight: 44,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Row(
        children: [
          Expanded(
            flex: 6,
            child: Text(
              suggestion.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (category != null) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Tooltip(
                  message: category.name,
                  excludeFromSemantics: true,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.brandDark,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () => _selectDescription(suggestion),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) {
      return;
    }
    _initialized = true;

    // Read the arguments once: doing this in build() would overwrite the
    // controllers (and clear any text selection) on every rebuild.
    final Object? args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic> && args['entry'] is Entry) {
      _loadEntryFromArguments(
        args['entry'] as Entry,
        keepId: args['duplicate'] != true,
      );
    }
  }

  @override
  void initState() {
    _numericController = TextEditingController();
    _descriptionController = TextEditingController();
    _dateController = TextEditingController();
    _dateController.text = FormatHelper.formatDateToString(DateTime.now());

    _descriptionFocus = FocusNode();
    _descriptionFocus.addListener(_onDescriptionFocusChanged);
    _priceFocus = FocusNode();

    _entryBloc = context.read<EntryBloc>();

    context.read<CategoryBloc>().add(LoadCategories());
    super.initState();
  }

  @override
  void dispose() {
    _descriptionDebounce?.cancel();
    _descriptionFocus.removeListener(_onDescriptionFocusChanged);
    _dateController.dispose();
    _numericController.dispose();
    _descriptionController.dispose();

    _descriptionFocus.dispose();
    _priceFocus.dispose();

    _entryBloc?.add(SetEntryInitialState());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: _entryId == null ? 'Aggiungi spesa' : 'Aggiorna spesa',
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _saving
                ? null
                : () {
                    final category = _selectedCategory;
                    if (category == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Seleziona una categoria')),
                      );
                      return;
                    }

                    if (!_formKey.currentState!.validate()) {
                      return;
                    }

                    // Con le voci il prezzo è sempre la loro somma.
                    final double? price = _items.isNotEmpty
                        ? _itemsTotal
                        : (_numericController.text.isNotEmpty
                            ? FormatHelper.formatStringToCurrency(
                                _numericController.text)
                            : null);

                    final Entry entry = Entry(
                        date: FormatHelper.formatStringToDate(
                            _dateController.text),
                        description: _descriptionController.text,
                        price: price,
                        categoryId: category.id,
                        isIncoming: category.isIncoming,
                        items: List<EntryItem>.of(_items));

                    setState(() => _saving = true);
                    if (_entryId == null) {
                      _clearDescriptionSuggestions();
                      _entryBloc?.add(AddNewEntry(
                        entry,
                        requestId: _saveRequestId ??= _newSaveRequestId(),
                      ));
                    } else {
                      _entryBloc?.add(UpdateEntry(_entryId!, entry));
                    }
                  },
          )
        ],
      ),
      body: MultiBlocListener(
        listeners: [
          BlocListener<EntryBloc, EntryState>(
            listenWhen: (previous, current) =>
                current is EntryAdded ||
                current is EntryUpdated ||
                current is EntryRemoved ||
                current is EntryError,
            listener: (context, state) {
              if (state is EntryError) {
                if (_saving) setState(() => _saving = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message)),
                );
                return;
              }

              // Go to home page after entry adding/updating
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacementNamed(RoutePaths.home);
              }
            },
          ),
          BlocListener<CategoryBloc, CategoryState>(
            listenWhen: (previous, current) =>
                current is CategoryListLoading ||
                current is CategoryListLoaded ||
                current is CategoryChanged,
            listener: (context, state) {
              if (state is CategoryListLoading) {
                //return const CircularProgressIndicator();
              } else if (state is CategoryListLoaded) {
                // Sort a copy: the list belongs to the bloc state.
                _categories = [...state.categories]
                  ..sort((a, b) => a.name.compareTo(b.name));

                if (_selectedCategoryId == null && _categories.isNotEmpty) {
                  _selectedCategoryId = _categories
                      .firstWhere((c) => c.isDefault,
                          orElse: () => _categories.first)
                      .id;
                }
              } else if (state is CategoryChanged) {
                _clearDescriptionSuggestions();
                _selectedCategoryId = state.selectedCategoryId;
              }
            },
          ),
        ],
        child: BlocBuilder<EntryBloc, EntryState>(
          buildWhen: (previous, current) =>
              current is EntryLoaded ||
              current is EntryOperationInProgress ||
              current is EntryError,
          builder: (context, entryState) {
            return BlocBuilder<CategoryBloc, CategoryState>(
              buildWhen: (previous, current) =>
                  current is CategoryListLoading ||
                  current is CategoryListLoaded ||
                  current is CategoryChanged ||
                  current is CategoryError,
              builder: (context, state) {
                if (state is CategoryListLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is CategoryError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        AppButton('Riprova', () {
                          context.read<CategoryBloc>().add(LoadCategories());
                        }),
                      ],
                    ),
                  );
                }

                return Container(
                  margin: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category
                          const Text('Categoria'),
                          const SizedBox(height: 10),
                          BlocBuilder<CategoryBloc, CategoryState>(
                            buildWhen: (previous, current) =>
                                current is CategoryChanged,
                            builder: (context, state) {
                              if (_selectedCategory != null) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  child: Column(
                                    spacing: 5,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                            color: AppColors.brand
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: AppColors.brand,
                                                width: 2)),
                                        child: IconButton(
                                          onPressed: () {
                                            context
                                                .read<CategoryBloc>()
                                                .add(ChangeCategory(null));
                                          },
                                          icon: Icon(
                                              CategoryType.fromId(
                                                      _selectedCategory!.id)
                                                  .icon,
                                              color: AppColors.brand),
                                        ),
                                      ),
                                      Text(
                                        _selectedCategory!.name,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.brand,
                                            fontWeight: FontWeight.bold),
                                      )
                                    ],
                                  ),
                                );
                              }

                              return SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.7,
                                child: GridView.count(
                                  crossAxisCount: 4,
                                  children: _categories
                                      .map((c) => Column(
                                            children: [
                                              // IconButton con indicazione dello stato selezionato
                                              Container(
                                                decoration: BoxDecoration(
                                                  color:
                                                      _selectedCategory?.id ==
                                                              c.id
                                                          ? AppColors.brand
                                                              .withValues(
                                                                  alpha: 0.12)
                                                          : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: _selectedCategory
                                                              ?.id ==
                                                          c.id
                                                      ? Border.all(
                                                          color:
                                                              AppColors.brand,
                                                          width: 2)
                                                      : null,
                                                ),
                                                child: IconButton(
                                                  onPressed: () {
                                                    context
                                                        .read<CategoryBloc>()
                                                        .add(ChangeCategory(
                                                            c.id));
                                                  },
                                                  icon: Icon(
                                                    CategoryType.fromId(c.id)
                                                        .icon,
                                                    color:
                                                        _selectedCategory?.id ==
                                                                c.id
                                                            ? AppColors.brand
                                                            : AppColors.inkSoft,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                c.name,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      _selectedCategory?.id ==
                                                              c.id
                                                          ? AppColors.brand
                                                          : AppColors.ink,
                                                  fontWeight:
                                                      _selectedCategory?.id ==
                                                              c.id
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                ),
                                              )
                                            ],
                                          ))
                                      .toList(),
                                ),
                              );
                            },
                          ),
                          // Date
                          Visibility(
                            visible: _selectedCategoryId != null,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Data'),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                      controller: _dateController,
                                      enabled: entryState
                                          is! EntryOperationInProgress,
                                      decoration: const InputDecoration(
                                          prefixIcon: Icon(Icons.calendar_today,
                                              size: 20),
                                          labelText: "Seleziona una data"),
                                      readOnly: true,
                                      onTap: () async {
                                        DateTime? pickedDate =
                                            await showDatePicker(
                                                context: context,
                                                locale: const Locale('it'),
                                                initialDate: FormatHelper
                                                    .formatStringToDate(
                                                        _dateController.text),
                                                firstDate: DateTime(2000),
                                                lastDate: DateTime(2101));

                                        if (pickedDate != null) {
                                          _dateController.text =
                                              FormatHelper.formatDateToString(
                                                  pickedDate);
                                          if (context.mounted) {
                                            _entryBloc?.add(
                                                ChangeEntryDate(pickedDate));
                                          }

                                          _descriptionFocus.requestFocus();
                                        }
                                      })
                                ],
                              ),
                            ),
                          ),
                          // Description
                          Visibility(
                            visible: _selectedCategoryId != null,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Descrizione'),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: _descriptionController,
                                    focusNode: _descriptionFocus,
                                    enabled:
                                        entryState is! EntryOperationInProgress,
                                    keyboardType: TextInputType.text,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: const InputDecoration(
                                      labelText: 'Inserisci la descrizione',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: _validateStringInput,
                                    onChanged: _onDescriptionChanged,
                                    onFieldSubmitted: (value) {
                                      _priceFocus.requestFocus();
                                    },
                                  ),
                                  if (_descriptionSuggestions.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _buildDescriptionSuggestions(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          // Price
                          Visibility(
                            visible: _selectedCategoryId != null,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Prezzo'),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                      controller: _numericController,
                                      focusNode: _priceFocus,
                                      enabled: entryState
                                          is! EntryOperationInProgress,
                                      readOnly: _items.isNotEmpty,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      inputFormatters: const [
                                        CurrencyInputFormatter()
                                      ],
                                      decoration: InputDecoration(
                                        labelText: _items.isNotEmpty
                                            ? 'Prezzo calcolato'
                                            : 'Inserisci il prezzo',
                                        prefixIcon: _items.isNotEmpty
                                            ? const Icon(Icons.lock_outline,
                                                size: 20)
                                            : null,
                                        helperText: _items.isNotEmpty
                                            ? 'Somma di ${_items.length} ${_items.length == 1 ? 'voce' : 'voci'}'
                                            : null,
                                        border: const OutlineInputBorder(),
                                      ),
                                      validator: _items.isNotEmpty
                                          ? null
                                          : _validateNumericInput),
                                ],
                              ),
                            ),
                          ),
                          // Sottovoci della spesa
                          Visibility(
                            visible: _selectedCategoryId != null,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text('Sottovoci'),
                                      ),
                                      if (_items.isNotEmpty)
                                        Text(
                                          FormatHelper.formatCurrencyToString(
                                              _itemsTotal),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_items.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'Nessuna voce: il prezzo lo inserisci qui sopra.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.inkSoft),
                                      ),
                                    )
                                  else
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                            color: AppColors.outline),
                                      ),
                                      child: Column(
                                        children: [
                                          for (int i = 0;
                                              i < _items.length;
                                              i++)
                                            _buildItemRow(i),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed:
                                        entryState is EntryOperationInProgress
                                            ? null
                                            : _addItem,
                                    icon: const Icon(Icons.add, size: 20),
                                    label: const Text('Aggiungi voce'),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 46),
                                      foregroundColor: AppColors.brand,
                                      side: const BorderSide(
                                          color: AppColors.outline),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Submit button to validate form
                          Visibility(
                            visible: _selectedCategoryId != null,
                            child: BlocBuilder<EntryBloc, EntryState>(
                              builder: (context, state) {
                                if (state is EntryOperationInProgress) {
                                  return Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                return Visibility(
                                  visible: _entryId != null,
                                  child: Container(
                                    margin: EdgeInsets.symmetric(vertical: 20),
                                    child: Center(
                                      child: AppButton('Elimina',
                                          style: ButtonStyle(
                                            backgroundColor:
                                                WidgetStateProperty.all(
                                                    AppColors.expense),
                                            foregroundColor:
                                                WidgetStateProperty.all(
                                                    Colors.white),
                                          ), () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Attenzione'),
                                            content: const Text(
                                                'Sei sicuro di voler eliminare la spesa?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                                child: const Text('Annulla'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  // Esegui l'operazione di eliminazione
                                                  context.read<EntryBloc>().add(
                                                      DeleteEntry(_entryId!));
                                                  Navigator.of(context).pop();
                                                },
                                                child: const Text('Conferma'),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Precompila il form da una spesa esistente.
  ///
  /// Con [keepId] a false la spesa viene duplicata: categoria, descrizione e
  /// prezzo sono copiati, ma il salvataggio crea un nuovo record e la data
  /// resta quella di oggi.
  void _loadEntryFromArguments(Entry entry, {bool keepId = true}) {
    _entryId = keepId ? entry.id : null;

    if (keepId) {
      _dateController.text = FormatHelper.formatDateToString(entry.date);
    }
    _descriptionController.text = entry.description;

    if (entry.price != null) {
      _numericController.text =
          FormatHelper.formatDecimalForInput(entry.price!);
    }

    _selectedCategoryId = entry.categoryId;
    _items = List<EntryItem>.of(entry.items);
  }

  /// Righe della sezione sottovoci nel form.
  Widget _buildItemRow(int index) {
    final EntryItem item = _items[index];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 2, 2, 2),
      decoration: BoxDecoration(
        border: Border(
          top: index == 0
              ? BorderSide.none
              : const BorderSide(color: AppColors.outline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            FormatHelper.formatCurrencyToString(item.price),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          IconButton(
            iconSize: 18,
            tooltip: 'Modifica voce',
            color: AppColors.inkSoft,
            onPressed: () => _editItem(index),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            iconSize: 18,
            tooltip: 'Rimuovi voce',
            color: AppColors.inkSoft,
            onPressed: () => _removeItem(index),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Future<void> _addItem() async {
    final EntryItem? item = await showEntryItemDialog(context);
    if (item == null || !mounted) {
      return;
    }

    setState(() {
      _items = <EntryItem>[..._items, item];
    });
    _syncPriceWithItems();
  }

  Future<void> _editItem(int index) async {
    final EntryItem? edited = await showEntryItemDialog(
      context,
      initial: _items[index],
    );
    if (edited == null || !mounted) {
      return;
    }

    setState(() {
      _items = List<EntryItem>.of(_items)..[index] = edited;
    });
    _syncPriceWithItems();
  }

  Future<void> _removeItem(int index) async {
    final EntryItem item = _items[index];

    final bool? shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovere la voce?'),
        content: Text('"${item.description}" sarà tolta dalla spesa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rimuovi', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldRemove != true || !mounted) {
      return;
    }

    setState(() {
      _items = List<EntryItem>.of(_items)..removeAt(index);
    });
    _syncPriceWithItems();
  }

  /// Il prezzo segue la somma delle voci; senza voci resta modificabile.
  void _syncPriceWithItems() {
    if (_items.isNotEmpty) {
      _numericController.text = FormatHelper.formatDecimalForInput(_itemsTotal);
    }
  }
}
