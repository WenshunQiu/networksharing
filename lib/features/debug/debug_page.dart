import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dart:io';

import '../../data/app_logger.dart';
import '../../data/platform_network_control.dart';
import '../bluetooth/bluetooth_view_model.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({required this.bluetooth, super.key});
  final BluetoothViewModel bluetooth;

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  String? _hotspotStatus;
  String? _wifiStatus;
  bool _busy = false;
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.bluetooth,
    builder: (context, _) => ScaffoldPage(
      header: PageHeader(
        title: const Text('Debug'),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '网络联通测试',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : widget.bluetooth.runLocalNetworkProbe,
                  child: const Text('检测本机网络'),
                ),
                FilledButton(
                  onPressed: _busy ? null : widget.bluetooth.runNetworkProbe,
                  child: const Text('检测本机网络并通知对端'),
                ),
                if (widget.bluetooth.lastNetworkProbeResult case final result?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(result),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _runNotificationTest,
                  child: const Text('发送通知测试（本机和对端）'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _requestPeerHotspot,
                  child: const Text('请求对端开启热点'),
                ),
                if (widget.bluetooth.peerHotspotRequestPending)
                  InfoBar(
                    title: const Text('对端请求开启本机热点'),
                    content: const Text('允许后会尝试启动热点并将热点凭据发送给对端。'),
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Button(
                          onPressed: _busy ? null : _acceptHotspotRequest,
                          child: const Text('开启并连接'),
                        ),
                        Button(
                          onPressed: () =>
                              widget.bluetooth.respondToPeerHotspot(false),
                          child: const Text('拒绝'),
                        ),
                      ],
                    ),
                    severity: InfoBarSeverity.warning,
                  ),
                const SizedBox(height: 24),
                Text(
                  '热点控制',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy || widget.bluetooth.hotspotBusy
                      ? null
                      : _toggleHotspot,
                  child: Text(
                    defaultTargetPlatform == TargetPlatform.android
                        ? '尝试开启手机热点'
                        : '尝试开启 Windows 移动热点',
                  ),
                ),
                Button(
                  onPressed: _busy || widget.bluetooth.hotspotBusy
                      ? null
                      : () => widget.bluetooth.controlHotspot('stopHotspot'),
                  child: const Text('关闭本机热点'),
                ),
                Button(
                  onPressed: _busy || widget.bluetooth.hotspotBusy
                      ? null
                      : () => widget.bluetooth.controlHotspot('getHotspot'),
                  child: const Text('读取本机热点信息并发送给对端'),
                ),
                if (widget.bluetooth.localHotspotStatus case final status?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(status),
                  ),
                if (widget.bluetooth.hotspotRequestStatus case final status?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(status),
                  ),
                if (_hotspotStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_hotspotStatus!),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Wi-Fi 网络',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _selectWifi,
                  child: const Text('选择并连接 Wi-Fi'),
                ),
                if (_wifiStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_wifiStatus!),
                  ),
                const SizedBox(height: 16),
                TextBox(
                  controller: _ssidController,
                  placeholder: '连接 Wi-Fi：SSID',
                ),
                const SizedBox(height: 8),
                PasswordBox(
                  controller: _passwordController,
                  placeholder: 'Wi-Fi 密码',
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _connectEnteredWifi,
                  child: const Text('连接输入的 Wi-Fi'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Debug 热点凭据传输',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _sendCredentials,
                  child: const Text('通过蓝牙发送给已配对设备'),
                ),
                if (widget.bluetooth.wifiTransferStatus case final status?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(status),
                  ),
                if (widget.bluetooth.lastReceivedWifiCredentials
                    case final credentials?)
                  InfoBar(
                    title: const Text('收到调试凭据'),
                    content: Text(credentials),
                  ),
                if (widget.bluetooth.receivedWifiSsid case final ssid?)
                  FilledButton(
                    onPressed: _busy ? null : () => _connectReceivedWifi(ssid),
                    child: Text('连接收到的 Wi-Fi：$ssid'),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _toggleHotspot() async {
    setState(() => _busy = true);
    AppLogger.instance.info('debug', 'hotspot.toggle_requested');
    try {
      final success = await widget.bluetooth.controlHotspot('startHotspot');
      _hotspotStatus = widget.bluetooth.localHotspotStatus;
      AppLogger.instance.info('debug', 'hotspot.toggle_result', {
        'success': success,
      });
    } catch (error) {
      _hotspotStatus = error.toString();
      AppLogger.instance.error('debug', 'hotspot.toggle_failed', {
        'errorType': error.runtimeType.toString(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectWifi() async {
    AppLogger.instance.info('debug', 'wifi.selection_requested');
    try {
      final result = defaultTargetPlatform == TargetPlatform.windows
          ? await _openWindowsSettings(
              'ms-settings:network-wifi',
              '已打开 Windows Wi-Fi 设置，请选择网络并连接。',
            )
          : await const MethodChannel('networksharing/debug')
                .invokeMethod<String>('selectWifi');
      if (mounted) setState(() => _wifiStatus = result ?? '系统未返回状态');
      AppLogger.instance.info('debug', 'wifi.selection_result', {
        'result': result,
      });
    } catch (error) {
      if (mounted) setState(() => _wifiStatus = error.toString());
      AppLogger.instance.error('debug', 'wifi.selection_failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  Future<void> _runNotificationTest() async {
    try {
      await widget.bluetooth.sendNotificationTest();
    } catch (error) {
      if (mounted) setState(() => _hotspotStatus = error.toString());
      AppLogger.instance.warning('notification', 'test.failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  Future<void> _requestPeerHotspot() async {
    try {
      await widget.bluetooth.requestPeerHotspot();
      if (mounted) setState(() => _hotspotStatus = '已向对端发送开启热点确认请求。');
    } catch (error) {
      if (mounted) setState(() => _hotspotStatus = error.toString());
    }
  }

  Future<void> _sendCredentials() async {
    try {
      await widget.bluetooth.sendDebugWifiCredentials(
        _ssidController.text,
        _passwordController.text,
      );
      if (mounted) setState(() => _wifiStatus = '调试凭据已通过蓝牙发送。');
    } catch (error) {
      if (mounted) setState(() => _wifiStatus = error.toString());
      AppLogger.instance.error('debug', 'wifi.credentials_send_failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  Future<void> _connectEnteredWifi() async {
    await _connectWifi(_ssidController.text.trim(), _passwordController.text);
  }

  Future<void> _acceptHotspotRequest() async {
    await widget.bluetooth.respondToPeerHotspot(true);
  }

  Future<void> _connectReceivedWifi(String ssid) async {
    await _connectWifi(ssid, widget.bluetooth.receivedWifiPassword ?? '');
  }

  Future<void> _connectWifi(String ssid, String password) async {
    if (ssid.trim().isEmpty) {
      if (mounted) setState(() => _wifiStatus = '请填写 SSID。');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await PlatformNetworkControl().execute(
        'connectWifi',
        ssid: ssid.trim(),
        password: password,
      );
      if (mounted) setState(() => _wifiStatus = result['message']?.toString());
      await widget.bluetooth
          .reportWifiConnectionResult(result['success'] == true)
          .catchError((Object error) {
            AppLogger.instance.warning(
              'debug',
              'wifi.connection_result_send_failed',
              {'errorType': error.runtimeType.toString()},
            );
          });
    } catch (error) {
      if (mounted) setState(() => _wifiStatus = error.toString());
      await widget.bluetooth
          .reportWifiConnectionResult(false)
          .catchError((Object _) {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _openWindowsSettings(String uri, String message) async {
    await Process.start('explorer.exe', [uri], mode: ProcessStartMode.detached);
    return message;
  }
}
