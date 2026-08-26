import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoza_send/core/constants/app_constants.dart';
import 'package:hoza_send/core/models/hoza_device.dart';
import 'package:hoza_send/network/discovery/discovery_beacon.dart';
import 'package:hoza_send/network/discovery/network_info.dart';

HozaDevice _device({
  String id = 'aaaa1111bbbb2222',
  String name = 'Test phone',
  String address = '192.168.1.20',
}) {
  return HozaDevice(
    id: id,
    name: name,
    platform: DevicePlatform.android,
    address: address,
    port: AppConstants.transferPort,
    appVersion: AppConstants.appVersion,
    lastSeen: DateTime(2026),
  );
}

DiscoveryBeacon? _decode(List<int> bytes, {String from = '192.168.1.20'}) {
  return DiscoveryBeacon.decode(bytes, address: from, seenAt: DateTime(2026));
}

void main() {
  group('DiscoveryBeacon', () {
    test('round trips every beacon type', () {
      for (final BeaconType type in BeaconType.values) {
        final DiscoveryBeacon? decoded =
            _decode(DiscoveryBeacon.encode(_device(), type));
        expect(decoded, isNotNull, reason: type.name);
        expect(decoded!.type, type);
        expect(decoded.device.id, 'aaaa1111bbbb2222');
        expect(decoded.device.name, 'Test phone');
        expect(decoded.device.port, AppConstants.transferPort);
      }
    });

    test('only a hello asks to be answered, so replies cannot loop', () {
      expect(BeaconType.hello.wantsReply, isTrue);
      expect(BeaconType.reply.wantsReply, isFalse);
      expect(BeaconType.goodbye.wantsReply, isFalse);
    });

    test('the address comes from the packet, never from its contents', () {
      final List<int> bytes = DiscoveryBeacon.encode(
        _device(address: '10.0.0.9'),
        BeaconType.hello,
      );
      expect(_decode(bytes, from: '192.168.43.7')!.device.address,
          '192.168.43.7');
    });

    test('a beacon from an unknown build is treated as a hello', () {
      // What an older build sends when a newer one adds a type it has never
      // heard of: the packet still means "I am here", and answering it is
      // right.
      final String payload = jsonEncode(<String, Object?>{
        'v': AppConstants.protocolVersion,
        't': 'something-new',
        'id': 'ffff0000ffff0000',
        'name': 'Future phone',
        'platform': 'android',
        'port': AppConstants.transferPort,
        'version': '9.9.9',
      });
      final DiscoveryBeacon? decoded =
          _decode(utf8.encode('${AppConstants.beaconMagic}$payload'));
      expect(decoded?.type, BeaconType.hello);
    });

    test('rejects anything that is not one of ours', () {
      expect(_decode(utf8.encode('random udp traffic')), isNull);
      expect(_decode(utf8.encode('${AppConstants.beaconMagic}not json')), isNull);
      expect(_decode(const <int>[0xC3, 0x28, 0xC3, 0x28, 0xC3, 0x28]), isNull);
      expect(_decode(const <int>[]), isNull);

      final String wrongVersion = jsonEncode(<String, Object?>{
        'v': AppConstants.protocolVersion + 1,
        't': 'hello',
        'id': 'ffff0000ffff0000',
        'name': 'Newer phone',
      });
      expect(
        _decode(utf8.encode('${AppConstants.beaconMagic}$wrongVersion')),
        isNull,
      );

      final String noName = jsonEncode(<String, Object?>{
        'v': AppConstants.protocolVersion,
        't': 'hello',
        'id': 'ffff0000ffff0000',
        'name': '',
      });
      expect(
        _decode(utf8.encode('${AppConstants.beaconMagic}$noName')),
        isNull,
      );
    });
  });

  group('NetworkInfo', () {
    test('sameSubnet is what decides whether a peer needs a router', () {
      expect(NetworkInfo.sameSubnet('192.168.1.5', '192.168.1.200'), isTrue);
      expect(NetworkInfo.sameSubnet('192.168.43.1', '192.168.43.55'), isTrue);
      expect(NetworkInfo.sameSubnet('192.168.1.5', '192.168.2.5'), isFalse);
      expect(NetworkInfo.sameSubnet('192.168.1.5', '10.0.0.5'), isFalse);
      expect(NetworkInfo.sameSubnet('nonsense', '192.168.1.5'), isFalse);
    });

    test('only RFC 1918 ranges are eligible for a unicast sweep', () {
      expect(NetworkInfo.isPrivate('192.168.43.1'), isTrue);
      expect(NetworkInfo.isPrivate('10.42.0.7'), isTrue);
      expect(NetworkInfo.isPrivate('172.16.0.1'), isTrue);
      expect(NetworkInfo.isPrivate('172.31.255.254'), isTrue);
      expect(NetworkInfo.isPrivate('172.15.0.1'), isFalse);
      expect(NetworkInfo.isPrivate('172.32.0.1'), isFalse);
      expect(NetworkInfo.isPrivate('8.8.8.8'), isFalse);
      expect(NetworkInfo.isPrivate('not-an-address'), isFalse);
    });

    test('a local address knows its own subnet broadcast', () {
      const LocalAddress local =
          LocalAddress(address: '192.168.43.129', interfaceName: 'wlan0');
      expect(local.prefix, '192.168.43');
      expect(local.broadcast, '192.168.43.255');
    });
  });

  group('HozaDevice', () {
    test('offers every address to try, best first and without repeats', () {
      final HozaDevice device = _device(address: '192.168.43.5').copyWith(
        alternateAddresses: <String>['10.0.0.5', '192.168.43.5'],
      );
      expect(
        device.candidateAddresses,
        <String>['192.168.43.5', '10.0.0.5'],
      );
    });

    test('a device with one address still has one candidate', () {
      expect(_device().candidateAddresses, <String>['192.168.1.20']);
    });

    test('identity survives a rename, so one phone is never listed twice', () {
      final HozaDevice before = _device(name: 'Old name');
      final HozaDevice after = before.copyWith(name: 'New name');
      expect(after, before);
      expect(after.hashCode, before.hashCode);
    });
  });
}
