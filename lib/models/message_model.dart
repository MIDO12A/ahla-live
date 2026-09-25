class MessageModel {
  final String msgId;
  final String roomId;
  final String senderUid;
  final String senderName;
  final String senderPhotoUrl;
  final String text;
  final String type;
  final int timestamp;
  final String? imageUrl;
  final String? activeBubble;
  final Map<String, dynamic>? giftPayload;
  final Map<String, dynamic>? luckyBagPayload;

  MessageModel({
    this.msgId = '',
    this.roomId = '',
    this.senderUid = '',
    this.senderName = '',
    this.senderPhotoUrl = '',
    this.text = '',
    this.type = 'text',
    this.timestamp = 0,
    this.imageUrl,
    this.activeBubble,
    this.giftPayload,
    this.luckyBagPayload,
  });

  factory MessageModel.fromMap(Map map) {
    final payloadRaw = map['gift_payload'];
    final luckyBagRaw = map['lucky_bag_payload'];

    int parsedTimestamp = 0;
    final createdVal = map['created_at'] ?? map['timestamp'];
    if (createdVal is int) {
      parsedTimestamp = createdVal;
    } else if (createdVal != null && createdVal.runtimeType.toString() == 'Timestamp') {
      try {
        parsedTimestamp = (createdVal as dynamic).millisecondsSinceEpoch as int;
      } catch (_) {}
    } else if (createdVal != null) {
      parsedTimestamp = DateTime.tryParse(createdVal.toString())?.millisecondsSinceEpoch ?? 0;
    }

    final rawImage = map['image_url'] ?? map['imageUrl'];
    final textVal = map['text']?.toString() ?? '';
    final typeVal = map['type']?.toString() ?? 'text';
    final resolvedImage = rawImage != null
        ? rawImage.toString()
        : (typeVal == 'image' && (textVal.startsWith('http://') || textVal.startsWith('https://'))
            ? textVal
            : null);

    return MessageModel(
      msgId: map['msg_id']?.toString() ?? '',
      roomId: map['room_id']?.toString() ?? '',
      senderUid: map['sender_uid']?.toString() ?? '',
      senderName: map['sender_name']?.toString() ?? '',
      senderPhotoUrl: map['sender_photo_url']?.toString() ?? '',
      text: textVal,
      type: typeVal,
      timestamp: parsedTimestamp,
      imageUrl: resolvedImage,
      activeBubble: map['active_bubble']?.toString(),
      giftPayload: payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : null,
      luckyBagPayload: luckyBagRaw is Map
          ? Map<String, dynamic>.from(luckyBagRaw)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'msg_id': msgId,
        'room_id': roomId,
        'sender_uid': senderUid,
        'sender_name': senderName,
        'sender_photo_url': senderPhotoUrl,
        'text': text,
        'type': type,
        'created_at': timestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String()
            : null,
        'image_url': imageUrl,
        'active_bubble': activeBubble,
        if (giftPayload != null) 'gift_payload': giftPayload,
        if (luckyBagPayload != null) 'lucky_bag_payload': luckyBagPayload,
      };
}
