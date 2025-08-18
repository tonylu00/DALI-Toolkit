# dalimaster

DALI Inspector V2 (cross platform)

## Getting Started

This project is a cross platform implementation of DALI Master.
Supported platforms: Windows, Linux, MacOS, iOS, Android.

### 总线状态监测 (Type0 网关)
当连接到被判定为 type0 的网关时，如果在空闲通知中接收到连续两个字节 0xFF 0xFD，界面标题处会显示“总线异常”；若 5 秒内未再次收到该序列，将自动恢复为“总线正常”。
（假设 checkGatewayType 返回 0 即为 type0 网关，如实际判定规则不同请调整 ConnectionManager.gatewayType 逻辑。）
