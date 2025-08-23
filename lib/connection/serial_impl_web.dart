import 'connection.dart';
import 'serial_web.dart';

Connection createSerialConnectionImpl() => SerialWebManager();

bool isSerialSupportedImpl() => true;
