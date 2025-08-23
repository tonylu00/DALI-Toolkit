# dalimaster

DALI Inspector V2 (cross platform)

## Getting Started

This project is a cross platform implementation of DALI Master.
Supported platforms: Windows, Linux, MacOS, iOS, Android.

### 总线状态监测 (Type0 网关)
当连接到被判定为 type0 的网关时，如果在空闲通知中接收到连续两个字节 0xFF 0xFD，界面标题处会显示“总线异常”；若 5 秒内未再次收到该序列，将自动恢复为“总线正常”。
（假设 checkGatewayType 返回 0 即为 type0 网关，如实际判定规则不同请调整 ConnectionManager.gatewayType 逻辑。）

### Casdoor 登录集成说明

已加入依赖: `casdoor_flutter_sdk`。

配置文件: `lib/auth/casdoor_config.dart` 含占位符，需要替换为 Casdoor 控制台真实值:

```
const String kCasdoorClientId = '...';
const String kCasdoorServerUrl = 'https://door.casdoor.com';
const String kCasdoorOrganization = 'YOUR_ORG';
const String kCasdoorAppName = 'YOUR_APP';
const String kCasdoorRedirectUri = 'yourapp://callback';
```

`kCasdoorRedirectUri` 需与移动端 URL Scheme / Android Intent Filter 一致。

#### iOS 配置
在 `ios/Runner/Info.plist` 增加 URL Types:
```
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>yourapp</string>
    </array>
  </dict>
</array>
```

#### Android 配置
在 `android/app/src/main/AndroidManifest.xml` 的 `<activity android:name="io.flutter.embedding.android.FlutterActivity" ...>` 内添加 intent filter:
```
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="yourapp" android:host="callback" />
</intent-filter>
```

#### Web (可选)
如需 Web，在 `web/` 创建 `callback.html`:
```
<!DOCTYPE html>
<title>Authentication complete</title>
<p>Authentication complete, you can close this window.</p>
<script>
  window.opener.postMessage({'casdoor-auth': window.location.href}, window.location.origin);
  window.close();
</script>
```
并将重定向地址设为运行域名 `/callback` (例: `http://localhost:8080/callback`).

#### 登录流程
`lib/pages/login.dart`:
1. 点击按钮 -> `Casdoor(config)` 展示授权窗口 (show)
2. 返回 code -> `requestOauthAccessToken` 获取 token 响应 -> `Navigator.pop` 返回

调用方可解析返回 JSON 获取 `access_token` / `id_token`，并可调用解码、用户信息接口。

### 认证服务扩展 (刷新 / 登出 / 安全存储)

`lib/auth/auth_service.dart` 实现：
- 登录：调用 Casdoor 授权，自动获取用户信息并安全存储 token（`flutter_secure_storage`）
- 刷新：在读取缓存时检测过期自动刷新（若存在 refresh_token）
- 登出：`logout(revoke: true)` 可请求 OIDC logout 并清除本地存储
- 用户信息：`getCachedUser()` 若 token 有效直接返回，过期则尝试刷新

存储格式：单一 key `auth_tokens` (JSON 序列化) 包含 accessToken / refreshToken / idToken / expiresAt。

使用示例：
```dart
final auth = AuthService();
final user = await auth.getCachedUser();
if (user == null) {
  final (tokens, profile) = await auth.login();
  print(profile.username);
} else {
  print('Cached user: ${user.username}');
}
```

注意事项：
1. iOS Keychain 与 Android EncryptedSharedPreferences 由 flutter_secure_storage 统一封装
2. 若需要多实例环境/多账号，可为 key 增加租户或用户前缀
3. 生产环境建议：
   - 打开设备硬件加密 (Android API >=23 已默认)
   - 如需后台静默刷新，可在应用启动时调用 `getCachedUser()` 触发刷新
4. 若后端配置不返回 refresh_token，则需缩短 access token 失效前的 UI 交互或引导重新登录

## Server backend as a Git submodule

The backend service lives in the `server/` directory and is tracked as a Git submodule.

- Upstream repo: https://github.com/tonylu00/DALI-Toolkit-server

Common workflows:

1) Clone with submodules

```bash
git clone --recurse-submodules https://github.com/tonylu00/DALI-Toolkit.git
# or, if already cloned
cd DALI-Toolkit
git submodule update --init --recursive
```

2) Update the submodule to latest main and record the new pointer

```bash
# Option A: update inside submodule and commit pointer in parent
cd server
git fetch origin
git checkout main
git pull --ff-only
cd ..
git add server
git commit -m "chore: bump server submodule"

# Option B: from parent repo (updates remote-tracking for submodule)
git submodule update --remote --merge server
git add server
git commit -m "chore: bump server submodule"
```

3) Sync submodule remotes (rare)

```bash
git submodule sync --recursive
```

4) CI setup snippet

```bash
git submodule update --init --recursive
```
