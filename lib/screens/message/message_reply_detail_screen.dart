import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../services/cloudinary_service.dart';
import '../../providers/user_provider.dart';
import '../../models/message_model.dart';
import '../report/report_user_screen.dart';

class MessageReplyDetailScreen extends StatefulWidget {
  final String conversationId;
  final String otherUid;
  final String otherName;
  final String otherPhotoUrl;

  const MessageReplyDetailScreen({
    super.key,
    required this.conversationId,
    required this.otherUid,
    required this.otherName,
    required this.otherPhotoUrl,
  });

  @override
  State<MessageReplyDetailScreen> createState() =>
      _MessageReplyDetailScreenState();
}

class _MessageReplyDetailScreenState extends State<MessageReplyDetailScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SupabaseService _firebaseService = SupabaseService();
  List<MessageModel> _messages = [];
  bool _sendingImage = false;
  StreamSubscription? _messagesSub;

  @override
  void initState() {
    super.initState();
    _messagesSub = _firebaseService
        .privateMessagesStream(widget.conversationId)
        .listen((msgs) {
      if (mounted) {
        setState(() => _messages = msgs);
        WidgetsBinding.instance.addPostFrameCallback((_) =>
            _scrollToBottom());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      if (userProvider.currentUser != null) {
        _firebaseService.markConversationRead(
            userProvider.currentUser!.uid, widget.conversationId);
      }
    });
  }

  void _confirmBlockUser() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحظر'),
        content: const Text('هل أنت متأكد أنك تريد حظر هذا المستخدم؟ لن يتمكن من إرسال رسائل إليك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final userProvider = Provider.of<UserProvider>(context, listen: false);
              final user = userProvider.currentUser;
              if (user != null) {
                await _firebaseService.setDoc('blocks', '${user.uid}_${widget.otherUid}', {
                  'blockerId': user.uid,
                  'blockedId': widget.otherUid,
                  'created_at': DateTime.now().toIso8601String(),
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حظر المستخدم بنجاح')));
                }
              }
            },
            child: const Text('حظر', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    try {
      await _firebaseService.sendPrivateMessage(
        senderId: user.uid,
        senderName: user.name ?? '',
        senderPhotoUrl: user.photoUrl ?? '',
        receiverId: widget.otherUid,
        receiverName: widget.otherName,
        receiverPhotoUrl: widget.otherPhotoUrl,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;

    setState(() => _sendingImage = true);
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;
      if (user == null) return;

      final imageUrl = await CloudinaryService().uploadImage(
        File(image.path),
        publicId: 'chat_${DateTime.now().millisecondsSinceEpoch}',
      );

      await _firebaseService.sendPrivateMessage(
        senderId: user.uid,
        senderName: user.name ?? '',
        senderPhotoUrl: user.photoUrl ?? '',
        receiverId: widget.otherUid,
        receiverName: widget.otherName,
        receiverPhotoUrl: widget.otherPhotoUrl,
        text: '',
        imageUrl: imageUrl,
        type: 'image',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: R.image(R.backIc, width: 24, height: 24),
          ),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.otherPhotoUrl.isNotEmpty
                  ? R.cachedImage(widget.otherPhotoUrl)
                  : null,
              child: widget.otherPhotoUrl.isEmpty
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              widget.otherName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF16151A),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF16151A)),
            onSelected: (value) {
              if (value == 'report') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReportUserScreen(nickname: widget.otherName, avatar: widget.otherPhotoUrl, reportedUid: widget.otherUid)),
                );
              } else if (value == 'block') {
                _confirmBlockUser();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'report',
                child: Text('إبلاغ عن المستخدم'),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Text('حظر استلام رسائل (Block)'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: Color(0xFF9BA1B6)),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg.senderUid ==
                          Provider.of<UserProvider>(context, listen: false)
                              .currentUser
                              ?.uid;
                      return _buildMessageBubble(msg, isMe);
                    },
                  ),
          ),
          if (_sendingImage)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  msg.senderName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9BA1B6),
                  ),
                ),
              ),
            if (msg.type == 'image' && msg.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => _showImagePreview(msg.imageUrl!),
                  child: Image(
                    image: R.cachedImage(msg.imageUrl!),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 200,
                      color: Colors.white10,
                      child: const Icon(Icons.image, color: Colors.white24, size: 36),
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMe
                      ? const Color(0xFF1E90FF)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12).copyWith(
                    bottomRight: isMe ? const Radius.circular(0) : null,
                    bottomLeft: !isMe ? const Radius.circular(0) : null,
                  ),
                ),
                child: Text(
                  msg.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: isMe ? Colors.white : const Color(0xFF16151A),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatTime(msg.timestamp),
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF9BA1B6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE8E8E8), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F5FC),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.image, size: 20, color: Color(0xFF9BA1B6)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F5FC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _msgController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF1E90FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: Image(image: R.cachedImage(url), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
