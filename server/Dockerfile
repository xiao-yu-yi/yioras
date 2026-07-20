# 多阶段构建:一次构建产出 api 与 ws 两个二进制,compose 里用 command 区分入口
# 注:不写 syntax 指令,避免离线/受限网络下拉取 dockerfile frontend 镜像失败

FROM golang:1.26-alpine AS builder
# 国内网络可用 --build-arg GOPROXY=https://goproxy.cn,direct 加速
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY} CGO_ENABLED=0

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -trimpath -ldflags="-s -w" -o /out/yiora-api ./cmd/api \
    && go build -trimpath -ldflags="-s -w" -o /out/yiora-ws ./cmd/ws

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 yiora
ENV TZ=Asia/Shanghai
WORKDIR /app
COPY --from=builder /out/yiora-api /out/yiora-ws /app/
COPY etc /app/etc
USER yiora
# 默认起 api;ws 容器在 compose 里覆盖 command
CMD ["/app/yiora-api", "-f", "etc/docker/yiora-api.yaml"]
