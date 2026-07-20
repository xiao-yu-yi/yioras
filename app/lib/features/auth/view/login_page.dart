import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../controller/auth_controller.dart';
import '../data/auth_api.dart';

/// 邮箱登录页（v1.1：仅邮箱一种登录方式），内置「登录 / 注册」双模式切换。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

enum _AuthMode { login, register }

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _nicknameController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _submitting = false;
  bool _obscurePassword = true;

  /// 服务端返回的业务错误（展示在提交按钮上方）
  String? _serverError;

  /// 验证码倒计时剩余秒数，0 表示可发送
  int _codeCountdown = 0;
  bool _sendingCode = false;
  Timer? _countdownTimer;

  static final _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (_submitting || _mode == mode) return;
    setState(() {
      _mode = mode;
      _serverError = null;
      // 切换模式后重置校验痕迹，避免另一模式的错误文案残留
      _formKey.currentState?.reset();
    });
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _serverError = '请先填写正确的邮箱，再获取验证码');
      return;
    }
    setState(() {
      _sendingCode = true;
      _serverError = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .sendEmailCode(email: email, scene: EmailCodeScene.register);
      if (!mounted) return;
      setState(() => _codeCountdown = 60);
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _codeCountdown -= 1);
        if (_codeCountdown <= 0) timer.cancel();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证码已发送，请查收邮箱')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _serverError = e.message);
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _serverError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    final auth = ref.read(authControllerProvider.notifier);
    try {
      if (_mode == _AuthMode.login) {
        await auth.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await auth.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          code: _codeController.text.trim(),
          nickname: _nicknameController.text.trim(),
        );
      }
      // 成功后登录态变化由路由 redirect 自动跳转首页，页面无需导航
    } on ApiException catch (e) {
      if (mounted) setState(() => _serverError = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRegister = _mode == _AuthMode.register;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      'Yiora',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '兴趣圈子 · 有趣灵魂的聚集地',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SegmentedButton<_AuthMode>(
                      segments: const [
                        ButtonSegment(
                          value: _AuthMode.login,
                          label: Text('登录'),
                        ),
                        ButtonSegment(
                          value: _AuthMode.register,
                          label: Text('注册'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (selection) =>
                          _switchMode(selection.first),
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      enabled: !_submitting,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        hintText: '邮箱',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return '请输入邮箱';
                        if (!_emailRegex.hasMatch(email)) return '邮箱格式不正确';
                        return null;
                      },
                    ),
                    if (isRegister) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _codeController,
                        enabled: !_submitting,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        maxLength: 6,
                        decoration: InputDecoration(
                          hintText: '邮箱验证码',
                          counterText: '',
                          prefixIcon: const Icon(Icons.verified_outlined),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: TextButton(
                              onPressed: (_codeCountdown > 0 || _sendingCode)
                                  ? null
                                  : _sendCode,
                              child: _sendingCode
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _codeCountdown > 0
                                          ? '${_codeCountdown}s'
                                          : '获取验证码',
                                    ),
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (!isRegister) return null;
                          final code = value?.trim() ?? '';
                          if (code.isEmpty) return '请输入验证码';
                          if (code.length < 4) return '验证码格式不正确';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nicknameController,
                        enabled: !_submitting,
                        textInputAction: TextInputAction.next,
                        maxLength: 30,
                        decoration: const InputDecoration(
                          hintText: '昵称',
                          counterText: '',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (!isRegister) return null;
                          final nickname = value?.trim() ?? '';
                          if (nickname.isEmpty) return '请输入昵称';
                          if (nickname.length < 2) return '昵称至少 2 个字符';
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_submitting,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: isRegister ? '设置密码（至少 8 位）' : '密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final password = value ?? '';
                        if (password.isEmpty) return '请输入密码';
                        if (isRegister && password.length < 8) {
                          return '密码至少 8 位';
                        }
                        return null;
                      },
                    ),
                    if (_serverError != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 18,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _serverError!,
                                style: TextStyle(
                                  color: scheme.error,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(isRegister ? '注册并登录' : '登录'),
                    ),
                    const SizedBox(height: 12),
                    if (!isRegister)
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('找回密码将在后续版本开放')),
                              ),
                        child: const Text('忘记密码？'),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '注册即代表同意《用户协议》与《隐私政策》',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
