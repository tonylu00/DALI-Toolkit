import 'base.dart';

class DaliDT1 {
  final DaliBase base;

  DaliDT1(this.base);

  /// Start DT1 selftest (0xe3, 227)
  /// Type 1: emergency light
  Future<void> startDT1Test(int a, [int? t]) async {
    int addr = a * 2 + 1;
    int type = t ?? 1;
    if (type == 1) {
      await base.dtSelect(1);
      await base.sendCmd(addr, 0xe3);
    } else {
      // log.error("bad DT1 type, must be 1")
    }
  }

  /// Get DT1 emergency mode (0xfa, 250)
  Future<int?> getDT1EmergencyMode(int a) async {
    int addr = a * 2 + 1;
    await base.dtSelect(1);
    int ret = await base.query(addr, 0xfa);
    return (ret >= 0) ? ret : null;
  }

  /// Get DT1 feature (0xfb, 251)
  Future<int?> getDT1Feature(int a) async {
    int addr = a * 2 + 1;
    await base.dtSelect(1);
    int ret = await base.query(addr, 0xfb);
    return (ret >= 0) ? ret : null;
  }

  /// Get DT1 failure status (0xfc, 252)
  Future<int?> getDT1FailureStatus(int a) async {
    int addr = a * 2 + 1;
    await base.dtSelect(1);
    int ret = await base.query(addr, 0xfc);
    return (ret >= 0) ? ret : null;
  }

  /// Get DT1 emergency status (0xfd, 253)
  Future<int?> getDT1Status(int a) async {
    int addr = a * 2 + 1;
    await base.dtSelect(1);
    int ret = await base.query(addr, 0xfd);
    return (ret >= 0) ? ret : null;
  }

  /// Get DT1 self test status
  Future<int?> getDT1SelfTestStatus(int a) async {
    int? ret = await getDT1FailureStatus(a);
    if (ret == null) return null;
    // bit.btest(ret, 0x01) => check if bit0 is set
    bool inProgress = (ret & 0x01) != 0;
    return inProgress ? 1 : 0;
  }

  /// Perform DT1 selftest and wait for completion
  Future<bool> performDT1Test(int a, [int? t]) async {
    int timeout = t ?? 5;
    await startDT1Test(a);
    for (int i = 0; i < timeout; i++) {
      int? ret = await getDT1SelfTestStatus(a);
      if (ret == 0) {
        // log.info("DT1 self test completed")
        return true;
      } else if (ret == 1) {
        // log.info("DT1 self test in progress")
      } else if (ret == 2) {
        // log.info("DT1 self test failed")
        return false;
      } else {
        // log.info("DT1 self test status unknown")
        return false;
      }
      // TODO: replace with actual delay, e.g. Future.delayed()
    }
    return false;
  }
}