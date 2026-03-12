import 'package:flutter/material.dart';
import '../services/rtsp_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final RtspService _rtspService;
  int _speakerVolume = 1;
  bool _isSettingVolume = false;

  @override
  void initState() {
    super.initState();
    _rtspService = RtspService();
    _loadCurrentVolume();
  }

  @override
  void dispose() {
    _rtspService.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentVolume() async {
    // Could implement getting current volume if needed
    setState(() {
      _speakerVolume = 1; // Default to low
    });
  }

  Future<void> _setVolume(int volume) async {
    if (_isSettingVolume) return;

    setState(() {
      _isSettingVolume = true;
    });

    try {
      final success = await _rtspService.setSpeakerVolume(volume);
      if (mounted) {
        if (success) {
          setState(() {
            _speakerVolume = volume;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Volume set to ${_getVolumeLabel(volume)}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed: ${_rtspService.errorMessage ?? "Unknown error"}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSettingVolume = false;
        });
      }
    }
  }

  String _getVolumeLabel(int volume) {
    const labels = ['Off', 'Low', 'Middle', 'High', 'Very High'];
    return labels[volume];
  }

  IconData _getVolumeIcon(int volume) {
    switch (volume) {
      case 0: return Icons.volume_off;
      case 1: return Icons.volume_down;
      case 2: return Icons.volume_mute;
      case 3: return Icons.volume_up;
      case 4: return Icons.volume_up;
      default: return Icons.volume_down;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: ListView(
        children: [
          // Speaker Volume Section
          _buildSectionHeader('Speaker Volume'),
          _buildVolumeControl(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildVolumeControl() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getVolumeIcon(_speakerVolume),
                color: Colors.white70,
              ),
              const SizedBox(width: 12),
              Text(
                'Current: ${_getVolumeLabel(_speakerVolume)}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Volume level buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(5, (index) {
              return _buildVolumeButton(index);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeButton(int volume) {
    final isSelected = _speakerVolume == volume;
    return InkWell(
      onTap: _isSettingVolume ? null : () => _setVolume(volume),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade700 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue.shade500 : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getVolumeIcon(volume), size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              _getVolumeLabel(volume),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
