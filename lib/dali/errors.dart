import '../toast.dart';

/// DALI 查询相关错误类型定义
/// 之前用返回 -1 / -2 表示错误, 现在改为抛出异常。

sealed class DaliQueryException implements Exception {
  final String message;
  final int? addr;
  final int? cmd;
  const DaliQueryException(this.message, {this.addr, this.cmd});
  @override
  String toString() =>
      '${runtimeType.toString()}: $message (addr=${addr ?? '-'}, cmd=${cmd ?? '-'})';
}

/// 总线当前不可操作 (硬件/连接异常)
class DaliBusUnavailableException extends DaliQueryException {
  const DaliBusUnavailableException({int? addr, int? cmd})
      : super('Bus unavailable', addr: addr, cmd: cmd);
}

/// 网关未响应 (超出最大重试次数仍无任何正确格式数据帧)
class DaliGatewayTimeoutException extends DaliQueryException {
  const DaliGatewayTimeoutException({int? addr, int? cmd})
      : super('Gateway no response', addr: addr, cmd: cmd);
}

/// 设备未响应 (收到了 NACK / 标志帧 254)
class DaliDeviceNoResponseException extends DaliQueryException {
  const DaliDeviceNoResponseException({int? addr, int? cmd})
      : super('Device no response', addr: addr, cmd: cmd);
}

/// 收到无效/损坏的帧
class DaliInvalidFrameException extends DaliQueryException {
  final List<int>? frame;
  const DaliInvalidFrameException(this.frame, {int? addr, int? cmd})
      : super('Invalid frame: $frame', addr: addr, cmd: cmd);
}

/// 将 DaliQueryException 映射为本地化 key
String mapDaliErrorToMessage(DaliQueryException e) {
  if (e is DaliBusUnavailableException) return 'dali.error.bus_unavailable';
  if (e is DaliGatewayTimeoutException) return 'dali.error.gateway_timeout';
  if (e is DaliDeviceNoResponseException) return 'dali.error.device_no_response';
  if (e is DaliInvalidFrameException) return 'dali.error.invalid_frame';
  return 'dali.error.unknown';
}

/// 统一包装器：执行一个 DALI 异步操作，捕获异常并交由回调处理
Future<T?> daliSafe<T>(Future<T> Function() action,
    {void Function(String msg)? onError, bool rethrowOthers = false}) async {
  try {
    return await action();
  } on DaliQueryException catch (e) {
    final msg = mapDaliErrorToMessage(e);
    if (onError != null) onError(msg);
    return null; // 失败返回 null
  } catch (e) {
    if (rethrowOthers) rethrow;
    if (onError != null) onError('非预期错误: $e');
    return null;
  }
}

void showDaliErrorToast(DaliQueryException e) {
  ToastManager().showErrorToast(mapDaliErrorToMessage(e));
}

Future<T?> daliSafeToast<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DaliQueryException catch (e) {
    showDaliErrorToast(e);
    return null;
  }
}
