#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通过 GitHub Git Data API 把本地提交推到远端 main（沙箱里 git push 不可用）。

为什么不用 git push：沙箱内 github.com 的 443 在传 pack 时会被 TLS 断连
（GnuTLS recv error (-110)），但 api.github.com 完全可达。所以走 API：
  逐个 POST /git/blobs → POST /git/trees（base_tree = 远端树）
  → POST /git/commits（parents = [远端 main]）
  → PATCH /git/refs/heads/main（force=false）
效果等价于一次合并提交：远端已有内容全部保留，不丢任何文件。

⚠️ 三个踩过的坑，这个脚本专门防了：

1) **推完必须回读校验**。
   早期版本从 /tmp/added.txt、/tmp/modif.txt 两个外部临时文件读清单，
   那文件早就过期了 → 只推了 2 个文件却打印「DONE」，静默漏掉 16 个。
   现在差异自己算（比对本地 HEAD 树与远端树），推完逐个 GET 回读比对 size，
   不一致就非零退出。**不要**改成「打日志说成功就算成功」。

2) **core.quotePath=false 是铁律**。
   git ls-tree 默认把中文路径转义成八进制（"\\346\\233\\264..."），
   拿它去 open() 会 FileNotFoundError；拿去和 API 返回的 UTF-8 路径比对
   又会误报「远端独有」。本脚本所有 git 调用都带这个参数。

3) **norm() 不能用 lstrip("./")**。
   那会把 .env.example 变成 env.example、.gitignore 变成 gitignore，
   点号文件被静默跳过（真实发生过一次）。

用法：
  TOK=<github token> REPO=owner/name python3 scripts/github-push-api.py
  TOK=... python3 scripts/github-push-api.py --dry-run   # 只看要推哪些
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = os.environ.get("REPO", "Ezra-Maker-MAX/clothes")
API = f"https://api.github.com/repos/{REPO}"
TOK = os.environ.get("TOK", "")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DELAY = float(os.environ.get("DELAY", "0.2"))

if not TOK:
    sys.exit("缺少环境变量 TOK=<github personal access token>")
DRY = "--dry-run" in sys.argv


def req(method, path, body=None):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {TOK}")
    r.add_header("Accept", "application/vnd.github+json")
    r.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data:
        r.add_header("Content-Type", "application/json")
    for attempt in range(5):
        try:
            with urllib.request.urlopen(r, timeout=90) as resp:
                txt = resp.read()
            return json.loads(txt) if txt else {}
        except urllib.error.HTTPError as e:
            msg = e.read().decode()[:300]
            if e.code in (502, 503, 504) and attempt < 4:
                time.sleep(2 + attempt * 2)
                continue
            raise RuntimeError(f"{method} {url} -> HTTP {e.code}: {msg}")
        except Exception:
            if attempt < 4:
                time.sleep(2 + attempt * 2)
                continue
            raise
    raise RuntimeError("unreachable")


def norm(p):
    p = p.replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p.lstrip("/")


def remote_blobs(sha):
    """远端某 commit 的 tree 里所有 blob：路径 → sha"""
    tree = req("GET", f"/git/commits/{sha}")["tree"]["sha"]
    out = {}
    cursor = None
    while True:
        q = f"/git/trees/{tree}?recursive=1"
        if cursor:
            q += f"&cursor={cursor}"
        t = req("GET", q)
        for e in t.get("tree", []):
            if e.get("type") == "blob":
                out[e["path"]] = e["sha"]
        if not t.get("truncated"):
            return out
        cursor = t.get("cursor")


def local_blobs():
    out = {}
    for line in subprocess.check_output(
        ["git", "-c", "core.quotePath=false", "ls-tree", "-r", "--full-tree", "HEAD"],
        cwd=ROOT,
    ).decode("utf-8", "ignore").split("\n"):
        if not line.strip():
            continue
        meta, path = line.split("\t", 1)
        mode, otype, sha = meta.split()
        if otype == "blob":
            out[norm(path)] = (sha, mode)
    return out


def main():
    remote_sha = req("GET", "/git/ref/heads/main")["object"]["sha"]
    remote = remote_blobs(remote_sha)
    local = local_blobs()

    # 远端有、本地没有的文件：保留不动（删除留给人工确认，保守处理）
    only_remote = [p for p in remote if p not in local]
    paths = [p for p in sorted(local) if p not in remote or remote[p] != local[p][0]]

    print(f"远端 main = {remote_sha[:12]}（{len(remote)} 个文件）")
    print(f"本地 HEAD = {len(local)} 个文件")
    if only_remote:
        print(f"⚠️ 远端有 {len(only_remote)} 个本地没有的文件，将保留不动")
    print(f"待上传 {len(paths)} 个文件")
    if not paths:
        print("没有差异，无需推送")
        return

    if DRY:
        for p in paths:
            print("   ", p)
        return

    entries = []
    for i, p in enumerate(paths, 1):
        with open(os.path.join(ROOT, p), "rb") as fh:
            blob = req("POST", "/git/blobs",
                       {"content": base64.b64encode(fh.read()).decode(),
                        "encoding": "base64"})
        entries.append({"path": p, "mode": local[p][1], "type": "blob",
                        "sha": blob["sha"]})
        if i % 20 == 0 or i == len(paths):
            print(f"   blob {i}/{len(paths)}")
        time.sleep(DELAY)

    base_tree = req("GET", f"/git/commits/{remote_sha}")["tree"]["sha"]
    tree = req("POST", "/git/trees", {"base_tree": base_tree, "tree": entries})
    if tree.get("truncated"):
        sys.exit("tree 被截断，中止")
    print(f"新 tree = {tree['sha'][:12]}")

    msg = subprocess.check_output(
        ["git", "log", "-1", "--pretty=%B"], cwd=ROOT).decode("utf-8").strip()
    commit = req("POST", "/git/commits",
                 {"message": msg, "tree": tree["sha"], "parents": [remote_sha]})
    print(f"新 commit = {commit['sha'][:12]}")

    ref = req("PATCH", "/git/refs/heads/main",
              {"sha": commit["sha"], "force": False})
    new_sha = ref["object"]["sha"]
    print(f"main -> {new_sha[:12]}（force=false，快进）")

    # 回读校验：每个文件都必须真的在远端且大小一致
    bad = []
    for p in paths:
        r = req("GET", f"/contents/{urllib.parse.quote(p)}?ref={new_sha}")
        local_size = os.path.getsize(os.path.join(ROOT, p))
        if r.get("size") != local_size:
            bad.append(f"{p}: 远端 {r.get('size')} != 本地 {local_size}")
    if bad:
        print("\n✗ 校验失败，远端与本地不一致：")
        for b in bad:
            print("   ", b)
        sys.exit(1)
    print(f"\n✓ 校验通过：{len(paths)} 个文件全部落到远端 main（{new_sha[:12]}）")


if __name__ == "__main__":
    main()