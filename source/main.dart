import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NfcScannerApp());
}

class NfcScannerApp extends StatelessWidget {
  const NfcScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NFC Student Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457C5)),
        useMaterial3: true,
      ),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final TextEditingController _serverController =
      TextEditingController(text: 'http://192.168.137.1:3000');

  NfcAvailability? _availability;
  bool _scanning = false;
  bool _sending = false;
  bool _serverOk = false;

  String _statusTitle = 'Chưa bắt đầu quét';
  String _statusDetail = 'Nhập địa chỉ server laptop rồi bấm Bắt đầu quét.';
  String? _lastUid;
  String? _lastStudent;
  DateTime? _lastReadAt;

  @override
  void initState() {
    super.initState();
    _checkNfc();
  }

  @override
  void dispose() {
    if (_scanning) {
      NfcManager.instance.stopSession();
    }
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _checkNfc() async {
    final result = await NfcManager.instance.checkAvailability();
    if (!mounted) return;
    setState(() {
      _availability = result;
      if (result == NfcAvailability.disabled) {
        _statusTitle = 'NFC đang tắt';
        _statusDetail = 'Hãy bật NFC trong Cài đặt của điện thoại.';
      } else if (result == NfcAvailability.unsupported) {
        _statusTitle = 'Thiết bị không hỗ trợ NFC';
        _statusDetail = 'Cần một điện thoại Android có NFC.';
      }
    });
  }

  String get _baseUrl {
    var value = _serverController.text.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  bool _validServerUrl() {
    final uri = Uri.tryParse(_baseUrl);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _testServer() async {
    FocusScope.of(context).unfocus();

    if (!_validServerUrl()) {
      setState(() {
        _serverOk = false;
        _statusTitle = 'Địa chỉ server không hợp lệ';
        _statusDetail = 'Ví dụ: http://192.168.137.1:3000';
      });
      return;
    }

    setState(() {
      _statusTitle = 'Đang kiểm tra server...';
      _statusDetail = _baseUrl;
    });

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/state'))
          .timeout(const Duration(seconds: 4));

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _serverOk = true;
          _statusTitle = 'Đã kết nối laptop';
          _statusDetail = 'Server hoạt động: $_baseUrl';
        });
      } else {
        setState(() {
          _serverOk = false;
          _statusTitle = 'Server trả lỗi ${response.statusCode}';
          _statusDetail = 'Kiểm tra Node.js trên laptop.';
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _serverOk = false;
        _statusTitle = 'Kết nối quá thời gian';
        _statusDetail = 'Điện thoại và laptop phải cùng Wi-Fi/hotspot.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverOk = false;
        _statusTitle = 'Không kết nối được laptop';
        _statusDetail = e.toString();
      });
    }
  }

  Future<void> _startScanner() async {
    FocusScope.of(context).unfocus();

    await _checkNfc();

    if (_availability != NfcAvailability.enabled) {
      return;
    }

    if (!_validServerUrl()) {
      setState(() {
        _statusTitle = 'Nhập server trước';
        _statusDetail = 'Ví dụ: http://192.168.137.1:3000';
      });
      return;
    }

    if (_scanning) return;

    try {
      await NfcManager.instance.startSession(
        pollingOptions: const {NfcPollingOption.iso14443},
        noPlatformSoundsAndroid: false,
        onDiscovered: (NfcTag tag) {
          _handleTag(tag);
        },
      );

      if (!mounted) return;
      setState(() {
        _scanning = true;
        _statusTitle = 'Sẵn sàng quét';
        _statusDetail = 'Đưa thẻ NTAG215 sát mặt lưng điện thoại.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _statusTitle = 'Không thể mở máy quét NFC';
        _statusDetail = e.toString();
      });
    }
  }

  Future<void> _stopScanner() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _scanning = false;
      _statusTitle = 'Đã dừng quét';
      _statusDetail = 'Bấm Bắt đầu quét để tiếp tục.';
    });
  }

  Future<void> _handleTag(NfcTag tag) async {
    final androidTag = NfcTagAndroid.from(tag);

    if (androidTag == null) {
      if (!mounted) return;
      setState(() {
        _statusTitle = 'Không lấy được UID';
        _statusDetail = 'Thẻ không cung cấp Android tag identifier.';
      });
      return;
    }

    final uid = androidTag.id
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();

    final now = DateTime.now();

    // Chống gửi lặp khi người dùng vẫn giữ cùng một thẻ trên điện thoại.
    if (_lastUid == uid &&
        _lastReadAt != null &&
        now.difference(_lastReadAt!) < const Duration(seconds: 2)) {
      return;
    }

    if (_sending) return;

    _lastUid = uid;
    _lastReadAt = now;

    if (!mounted) return;
    setState(() {
      _sending = true;
      _lastStudent = null;
      _statusTitle = 'Đã đọc thẻ';
      _statusDetail = 'UID: $uid\nĐang gửi về laptop...';
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/nfc-scan'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'uid': uid,
              'date': DateTime.now().toUtc().toIso8601String(),
              'content': '',
            }),
          )
          .timeout(const Duration(seconds: 5));

      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      } catch (_) {}

      final type = body['type']?.toString() ?? '';
      final message = body['message']?.toString() ?? 'Đã gửi dữ liệu.';
      final student = body['student'];

      String? studentText;
      if (student is Map) {
        final name = student['name']?.toString() ?? '';
        final mssv = student['mssv']?.toString() ?? '';
        if (name.isNotEmpty || mssv.isNotEmpty) {
          studentText = [name, mssv].where((e) => e.isNotEmpty).join(' • ');
        }
      }

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (type == 'success') {
          await HapticFeedback.mediumImpact();
          await SystemSound.play(SystemSoundType.click);
        }

        setState(() {
          _serverOk = true;
          _lastStudent = studentText;
          if (type == 'success') {
            _statusTitle = '✓ Điểm danh thành công';
          } else if (type == 'duplicate') {
            _statusTitle = 'Đã điểm danh trước đó';
          } else if (type == 'unknown') {
            _statusTitle = 'Thẻ chưa đăng ký';
          } else if (type == 'rejected') {
            _statusTitle = 'Không đúng lớp học';
          } else {
            _statusTitle = 'Laptop đã nhận UID';
          }
          _statusDetail = '$message\nUID: $uid';
        });
      } else {
        setState(() {
          _serverOk = false;
          _statusTitle = 'Laptop trả lỗi ${response.statusCode}';
          _statusDetail = '$message\nUID: $uid';
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _serverOk = false;
        _statusTitle = 'Gửi thất bại';
        _statusDetail =
            'Không nhận phản hồi từ laptop.\nUID đã đọc: $uid';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverOk = false;
        _statusTitle = 'Gửi thất bại';
        _statusDetail = '$e\nUID đã đọc: $uid';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Color _statusColor(ColorScheme colors) {
    if (_statusTitle.contains('thành công') || _serverOk) {
      return colors.primaryContainer;
    }
    if (_statusTitle.contains('lỗi') ||
        _statusTitle.contains('thất bại') ||
        _statusTitle.contains('Không ')) {
      return colors.errorContainer;
    }
    return colors.surfaceContainerHighest;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final nfcText = switch (_availability) {
      NfcAvailability.enabled => 'NFC đã bật',
      NfcAvailability.disabled => 'NFC đang tắt',
      NfcAvailability.unsupported => 'Không hỗ trợ NFC',
      null => 'Đang kiểm tra NFC...',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Student Scanner'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.nfc,
                      size: 34,
                      color: _availability == NfcAvailability.enabled
                          ? colors.primary
                          : colors.error,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nfcText,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            _scanning
                                ? 'Máy quét đang hoạt động'
                                : 'Máy quét đang dừng',
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kiểm tra lại NFC',
                      onPressed: _checkNfc,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _serverController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ server trên laptop',
                hintText: 'http://192.168.137.1:3000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.laptop_windows),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _sending ? null : _testServer,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Kiểm tra kết nối laptop'),
            ),
            const SizedBox(height: 18),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _statusColor(colors),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Icon(
                    _scanning ? Icons.contactless : Icons.nfc_rounded,
                    size: 72,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusDetail,
                    textAlign: TextAlign.center,
                  ),
                  if (_lastStudent != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _lastStudent!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (_lastUid != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _lastUid!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (_sending) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!_scanning)
              FilledButton.icon(
                onPressed: _availability == NfcAvailability.enabled
                    ? _startScanner
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Text('Bắt đầu quét'),
                ),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: _stopScanner,
                icon: const Icon(Icons.stop),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Text('Dừng quét'),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Cách dùng: laptop chạy server Node.js → điện thoại và laptop cùng mạng → '
              'nhập IP laptop → kiểm tra kết nối → bắt đầu quét → đưa NTAG215 sát điện thoại.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
