#!/usr/bin/env python3
"""给 Strata 的 serve/frontend.py 打 chat-demo 兼容补丁（latest_reminder 角色）。

背景：DeepSeek 系客户端（本仓库的 chat-demo）会在每条提问前插入一条
role='latest_reminder' 的消息；模型家族不是 DeepSeek 时（如 Qwen3.8-Flash-Next），
其 chat template 不认识这个角色，渲染时抛 'Unexpected message role.'。

补丁在 ChatTemplate（两条 API 路径共用的渲染入口）加两处：
  1. __init__ 里探测模板是否原生支持该角色；
  2. render() 里把不认识的角色折叠成 user（原生支持的模板，如 DeepSeek V4.1
     的 fixture，保持原样）。

幂等：文件里已有标记时原样退出。原文件备份为 frontend.py.bak-chatdemo
（已存在备份时不覆盖）。写完做一次 py_compile 语法自检。

用法：
    python3 patches/patch_strata_frontend.py /path/to/strata/serve [--check]
退出码（--check）：0 = 已打过补丁；1 = 需要打；2 = 无法处理（文件缺失/锚点对不上）。
不带 --check 时：0 = 成功（含"已打过"），非 0 = 失败。
"""
import pathlib
import py_compile
import shutil
import sys

MARKER = 'native_latest_reminder'
INIT_ANCHOR = "self.caps = self._detect_caps()"
INIT_ADD = '''
        # DeepSeek-API clients interleave 'latest_reminder' turns (chat-demo sends one before every
        # question: the date, platform and language snapshot).  A template that renders the role
        # natively (the DeepSeek V4.1 fixture) keeps them; every other family's template raises
        # 'Unexpected message role.', so here they go in as user turns.
        self.native_latest_reminder = "latest_reminder" in self.source'''
RENDER_ANCHOR = "**kwargs) -> str:"
RENDER_ADD = '''
        if not self.native_latest_reminder:
            messages = [dict(m, role="user") if isinstance(m, dict) and m.get("role") == "latest_reminder"
                        else m for m in messages]'''


def fail(message: str) -> int:
    print(f"patch_strata_frontend: {message}", file=sys.stderr)
    return 2


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--check"]
    check = "--check" in sys.argv
    if len(args) != 1:
        print(__doc__)
        return 2
    target = pathlib.Path(args[0]) / "frontend.py"
    if not target.is_file():
        return fail(f"{target} 不存在（要传 serve 目录的路径）")
    text = target.read_text(encoding="utf-8")

    if MARKER in text:
        print(f"已打过补丁，跳过: {target}")
        return 0

    if INIT_ANCHOR not in text:
        return fail(f"找不到锚点 {INIT_ANCHOR!r}：Strata 版本可能不同，请手动改 {target}（见本文件头部说明）")

    render_at = text.find("def render(")
    if render_at < 0:
        return fail("找不到 def render(：Strata 版本可能不同，请手动改")
    try:
        render_at = text.index(RENDER_ANCHOR, render_at) + len(RENDER_ANCHOR)
    except ValueError:
        return fail(f"找不到锚点 {RENDER_ANCHOR!r}：请手动改 {target}")

    if check:
        print(f"需要打补丁: {target}")
        return 1

    backup = target.with_name("frontend.py.bak-chatdemo")
    if not backup.exists():
        shutil.copy2(target, backup)
        print(f"原文件已备份: {backup}")
    text = text.replace(INIT_ANCHOR, INIT_ANCHOR + INIT_ADD, 1)
    # INIT_ADD 把后面的内容整体推后了，render 的插入点要按替换后的文本重新定位
    render_at = text.index("def render(")
    render_at = text.index(RENDER_ANCHOR, render_at) + len(RENDER_ANCHOR)
    text = text[:render_at] + RENDER_ADD + text[render_at:]
    target.write_text(text, encoding="utf-8")
    try:
        py_compile.compile(str(target), doraise=True)
    except py_compile.PyCompileError as e:
        # 语法都过不了说明锚点落点有意外：恢复备份，交给人工
        shutil.copy2(backup, target)
        return fail(f"补丁后语法检查失败，已还原备份。请手动改：\n{e}")
    print(f"补丁完成: {target}（重启 Strata 服务后生效）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
