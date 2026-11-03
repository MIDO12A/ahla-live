import 'package:flutter/material.dart';
import '../../config/r.dart';
import 'package:zero/core/dtext.dart';

class GooglePayScreen extends StatefulWidget {
  const GooglePayScreen({super.key});

  @override
  State<GooglePayScreen> createState() => _GooglePayScreenState();
}

class _GooglePayScreenState extends State<GooglePayScreen> {
  bool _isConnected = false;
  String _logs = '';

  void _addLog(String msg) {
    setState(() => _logs = '$_logs\n[${DateTime.now().toString().substring(11, 19)}] $msg');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          // header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: R.image(R.backIc, width: 24, height: 24),
                  ),
                ),
                const Spacer(),
                const DText('Google Pay', style: TextStyle(fontSize: 17, color: Color(0xFF16151A), fontWeight: FontWeight.w500)),
                const Spacer(),
                const SizedBox(width: 32),
              ],
            ),
          ),
          // action buttons
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
            child: Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                _buildActionBtn('Connect', _isConnected ? null : () {
                  _addLog('Connecting to Google Play...');
                  _addLog('BillingClient started');
                  setState(() => _isConnected = true);
                  _addLog('Connected successfully');
                }, color: _isConnected ? Colors.green : null),
                _buildActionBtn('Query Products', _isConnected ? () {
                  _addLog('Querying product details...');
                  _addLog('Found 4 products');
                } : null),
                _buildActionBtn('Query Purchases', _isConnected ? () {
                  _addLog('Querying purchases...');
                  _addLog('No active purchases');
                } : null),
                _buildActionBtn('Purchase', _isConnected ? () {
                  _addLog('Launching billing flow...');
                  _addLog('Purchase flow started');
                } : null),
                _buildActionBtn('Disconnect', _isConnected ? () {
                  _addLog('Disconnecting Google Play...');
                  setState(() => _isConnected = false);
                  _addLog('Disconnected');
                } : null),
                _buildActionBtn('Save Orders', () {
                  _addLog('Saving failed orders...');
                  _addLog('Orders saved');
                }),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 0.5, color: Colors.grey.withValues(alpha: 0.3), margin: const EdgeInsets.symmetric(horizontal: 16)),
          // log area
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: DText(
                  _logs.isEmpty ? 'Logs will appear here...' : _logs,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF485FED), fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(String text, VoidCallback? onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF485FED),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: DText(text, style: const TextStyle(fontSize: 13, color: Colors.white)),
        ),
      ),
    );
  }
}
