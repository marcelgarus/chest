import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import '../../bytes.dart';
import '../../compress.dart';
import '../../utils.dart';
import '../storage.dart';
import 'file.dart';
import 'message.dart';
import 'storage.dart';

/// The [VmBackend] is responsible for managing access to a `.chest` file.
///
/// Multiple [Storage]s of the same chest running on different [Isolate]s all
/// communicate with the same [VmBackend].
///
/// ## File layout
///
/// TODO: Compress bytes.
/// | version | updates |
/// | 8 B     | ...     |
///
/// All updates have the following layout:
///
/// | validity | path                         | data          |
/// |          | num segments | segments      | length | data |
/// |          |              | length | data |        |      |
/// | 1 B      | 8 B          | 8 B    | 8 B  | 8 B    | 8 B  |
///
/// The first udpate always has an empty path.
class VmBackend {
  VmBackend({
    required String name,
    required Stream<Action> incomingActions,
    required this.sendEvent,
    required this.dispose,
  }) : _file = SyncFile('$name.chest') {
    incomingActions.listen(_handleAction);
    _registerServiceMethods();
  }

  final SyncFile _file;
  final void Function(Event event) sendEvent;
  final void Function() dispose;

  Future<void> _handleAction(Action action) async {
    print('Handling action $action.');
    if (action is GetValueAction) {
      sendEvent(WholeValueEvent(_getValue()));
    } else if (action is SetValueAction) {
      _setValue(action.path, action.value);
    } else if (action is FlushAction) {
      _flush();
      sendEvent(FlushedEvent(action.uuid));
    } else if (action is CloseAction) {
      _close();
    } else {
      throw UnimplementedError('Backend: Unknown action $action.');
    }
  }

  Value? _getValue() {
    if (_file.length() == 0) {
      return null;
    }
    _file.goToStart();
    final version = _file.readInt();
    if (version > 0) throw 'Version too big: $version.';

    Value? value;

    while (_file.position() < _file.length()) {
      final validity = _file.readByte();
      if (validity == 0) {
        _file.truncate(_file.position() - 1);
        break;
      }

      final pathLength = _file.readInt();
      final segments = <Block>[];
      for (var i = 0; i < pathLength; i++) {
        final segmentLength = _file.readInt();
        final segmentBytes = Uint8List(segmentLength);
        _file.readBytesInto(segmentBytes);
        segments.add(BlockView.of(segmentBytes.buffer));
      }
      final path = Path(segments);

      final valueLength = _file.readInt();
      final valueBytes = Uint8List(valueLength);
      _file.readBytesInto(valueBytes);
      final valueBlock = BlockView.of(valueBytes.buffer);

      if (value == null) {
        if (!path.isRoot) throw 'First update was not for root.';
        value = Value(valueBlock);
      } else {
        value.update(path, valueBlock);
      }
    }
    return value;
  }

  void _setValue(Path<Block> path, Block value) {
    final bytes = value.toBytes();
    if (path.isRoot) {
      _file
        ..clear()
        ..writeInt(0); // version
    }
    final start = _file.length();
    _file
      ..goToEnd()
      ..writeByte(0) // validity byte
      ..flush()
      ..writeInt(path.length);
    for (final key in path.keys) {
      final bytes = key.toBytes();
      _file
        ..writeInt(bytes.length)
        ..writeBytes(bytes);
    }
    _file
      ..writeInt(bytes.length)
      ..writeBytes(bytes)
      ..flush()
      ..goTo(start)
      ..writeByte(1) // make transaction valid
      ..flush();
    // TODO: Broadcast the value.
  }

  void _flush() {
    _file.flush();
  }

  void _close() {
    print('Closing the file properly.');
    _file.close();
    dispose();
  }

  void _registerServiceMethods() {
    // registerExtension('ext.chest.num_chunks', (method, parameters) async {
    //   print("Returning the number of chunks.");
    //   return ServiceExtensionResponse.result(json.encode({
    //     'type': 'size',
    //     'size': _chunky.numberOfChunks,
    //   }));
    // });
  }
}
