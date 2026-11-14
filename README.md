# Deepseek-Chat-Strata-Qwen3.8-Flash-Next

[English](https://github.com/deepseek-ai/chat-demo) | 简体中文

基于 [deepseek-ai/chat-demo](https://github.com/deepseek-ai/chat-demo)（MIT）的定制版：把这款浏览器聊天前端接到**本地 Strata 服务器**上（Qwen3.8-Flash-Next 等 `qwen4exp` 模型），走 Anthropic 兼容接口。无应用后端，浏览器直连；开发服务器代理转发，**不需要任何 CORS 配置**，Strata 侧零改动（只打一个可选的角色兼容补丁，见下文）。

```
浏览器 (localhost:8091)
   │  同源请求，无 CORS 问题
   ▼
rspack dev-server  ←  /anthropic/* 改写为 /v1/*，/models 原样转发
   ▼
Strata 服务器 (默认 http://127.0.0.1:8080)
   └─ Qwen3.8-Flash-Next（UD-IQ3_XXS，Anthropic 兼容 API，支持图片与思考）
```

功能与上游一致：多会话、流式回答、深度思考（思考内容走 Anthropic thinking 块）、Markdown / KaTeX / Mermaid、历史导入导出等。深度思考开关、`system`、`max_tokens` 都被 Strata 正确执行；上游的 `title`、`safety_check` 等私有字段被 Strata 静默忽略。

## 快速开始

前提：一台跑着 [Strata](https://github.com/Niko1221/Strata) 的机器（装好 Terminal 和模型，`strata launch` 能出地址），Node.js 22.12+，python3（打补丁用）。

```sh
git clone https://github.com/aifeifei798/Deepseek-Chat-Strata-Qwen3.8-Flash-Next.git
cd Deepseek-Chat-Strata-Qwen3.8-Flash-Next
./install.sh            # 装依赖、生成 .env、给 Strata 打本项目专用的兼容补丁（说明见下文）
./serve.sh start        # 拉起网页（.env 配了 STRATA_MODEL_PATH 时连 Strata 一起拉起）
```

打开 **http://localhost:8091**，设置里 **API Key 随便填**（本地服务不校验），开始聊天。

## .env 配置

`./install.sh` 会从 [.env.example](.env.example) 生成 `.env`（不入库），改完重启 `./serve.sh` 生效；环境变量优先于文件：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `STRATA_URL` | `http://127.0.0.1:8080` | Strata 服务地址，代理后端 + serve.sh 探测用 |
| `DEV_PORT` | `8091` | 网页开发服务器端口（8090 是上游默认值，常被占用） |
| `API_ORIGIN` | 空 | 留空走同源代理（推荐）；显式设置会同时影响 `pnpm build` 产物 |
| `STRATA_BIN` | `~/.local/bin/strata` | Strata 可执行文件路径 |
| `STRATA_MODEL_PATH` | 空 | 模型分片路径（任一分片）；设置后 `./serve.sh start` 自动拉起 Strata |
| `STRATA_LAUNCH_ARGS` | 空 | 传给 `strata launch` 的额外参数，含空格要加引号 |

## 管理命令（serve.sh）

| 命令 | 作用 |
| --- | --- |
| `./serve.sh start` | 起服务：Strata（按需）+ 网页开发服务器 |
| `./serve.sh stop` | 停网页开发服务器（不动 Strata） |
| `./serve.sh restart` | 重启网页开发服务器 |
| `./serve.sh status` | 两个服务的状态 + 补丁状态 |
| `./serve.sh logs` | 看开发服务器日志 |
| `./serve.sh strata-start` / `strata-stop` | 单独拉起 / 停掉 Strata（停掉会释放显存） |

## 关于 Strata 补丁（本项目专用）

> [!IMPORTANT]
> **这个补丁只为本项目（chat-demo 前端）而存在**，随 `./install.sh` 打到本机的 Strata 上。它**不是 Strata 的通用补丁**：
> - 用其他客户端（Claude Code、OpenCode、`strata connect` 列表里的应用等）连 Strata 时**不需要、也不要打**它；
> - 换掉本前端后就与它无关；留着它对别的客户端零影响（它们从不发送 `latest_reminder`，折叠逻辑不会触发），卸载本项目也不必回滚。

**为什么需要**：chat-demo 每条提问前会插入一条 `role: "latest_reminder"` 的消息（日期 / 平台 / 语言快照，DeepSeek API 的私有角色）。非 DeepSeek 模型家族的 chat template 不认识它，渲染时报 `Unexpected message role.`。只有本项目会发这种消息，所以只有本项目需要这个补丁。

**它做什么**：`install.sh` 用 [patches/patch_strata_frontend.py](patches/patch_strata_frontend.py) 在 Strata 的 `serve/frontend.py`（两条 API 路径共用的模板渲染入口）加一个兼容：模板原生支持该角色的（DeepSeek V4.1）保持原样，不认识的家族折叠成 user。补丁幂等、自动备份原文件（`frontend.py.bak-chatdemo`）、写完做语法自检；`serve.sh status` 会随时检查它还在不在。

**维护**：`strata update` 升级 Terminal 后补丁可能被新文件覆盖，再跑一次 `./install.sh` 即可恢复。给**运行中**的 Strata 打完补丁要重启服务才生效（`strata launch --stop` 后重新启动；注意 `strata launch --restart` 只重载模型，不会重启 serve 进程重新读 Python 代码）。

Strata 装在非默认位置时：`./install.sh --strata-home /path/to/strata`，或直接 `STRATA_SERVE_DIR=/path/to/serve ./install.sh`。

## 与上游的差异

- [rspack.config.ts](rspack.config.ts)：读 `.env`；开发服务器加同源代理（`/anthropic/*` → `/v1/*` 改写、`/models` 直转）；仅影响 `pnpm dev`，`pnpm build` 产物仍指向 `https://api.deepseek.com`（除非 `.env` 设置了 `API_ORIGIN`）
- 新增 [.env.example](.env.example)、[install.sh](install.sh)、[serve.sh](serve.sh)、[patches/](patches/)（`patches/` 里的补丁只服务于本前端，见[上文](#关于-strata-补丁本项目专用)）
- 其余代码与上游 v0.1.1 一致；应用自身的功能说明见 [上游 README](https://github.com/deepseek-ai/chat-demo#readme)

## 开发

| 命令 | 用途 |
| --- | --- |
| `pnpm dev` | 开发服务器（同 `./serve.sh start` 的网页部分，前台运行） |
| `pnpm build` | 构建到 `dist/`（产物指向 api.deepseek.com，除非 `.env` 设置 `API_ORIGIN`） |
| `pnpm type` | TypeScript 类型检查 |
| `pnpm lint` | oxlint 检查 |
| `pnpm format` | oxfmt 格式化 |

历史导入导出的格式见 [src/services/chat/history/README.md](src/services/chat/history/README.md)。

## 已知限制

- **附件上传不可用**：chat-demo 走 Anthropic Files API（`/v1/files`），Strata 没有这个端点；语音输入是浏览器本机功能，可用
- **智能搜索 / 链接阅读**是 DeepSeek 云端能力，接本地模型没有意义（开关会被 Strata 忽略）
- API Key 仅作占位：本地 Strata 默认不校验；若你的 Strata 用 `--access lan` 等开了 key 的模式，把真 key 填进去即可

## License

[MIT](LICENSE)（继承上游）。模型与推理服务请遵循 Strata 和所用模型自身的许可。
