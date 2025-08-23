import 'connection.dart';
import 'serial_usb.dart';

Connection createSerialConnectionImpl() => SerialUsbConnection();

bool isSerialSupportedImpl() => true;
