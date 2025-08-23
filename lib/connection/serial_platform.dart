import 'connection.dart';

import 'serial_impl_stub.dart'
    if (dart.library.io) 'serial_impl_io.dart'
    if (dart.library.html) 'serial_impl_web.dart' as impl;

/// Create a serial connection instance for current platform.
Connection createSerialConnection() => impl.createSerialConnectionImpl();

/// Whether serial connection is supported on current platform.
bool isSerialSupported() => impl.isSerialSupportedImpl();
