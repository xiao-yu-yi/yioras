/// 当前登录用户（对应 /users/me 与登录响应中的 user 字段）。
class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayNo,
    required this.nickname,
    this.email = '',
    this.avatar = '',
    this.signature = '',
    this.level = 0,
  });

  final int id;

  /// 展示编号（靓号 ID，如 N101215）
  final String displayNo;
  final String nickname;
  final String email;
  final String avatar;
  final String signature;
  final int level;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: (json['id'] as num).toInt(),
    displayNo: json['displayNo'] as String? ?? '',
    nickname: json['nickname'] as String? ?? '',
    email: json['email'] as String? ?? '',
    avatar: json['avatar'] as String? ?? '',
    signature: json['signature'] as String? ?? '',
    level: (json['level'] as num?)?.toInt() ?? 0,
  );

  AuthUser copyWith({String? nickname, String? avatar, String? signature}) =>
      AuthUser(
        id: id,
        displayNo: displayNo,
        nickname: nickname ?? this.nickname,
        email: email,
        avatar: avatar ?? this.avatar,
        signature: signature ?? this.signature,
        level: level,
      );
}
