import 'package:flutter/material.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/screens/downloader/tiktok/tiktok.screen.dart';
import 'package:wavvy/screens/downloader/youtube/ytdlp.screen.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

class DownloaderHubScreen extends StatelessWidget {
  const DownloaderHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          const GroupHeader("Sources"),
          InsetGroup(
            dividerIndent: 58,
            children: [
              _buildNavTile(
                context,
                title: "YouTube Downloader",
                subtitle: "Search and download music/video",
                icon: Icons.play_arrow_rounded,
                color: const Color(0xFFD32F2F),
                onTap: () => AppNav.push(const YtdlpSearchScreen()),
              ),
              _buildNavTile(
                context,
                title: "TikTok Downloader",
                subtitle: "Download without watermark",
                icon: Icons.music_note_rounded,
                color: const Color(0xFF2B2B2B),
                onTap: () => AppNav.push(const TikTokSearchScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final a = Aqua.of(context);

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconBadge(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: a.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: a.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: a.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
