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
      // log.error("bad device type, must be 1")
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

  /// Get detailed DT1 test status with more information
  Future<Map<String, dynamic>?> getDT1TestStatusDetailed(int a) async {
    int? failureStatus = await getDT1FailureStatus(a);
    int? emergencyStatus = await getDT1Status(a);
    int? emergencyMode = await getDT1EmergencyMode(a);
    int? feature = await getDT1Feature(a);

    if (failureStatus == null) return null;

    bool testInProgress = (failureStatus & 0x01) != 0;
    bool lampFailure = (failureStatus & 0x02) != 0;
    bool batteryFailure = (failureStatus & 0x04) != 0;
    bool functionTestActive = (failureStatus & 0x08) != 0;
    bool durationTestActive = (failureStatus & 0x10) != 0;
    bool testDone = (failureStatus & 0x20) != 0;
    bool identifyActive = (failureStatus & 0x40) != 0;
    bool physicalSelectionActive = (failureStatus & 0x80) != 0;

    return {
      'failureStatus': failureStatus,
      'emergencyStatus': emergencyStatus,
      'emergencyMode': emergencyMode,
      'feature': feature,
      'testInProgress': testInProgress,
      'lampFailure': lampFailure,
      'batteryFailure': batteryFailure,
      'functionTestActive': functionTestActive,
      'durationTestActive': durationTestActive,
      'testDone': testDone,
      'identifyActive': identifyActive,
      'physicalSelectionActive': physicalSelectionActive,
    };
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
      // Wait for 1 second before checking again
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }
}
