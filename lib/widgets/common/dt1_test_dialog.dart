import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '/dali/dali.dart';

class DT1TestDialog extends StatefulWidget {
  final String gatewayAddress;
  final int deviceAddress;
  final int deviceType;

  const DT1TestDialog({
    super.key,
    required this.gatewayAddress,
    required this.deviceAddress,
    required this.deviceType,
  });

  static void show(
    BuildContext context, {
    required String gatewayAddress,
    required int deviceAddress,
    required int deviceType,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return DT1TestDialog(
          gatewayAddress: gatewayAddress,
          deviceAddress: deviceAddress,
          deviceType: deviceType,
        );
      },
    );
  }

  @override
  State<DT1TestDialog> createState() => _DT1TestDialogState();
}

class _DT1TestDialogState extends State<DT1TestDialog> with TickerProviderStateMixin {
  bool _isTestRunning = false;
  String _testStatus = 'Ready';
  Color _statusColor = Colors.grey;
  bool _testCompleted = false;
  bool? _testResult;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startTest() async {
    setState(() {
      _isTestRunning = true;
      _testStatus = 'test.dt1.starting'.tr();
      _statusColor = Colors.orange;
      _testCompleted = false;
      _testResult = null;
    });

    _animationController.repeat();

    try {
      final dt1 = Dali.instance.dt1;
      if (dt1 != null) {
        // Start the DT1 test
        await dt1.startDT1Test(widget.deviceAddress, widget.deviceType);

        setState(() {
          _testStatus = 'test.dt1.in_progress_wait'.tr();
        });

        // Monitor the test with detailed status updates
        int maxAttempts = 30; // 30 seconds timeout
        for (int i = 0; i < maxAttempts && _isTestRunning; i++) {
          await Future.delayed(const Duration(seconds: 1));

          if (!_isTestRunning) break;

          // Get detailed test status
          Map<String, dynamic>? detailedStatus =
              await dt1.getDT1TestStatusDetailed(widget.deviceAddress);

          if (detailedStatus != null) {
            setState(() {
              if (detailedStatus['testInProgress'] == true) {
                final elapsed = detailedStatus['elapsedSeconds']?.toString() ?? (i + 1).toString();
                _testStatus = 'test.dt1.in_progress_seconds'
                    .tr(namedArgs: {'elapsed': elapsed, 'total': maxAttempts.toString()});
              } else if (detailedStatus['testDone'] == true) {
                // Test completed, check for failures
                bool hasFailure = detailedStatus['lampFailure'] == true ||
                    detailedStatus['batteryFailure'] == true;

                _testResult = !hasFailure;
                _testCompleted = true;
                _isTestRunning = false;

                if (hasFailure) {
                  List<String> failures = [];
                  if (detailedStatus['lampFailure'] == true) {
                    failures.add('Lamp failure');
                  }
                  if (detailedStatus['batteryFailure'] == true) {
                    failures.add('Battery failure');
                  }
                  _testStatus = 'Test completed with failures: ${failures.join(', ')}';
                  _statusColor = Colors.red;
                } else {
                  _testStatus = 'test.dt1.success'.tr();
                  _statusColor = Colors.green;
                }
                return; // Exit the function early
              }
            });
          }
        }

        // If we reach here and test is still running, it's a timeout
        if (_isTestRunning) {
          setState(() {
            _testResult = false;
            _testCompleted = true;
            _isTestRunning = false;
            _testStatus = 'test.dt1.failed_or_timeout'.tr();
            _statusColor = Colors.red;
          });
        }
      } else {
        throw Exception('DT1 module not available');
      }
    } catch (e) {
      setState(() {
        _testResult = false;
        _testCompleted = true;
        _isTestRunning = false;
        _testStatus = 'test.dt1.error'.tr(namedArgs: {'message': e.toString()});
        _statusColor = Colors.red;
      });
    }

    _animationController.stop();
    _animationController.reset();
  }

  void _stopTest() {
    setState(() {
      _isTestRunning = false;
      _testStatus = 'test.dt1.stopped_by_user'.tr();
      _statusColor = Colors.orange;
      _testCompleted = true;
      _testResult = null;
    });

    _animationController.stop();
    _animationController.reset();
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isTestRunning)
                RotationTransition(
                  turns: _animation,
                  child: Icon(
                    Icons.refresh,
                    color: _statusColor,
                    size: 24,
                  ),
                )
              else
                Icon(
                  _testCompleted
                      ? (_testResult == true ? Icons.check_circle : Icons.error)
                      : Icons.info,
                  color: _statusColor,
                  size: 24,
                ),
              const SizedBox(width: 8),
              Text(
                'test.dt1.status'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: _statusColor.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _testStatus,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: _statusColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.flash_on,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text('test.dt1.title'.tr()),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Information Section
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.devices,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'test.dt1.device_info'.tr(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('test.dt1.gateway_address'.tr(), widget.gatewayAddress),
                  _buildInfoRow('device.address'.tr(), widget.deviceAddress.toString()),
                  _buildInfoRow('device.type'.tr(), 'DT${widget.deviceType} (Emergency Light)'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Test Status Section
            _buildStatusIndicator(),
          ],
        ),
      ),
      actions: [
        if (_isTestRunning)
          TextButton(
            onPressed: _stopTest,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stop, size: 18),
                const SizedBox(width: 4),
                Text('test.dt1.stop_button'.tr()),
              ],
            ),
          )
        else
          TextButton(
            onPressed: _testCompleted ? null : _startTest,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow, size: 18),
                const SizedBox(width: 4),
                Text('test.dt1.start_button'.tr()),
              ],
            ),
          ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _isTestRunning ? null : () => Navigator.of(context).pop(),
          child: Text('Close'.tr()),
        ),
      ],
    );
  }
}
