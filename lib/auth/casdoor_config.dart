import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart';

const String kCasdoorClientId = '6f3afba318d2780a370b';
const String kCasdoorServerUrl = 'https://account.tonycloud.cn/';
const String kCasdoorOrganization = 'tonycloud';
const String kCasdoorAppName = 'application_dalitoolkit';
const String kCasdoorRedirectUri = 'dalitoolkit://callback'; // 与应用注册的 scheme 匹配

final AuthConfig casdoorConfig = AuthConfig(
  serverUrl: kCasdoorServerUrl,
  clientId: kCasdoorClientId,
  redirectUri: kCasdoorRedirectUri,
  organizationName: kCasdoorOrganization,
  appName: kCasdoorAppName,
);
