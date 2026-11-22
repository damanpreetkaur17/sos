import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ShakeSafeScreen extends StatefulWidget {
  const ShakeSafeScreen({super.key});

  @override
  State<ShakeSafeScreen> createState() => _ShakeSafeScreenState();
}

class _ShakeSafeScreenState extends State<ShakeSafeScreen> {
  static const _shakeThreshold = 20.0;
  static const _shakeCooldown = Duration(seconds: 10);

  StreamSubscription<UserAccelerometerEvent>? _shakeSubscription;
  Timer? _countdownTimer;
  Timer? _holdTimer;
  DateTime? _lastShakeAt;
  int _countdown = 0;
  bool _isPreparingSos = false;
  int _activationToken = 0;
  String? _notice;
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  String _savedContactName = '';
  String _savedContactPhone = '';
  List<Map<String, dynamic>> _history = [];
  bool _contactLoaded = false;
  String? _locationFailure;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _startShakeDetection();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _holdTimer?.cancel();
    _shakeSubscription?.cancel();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  String _formatIndianMobileDigits(String digits) {
    final limited = digits
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(
          0,
          digits.replaceAll(RegExp(r'[^0-9]'), '').length > 10
              ? 10
              : digits.replaceAll(RegExp(r'[^0-9]'), '').length,
        );
    if (limited.length <= 5) {
      return limited;
    }
    return '${limited.substring(0, 5)} ${limited.substring(5)}';
  }

  String _normalizeIndianMobile(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits)) {
      return '';
    }
    return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
  }

  String _getSmsRecipient() {
    var digits = _savedContactPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('91') && digits.length == 12) {
      digits = digits.substring(2);
    }
    return '+91$digits';
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('shakesafe_contact_name') ?? '';
    final savedPhone = prefs.getString('shakesafe_contact_phone') ?? '';
    final phone = _normalizeIndianMobile(savedPhone);
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final digitsAfterCountryCode = digits.startsWith('91')
        ? digits.substring(2)
        : digits;
    final phoneFieldValue = digitsAfterCountryCode.isEmpty
        ? ''
        : _formatIndianMobileDigits(digitsAfterCountryCode);
    final historyJson = prefs.getStringList('shakesafe_alert_history') ?? [];
    final history = <Map<String, dynamic>>[];

    for (final item in historyJson) {
      try {
        final value = jsonDecode(item);
        if (value is Map<String, dynamic>) {
          history.add(value);
        }
      } catch (_) {}
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _savedContactName = name;
      _savedContactPhone = phone;
      _contactNameController.text = name;
      _contactPhoneController.text = phoneFieldValue;
      _history = history;
      _contactLoaded = true;
    });
  }

  Future<void> _saveContact() async {
    final name = _contactNameController.text.trim();
    final phoneDigits = _contactPhoneController.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    if (name.isEmpty) {
      setState(() {
        _notice = 'Enter both a contact name and phone number.';
      });
      return;
    }
    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(phoneDigits)) {
      setState(() {
        _phoneError = 'Enter exactly 10 digits starting with 6, 7, 8, or 9.';
        _notice = null;
      });
      return;
    }

    final phone = _normalizeIndianMobile(phoneDigits);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shakesafe_contact_name', name);
    await prefs.setString('shakesafe_contact_phone', phone);
    if (!mounted) {
      return;
    }
    setState(() {
      _savedContactName = name;
      _savedContactPhone = phone;
      _phoneError = null;
      _notice = 'Emergency contact saved';
    });
  }

  Future<void> _recordAttempt(String status, {String? detail}) async {
    final record = <String, dynamic>{
      'status': status,
      'detail': detail,
      'timestamp': DateTime.now().toIso8601String(),
    };
    final nextHistory = [record, ..._history].take(10).toList();
    setState(() => _history = nextHistory);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'shakesafe_alert_history',
      nextHistory.map((item) => jsonEncode(item)).toList(),
    );
  }

  void _startShakeDetection() {
    _shakeSubscription = userAccelerometerEventStream().listen(
      (event) {
        final acceleration = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );
        if (acceleration < _shakeThreshold || _countdown > 0) {
          return;
        }

        final now = DateTime.now();
        if (_lastShakeAt != null &&
            now.difference(_lastShakeAt!) < _shakeCooldown) {
          return;
        }

        _lastShakeAt = now;
        _startCountdown();
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _notice = 'Shake detection is unavailable on this device.';
          });
        }
      },
    );
  }

  void _startCountdown() {
    if (_countdown > 0 || _isPreparingSos) {
      return;
    }

    _countdownTimer?.cancel();
    _activationToken++;
    setState(() {
      _countdown = 5;
      _notice = null;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
        _prepareAndShareSos(_activationToken);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _cancelCountdown() {
    _activationToken++;
    _countdownTimer?.cancel();
    _recordAttempt('Cancelled', detail: '5-second countdown cancelled');
    setState(() {
      _countdown = 0;
      _isPreparingSos = false;
      _notice = 'SOS cancelled';
    });
  }

  void _beginHold(TapDownDetails details) {
    if (_countdown > 0 || _isPreparingSos) {
      return;
    }
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 600), _startCountdown);
  }

  void _cancelHold([TapUpDetails? details]) {
    _holdTimer?.cancel();
  }

  Future<void> _prepareAndShareSos(int token) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isPreparingSos = true;
      _locationFailure = null;
    });
    final location = await _getLocation(token);
    if (!mounted || token != _activationToken) {
      return;
    }

    setState(() => _isPreparingSos = false);

    final recipient = _getSmsRecipient();
    if (_savedContactPhone.isEmpty ||
        !RegExp(r'^\+91[6-9][0-9]{9}$').hasMatch(recipient)) {
      await _recordAttempt(
        'Not opened',
        detail: 'Emergency contact mobile number is missing or invalid',
      );
      if (mounted) {
        setState(() {
          _notice =
              'Save a valid emergency contact mobile number before sending SOS.';
        });
      }
      return;
    }

    final contactLine = _savedContactName.isNotEmpty
        ? '\nEmergency contact: $_savedContactName'
              '${_savedContactPhone.isNotEmpty ? ' ($_savedContactPhone)' : ''}'
        : '';

    final String message;
    if (location == null) {
      message =
          'EMERGENCY ALERT: I need help. I could not determine my current GPS location.$contactLine';
    } else {
      final latitude = location.latitude.toStringAsFixed(6);
      final longitude = location.longitude.toStringAsFixed(6);
      final mapsUrl = 'https://www.google.com/maps?q=$latitude,$longitude';
      message =
          'EMERGENCY ALERT: I need help.\n'
          'Latitude: $latitude\n'
          'Longitude: $longitude\n'
          'Location: $mapsUrl$contactLine';
    }

    final smsUri = 'sms:$recipient?body=${Uri.encodeComponent(message)}';
    var openedSms = false;
    try {
      openedSms = await launchUrl(
        Uri.parse(smsUri),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      openedSms = false;
    }

    if (openedSms) {
      await _recordAttempt(
        location == null
            ? 'Messaging app opened without location'
            : 'Messaging app opened',
        detail: location == null
            ? (_locationFailure ?? 'SOS SMS prepared without a GPS location')
            : 'SOS SMS prepared with latitude, longitude, and Google Maps link',
      );
      if (mounted) {
        setState(() {
          _notice =
              'Messaging app opened. Review and confirm sending in your SMS app.';
        });
      }
    } else {
      await _recordAttempt(
        'Not opened',
        detail: 'Could not open the device messaging application',
      );
      if (mounted) {
        setState(() {
          _notice = 'Could not open the messaging app. Please try again.';
        });
      }
    }
  }

  Future<Position?> _getLocation(int token) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted && token == _activationToken) {
          setState(() {
            _locationFailure = 'GPS is turned off';
            _notice =
                'GPS is turned off. Turn on location services and try again.';
            _isPreparingSos = false;
          });
        }
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted && token == _activationToken) {
          setState(() {
            _locationFailure = 'Location permission denied';
            _notice = permission == LocationPermission.deniedForever
                ? 'Location permission is blocked. Enable it in app settings.'
                : 'Location permission was denied. SOS could not include a location.';
            _isPreparingSos = false;
          });
        }
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      if (mounted && token == _activationToken) {
        setState(() {
          _locationFailure = 'Current location unavailable';
          _notice =
              'Unable to get your GPS location. Check browser or app location access and try again.';
          _isPreparingSos = false;
        });
      }
      return null;
    }
  }

  String _formatHistoryTime(String timestamp) {
    final date = DateTime.tryParse(timestamp);
    if (date == null) {
      return 'Recent';
    }
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $hour:$minute';
  }

  Widget _buildContactCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101C2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF20314A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_rounded, color: Color(0xFF6E91C9), size: 20),
              SizedBox(width: 8),
              Text(
                'Emergency contact',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _contactNameController,
            enabled: _contactLoaded,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Contact name',
              hintText: 'e.g. Alex',
              prefixIcon: Icon(Icons.badge_outlined),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Phone number',
            style: TextStyle(
              color: Color(0xFF9AA8BA),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 56,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF24344D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF20314A)),
                ),
                child: const Text(
                  '+91',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _contactPhoneController,
                  enabled: _contactLoaded,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [IndianMobileInputFormatter()],
                  onChanged: (_) {
                    if (_phoneError != null) {
                      setState(() => _phoneError = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: '98765 43210',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    isDense: true,
                    errorText: _phoneError,
                  ),
                  onSubmitted: (_) => _saveContact(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _contactLoaded ? _saveContact : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text(
                'Save contact',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF24344D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101C2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF20314A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_rounded, color: Color(0xFF6E91C9), size: 20),
              SizedBox(width: 8),
              Text(
                'Recent alerts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_history.isEmpty)
            const Text(
              'No SOS attempts yet',
              style: TextStyle(color: Color(0xFF9AA8BA)),
            )
          else
            for (final item in _history.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item['status'] == 'Cancelled'
                          ? Icons.cancel_outlined
                          : Icons.share_location_outlined,
                      size: 18,
                      color: item['status'] == 'Cancelled'
                          ? const Color(0xFF82C99A)
                          : const Color(0xFFFF7773),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['status']?.toString() ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (item['detail'] != null)
                            Text(
                              item['detail'].toString(),
                              style: const TextStyle(
                                color: Color(0xFF9AA8BA),
                                fontSize: 12,
                              ),
                            ),
                          Text(
                            _formatHistoryTime(
                              item['timestamp']?.toString() ?? '',
                            ),
                            style: const TextStyle(
                              color: Color(0xFF6F7F94),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final countdownActive = _countdown > 0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(
                    Icons.shield_rounded,
                    color: Color(0xFFE53935),
                    size: 30,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'ShakeSafe',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Spacer(),
                  StatusPill(),
                ],
              ),
              const SizedBox(height: 30),
              if (countdownActive) ...[
                Text(
                  _countdown.toString(),
                  key: ValueKey(_countdown),
                  style: const TextStyle(
                    height: 1,
                    fontSize: 88,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'SOS ACTIVATING',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                    color: Color(0xFFFF7773),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Preparing to share your location',
                  style: TextStyle(
                    color: Color(0xFF9AA8BA),
                    fontSize: 14,
                  ),
                ),
              ] else ...[
                const Text(
                  'Emergency SOS',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hold to activate emergency sharing',
                  style: TextStyle(
                    color: Color(0xFF9AA8BA),
                    fontSize: 15,
                  ),
                ),
              ],
              const SizedBox(height: 34),
              GestureDetector(
                onTapDown: countdownActive ? null : _beginHold,
                onTapUp: countdownActive ? null : _cancelHold,
                onTapCancel: countdownActive ? null : _cancelHold,
                onLongPress: countdownActive ? null : _startCountdown,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: countdownActive ? 238 : 220,
                  height: countdownActive ? 238 : 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF5A52), Color(0xFFCB1D22)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE53935).withValues(alpha: 0.38),
                        blurRadius: countdownActive ? 48 : 32,
                        spreadRadius: countdownActive ? 8 : 2,
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 7,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: countdownActive
                        ? const Icon(
                            Icons.notifications_active_rounded,
                            key: ValueKey('active'),
                            color: Colors.white,
                            size: 74,
                          )
                        : const Column(
                            key: ValueKey('idle'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.emergency_share_rounded,
                                color: Colors.white,
                                size: 58,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'SOS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              if (countdownActive)
                SizedBox(
                  width: 220,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _cancelCountdown,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text(
                      'Cancel SOS',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF4B5A70)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxWidth: 310),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101C2C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF20314A)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.vibration_rounded,
                        size: 20,
                        color: Color(0xFF6E91C9),
                      ),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Shake your phone to activate',
                          style: TextStyle(
                            color: Color(0xFFC7D0DE),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isPreparingSos) ...[
                const SizedBox(height: 18),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF6E91C9),
                  ),
                ),
              ] else if (_notice != null) ...[
                const SizedBox(height: 16),
                Text(
                  _notice!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _notice == 'SOS cancelled'
                        ? const Color(0xFF82C99A)
                        : _notice == 'Emergency contact saved'
                        ? const Color(0xFF82C99A)
                        : const Color(0xFFFFA09C),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_locationFailure != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () async {
                      final permission = await Geolocator.checkPermission();
                      if (permission == LocationPermission.deniedForever) {
                        await Geolocator.openAppSettings();
                      } else {
                        await Geolocator.openLocationSettings();
                      }
                    },
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Open location settings'),
                  ),
                ],
              ],
              const SizedBox(height: 28),
              _buildContactCard(),
              const SizedBox(height: 16),
              _buildHistoryCard(),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class IndianMobileInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }
    final formatted = digits.length <= 5
        ? digits
        : '${digits.substring(0, 5)} ${digits.substring(5)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF10231F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1D4638)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: Color(0xFF68D391)),
          SizedBox(width: 6),
          Text(
            'READY',
            style: TextStyle(
              color: Color(0xFF68D391),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
