import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal ZIP writer. Dependency-free on purpose: EPUB needs the first entry
/// ("mimetype") to be STORED and the rest DEFLATED, which is awkward to
/// guarantee through third-party archive packages.
class ZipWriter {
  final BytesBuilder _body = BytesBuilder();
  final List<_Entry> _entries = [];

  static final Uint32List _crcTable = _makeCrcTable();

  static Uint32List _makeCrcTable() {
    final t = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      t[i] = c;
    }
    return t;
  }

  static int crc32(List<int> data) {
    int c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  void addString(String name, String text, {bool store = false}) =>
      addBytes(name, utf8.encode(text), store: store);

  void addBytes(String name, List<int> data, {bool store = false}) {
    final nameBytes = utf8.encode(name);
    final crc = crc32(data);
    List<int> payload;
    int method;
    if (store) {
      payload = data;
      method = 0;
    } else {
      payload = ZLibEncoder(raw: true, level: 9).convert(data);
      method = 8;
      if (payload.length >= data.length) {
        payload = data;
        method = 0;
      }
    }
    final offset = _body.length;
    _body.add(_u32(0x04034b50));
    _body.add(_u16(method == 0 ? 10 : 20)); // version needed
    _body.add(_u16(0)); // flags
    _body.add(_u16(method));
    _body.add(_u16(0)); // mod time
    _body.add(_u16(0x21)); // mod date (1996-01-01)
    _body.add(_u32(crc));
    _body.add(_u32(payload.length));
    _body.add(_u32(data.length));
    _body.add(_u16(nameBytes.length));
    _body.add(_u16(0));
    _body.add(nameBytes);
    _body.add(payload);
    _entries.add(_Entry(nameBytes, method, crc, payload.length, data.length, offset));
  }

  Uint8List finish() {
    final out = BytesBuilder();
    out.add(_body.toBytes());
    final cdStart = out.length;
    for (final e in _entries) {
      out.add(_u32(0x02014b50));
      out.add(_u16(20)); // version made by
      out.add(_u16(e.method == 0 ? 10 : 20));
      out.add(_u16(0));
      out.add(_u16(e.method));
      out.add(_u16(0));
      out.add(_u16(0x21));
      out.add(_u32(e.crc));
      out.add(_u32(e.compressed));
      out.add(_u32(e.raw));
      out.add(_u16(e.name.length));
      out.add(_u16(0));
      out.add(_u16(0));
      out.add(_u16(0));
      out.add(_u16(0));
      out.add(_u32(0));
      out.add(_u32(e.offset));
      out.add(e.name);
    }
    final cdSize = out.length - cdStart;
    out.add(_u32(0x06054b50));
    out.add(_u16(0));
    out.add(_u16(0));
    out.add(_u16(_entries.length));
    out.add(_u16(_entries.length));
    out.add(_u32(cdSize));
    out.add(_u32(cdStart));
    out.add(_u16(0));
    return out.toBytes();
  }

  static List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _u32(int v) =>
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
}

class _Entry {
  _Entry(this.name, this.method, this.crc, this.compressed, this.raw, this.offset);
  final List<int> name;
  final int method;
  final int crc;
  final int compressed;
  final int raw;
  final int offset;
}
