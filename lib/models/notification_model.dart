class NotificationModel {
  final String id;
  final String uid;
  final String type;
  final String actorUid;
  final String title;
  final String body;
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
    this.data,
    this.isRead = false,
    DateTime? sentAt,
  }) : sentAt = sentAt ?? DateTime.now();

  factory NotificationModel.fromMap(Map map) {
    return NotificationModel(
      id: map['id']?.toString() ?? '',
      uid: map['uid']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      actorUid: map['actor_uid']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? map['message']?.toString() ?? '',
      data: map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : null,
      isRead: map['is_read'] as bool? ?? map['isRead'] as bool? ?? false,
      sentAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : (map['sent_at'] != null
              ? DateTime.tryParse(map['sent_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
    );
  }
}
