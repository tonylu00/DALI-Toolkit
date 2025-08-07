import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '/widgets/common/dt1_test_dialog.dart';
import '/dali/dali.dart';

class DT1TestPage extends StatefulWidget {
  const DT1TestPage({super.key});

  @override
  State<DT1TestPage> createState() => _DT1TestPageState();
}

class _DT1TestPageState extends State<DT1TestPage> {
  String _gatewayAddress = '192.168.1.100';
  int _deviceAddress = 1;
  int _deviceType = 1;

  void _showDT1TestDialog() {
    DT1TestDialog.show(
      context,
      gatewayAddress: _gatewayAddress,
      deviceAddress: _deviceAddress,
      deviceType: _deviceType,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('DT1 Emergency Test'.tr()),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Test Configuration',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Gateway Address
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Gateway Address'.tr(),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.router),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _gatewayAddress = value;
                        });
                      },
                      controller: TextEditingController(text: _gatewayAddress),
                    ),
                    const SizedBox(height: 16),

                    // Device Address
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Device Address'.tr(),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.location_on),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          _deviceAddress = int.tryParse(value) ?? 1;
                        });
                      },
                      controller: TextEditingController(text: _deviceAddress.toString()),
                    ),
                    const SizedBox(height: 16),

                    // Device Type
                    DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: 'Device Type'.tr(),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.device_hub),
                      ),
                      value: _deviceType,
                      items: const [
                        DropdownMenuItem(
                          value: 1,
                          child: Text('DT1 (Emergency Light)'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _deviceType = value ?? 1;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Current device info
            StreamBuilder<int>(
              stream: Dali.instance.addr?.selectedDeviceStream,
              builder: (context, snapshot) {
                final selectedAddress = snapshot.data ?? Dali.instance.base?.selectedAddress ?? 127;
                return Card(
                  elevation: 1,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Current Selection',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Selected Device Address: $selectedAddress',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You can use this address for testing by clicking "Use Selected Address" below.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const Spacer(),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<int>(
                    stream: Dali.instance.addr?.selectedDeviceStream,
                    builder: (context, snapshot) {
                      final selectedAddress =
                          snapshot.data ?? Dali.instance.base?.selectedAddress ?? 127;
                      return ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _deviceAddress = selectedAddress;
                          });
                        },
                        icon: const Icon(Icons.sync),
                        label: Text('Use Selected Address'.tr()),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showDT1TestDialog,
                    icon: const Icon(Icons.flash_on),
                    label: Text('Start Emergency Test'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
