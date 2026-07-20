# demo-reset: restore the admin console demo state on a running compose stack.
#   - admin account back to initial credentials (admin / admin123, forced password change)
#   - TOTP unbound, recovery codes cleared, login-fail lockout cleared, stale tickets cleared
#   - business data (posts/users/audits) is left untouched; run smoke.ps1 first if the DB is empty
# usage: powershell -ExecutionPolicy Bypass -File .\scripts\demo-reset.ps1

$ErrorActionPreference = 'Stop'

# 1. stack must be up
$api = docker ps --filter "name=yiora-api-1" --format "{{.Names}}"
if (-not $api) {
    Write-Output "stack is not running. start it first:"
    Write-Output "  cd server; docker compose up -d --build"
    Write-Output "  (fresh volume? run scripts\smoke.ps1 once to seed demo data)"
    exit 1
}

# 2. reset the initial admin account (bcrypt of 'admin123', same hash as 008 seed)
$sql = @(
    "UPDATE admin_user SET password_hash='`$2a`$10`$ZhCQV.pW8YeGEoDGbNHrWujUGjBYHxKunSD70uW0B7LbutEjed7vK', must_change_pwd=1, totp_secret='', totp_enabled=0 WHERE username='admin';",
    "DELETE FROM admin_recovery_code WHERE admin_id = (SELECT id FROM (SELECT id FROM admin_user WHERE username='admin') t);"
) -join ' '
# mysql prints a password warning to stderr; don't let EAP=Stop turn it into a failure
$ErrorActionPreference = 'Continue'
docker exec yiora-mysql-1 mysql -uroot -proot123 yiora -e $sql 2>$null
if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = 'Stop'; throw "mysql reset failed" }

# 3. clear redis side-state: lockout counters, totp tickets/pending, stale captchas
$keys = docker exec yiora-redis-1 redis-cli --scan --pattern "admin:*" 2>$null
if ($keys) { $keys | ForEach-Object { docker exec yiora-redis-1 redis-cli DEL $_ | Out-Null } }

# 4. verify
$row = docker exec yiora-mysql-1 mysql -uroot -proot123 yiora -N -e "SELECT username, must_change_pwd, totp_enabled FROM admin_user WHERE username='admin';" 2>$null
$ErrorActionPreference = 'Stop'
Write-Output "admin state: $row (expect: admin 1 0)"
Write-Output ""
Write-Output "demo ready ->"
Write-Output "  console  : http://localhost:5173   (cd admin-web; npm run dev)"
Write-Output "  account  : admin / admin123        (captcha required; forced password change on first login)"
Write-Output "  minio ui : http://localhost:9001   (yiora-minio / yiora-minio-secret)"
Write-Output "  suggested tour: change password -> Security page bind TOTP -> Banner upload widget -> MinIO bucket"
Write-Output "DEMO_RESET_DONE"
