import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../../../services/dynamic_config_service.dart';

class BottomBar extends StatelessWidget {
  final bool isMicOn;
  final bool showMic;
  final int msgCount;
  final VoidCallback? onChat;
  final VoidCallback? onEmoj;
  final VoidCallback? onMic;
  final VoidCallback? onGift;
  final VoidCallback? onMusic;
  final VoidCallback? onMsg;
  final VoidCallback? onFunction;

  const BottomBar({
    super.key,
    this.isMicOn = true,
    this.showMic = true,
    this.msgCount = 0,
    this.onChat,
    this.onEmoj,
    this.onMic,
    this.onGift,
    this.onMusic,
    this.onMsg,
    this.onFunction,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final cfg = DynamicConfigService.instance;
    final giftIcon = cfg.roomGiftIcon.isNotEmpty ? cfg.roomGiftIcon : R.roomGiftIc;
    final chatIcon = cfg.roomChatIcon.isNotEmpty ? cfg.roomChatIcon : R.roomChatIc;
    final emojiIcon = cfg.roomEmojiIcon.isNotEmpty ? cfg.roomEmojiIcon : R.roomEmojIc;
    final micOnIcon = cfg.roomMicOnIcon.isNotEmpty ? cfg.roomMicOnIcon : R.roomMicphoneIc;
    final micOffIcon = cfg.roomMicOffIcon.isNotEmpty ? cfg.roomMicOffIcon : R.roomMicphoneCloseIc;
    final musicIcon = cfg.roomMusicIcon.isNotEmpty ? cfg.roomMusicIcon : R.roomSetMusicIc;
    final msgIcon = cfg.roomMsgIcon.isNotEmpty ? cfg.roomMsgIcon : R.roomMsgIc;
    final functionIcon = cfg.roomFunctionIcon.isNotEmpty ? cfg.roomFunctionIcon : R.roomFunctionIc;

    return SizedBox(
      height: 63,
      child: Stack(
        children: [
          // iv_gift: Centered gift button
          Positioned(
            left: 0,
            right: 0,
            bottom: 15,
            child: Center(
              child: GestureDetector(
                onTap: onGift,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: R.loadAsset(
                    giftIcon,
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          // Action Group 1 (chat, emoj, mic): Left in LTR, Right in RTL
          Positioned(
            left: isAr ? null : 0,
            right: isAr ? 0 : null,
            bottom: 15,
            child: SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: isAr
                    ? [
                        if (showMic) ...[
                          _Btn(
                            asset: isMicOn ? micOnIcon : micOffIcon,
                            size: 32,
                            onTap: onMic,
                          ),
                          const SizedBox(width: 10),
                        ],
                        _Btn(asset: emojiIcon, size: 32, onTap: onEmoj),
                        const SizedBox(width: 10),
                        _Btn(asset: chatIcon, size: 32, onTap: onChat),
                        const SizedBox(width: 14),
                      ]
                    : [
                        const SizedBox(width: 14),
                        _Btn(asset: chatIcon, size: 32, onTap: onChat),
                        const SizedBox(width: 10),
                        _Btn(asset: emojiIcon, size: 32, onTap: onEmoj),
                        if (showMic) ...[
                          const SizedBox(width: 10),
                          _Btn(
                            asset: isMicOn ? micOnIcon : micOffIcon,
                            size: 32,
                            onTap: onMic,
                          ),
                        ],
                      ],
              ),
            ),
          ),

          // Action Group 2 (music, msg, function): Right in LTR, Left in RTL
          Positioned(
            left: isAr ? 0 : null,
            right: isAr ? null : 0,
            bottom: 15,
            child: SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: isAr
                    ? [
                        const SizedBox(width: 14),
                        _Btn(asset: functionIcon, size: 32, onTap: onFunction),
                        const SizedBox(width: 10),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _Btn(asset: msgIcon, size: 32, onTap: onMsg),
                            if (msgCount > 0)
                              Positioned(
                                top: -4,
                                right: 18,
                                child: _buildBadge(),
                              ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        _Btn(asset: musicIcon, size: 32, onTap: onMusic),
                      ]
                    : [
                        _Btn(asset: musicIcon, size: 32, onTap: onMusic),
                        const SizedBox(width: 10),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _Btn(asset: msgIcon, size: 32, onTap: onMsg),
                            if (msgCount > 0)
                              Positioned(
                                top: -4,
                                left: 18,
                                child: _buildBadge(),
                              ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        _Btn(asset: functionIcon, size: 32, onTap: onFunction),
                        const SizedBox(width: 14),
                      ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 17,
        minHeight: 10,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE82323),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$msgCount',
        style: const TextStyle(
          fontSize: 9,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String asset;
  final double size;
  final VoidCallback? onTap;
  const _Btn({required this.asset, required this.size, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: R.loadAsset(
        asset,
        width: size,
        height: size,
      ),
    );
  }
}
