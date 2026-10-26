"""极简 GitHub REST 客户端（纯标准库），供 ci/ 下的协作脚本复用。

令牌只从环境变量 GITHUB_TOKEN 读取（可缺省：公开仓库的只读请求无需令牌）；不打印令牌，不写本地文件。
"""
import json
import os
import urllib.error
import urllib.parse
import urllib.request

API = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")


class GitHubError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status


def request(method: str, path: str, body=None):
    """发送一次请求，返回 (JSON 或 None, Link 头)。path 可以是完整 URL。"""
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    token = os.environ.get("GITHUB_TOKEN", "")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return (json.loads(raw) if raw else None), resp.headers.get("Link", "")
    except urllib.error.HTTPError as err:
        detail = err.read().decode("utf-8", "replace")[:300]
        raise GitHubError(err.code, detail) from None


def paginate(path: str) -> list:
    """按 Link 头翻页取回列表接口的全部条目（每页 100）。"""
    url = f"{path}{'&' if '?' in path else '?'}per_page=100"
    items = []
    while url:
        page, link = request("GET", url)
        items.extend(page or [])
        url = next_link(link)
    return items


def next_link(link: str):
    for part in link.split(","):
        seg = part.split(";")
        if len(seg) >= 2 and 'rel="next"' in seg[1]:
            return seg[0].strip().strip("<>")
    return None


def quote(name: str) -> str:
    """标签名放进 URL 路径前转义（如 risk:L2）。"""
    return urllib.parse.quote(name, safe="")


def pr_files(repo: str, number: int) -> list:
    """PR 改动文件条目（filename、previous_filename、additions、deletions 等原样返回）。"""
    return paginate(f"/repos/{repo}/pulls/{number}/files")
