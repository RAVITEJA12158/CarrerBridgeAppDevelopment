import 'package:flutter/material.dart';

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
          // Save / bookmark toggle
          IconButton(
            onPressed: onSave,
            icon: Icon(
              isSaved ? Icons.bookmark : Icons.bookmark_outline,
              color: isSaved
                  ? const Color(0xFF1E90FF)
                  : Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Company icon + title ──────────────────────────────
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.withOpacity(0.35)),
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
                          color: Colors.white.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Details ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
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

            // ── Description ───────────────────────────────────────
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
                  color: Colors.white.withOpacity(0.7),
                  height: 1.6,
                ),
              ),
            ],

            // ── Apply link display ────────────────────────────────
            if (applyLink.isNotEmpty) ...[
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E90FF).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF1E90FF).withOpacity(0.25),
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
                    const Text(
                      'Open the link below on your browser to apply:',
                      style: TextStyle(fontSize: 13, color: Color(0xFF7FA7C9)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      applyLink,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1E90FF),
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF1E90FF),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
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
          Icon(icon, size: 16, color: Colors.white.withOpacity(0.4)),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.4),
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
