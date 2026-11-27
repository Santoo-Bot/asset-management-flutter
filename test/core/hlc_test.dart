import 'package:asset_app/core/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('urut naik walau jam yang sama atau mundur', () {
    var t = 1000;
    final hlc = Hlc('dev-a', now: () => t);
    final a = hlc.next();
    final b = hlc.next(); // jam sama → counter naik
    t = 500; // jam mundur
    final c = hlc.next();
    expect(a.compareTo(b), lessThan(0));
    expect(b.compareTo(c), lessThan(0));
  });

  test('observe memajukan jam lokal melewati stempel perangkat lain', () {
    final hlc = Hlc('dev-a', now: () => 1000);
    hlc.observe('0000000009999-0003-dev-b');
    expect(hlc.next().compareTo('0000000009999-0003-dev-b'), greaterThan(0));
  });
}
