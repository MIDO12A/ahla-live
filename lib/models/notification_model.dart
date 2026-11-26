class NotificationModel {
  final String id;
  final String uid;
  final String type;
  final String actorUid;
  final String title;
  final String body;
  final String? imageUrl;
  final String? linkUrl;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime sentAt;

  DateTime get createdAt => sentAt;

  NotificationModel({
    required this.id,
    required this.uid,
    required this.type,
    required this.actorUid,
    this.title = '',
    this.body = '',
    this.imageUrl,
    this.linkUrl,
    this.data,
    this.isRead = false,
    DateTime? sentAt,
  }) : sentAt = sentAt ?? DateTime.now();

  factory NotificationModel.fromMap(Map map) {
    final rawData = map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : null;
    final img = map['image_url']?.toString() ??
        map['imageUrl']?.toString() ??
        rawData?['image_url']?.toString() ??
        rawData?['img']?.toString();
    final link = map['link_url']?.toString() ??
        map['linkUrl']?.toString() ??
        rawData?['link_url']?.toString() ??
        rawData?['url']?.toString() ??
        rawData?['action_url']?.toString();

    return NotificationModel(
      id: map['id']?.toString() ?? '',
      uid: (map['uid'] != null && map['uid'].toString().isNotEmpty)
          ? map['uid'].toString()
          : (map['target']?.toString() ?? ''),
      type: (map['type'] != null && map['type'].toString().isNotEmpty)
          ? map['type'].toString()
          : 'system',
      actorUid: map['actor_uid']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? map['message']?.toString() ?? '',
      imageUrl: (img != null && img.trim().isNotEmpty) ? img.trim() : null,
      linkUrl: (link != null && link.trim().isNotEmpty) ? link.trim() : null,
      data: rawData,
      isRead: map['is_read'] as bool? ?? map['isRead'] as bool? ?? false,
      sentAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : (map['sent_at'] != null
              ? DateTime.tryParse(map['sent_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
    );
  }
}
