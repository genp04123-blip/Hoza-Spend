import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../core/utils/log.dart';

/// The netmask of every IPv4 address this device holds, keyed by address.
///
/// `dart:io` lists interfaces and their addresses but not the mask that goes
/// with them, and the mask is the whole difference between guessing a subnet
/// and knowing it. Guessing means assuming a /24, which is right for every
/// home router and every Android hotspot and wrong for a great many offices:
/// on a /23 the assumed broadcast address is an ordinary host, so beacons go
/// to a machine that may not exist, and the half of the subnet with the other
/// third octet is invisible to the sweep.
///
/// The operating system will simply tell us, through an API every platform has
/// had for decades. POSIX has `getifaddrs`, which covers Android, iOS, macOS
/// and Linux in one call; Windows has `GetIpAddrTable`, which hands back a
/// flat array of address-and-mask pairs. Both are public, neither needs a
/// plugin, and either failing costs nothing - the caller falls back to the /24
/// it would have assumed anyway.
class InterfaceTable {
  const InterfaceTable._();

  static const String _tag = 'Network';

  /// Set once a lookup has failed, so a platform where this cannot work pays
  /// for the attempt exactly one time rather than on every retarget.
  static bool _unavailable = false;

  /// Address to prefix length, for every IPv4 address the OS reports.
  ///
  /// An empty map means "ask somewhere else", never "this device has no
  /// addresses" - the address list itself comes from `dart:io`, and this only
  /// ever answers the narrower question of how wide each one's subnet is.
  static Map<String, int> prefixLengths() {
    if (_unavailable) return const <String, int>{};
    try {
      final Map<String, int> masks =
          Platform.isWindows ? _readWindows() : _readPosix();
      if (masks.isEmpty) _unavailable = true;
      return masks;
    } catch (error) {
      // A missing symbol, a struct this platform lays out differently, a
      // hardened runtime refusing the lookup. None of them are worth a second
      // attempt, and none of them are worth failing discovery over.
      Log.warn(_tag, 'Could not read interface netmasks: $error');
      _unavailable = true;
      return const <String, int>{};
    }
  }

  // --- POSIX ---------------------------------------------------------------

  static _GetIfAddrs? _getifaddrs;
  static _FreeIfAddrs? _freeifaddrs;

  static Map<String, int> _readPosix() {
    final DynamicLibrary libc = DynamicLibrary.process();
    final _GetIfAddrs get = _getifaddrs ??=
        libc.lookupFunction<_GetIfAddrsNative, _GetIfAddrs>('getifaddrs');
    final _FreeIfAddrs release = _freeifaddrs ??=
        libc.lookupFunction<_FreeIfAddrsNative, _FreeIfAddrs>('freeifaddrs');

    final Pointer<Pointer<_IfAddrs>> head = calloc<Pointer<_IfAddrs>>();
    try {
      if (get(head) != 0) return const <String, int>{};
      final Map<String, int> masks = <String, int>{};
      try {
        Pointer<_IfAddrs> node = head.value;
        while (node != nullptr) {
          final _IfAddrs entry = node.ref;
          final String? address = _readAddress(entry.addr);
          final int? prefix = _readPrefix(entry.netmask);
          if (address != null && prefix != null) masks[address] = prefix;
          node = entry.next;
        }
      } finally {
        // Freed even if walking the list throws: the list is the kernel's own
        // memory, handed to this process to give back.
        if (head.value != nullptr) release(head.value);
      }
      return masks;
    } finally {
      calloc.free(head);
    }
  }

  /// macOS and iOS inherit the BSD `sockaddr`, which spends its first byte on
  /// a length and puts the family in the second. Linux and Android have no
  /// length byte and a two-byte family. Everything after that - the port, then
  /// the four address bytes at offset 4 - is identical.
  static bool get _isBsdLayout => Platform.isMacOS || Platform.isIOS;

  static const int _afInet = 2;

  static int? _family(Pointer<Uint8> sockaddr) {
    if (sockaddr == nullptr) return null;
    return _isBsdLayout ? sockaddr[1] : sockaddr.cast<Uint16>().value;
  }

  static String? _readAddress(Pointer<Uint8> sockaddr) {
    if (_family(sockaddr) != _afInet) return null;
    return '${sockaddr[4]}.${sockaddr[5]}.${sockaddr[6]}.${sockaddr[7]}';
  }

  /// Counts the leading ones in a netmask.
  ///
  /// BSD stores a netmask in a `sockaddr` whose family is usually left at zero
  /// rather than set to AF_INET, which is a quirk rather than a mistake: a
  /// mask is not an address and has no family. Accepted there on the strength
  /// of its length byte instead.
  static int? _readPrefix(Pointer<Uint8> sockaddr) {
    if (sockaddr == nullptr) return null;
    final int? family = _family(sockaddr);
    if (family != _afInet) {
      final bool bsdMask = _isBsdLayout && family == 0 && sockaddr[0] >= 8;
      if (!bsdMask) return null;
    }
    return _prefixFromOctets(
      sockaddr[4],
      sockaddr[5],
      sockaddr[6],
      sockaddr[7],
    );
  }

  // --- Windows -------------------------------------------------------------

  /// `MIB_IPADDRROW`: address, interface index, mask, broadcast, reassembly
  /// size, then two shorts.
  static const int _rowBytes = 24;

  /// `MIB_IPADDRTABLE` opens with a `DWORD` count before the first row.
  static const int _tableHeaderBytes = 4;

  static const int _errorInsufficientBuffer = 122;

  static _GetIpAddrTable? _getIpAddrTable;

  static Map<String, int> _readWindows() {
    final _GetIpAddrTable read = _getIpAddrTable ??=
        DynamicLibrary.open('iphlpapi.dll')
            .lookupFunction<_GetIpAddrTableNative, _GetIpAddrTable>(
      'GetIpAddrTable',
    );

    // Two passes at most: one with a buffer big enough for any ordinary
    // machine, and one with the exact size Windows asks for if it is not.
    int size = 4096;
    for (int attempt = 0; attempt < 2; attempt++) {
      final Pointer<Uint8> buffer = calloc<Uint8>(size);
      final Pointer<Uint32> length = calloc<Uint32>();
      length.value = size;
      try {
        final int status = read(buffer, length, 0);
        if (status == _errorInsufficientBuffer) {
          size = length.value;
          continue;
        }
        if (status != 0) return const <String, int>{};

        final Map<String, int> masks = <String, int>{};
        final int rows = buffer.cast<Uint32>().value;
        for (int row = 0; row < rows; row++) {
          final int at = _tableHeaderBytes + row * _rowBytes;
          // Both fields hold the four address bytes in network order, so they
          // read straight out as octets.
          final String address = '${buffer[at]}.${buffer[at + 1]}.'
              '${buffer[at + 2]}.${buffer[at + 3]}';
          final int? prefix = _prefixFromOctets(
            buffer[at + 8],
            buffer[at + 9],
            buffer[at + 10],
            buffer[at + 11],
          );
          if (prefix != null) masks[address] = prefix;
        }
        return masks;
      } finally {
        calloc.free(buffer);
        calloc.free(length);
      }
    }
    return const <String, int>{};
  }

  /// Leading ones in a four-octet mask, or null if the mask has a hole in it.
  ///
  /// A discontiguous mask is not something a real interface has, and refusing
  /// it leaves the caller on its /24 default - a better answer than a subnet
  /// nobody is on.
  static int? _prefixFromOctets(int a, int b, int c, int d) {
    int bits = 0;
    bool sawZero = false;
    for (final int value in <int>[a, b, c, d]) {
      for (int bit = 7; bit >= 0; bit--) {
        if ((value >> bit) & 1 == 1) {
          if (sawZero) return null;
          bits++;
        } else {
          sawZero = true;
        }
      }
    }
    return bits;
  }
}

/// `struct ifaddrs`. Only the first five fields are read, and those five are
/// laid out identically on glibc, bionic and BSD; what follows them differs
/// between the two and is deliberately not declared.
final class _IfAddrs extends Struct {
  external Pointer<_IfAddrs> next;
  external Pointer<Uint8> name;

  @Uint32()
  external int flags;

  external Pointer<Uint8> addr;
  external Pointer<Uint8> netmask;
}

typedef _GetIfAddrsNative = Int32 Function(Pointer<Pointer<_IfAddrs>>);
typedef _GetIfAddrs = int Function(Pointer<Pointer<_IfAddrs>>);

typedef _FreeIfAddrsNative = Void Function(Pointer<_IfAddrs>);
typedef _FreeIfAddrs = void Function(Pointer<_IfAddrs>);

typedef _GetIpAddrTableNative = Uint32 Function(
  Pointer<Uint8>,
  Pointer<Uint32>,
  Int32,
);
typedef _GetIpAddrTable = int Function(Pointer<Uint8>, Pointer<Uint32>, int);
