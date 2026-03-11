import 'package:flutter/material.dart';
import '../models/f9_file.dart';
import 'file_thumbnail.dart';

class FileListItem extends StatelessWidget {
  final F9File file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double thumbnailSize;

  const FileListItem({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
    this.thumbnailSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              FileThumbnail(
                file: file,
                size: thumbnailSize,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.dateString,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          file.type == FileType.video ? Icons.movie : Icons.photo,
                          size: 14,
                          color: Colors.white.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          file.sizeString,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                        if (file.type == FileType.video && file.duration > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 12,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.white60,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            file.durationString,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (file.hasGps)
                          const Icon(
                            Icons.gps_fixed,
                            size: 16,
                            color: Colors.lightGreen,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
