import 'package:flutter_test/flutter_test.dart';
import 'package:hoza_send/network/discovery/interface_table.dart';
import 'package:hoza_send/network/discovery/network_info.dart';

/// The subnet maths discovery stands on.
///
/// Worth pinning down because every one of these was previously answered by
/// cutting the string at the last dot, which is only right on a /24. The cases
/// that matter here are the ones where a /24 assumption gives a confidently
/// wrong answer rather than no answer.
void main() {
  group('Ipv4', () {
    test('round trips an address through its integer form', () {
      for (final String address in <String>[
        '0.0.0.0',
        '10.0.0.1',
        '192.168.43.129',
        '172.16.255.254',
        '255.255.255.255',
      ]) {
        expect(Ipv4.format(Ipv4.parse(address)!), address, reason: address);
      }
    });

    test('refuses anything that is not four octets', () {
      expect(Ipv4.parse('192.168.1'), isNull);
      expect(Ipv4.parse('192.168.1.5.7'), isNull);
      expect(Ipv4.parse('192.168.1.256'), isNull);
      expect(Ipv4.parse('192.168.1.-1'), isNull);
      expect(Ipv4.parse('192.168.one.5'), isNull);
      expect(Ipv4.parse(''), isNull);
    });

    test('builds the mask for a prefix length', () {
      expect(Ipv4.format(Ipv4.mask(24)), '255.255.255.0');
      expect(Ipv4.format(Ipv4.mask(23)), '255.255.254.0');
      expect(Ipv4.format(Ipv4.mask(22)), '255.255.252.0');
      expect(Ipv4.format(Ipv4.mask(16)), '255.255.0.0');
      expect(Ipv4.format(Ipv4.mask(8)), '255.0.0.0');
      expect(Ipv4.format(Ipv4.mask(32)), '255.255.255.255');
      // Both ends clamp rather than shifting off the edge of the word.
      expect(Ipv4.format(Ipv4.mask(0)), '0.0.0.0');
      expect(Ipv4.format(Ipv4.mask(-4)), '0.0.0.0');
      expect(Ipv4.format(Ipv4.mask(40)), '255.255.255.255');
    });
  });

  group('LocalAddress', () {
    test('a /24 broadcasts where it always did', () {
      const LocalAddress local =
          LocalAddress(address: '192.168.43.129', interfaceName: 'wlan0');
      expect(local.prefixLength, 24);
      expect(local.broadcast, '192.168.43.255');
      expect(local.hostCount, 254);
    });

    test('a /23 broadcasts at the top of the pair, not the top of its own /24',
        () {
      // The case the old code got wrong: 10.1.0.255 is an ordinary host on a
      // /23, so a beacon sent there reached one machine that may not exist
      // rather than every machine on the link.
      const LocalAddress lower = LocalAddress(
        address: '10.1.0.40',
        interfaceName: 'eth0',
        prefixLength: 23,
      );
      const LocalAddress upper = LocalAddress(
        address: '10.1.1.200',
        interfaceName: 'eth0',
        prefixLength: 23,
      );
      expect(lower.broadcast, '10.1.1.255');
      expect(upper.broadcast, '10.1.1.255');
      expect(lower.hostCount, 510);
    });

    test('both halves of a /23 count as reachable without a router', () {
      const LocalAddress local = LocalAddress(
        address: '10.1.0.40',
        interfaceName: 'eth0',
        prefixLength: 23,
      );
      // The peer the old ranking pushed to the back of the list, behind any
      // address that merely shared three octets.
      expect(local.contains('10.1.1.200'), isTrue);
      expect(local.contains('10.1.0.9'), isTrue);
      expect(local.contains('10.1.2.9'), isFalse);
      expect(local.contains('nonsense'), isFalse);
    });

    test('wider masks still resolve to one subnet', () {
      const LocalAddress twentyTwo = LocalAddress(
        address: '172.20.5.17',
        interfaceName: 'eth0',
        prefixLength: 22,
      );
      expect(twentyTwo.broadcast, '172.20.7.255');
      expect(twentyTwo.contains('172.20.4.1'), isTrue);
      expect(twentyTwo.contains('172.20.7.254'), isTrue);
      expect(twentyTwo.contains('172.20.8.1'), isFalse);
      expect(twentyTwo.hostCount, 1022);

      const LocalAddress sixteen = LocalAddress(
        address: '10.42.7.3',
        interfaceName: 'wlan0',
        prefixLength: 16,
      );
      expect(sixteen.broadcast, '10.42.255.255');
      expect(sixteen.contains('10.42.200.9'), isTrue);
      expect(sixteen.contains('10.43.0.1'), isFalse);
    });

    test('a point-to-point link has no hosts to sweep', () {
      const LocalAddress thirtyOne = LocalAddress(
        address: '10.0.0.1',
        interfaceName: 'tun0',
        prefixLength: 31,
      );
      expect(thirtyOne.hostCount, 0);
      // Nothing sensible to direct a broadcast at, so it falls back to the
      // limited one rather than inventing an address.
      expect(thirtyOne.broadcast, '255.255.255.255');
    });

    test('the label keeps its old meaning for anything that shows it', () {
      const LocalAddress local = LocalAddress(
        address: '10.1.1.200',
        interfaceName: 'eth0',
        prefixLength: 23,
      );
      expect(local.prefix, '10.1.1');
    });
  });

  group('NetworkInfo.sameSubnet', () {
    test('still answers for a /24 when nothing better is known', () {
      expect(NetworkInfo.sameSubnet('192.168.1.5', '192.168.1.200'), isTrue);
      expect(NetworkInfo.sameSubnet('192.168.1.5', '192.168.2.5'), isFalse);
      expect(NetworkInfo.sameSubnet('nonsense', '192.168.1.5'), isFalse);
    });

    test('takes a real prefix length when one is available', () {
      expect(
        NetworkInfo.sameSubnet('10.1.0.40', '10.1.1.200', prefixLength: 23),
        isTrue,
      );
      expect(
        NetworkInfo.sameSubnet('10.1.0.40', '10.1.1.200', prefixLength: 24),
        isFalse,
      );
      expect(
        NetworkInfo.sameSubnet('10.1.0.40', '10.2.0.40', prefixLength: 16),
        isFalse,
      );
      expect(
        NetworkInfo.sameSubnet('10.1.0.40', '10.2.0.40', prefixLength: 8),
        isTrue,
      );
    });
  });

  group('InterfaceTable', () {
    // Reads the machine the test is running on, so it cannot assert what it
    // will find. What it can assert is that whatever comes back is usable -
    // which is the part that would break if a struct were laid out wrongly on
    // some platform, and it would break loudly here rather than quietly
    // sending beacons to an address nobody is listening on.
    test('reports only masks that make sense, or nothing at all', () {
      final Map<String, int> masks = InterfaceTable.prefixLengths();
      masks.forEach((String address, int prefixLength) {
        expect(Ipv4.parse(address), isNotNull, reason: address);
        expect(prefixLength, inInclusiveRange(0, 32), reason: address);
      });
    });

    test('asking twice gives the same answer', () {
      expect(InterfaceTable.prefixLengths(), InterfaceTable.prefixLengths());
    });
  });

  group('NetworkInfo.signatureOf', () {
    test('a mask change alone is a different network', () {
      // A renewed lease that keeps the address and widens the mask changes
      // which peers are reachable, so discovery has to start its list again.
      const LocalAddress narrow =
          LocalAddress(address: '10.1.0.40', interfaceName: 'eth0');
      const LocalAddress wide = LocalAddress(
        address: '10.1.0.40',
        interfaceName: 'eth0',
        prefixLength: 23,
      );
      expect(
        NetworkInfo.signatureOf(<LocalAddress>[narrow]),
        isNot(NetworkInfo.signatureOf(<LocalAddress>[wide])),
      );
    });

    test('the order interfaces are listed in does not matter', () {
      const LocalAddress a =
          LocalAddress(address: '192.168.1.5', interfaceName: 'wlan0');
      const LocalAddress b =
          LocalAddress(address: '10.0.0.5', interfaceName: 'eth0');
      expect(
        NetworkInfo.signatureOf(<LocalAddress>[a, b]),
        NetworkInfo.signatureOf(<LocalAddress>[b, a]),
      );
    });
  });
}
