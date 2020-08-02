import 'dart:typed_data';

import 'package:chest/chunky/chunky.dart';

/// The first byte of all chunks contains a value indicating their type.
///
/// # Layout
///
/// ```
/// | n  | rest                                                                |
/// | 1B | fill                                                                |
/// ```
extension TypedChunk on Chunk {
  int get type => getUint8(0);
  set type(int type) => setUint8(0, type);
}

extension ChunkUtils on Chunk {
  // The id of a chunk.
  int getChunkId(int offset) => getInt64(offset);
  void setChunkId(int offset, int chunkId) => setInt64(offset, chunkId);

  // The id of a document.
  int getDocId(int offset) => getInt64(offset);
  void setDocId(int offset, int docId) => setInt64(offset, docId);

  // A reference to an offset inside a chunk.
  int getOffset(int offset) => getUint16(offset);
  void setOffset(int offset, int offsetValue) => setUint16(offset, offsetValue);

  // Writes a copy of the given bytes to the offset.
  void writeCopy(Uint8List bytes, int offset) {
    for (var i = 0; i < bytes.length; i++) {
      final byte = bytes[i];
      setUint8(offset + i, byte);
    }
  }

  void clear(int start, int end) {
    for (var i = start; i < end; i++) {
      setUint8(i, 0);
    }
  }
}

const chunkIdLength = 8;
const docIdLength = 8;
const offsetLength = 2;

int binarySearch(int length, int Function(int) keyByIndex, int key) {
  // print('Searching for $key in length $length.');
  var min = 0;
  var max = length;
  while (min < max) {
    // print('min=$min, max=$max');
    int mid = min + ((max - min) >> 1);
    final currentItem = keyByIndex(mid);
    final res = currentItem.compareTo(key);
    // print('Result of comparing $currentItem to $key is $res');
    if (res == 0) {
      return mid;
    } else if (res < 0) {
      min = mid + 1;
    } else {
      max = mid;
    }
  }
  // print('Binary search didnt find the value. min=$min max=$max');
  return null;
}

abstract class ChunkWrapper implements Chunk {
  Chunk get chunk;

  ByteBuffer get buffer => chunk.buffer;
  Uint8List get bytes => chunk.bytes;

  int getUint8(int offset) => chunk.getUint8(offset);
  void setUint8(int offset, int value) => chunk.setUint8(offset, value);

  int getUint16(int offset) => chunk.getUint16(offset);
  void setUint16(int offset, int value) => chunk.setUint16(offset, value);

  int getInt64(int offset) => chunk.getInt64(offset);
  void setInt64(int offset, int value) => chunk.setInt64(offset, value);

  List<int> getBytes(int offset, int length) => chunk.getBytes(offset, length);
  void setBytes(int offset, List<int> bytes) => chunk.setBytes(offset, bytes);
}