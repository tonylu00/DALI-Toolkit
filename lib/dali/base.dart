import 'package:flutter/material.dart';

import 'comm.dart';

class DaliStatus {
  int _status;
  DaliStatus(this._status);

  bool get controlGearPresent => (_status & 0x01) == 0x01;
  set controlGearPresent(bool value) => _status = value ? (_status | 0x01) : (_status & ~0x01);

  bool get lampFailure => (_status & 0x02) == 0x02;
  set lampFailure(bool value) => _status = value ? (_status | 0x02) : (_status & ~0x02);

  bool get lampPowerOn => (_status & 0x04) == 0x04;
  set lampPowerOn(bool value) => _status = value ? (_status | 0x04) : (_status & ~0x04);

  bool get limitError => (_status & 0x08) == 0x08;
  set limitError(bool value) => _status = value ? (_status | 0x08) : (_status & ~0x08);

  bool get fadingCompleted => (_status & 0x10) == 0x10;
  set fadingCompleted(bool value) => _status = value ? (_status | 0x10) : (_status & ~0x10);

  bool get resetState => (_status & 0x20) == 0x20;
  set resetState(bool value) => _status = value ? (_status | 0x20) : (_status & ~0x20);

  bool get missingShortAddress => (_status & 0x40) == 0x40;
  set missingShortAddress(bool value) => _status = value ? (_status | 0x40) : (_status & ~0x40);

  bool get psFault => (_status & 0x80) == 0x80;
  set psFault(bool value) => _status = value ? (_status | 0x80) : (_status & ~0x80);
}

class DaliFadeTime {
  
}

class DaliBase extends DaliComm {
  DaliBase(super.manager);

  final int broadcast = 127;
  bool isAllocAddr = false;
  int lastAllocAddr = 0;
  int selectedAddress = 127;

  int mcuTicks() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> toScene(int a, int s, {int? t, int? d, int? g}) async {
    int addr = a * 2 + 1;
    int scene = 16 + s;
    await send(addr, scene, t: t, d: d, g: g);
  }

  Future<void> reset(int a, {int t = 2, int? d, int? g}) async {
    await send(a, 0x20, t: t, d: d, g: g);
  }

  Future<void> off(int a, {int? t, int? d, int? g}) async {
    int addr = a * 2 + 1;
    await sendCmd(addr, 0x00, t: t, d: d, g: g);
    //await setBright(a, 0, t: t, d: d, g: g);
  }

  Future<void> on(int a, {int? t, int? d, int? g}) async {
    int addr = a * 2 + 1;
    await sendCmd(addr, 0x05, t: t, d: d, g: g);
    //await setBright(a, 254, t: t, d: d, g: g);
  }

  Future<void> recallMaxLevel(int a, {int? t, int? d, int? g}) async {
    int addr = a * 2 + 1;
    await sendCmd(addr, 0x05, t: t, d: d, g: g);
  }

  Future<void> recallMinLevel(int a, {int? t, int? d, int? g}) async {
    int addr = a * 2 + 1;
    await sendCmd(addr, 0x06, t: t, d: d, g: g);
  }

  int groupToAddr(int gp) {
    return 64 + gp;
  }

  Future<void> sendExtCmd(int cmd, int value, {int? t, int? d, int? g}) async {
    await sendExtRawNew(cmd, value, d: d, g: g);
  }

  Future<void> setDTR(int value) async {
    await sendCmd(0xa3, value, t: 1);
  }

  Future<void> setDTR1(int value) async {
    await sendCmd(0xc3, value, t: 1);
  }

  Future<void> setDTR2(int value) async {
    await sendCmd(0xc5, value, t: 1);
  }

  Future<int> getDTR(int a) async {
    return await query(a, 0x98);
  }

  Future<int> getDTR1(int a) async {
    return await query(a, 0x9c);
  }

  Future<int> getDTR2(int a) async {
    return await query(a, 0x9d);
  }

  Future<void> copyCurrentBrightToDTR(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0x21);
  }

  Future<void> queryColourValue(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0xfa);
  }

  Future<void> storeDTRAsAddr(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0x80);
  }

  Future<void> storeDTRAsSceneBright(int a, int s, {int? g}) async {
    int addr = a * 2 + 1;
    int value = s + 64;
    await sendExtCmd(addr, value, g: g);
  }

  Future<void> storeScene(int a, int s) async {
    await copyCurrentBrightToDTR(a);
    await storeDTRAsSceneBright(a, s);
  }

  Future<void> removeScene(int a, int s) async {
    int addr = a * 2 + 1;
    int value = s + 0x50;
    await sendExtCmd(addr, value);
  }

  Future<void> addToGroup(int a, int g) async {
    int addr = a * 2 + 1;
    int value = g + 0x60;
    await sendExtCmd(addr, value);
  }

  Future<void> removeFromGroup(int a, int g) async {
    int addr = a * 2 + 1;
    int value = g + 0x70;
    await sendExtCmd(addr, value);
  }

  Future<void> storeDTRAsFadeTime(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0x2e);
  }

  Future<void> storeDTRAsFadeRate(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0x2f);
  }

  Future<void> storeDTRAsPoweredBright(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0x2d);
  }

  Future<void> storeDTRAsSystemFailureLevel(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0x2c);
  }

  Future<void> storeDTRAsMinLevel(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0x2b);
  }

  Future<void> storeDTRAsMaxLevel(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0x2a);
  }

  Future<void> storeColourTempLimits(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0xf2);
  }

  Future<bool> getOnlineStatus(int a) async {
    int res = await query(a, 0x91);
    return res == 255;
  }

  Future<int?> getBright(int a) async {
    int res = await query(a, 0xa0);
    if (res == 255) {
      debugPrint('Device report bright unknown');
      return 254;
    }
    return res;
  }

  Future<int> getDeviceType(int a) async {
    int addr = a * 2 + 1;
    return await queryCmd(addr, 0x99);
  }

  Future<int> getDeviceExtType(int a) async {
    int addr = a * 2 + 1;
    return await queryCmd(addr, 0x9a);
  }

  Future<int> getDeviceVersion(int a) async {
    int addr = a * 2 + 1;
    return await queryCmd(addr, 0x97);
  }

  Future<void> dtSelect(int value) async {
    await sendCmd(0xc1, value, t: 1);
  }

  Future<void> activate(int a) async {
    int addr = a * 2 + 1;
    await sendCmd(addr, 0xe2, t: 1);
  }

  Future<void> setDTRAsColourX(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0xe0);
  }

  Future<void> setDTRAsColourY(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0xe1);
  }

  Future<void> setDTRAsColourRGB(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0xe2);
  }

  Future<void> setDTRAsColourTemp(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0xe7);
  }

  Future<void> copyReportColourToTemp(int a) async {
    int addr = a * 2 + 1;
    await sendExtCmd(addr, 0xee);
  }

  Future<void> setGradualChangeSpeed(int a, int value) async {
    await setDTR(value);
    await storeDTRAsFadeTime(a);
  }

  Future<void> setGradualChangeRate(int a, int value) async {
    await setDTR(value);
    await storeDTRAsFadeRate(a);
  }

  Future<List<int>> getGradualChange(int a, {int? d, int? g}) async {
    int ret = await query(a, 0xa5, d: d, g: g);
    int rate = ret;
    int speed = 0;
    while (rate > 255) {
      rate -= 256;
      speed++;
    }
    return [rate, speed];
  }

  Future<int> getGradualChangeRate(int a, {int? d, int? g}) async {
    List<int> rs = await getGradualChange(a, d: d, g: g);
    return rs[0];
  }

  Future<int> getGradualChangeSpeed(int a, {int? d, int? g}) async {
    List<int> rs = await getGradualChange(a, d: d, g: g);
    return rs[1];
  }

  Future<void> setPowerOnLevel(int a, int value) async {
    await setDTR(value);
    await storeDTRAsPoweredBright(a);
  }

  Future<int> getPowerOnLevel(int a) async {
    return await query(a, 0xa1);
  }

  Future<void> setSystemFailureLevel(int a, int value) async {
    await setDTR(value);
    await storeDTRAsSystemFailureLevel(a);
  }

  Future<int> getSystemFailureLevel(int a) async {
    return await query(a, 0xa2);
  }

  Future<void> setMinLevel(int a, int value) async {
    await setDTR(value);
    await storeDTRAsMinLevel(a);
  }

  Future<int> getMinLevel(int a) async {
    return await query(a, 0xa3);
  }

  Future<void> setMaxLevel(int a, int value) async {
    await setDTR(value);
    await storeDTRAsMaxLevel(a);
  }

  Future<int> getMaxLevel(int a) async {
    return await query(a, 0xa4);
  }

  Future<void> setPhysicalMinLevel(int a, int value) async {
    await setDTR(value);
    await storeDTRAsMinLevel(a);
  }

  Future<int> getPhysicalMinLevel(int a) async {
    return await query(a, 0xa5);
  }

  Future<void> setFadeTime(int a, int value) async {
    await setDTR(value);
    await storeDTRAsFadeTime(a);
  }

  Future<int> getFadeTime(int a) async {
    return await query(a, 0xa6);
  }

  Future<void> setFadeRate(int a, int value) async {
    await setDTR(value);
    await storeDTRAsFadeRate(a);
  }

  Future<int> getFadeRate(int a) async {
    return await query(a, 0xa7);
  }

  Future<int> getGroupH(int a) async {
    return await query(a, 0xc1);
  }

  Future<int> getGroupL(int a) async {
    return await query(a, 0xc0);
  }

  Future<int> getGroup(int a) async {
    int h = await getGroupH(a);
    int l = await getGroupL(a);
    return h * 256 + l;
  }

  Future<void> setGroup(int a, int value) async {
    final currentGroup = await getGroup(a);
    if (currentGroup == value) {
      return;
    }
    for (int i = 0; i < 16; i++) {
      if ((currentGroup & (1 << i)) != (value & (1 << i))) {
        if ((value & (1 << i)) != 0) {
          await addToGroup(a, i);
        } else {
          await removeFromGroup(a, i);
        }
      }
    }
  }

  Future<int> getScene(int a, int b) async {
    int sc = b;
    return await query(a, 0xb0 + sc);
  }

  Future<void> setScene(int a, int b) async {
    await setDTR(b);
    await storeDTRAsSceneBright(a, b);
  }

  Future<Map<int, int>> getScenes(int a) async {
    Map<int, int> ret = {};
    for (int i = 0; i < 16; i++) {
      int r = await getScene(a, i);
      ret[i] = r;
    }
    return ret;
  }

  Future<int> getStatus(int a) async {
    return await query(a, 0x90);
  }

  Future<bool> getControlGearPresent(int a) async {
    int ret = await query(a, 0x91);
    return (ret == 255);
  }

  Future<bool> getLampFailureStatus(int a) async {
    int ret = await query(a, 0x92);
    return (ret == 255);
  }

  Future<bool> getLampPowerOnStatus(int a) async {
    int ret = await query(a, 0x93);
    return (ret == 255);
  }

  Future<bool> getLimitError(int a) async {
    int ret = await query(a, 0x94);
    return (ret == 255);
  }

  Future<bool> getResetStatus(int a) async {
    int ret = await query(a, 0x95);
    return (ret == 255);
  }

  Future<bool> getMissingShortAddress(int a) async {
    int ret = await query(a, 0x96);
    return (ret == 255);
  }

  Future<void> terminate() async {
    await sendCmd(0xa1, 0x00, t: 2, d: 20);
  }

  Future<void> randomise() async {
    await sendExtCmd(0xa7, 0x00);
  }

  Future<void> initialiseAll() async {
    await sendExtCmd(0xa5, 0x00);
  }

  Future<void> initialise() async {
    await sendExtCmd(0xa5, 0xff);
  }

  Future<void> withdraw() async {
    await sendCmd(0xab, 0x00, t: 2);
  }

  Future<void> cancel() async {
    await sendCmd(0xad, 0x00, t: 2);
  }

  Future<void> physicalSelection() async {
    await sendCmd(0xbd, 0x00, t: 2);
  }

  Future<void> queryAddressH(int addr) async {
    await sendCmd(0xb1, addr, t: 1);
  }

  Future<void> queryAddressM(int addr) async {
    await sendCmd(0xb3, addr, t: 1);
  }

  Future<void> queryAddressL(int addr) async {
    await sendCmd(0xb5, addr, t: 1);
  }

  Future<void> programShortAddr(int a) async {
    int addr = a * 2 + 1;
    await sendCmd(0xb7, addr, t: 1);
  }

  Future<int> queryShortAddr() async {
    int ret1 = await queryCmd(0xbb, 0x00);
    int ret = ret1 - 1;
    return ret ~/ 2;
  }

  Future<void> verifyShortAddr(int a) async {
    int addr = a * 2 + 1;
    await sendCmd(0xb9, addr, t: 1);
  }

  Future<bool> compare(int h, int m, int l) async {
    await queryAddressL(l);
    await queryAddressM(m);
    await queryAddressH(h);
    int ret = await queryCmd(0xa9, 0x00);
    if (ret == -1) {
      return false;
    } else if (ret >= 0) {
      return true;
    }
    return false;
  }

  Future<int> getRandomAddrH(int addr) async {
    return await query(addr, 0xc2);
  }

  Future<int> getRandomAddrM(int addr) async {
    return await query(addr, 0xc3);
  }

  Future<int> getRandomAddrL(int addr) async {
    return await query(addr, 0xc4);
  }
}