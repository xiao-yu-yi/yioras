// Package xerr 业务错误码。响应包 code 含义见 docs/Yiora开发需求文档.md 4.3-8。
package xerr

import "fmt"

const (
	CodeOK             = 0
	CodeInvalidParam   = 40000 // 参数错误
	CodeUnauthorized   = 40100 // 未登录/Token失效
	CodeForbidden      = 40300 // 无权限
	CodeNotFound       = 40400 // 资源不存在
	CodeTooFrequent    = 42900 // 触发频控
	CodeContentBlocked = 42200 // 内容命中违禁词
	CodeEmailTaken     = 41001 // 邮箱已注册
	CodeBadCode        = 41002 // 验证码错误或过期
	CodeBadCredential  = 41003 // 邮箱或密码错误
	CodeServer         = 50000 // 服务器内部错误
)

type BizError struct {
	Code int
	Msg  string
}

func (e *BizError) Error() string { return fmt.Sprintf("biz %d: %s", e.Code, e.Msg) }

func New(code int, msg string) *BizError { return &BizError{Code: code, Msg: msg} }

func Param(msg string) *BizError { return New(CodeInvalidParam, msg) }
