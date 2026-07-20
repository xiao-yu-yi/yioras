import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/ws/ws_providers.dart';
import '../../messages/model/message_models.dart';
import '../controller/chat_controller.dart';
import '../model/chat_message.dart';

/// 私信聊天页（文档 3.7）：文本气泡 + 发送状态 + 失败重发。
/// 撤回/已读回执/图片与分享卡片消息随 M2 后续迭代。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.conversationId});

  final int conversationId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 进入会话即消费未读角标（骨架期粗粒度）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final peer = ref
          .read(chatControllerProvider(widget.conversationId))
          .value
          ?.peer;
      if (peer != null && peer.unread > 0) {
        ref.read(conversationBadgeProvider.notifier).consume(peer.unread);
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatControllerProvider(widget.conversationId).notifier).send(text);
    _inputController.clear();
    // 滚到底部看最新消息（reverse 列表 0 即底部）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider(widget.conversationId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: switch (chat) {
          AsyncData(:final value) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value.peer.peerName),
              if (value.peer.isBot) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '官方机器人',
                    style: TextStyle(fontSize: 10, color: scheme.primary),
                  ),
                ),
              ],
            ],
          ),
          _ => const Text('聊天'),
        },
      ),
      body: switch (chat) {
        AsyncData(:final value) => Column(
          children: [
            Expanded(
              child: _MessageList(
                state: value,
                controller: _scrollController,
                onResend: (localId) => ref
                    .read(
                      chatControllerProvider(widget.conversationId).notifier,
                    )
                    .resend(localId),
              ),
            ),
            _InputBar(controller: _inputController, onSend: _send),
          ],
        ),
        AsyncError(:final error) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                error is ApiException ? error.message : '加载失败，请稍后重试',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref
                    .read(
                      chatControllerProvider(widget.conversationId).notifier,
                    )
                    .retryFirstLoad(),
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.state,
    required this.controller,
    required this.onResend,
  });

  final ChatState state;
  final ScrollController controller;
  final void Function(String localId) onResend;

  @override
  Widget build(BuildContext context) {
    if (state.messages.isEmpty) {
      return const Center(child: Text('打个招呼开始聊天吧'));
    }
    // reverse 列表：index 0 为最新消息
    final reversed = state.messages.reversed.toList();
    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: reversed.length,
      itemBuilder: (context, index) {
        final message = reversed[index];
        final previous = index + 1 < reversed.length
            ? reversed[index + 1]
            : null;
        // 与上一条间隔超 5 分钟展示时间条
        final showTime =
            previous == null ||
            message.createdAt.difference(previous.createdAt).inMinutes >= 5;
        return Column(
          children: [
            if (showTime)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  formatRelativeTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            _Bubble(
              key: ValueKey(message.localId),
              message: message,
              peer: state.peer,
              onResend: onResend,
            ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.peer,
    required this.onResend,
  });

  final ChatMessage message;
  final ConversationSummary peer;
  final void Function(String localId) onResend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.mine;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? scheme.primary : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 3),
          bottomRight: Radius.circular(mine ? 3 : 14),
        ),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          fontSize: 15,
          height: 1.45,
          color: mine ? Colors.white : scheme.onSurface,
        ),
      ),
    );

    // 自己消息左侧的状态指示
    final Widget? statusWidget = switch (message.status) {
      ChatSendStatus.sending => const Padding(
        padding: EdgeInsets.only(right: 6),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.8),
        ),
      ),
      ChatSendStatus.failed => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => onResend(message.localId),
          child: Icon(Icons.error, size: 18, color: scheme.error),
        ),
      ),
      ChatSendStatus.sent => null,
    };

    final avatar = CircleAvatar(
      radius: 17,
      backgroundColor: mine
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      foregroundImage: (!mine && peer.peerAvatar.isNotEmpty)
          ? CachedNetworkImageProvider(peer.peerAvatar)
          : null,
      child: mine
          ? Icon(Icons.person, size: 18, color: scheme.primary)
          : (peer.isBot
                ? Icon(
                    Icons.smart_toy_outlined,
                    size: 18,
                    color: scheme.primary,
                  )
                : Text(
                    peer.peerName.isEmpty
                        ? '?'
                        : peer.peerName.characters.first,
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  )),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: mine
            ? [?statusWidget, bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: 500,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: '文明交流，理性发言…',
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
