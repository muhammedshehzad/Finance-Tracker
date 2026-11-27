import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/txn.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../widgets/common.dart';
import '../widgets/txn_tile.dart';

/// Searches notes, descriptions and payees across all months.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Txn> _results = const [];
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
  }

  Future<void> _run(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    final results = await ref.read(repositoryProvider).txnsBetween(DateTime(2000), DateTime(2100), search: q);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dbRevisionProvider, (_, _) => _run(_controller.text));
    final lookups = ref.watch(lookupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search notes or payees', border: InputBorder.none),
          onChanged: _onChanged,
        ),
      ),
      body: AsyncBody(
        value: lookups,
        builder: (l) {
          if (!_searched) return const EmptyState(icon: AppIcons.search, message: 'Type at least two letters.');
          if (_results.isEmpty) return const EmptyState(icon: AppIcons.noResults, message: 'No matches.');
          return ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) => TxnTile(txn: _results[i], lookups: l, showDate: true),
          );
        },
      ),
    );
  }
}
