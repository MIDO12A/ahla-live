import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_service.dart';
import '../../providers/user_provider.dart';
import '../../services/room_state_service.dart';
import '../../screens/room/room_screen.dart' show navigateToRoom;

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final TextEditingController _introduceController = TextEditingController();
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _pwdController = TextEditingController();
  final SupabaseService _firebaseService = SupabaseService();
  bool _isLoading = false;

  int _selectedType = 0;
  int _currentStep = 1;
  bool _isLocked = false;

  // Room photo
  String? _roomPhotoLocalPath;
  String? _roomPhotoUrl;
  bool _isUploadingPhoto = false;

  final List<String> _roomTypes = [
    'Music',
    'Party',
    'Hobby',
    'Games',
    'Social',
    'Chat',
  ];

  final List<String> _roomTypeIcons = [
    'assets/mipmap-xxhdpi/discover_music_ic.webp',
    'assets/mipmap-xxhdpi/discover_room_party_ic.webp',
    'assets/mipmap-xxhdpi/discover_room_hobby_ic.webp',
    'assets/mipmap-xxhdpi/discover_game_teaming_ic.webp',
    'assets/mipmap-xxhdpi/discover_room_social_share_ic.webp',
    'assets/mipmap-xxhdpi/discover_room_chat_ic.webp',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkExistingRoom());
  }

  Future<RoomModel?> _findUserExistingRoom(UserModel user) async {
    final targetRoomId = user.hostedRoomId;
    if (targetRoomId != null && targetRoomId.isNotEmpty && targetRoomId != 'null') {
      final candidate = await _firebaseService.getRoom(targetRoomId);
      if (candidate != null && (candidate.hostUid == user.uid || (user.customId.isNotEmpty && candidate.hostUid == user.customId))) {
        return candidate;
      }
    }
    final candidateUid = await _firebaseService.getRoomByHost(user.uid);
    if (candidateUid != null && (candidateUid.hostUid == user.uid || (user.customId.isNotEmpty && candidateUid.hostUid == user.customId))) {
      return candidateUid;
    }
    if (user.customId.isNotEmpty) {
      final candidateCustom = await _firebaseService.getRoomByHost(user.customId) ?? await _firebaseService.getRoom(user.customId);
      if (candidateCustom != null && (candidateCustom.hostUid == user.uid || candidateCustom.hostUid == user.customId)) {
        return candidateCustom;
      }
    }
    try {
      final sbRoom = await SupabaseDataService().getRoomByHostUid(user.uid) ??
          (user.customId.isNotEmpty ? await SupabaseDataService().getRoomByHostUid(user.customId) : null);
      if (sbRoom != null) return sbRoom;
    } catch (_) {}
    return null;
  }

  Future<void> _checkExistingRoom() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    final existingRoom = await _findUserExistingRoom(user);
    if (existingRoom != null && mounted) {
      final minSvc = MinimizedRoomService();
      if (minSvc.isActive && minSvc.roomId != existingRoom.roomId) {
        await minSvc.exitRoom(user.uid);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لديك غرفة مفعلة بالفعل، جاري نقلك إليها...'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      String targetRoomId = existingRoom.roomId;
      if (user.customId.isNotEmpty && existingRoom.roomId != user.customId) {
        await _firebaseService.migrateUserRoomId(user.uid, user.customId);
        targetRoomId = user.customId;
      } else {
        await _firebaseService.updateUser(user.uid, {'hosted_room_id': existingRoom.roomId});
      }
      await userProvider.loadUser(user.uid);
      if (mounted) {
        navigateToRoom(
          context,
          roomName: existingRoom.name,
          hostName: user.name,
          hostUid: existingRoom.hostUid,
          roomId: targetRoomId,
          replace: true,
        );
      }
    }
  }

  @override
  void dispose() {
    _introduceController.dispose();
    _roomNameController.dispose();
    _topicController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (_roomNameController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a room name')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not found')),
          );
        }
        return;
      }

      // Pre-check: if user already has an active room, go to it instead of recreating
      final existing = await _findUserExistingRoom(user);
      if (existing != null) {
        final minSvc = MinimizedRoomService();
        if (minSvc.isActive && minSvc.roomId != existing.roomId) {
          await minSvc.exitRoom(user.uid);
        }
        String targetRoomId = existing.roomId;
        if (user.customId.isNotEmpty && existing.roomId != user.customId) {
          await _firebaseService.migrateUserRoomId(user.uid, user.customId);
          targetRoomId = user.customId;
        } else {
          await _firebaseService.updateUser(user.uid, {'hosted_room_id': existing.roomId});
        }
        await userProvider.loadUser(user.uid);
        if (mounted) {
          navigateToRoom(
            context,
            roomName: existing.name,
            hostName: user.name,
            hostUid: existing.hostUid,
            roomId: targetRoomId,
            replace: true,
          );
        }
        return;
      }

      // Exit any active/minimized room the user was visiting
      final minSvc = MinimizedRoomService();
      if (minSvc.isActive) {
        await minSvc.exitRoom(user.uid);
      }

      final roomId = await _firebaseService.createRoom(
        name: _roomNameController.text.trim(),
        description: _introduceController.text.trim(),
        roomPhotoUrl: _roomPhotoUrl ?? '',
        hostUid: user.uid,
        hostCustomId: user.customId,
        hostName: user.name,
        hostPhotoUrl: user.photoUrl,
        isLocked: _isLocked,
        password: _pwdController.text.trim(),
        category: _roomTypes[_selectedType],
        country: user.country.isNotEmpty ? user.country : 'EG',
      );

      // Save hostedRoomId to user in Firebase
      await _firebaseService.updateUser(user.uid, {
        'hosted_room_id': roomId,
      });

      // Reload user data so UserProvider reflects the new room
      await userProvider.loadUser(user.uid);

      // Navigate to the room
      if (mounted) {
        navigateToRoom(
          context,
          roomName: _roomNameController.text.trim(),
          hostName: user.name,
          hostUid: user.uid,
          roomId: roomId,
          roomPassword: _pwdController.text.trim(),
          replace: true,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickRoomImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;
    setState(() {
      _roomPhotoLocalPath = image.path;
      _isUploadingPhoto = true;
    });
    try {
      final url = await CloudinaryService().uploadImage(File(image.path));
      if (mounted) setState(() => _roomPhotoUrl = url);
    } catch (e) {
      debugPrint('Error uploading room image: $e');
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [],
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Header
                      Stack(
                        children: [
                          Image.asset(
                            'assets/mipmap-xxhdpi/room_create_room_bg.webp',
                            width: double.infinity,
                            fit: BoxFit.fill,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 50, left: 16, right: 16),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    if (_currentStep == 2) {
                                      setState(() {
                                        _currentStep = 1;
                                      });
                                    } else {
                                      Navigator.pop(context);
                                    }
                                  },
                                  child: Image.asset(
                                    'assets/mipmap-xxhdpi/back_ic.webp',
                                    width: 28,
                                    height: 28,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  children: [
                                    Image.asset(
                                      'assets/mipmap-xxhdpi/room_create_label_ic.webp',
                                      width: 20,
                                      height: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Create Room',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF16151A),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_currentStep == 1) ...[
                        // Step 1: Choose Theme
                        const SizedBox(height: 27),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Choose Theme',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF16151A),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Room Type List
                        SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _roomTypes.length,
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedType = index;
                                  });
                                },
                                child: Container(
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedType == index
                                          ? const Color(0xFFFF9800)
                                          : Colors.grey.shade300,
                                      width: _selectedType == index ? 2 : 1,
                                    ),
                                    color: Colors.white,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Image.asset(
                                        _roomTypeIcons[index],
                                        width: 44,
                                        height: 44,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _roomTypes[index],
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF16151A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 35),
                        // Room Introduction
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Room Introduction',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF16151A),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Introduction Input
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                TextField(
                                  controller: _introduceController,
                                  maxLines: 3,
                                  maxLength: 40,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF16151A),
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Tell others about your room',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF9BA1B6),
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 16),
                                  ),
                                ),
                                Positioned(
                                  right: 12,
                                  bottom: 8,
                                  child: Text(
                                    '${_introduceController.text.length}/40',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9BA1B6),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      _introduceController.clear();
                                      setState(() {});
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Image.asset(
                                        'assets/mipmap-xxhdpi/room_create_hobby_refresh_ic.webp',
                                        width: 24,
                                        height: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        // Step 2: Room Details
                        const SizedBox(height: 16),
                        // Room Photo
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: _pickRoomImage,
                              child: Container(
                                width: 108,
                                height: 108,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    children: [
                                      if (_roomPhotoLocalPath != null)
                                        Image.file(
                                          File(_roomPhotoLocalPath!),
                                          width: 108,
                                          height: 108,
                                          fit: BoxFit.cover,
                                        )
                                      else
                                        Center(
                                          child: Image.asset(
                                            'assets/mipmap-xxhdpi/common_camera_ic.webp',
                                            width: 40,
                                            height: 40,
                                          ),
                                        ),
                                      if (_isUploadingPhoto)
                                        Container(
                                          color: Colors.black38,
                                          child: const Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Room Name
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Room Name',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF16151A),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                TextField(
                                  controller: _roomNameController,
                                  maxLength: 20,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF16151A),
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Enter room name',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF9BA1B6),
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 16),
                                  ),
                                ),
                                Positioned(
                                  right: 16,
                                  bottom: 8,
                                  child: Text(
                                    '${_roomNameController.text.length}/20',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9BA1B6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Topic
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Room Topic',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF16151A),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                TextField(
                                  controller: _topicController,
                                  maxLines: 3,
                                  maxLength: 100,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF16151A),
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Enter room topic',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF9BA1B6),
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 16),
                                  ),
                                ),
                                Positioned(
                                  right: 16,
                                  bottom: 8,
                                  child: Text(
                                    '${_topicController.text.length}/100',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9BA1B6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Lock room
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Lock Room',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF16151A),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _pwdController,
                                    enabled: _isLocked,
                                    maxLength: 6,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => setState(() {}),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF16151A),
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Enter 6-digit password',
                                      hintStyle: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF9BA1B6),
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                          vertical: 16),
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: _isLocked,
                                  onChanged: (value) {
                                    setState(() {
                                      _isLocked = value;
                                    });
                                  },
                                  activeColor: const Color(0xFFFF9800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Confirm Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: GestureDetector(
                onTap: () {
                  if (_currentStep == 1) {
                    setState(() {
                      _currentStep = 2;
                    });
                  } else {
                    _createRoom();
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Center(
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _currentStep == 1 ? 'Next' : 'Create Room',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
