import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class JobDetailPage extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool isSaved;
  final VoidCallback onSave;

  const JobDetailPage({
    super.key,
    required this.job,
    required this.isSaved,
    required this.onSave,
  });

  Future<void> _launchApplyLink(BuildContext context, String rawUrl) async {
    if (rawUrl.trim().isEmpty) return;

    String urlStr = rawUrl.trim();
    if (!urlStr.startsWith('http://') && !urlStr.startsWith('https://')) {
      urlStr = 'https://$urlStr';
    }

    final uri = Uri.tryParse(urlStr);
    if (uri == null) {
      _showSnack(context, '❌ Invalid link');
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        final launched2 = await launchUrl(uri, mode: LaunchMode.inAppWebView);
        if (!launched2) {
          await Clipboard.setData(ClipboardData(text: urlStr));
          if (context.mounted)
            _showSnack(context, '📋 Link copied — paste in your browser');
        }
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: urlStr));
      if (context.mounted)
        _showSnack(context, '📋 Link copied — paste in your browser');
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color c = job['color'] as Color;
    final String title = job['title'] ?? '';
    final String company = job['company'] ?? '';
    final String location = job['location'] ?? '';
    final String type = job['type'] ?? '';
    final String description = job['description'] ?? '';
    final String applyLink = job['applyLink'] ?? '';
    final String postedBy = (job['postedByRole'] ?? '')
        .toString()
        .toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060D1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Job Details',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            onPressed: onSave,
            icon: Icon(
              isSaved ? Icons.bookmark : Icons.bookmark_outline,
              color: isSaved
                  ? const Color(0xFF1E90FF)
                  : Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.withValues(alpha: 0.35)),
                  ),
                  child: Icon(Icons.business_center, color: c, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        company,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Details card ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  if (location.isNotEmpty)
                    _detailRow(
                      Icons.location_on_outlined,
                      'Location',
                      location,
                    ),
                  if (type.isNotEmpty)
                    _detailRow(Icons.work_outline, 'Job Type', type),
                  if (postedBy == 'alumni')
                    _detailRow(
                      Icons.people_outline,
                      'Posted by',
                      'Alumni Referral',
                      valueColor: const Color(0xFF00C9A7),
                    ),
                  if (applyLink.isNotEmpty)
                    _detailRow(
                      Icons.link,
                      'Apply Link',
                      applyLink,
                      valueColor: const Color(0xFF1E90FF),
                    ),
                ],
              ),
            ),

            // ── Description ────────────────────────────────────────
            if (description.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.6,
                ),
              ),
            ],

            // ── Apply section ──────────────────────────────────────
            if (applyLink.isNotEmpty) ...[
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E90FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF1E90FF).withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How to Apply',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Tappable link
                    GestureDetector(
                      onTap: () => _launchApplyLink(context, applyLink),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: Color(0xFF1E90FF),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              applyLink,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1E90FF),
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFF1E90FF),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Copy link button
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: applyLink));
                        if (context.mounted) {
                          _showSnack(context, '📋 Link copied to clipboard!');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.copy,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Copy Link',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Big Apply Now button ─────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => _launchApplyLink(context, applyLink),
                  icon: const Icon(
                    Icons.open_in_new,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Apply Now',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E90FF),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
