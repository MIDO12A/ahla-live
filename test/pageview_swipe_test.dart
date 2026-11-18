import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

Widget gridPage(String id, Map<String, ScrollController> ctrls, int seed) {
  return Padding(
    key: ValueKey('cat_grid_$id'),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: GridView.builder(
      controller: ctrls.putIfAbsent(id, () => ScrollController()),
      padding: const EdgeInsets.only(top: 6, bottom: 50),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      scrollCacheExtent: const ScrollCacheExtent.pixels(900),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 82 / 96,
      ),
      itemCount: 40,
      itemBuilder: (_, j) => Container(
        color: Colors.primaries[(seed + j) % Colors.primaries.length],
        margin: const EdgeInsets.all(4),
      ),
    ),
  );
}

void main() {
  testWidgets('PageView with per-page vertical GridViews swipes horizontally', (tester) async {
    final ctrls = <String, ScrollController>{};
    int page = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: PageView.builder(
            itemCount: 3,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            pageSnapping: true,
            onPageChanged: (i) => page = i,
            itemBuilder: (_, i) => gridPage('g$i', ctrls, i),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // fling left on the first grid — should advance to page 1
    await tester.fling(find.byType(GridView).first, const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();
    expect(page, 1, reason: 'fling left should move to page 1');

    // fling right — back to page 0
    await tester.fling(find.byType(GridView).first, const Offset(500, 0), 1200);
    await tester.pumpAndSettle();
    expect(page, 0, reason: 'fling right should move back to page 0');
  });
}
