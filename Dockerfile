# 使用Go 1.24镜像以匹配go.mod中的版本
FROM golang:1.24 AS builder

# 安装必要的构建工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 先复制go模块文件，利用Docker缓存
COPY go.mod go.sum ./
RUN GOPROXY=https://goproxy.cn go mod download

# 复制所有源代码
COPY . .

# 设置构建参数以避免git依赖
ARG VERSION=1.0.0
ARG COMMIT=render-build
ARG BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 构建应用
# 方式1：使用make（如果修复了Makefile）
# RUN GOPROXY=https://goproxy.cn VERSION=${VERSION} COMMIT=${COMMIT} make build

# 方式2：直接使用go build（推荐，更稳定）
RUN CGO_ENABLED=0 GOOS=linux go build -o ./bin/server ./cmd/init


# 最终运行镜像
FROM debian:stable-slim

# 安装运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    netbase \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get autoremove -y && apt-get autoclean -y

# 创建非root用户（Render安全最佳实践）
RUN groupadd -r appuser && useradd -r -g appuser appuser

# 创建应用目录
WORKDIR /app

# 从构建阶段复制二进制文件
COPY --from=builder --chown=appuser:appuser /src/bin/server /app/server

# 复制配置文件（如果需要）
COPY --from=builder --chown=appuser:appuser /src/configs /app/configs

# 切换为非root用户
USER appuser

# 健康检查（Render会自动使用）
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT:-8000}/health || exit 1

# 暴露端口（Render会动态分配端口，通过PORT环境变量传递）
EXPOSE ${PORT:-8000}
# 如果应用需要第二个端口
EXPOSE 9000

VOLUME /data/conf

CMD ["./server", "-conf", "/data/conf"]
