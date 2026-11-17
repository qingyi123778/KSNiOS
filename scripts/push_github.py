#!/usr/bin/env python3
"""用 Git Data API 一次性提交整个项目。

不走 git（github.com 直连 502），也不逐个 PUT（Contents API 24 次请求太慢），
改成 blobs → tree → commit → ref 四步，一次提交搞定。

用法： python scripts/push_github.py <token> [--skip-workflow]
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OWNER = "qingyi123778"
REPO = "KSNiOS"
SKIP_DIRS = {".git", "packages", ".theos", "obj", "__pycache__"}
SKIP_EXT = {".zip", ".deb", ".dylib"}


def call(method, path, token, body=None):
    url = API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "ksn-push")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        low = detail.lower()
        if "workflow" in low or "refusing" in low:
            sys.exit("\n[!] GitHub 拒绝写入 .github/workflows —— token 缺 workflow scope。\n"
                     "    原始响应：%s\n"
                     "    需要在网页上手动建这个文件，内容见 .github/workflows/build.yml。\n" % detail[:400])
        sys.exit("HTTP %d  %s %s\n%s" % (e.code, method, path, detail[:400]))


def collect():
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if os.path.splitext(f)[1].lower() in SKIP_EXT:
                continue
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            files.append((full, rel))
    return sorted(files, key=lambda x: x[1])


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    token = sys.argv[1].strip()
    skip_wf = "--skip-workflow" in sys.argv

    files = collect()
    if skip_wf:
        files = [(p, r) for p, r in files if not r.startswith(".github/")]
    print("[+] 待提交 %d 个文件" % len(files))

    ref = call("GET", "/repos/%s/%s/git/ref/heads/main" % (OWNER, REPO), token)
    head = ref["object"]["sha"]
    commit = call("GET", "/repos/%s/%s/git/commits/%s" % (OWNER, REPO, head), token)
    base_tree = commit["tree"]["sha"]
    print("[+] head %s  base_tree %s" % (head[:8], base_tree[:8]))

    tree = []
    for full, rel in files:
        with open(full, "rb") as fh:
            content = base64.b64encode(fh.read()).decode()
        blob = call("POST", "/repos/%s/%s/git/blobs" % (OWNER, REPO), token,
                    {"content": content, "encoding": "base64"})
        tree.append({"path": rel, "mode": "100644", "type": "blob", "sha": blob["sha"]})
        print("    blob %-44s %s" % (rel, blob["sha"][:8]))

    new_tree = call("POST", "/repos/%s/%s/git/trees" % (OWNER, REPO), token,
                    {"base_tree": base_tree, "tree": tree})
    print("[+] tree %s" % new_tree["sha"][:8])

    new_commit = call("POST", "/repos/%s/%s/git/commits" % (OWNER, REPO), token, {
        "message": "KSNiOS: 学习通 iOS 签到 tweak（Theos rootless）",
        "tree": new_tree["sha"],
        "parents": [head],
    })
    print("[+] commit %s" % new_commit["sha"][:8])

    call("PATCH", "/repos/%s/%s/git/refs/heads/main" % (OWNER, REPO), token,
         {"sha": new_commit["sha"], "force": False})
    print("[+] 已推送  https://github.com/%s/%s" % (OWNER, REPO))


if __name__ == "__main__":
    main()
