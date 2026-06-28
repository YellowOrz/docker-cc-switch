# docker-cc-switch

在浏览器中运行 [cc-switch](https://github.com/farion1231/cc-switch)（Claude Code / Codex / Gemini CLI 一站式配置切换器），无需在宿主机安装任何 GUI 依赖。

[![GitHub Actions](https://img.shields.io/github/actions/workflow/status/YellowOrz/docker-cc-switch/docker.yml?label=build)](https://github.com/YellowOrz/docker-cc-switch/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Docker%20Hub-blue?logo=docker)](https://hub.docker.com/r/orz2333/docker-cc-switch)

## 特性

- **浏览器访问** — 打开 `http://<IP>:3000` 即可使用，完整 GUI 体验
- **多架构支持** — 同时提供 `amd64` 和 `arm64` 镜像，x86 服务器和 ARM NAS 均可运行
- **开箱即用** — 基于 [LinuxServer.io baseimage-selkies](https://docs.linuxserver.io/images/docker-baseimage-selkies/)，s6-overlay 自动管理进程
- **数据持久化** — 挂载 `/config` 即可保留所有配置、数据库和 Skills

## 快速开始

### 方式 A：使用预构建镜像（推荐）

```bash
docker run -d \
  --name cc-switch \
  -p 3000:3000 -p 3001:3001 \
  -v ./config:/config \
  -e PASSWORD=changeme \
  --shm-size=1gb \
  --restart unless-stopped \
  orz2333/docker-cc-switch:latest
```

浏览器打开 `http://localhost:3000`，输入密码即可。

### 方式 B：Docker Compose

```bash
git clone https://github.com/YellowOrz/docker-cc-switch.git
cd docker-cc-switch
docker compose up -d
```

### 方式 C：本地构建

```bash
git clone https://github.com/YellowOrz/docker-cc-switch.git
cd docker-cc-switch

# Docker Compose
docker compose up -d --build

# 或纯 Docker
docker build -t docker-cc-switch .
docker run -d --name cc-switch -p 3000:3000 -p 3001:3001 \
  -v ./config:/config --shm-size=1gb docker-cc-switch
```

> 本地构建默认只生成当前架构的镜像。如需跨架构构建，参见下方「多架构构建」。

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PASSWORD` | _(空，无密码)_ | 浏览器访问密码，**生产环境务必设置** |
| `PUID` / `PGID` | `1000` | 容器内用户 UID/GID，建议与宿主机对齐以避免权限问题 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `LC_ALL` | `zh_CN.UTF-8` | 系统语言，影响 cc-switch UI 显示 |
| `TITLE` | `CC Switch` | 浏览器标签页标题 |
| `NO_GAMEPAD` | `true` | 禁用手柄输入注入 |
| `RESTART_APP` | `true` | cc-switch 关闭后自动重启，设为 `false` 可禁用 |
| `PIXELFLUX_WAYLAND` | _(未设置，默认 X11)_ | 设为 `true` 切换 Wayland 模式（x86_64 需 CPU 支持 AVX2） |
| `CUSTOM_PORT` | `3000` | HTTP 端口 |
| `CUSTOM_HTTPS_PORT` | `3001` | HTTPS 端口 |

## 数据与配置

容器内 home 目录为 `/config`（LSIO 的 abc 用户）。所有 cc-switch 数据均存储在此：

| 内容 | 容器内路径 |
|---|---|
| cc-switch 数据库/设置/备份/Skills | `/config/.cc-switch/` |
| Claude Code 配置 | `/config/.claude`、`/config/.claude.json` |
| Codex 配置 | `/config/.codex` |
| Gemini 配置 | `/config/.gemini` |

### 挂载本机配置

默认情况下 cc-switch 管理的是容器内的配置副本。如需直接管理宿主机的 Claude/Codex 配置，在 `docker-compose.yml` 中取消注释对应挂载行：

```yaml
volumes:
  - ./config:/config
  - ${HOME}/.claude:/config/.claude
  - ${HOME}/.codex:/config/.codex
  - ${HOME}/.gemini:/config/.gemini
```

## 多架构构建

> **⚠️ 未测试** — 以下多架构构建流程尚未实际验证，仅供参考。

本项目使用 Docker Buildx + QEMU 同时构建 `linux/amd64` 和 `linux/arm64`。

### CI 自动构建

推送到 GitHub 后，GitHub Actions 会自动构建多架构镜像并发布到 Docker Hub。

### 手动构建

```bash
docker buildx create --use --name multiarch
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <your-username>/docker-cc-switch:latest \
  --push .
```

## 技术原理

```
cc-switch (Tauri/WebKit2GTK)
    ↓ 渲染到
虚拟显示 (Xvfb / X11)
    ↓ 帧捕获 + 编码
Selkies 视频流 (WebSocket)
    ↓
浏览器前端 (HTML/JS/Canvas)
```

基础镜像 [LinuxServer.io baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies) 提供了完整的虚拟显示 → Web 流式传输管线，性能优于传统 VNC (noVNC) 方案。

## 升级 cc-switch

通过 `--build-arg` 指定版本号，无需修改任何文件：

```bash
docker build --build-arg CC_SWITCH_VERSION=3.17.0 -t docker-cc-switch .
```

不传此参数时使用 `Dockerfile` 中的默认值。Release 资产命名规律：`CC-Switch-v<版本>-Linux-<x86_64|arm64>.deb`

## 常见问题

**浏览器打开是黑屏/白屏？**
确认已设置 `--shm-size=1gb`（WebKit 渲染需要较大共享内存）。若仍未出现窗口，右键桌面 → CC Switch。

**中文显示成方块？**
镜像已内置 `fonts-wqy-zenhei`。若仍异常，确认 `LC_ALL=zh_CN.UTF-8`。

**构建 arm64 很慢？**
在 x86 上通过 QEMU 模拟构建 arm64 确实较慢（webkit2gtk 编译量大），属正常现象。建议使用 GitHub Actions 构建。

**镜像体积较大？**
selkies 基础镜像 + webkit2gtk 决定了镜像约 800MB–1GB。如需更小体积，可考虑改用 `jlesage/baseimage-gui`（noVNC 方案，约小一半），详见 [`docs/SELECTION.md`](docs/SELECTION.md)。

## 选型文档

完整的选型分析（base image 对比、厂商方案评估、多架构构建原理）见 [`docs/SELECTION.md`](docs/SELECTION.md)。

## 致谢

- [cc-switch](https://github.com/farion1231/cc-switch) by [farion1231](https://github.com/farion1231)
- [LinuxServer.io baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies)

## License

[MIT](LICENSE)
