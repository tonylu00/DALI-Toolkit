class DaliDecode {
  bool displayRaw = true;
  Map<int, String> cmd = {
    0x00: "OFF",
    0x01: "UP",
    0x02: "DOWN",
    0x03: "STEP_UP",
    0x04: "STEP_DOWN",
    0x05: "RECALL_MAX_LEVEL",
    0x06: "RECALL_MIN_LEVEL",
    0x07: "STEP_DOWN_AND_OFF",
    0x08: "ON_AND_STEP_UP",
    0x09: "ENABLE_DAPC_SEQUENCE",
    0x20: "RESET",
    0x21: "STORE_ACTUAL_LEVEL_IN_THE_DTR",
    0x2A: "STORE_THE_DTR_AS_MAX_LEVEL",
    0x2B: "STORE_THE_DTR_AS_MIN_LEVEL",
    0x2C: "STORE_THE_DTR_AS_SYS_FAIL_LEVEL",
    0x2D: "STORE_THE_DTR_AS_PWR_ON_LEVEL",
    0x2E: "STORE_THE_DTR_AS_FADE_TIME",
    0x2F: "STORE_THE_DTR_AS_FADE_RATE",
    0x80: "STORE_DTR_AS_SHORT_ADDRESS",
    0x90: "QUERY_STATUS",
    0x91: "QUERY_BALLAST",
    0x92: "QUERY_LAMP_FAILURE",
    0x93: "QUERY_LAMP_POWER_ON",
    0x94: "QUERY_LIMIT_ERROR",
    0x95: "QUERY_RESET_STATE",
    0x96: "QUERY_MISSING_SHORT_ADDRESS",
    0x97: "QUERY_VERSION_NUMBER",
    0x98: "QUERY_CONTENT_DTR",
    0x99: "QUERY_DEVICE_TYPE",
    0x9A: "QUERY_PHYSICAL_MINIMUM_LEVEL",
    0x9B: "QUERY_POWER_FAILURE",
    0xA0: "QUERY_ACTUAL_LEVEL",
    0xA1: "QUERY_MAX_LEVEL",
    0xA2: "QUERY_MIN_LEVEL",
    0xA3: "QUERY_POWER_ON_LEVEL",
    0xA4: "QUERY_SYSTEM_FAILURE_LEVEL",
    0xA5: "QUERY_FADE_TIME/FADE_RATE",
    0xC0: "QUERY_GROUPS_0-7",
    0xC1: "QUERY_GROUP_8-15",
    0xC2: "QUERY_RANDOM_ADDRESS_(H)",
    0xC3: "QUERY_RANDOM_ADDRESS_(M)",
    0xC4: "QUERY_RANDOM_ADDRESS_(L)",
    0xC5: "QUERY_??",
    0xE2: "ACTIVATE",
    0xE7: "SET_COLOR_TEMPERATURE",
    0xE8: "STEP_UP_COLOR_TEMPERATURE",
    0xE9: "STEP_DOWN_COLOR_TEMPERATURE",
    0xFA: "QUERY_COLOR_TEMPERATURE",
  };

  Map<int, String> sCMD = {
    0xA1: "TERMINATE",
    0xA3: "SET_DTR",
    0xA5: "INITIALIZE",
    0xA7: "RANDOMIZE",
    0xA9: "COMPARE",
    0xAB: "WITHDRAW",
    0xB1: "SEARCHADDRH",
    0xB3: "SSEARCHADDRM",
    0xB5: "SSEARCHADDRL",
    0xB7: "SPROGRAM_SHORT_ADDRESS",
    0xB9: "SVERIFY_SHORT_ADDRESS",
    0xBB: "SQUERY_SHORT_ADDRESS",
    0xBD: "SPHYSICAL_SELECTION",
    0xC1: "SENABLE_DEVECE_TYPE",
    0xC3: "SET_DTR_1",
    0xC5: "SET_DTR_2",
  };

  List<int> queryCmd = [
    0x91,
    0x92,
    0x93,
    0x94,
    0x95,
    0x96,
    0x97,
    0x98,
    0x99,
    0x9A,
    0x9B,
    0xA0,
    0xA1,
    0xA2,
    0xA3,
    0xA4,
    0xA5,
    0xA9,
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC4,
    0xC5,
    0xE2,
    0xE7,
    0xE8,
    0xE9,
    0xFA
  ];

  int isQueryCmd(int cmd) {
    if (queryCmd.contains(cmd)) {
      return 1;
    }
    return 0;
  }

  // Simplified decoding placeholders
  void decodeBright(int chr1, int chr2) {}

  void decodeScene(int chr1, int chr2) {}

  void decodeCmd(int chr1, int chr2) {}

  void decodeSpCmd(int chr1, int chr2) {}

  void decodeCmdResponse(int chr1, int chr2) {}

  void decode(int chr1, int chr2) {}
}