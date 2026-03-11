import 'package:flutter/material.dart';
import '../models/f9_file.dart';
import 'file_thumbnail.dart';

class FileGridItem extends StatelessWidget {
  final F9File file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double thumbnailSize;

  const FileGridItem({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
    this.thumbnailSize = 120,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: FileThumbnail(
                file: file,
                size: thumbnailSize,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                file.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    file.sizeString,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                  if (file.type == FileType.video && file.duration > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '·',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.access_time,
                      size: 12,
                      color: Colors.white60,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      file.durationString,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _formatDate(file.time),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      // Input format from API: "20240101120000"
      // Output format: "01/01"
      if (dateStr.length >= 8) {
        final month = dateStr.substring(4, 6);
        final day = dateStr.substring(6, 8);
        return '$month/$day';
      }
    } catch (_) {}
    return dateStr;
  }
}
