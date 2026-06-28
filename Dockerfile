# syntax=docker/dockerfile:1
#
# docker-cc-switch
# 在浏览器里运行 cc-switch（Claude Code / Codex / Gemini CLI 配置切换器）。
#
# 基础镜像：LinuxServer.io baseimage-selkies (Debian Trixie / glibc / 多架构 amd64+arm64)
# 访问方式：浏览器打开 http://<host>:3000  （HTTPS 为 3001）
#
# 为什么用 selkies 而不是旧的 kasmvnc：selkies 是 LSIO 新一代浏览器桌面方案，
# 替代了已废弃的 baseimage-kasmvnc，性能/保真度更好。
# 为什么选 Debian Trixie 而不是 Alpine：cc-switch 是 Tauri(WebKit2GTK) 应用，
# 依赖 glibc；Alpine 用 musl，二进制不兼容 webkit2gtk，会有坑。

FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie

# cc-switch 版本号；升级时改这里即可
ARG CC_SWITCH_VERSION=3.16.4
# buildx 注入：amd64 / arm64。直接 docker build 时取本机架构作 fallback。
ARG TARGETARCH

LABEL maintainer="YellowOrz"
LABEL org.opencontainers.image.title="docker-cc-switch"
LABEL org.opencontainers.image.source="https://github.com/farion1231/cc-switch"
LABEL org.opencontainers.image.description="cc-switch (Claude Code/Codex/Gemini CLI 配置切换器) in browser via LinuxServer Selkies"
LABEL org.opencontainers.image.licenses="MIT"

# RUN 里用了管道，开启 pipefail，让管道任一环失败都停止构建（hadolint DL4006）
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---- selkies 运行期环境变量 ----
# 默认走 X11 模式（不设 PIXELFLUX_WAYLAND）：对 WebKit2GTK 软件渲染最稳；
# selkies 在 x86_64 上启用 Wayland 还要求 CPU 支持 AVX2，X11 无此限制。
# 若你的机器有 AVX2 且想要更好性能，可在 docker run 时加 -e PIXELFLUX_WAYLAND=true。
ENV TITLE="CC Switch" \
    NO_GAMEPAD="true" \
    RESTART_APP="true" \
    TZ=Asia/Shanghai \
    LC_ALL=zh_CN.UTF-8 \
    LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN.UTF-8 \
    FILE_MANAGER_PATH=/config

# ---- Step 1: 生成中文 locale ----
# hadolint ignore=DL3008
RUN \
  apt-get update && \
  apt-get install -y --no-install-recommends locales && \
  sed -i 's/^# *\(zh_CN.UTF-8[[:space:]]*UTF-8\)/\1/' /etc/locale.gen && \
  locale-gen zh_CN.UTF-8 && \
  apt-get clean && rm -rf /var/lib/apt/lists/* && \
# ---- Step 2: 安装 cc-switch 运行依赖 ----
# hadolint ignore=DL3008
  apt-get update && \
  apt-get install -y --no-install-recommends --fix-missing \
      libwebkit2gtk-4.1-0 \
      libgtk-3-0 \
      libayatana-appindicator3-1 \
      librsvg2-2 \
      libssl3 \
      ca-certificates \
      wget \
      fonts-wqy-microhei \
      stalonetray && \
  apt-get clean && rm -rf /var/lib/apt/lists/* && \

# ---- Step 3: 下载并安装 cc-switch .deb ----
  ARCH_SUFFIX="$( \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64) echo x86_64 ;; \
      arm64) echo arm64   ;; \
      *) echo "不支持的架构: ${TARGETARCH:-$(dpkg --print-architecture)}" >&2; exit 1 ;; \
    esac \
  )" && \
  DEB_URL="https://github.com/farion1231/cc-switch/releases/download/v${CC_SWITCH_VERSION}/CC-Switch-v${CC_SWITCH_VERSION}-Linux-${ARCH_SUFFIX}.deb" && \
  echo "下载: ${DEB_URL}" && \
  # GitHub release CDN 偶尔 302/502，最多重试 3 次
  for i in 1 2 3; do \
    wget --no-verbose --timeout=30 --tries=3 -O /tmp/cc-switch.deb "${DEB_URL}" && break; \
    echo "  下载失败 (尝试 ${i}/3)，等待 5 秒后重试..." && sleep 5; \
  done && \
  dpkg -i /tmp/cc-switch.deb || apt-get install -f -y --no-install-recommends && \
  rm -f /tmp/cc-switch.deb && \
  # 把应用图标设为 selkies 页面图标
  ICON="$(find /usr/share/icons/hicolor -type f -name 'cc-switch.png' 2>/dev/null | sort -rV | head -n1)" && \
  if [ -n "$ICON" ]; then cp -f "$ICON" /usr/share/selkies/www/icon.png; fi && \
# ---- Step 4: 清理构建依赖，减小镜像 ----
  apt-get purge -y wget && \
  apt-get autoremove -y && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
         /usr/share/doc/* /usr/share/man/* /usr/share/info/* \
         /var/cache/debconf/*-old

# 覆盖 selkies rootfs：自启脚本 + Openbox 右键菜单
COPY root/ /

# cc-switch 的数据库/设置/备份都在 ~/.cc-switch (=容器内 /config/.cc-switch)，随此卷持久化
VOLUME /config

# selkies：3000=HTTP(浏览器), 3001=HTTPS(浏览器), 3000 端口同时承载 WebSocket
EXPOSE 3000 3001

# 不覆盖 CMD/ENTRYPOINT：由 selkies base 的 s6-overlay 负责拉起桌面/VNC/Web 服务
