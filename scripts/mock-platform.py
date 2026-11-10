#!/usr/bin/env python3
"""本地 mock 平台（联调用）。

用途：在模拟器/真机上走通「登录之后的成功路径」——真账号密码不能进仓库，
但接口形状、字段名、SSE 帧格式都能在这里 1:1 复刻（依据 docs/PROTOCOL.md 与
HarmonyOS 版的实测记录）。

用法：
    scripts/mock-platform.py            # 监听 0.0.0.0:8080
    adb reverse tcp:8080 tcp:8080       # 设备/模拟器的 127.0.0.1:8080 → 本机
    设置 → 调试 → API 基地址 = http://127.0.0.1:8080（重启 App）

覆盖的端点（与客户端调用一一对应）：
    POST /ac/api/auth/loginDesktopClient.action
    GET  /acx/user/users/current-user-info
    GET  /acx/chatbot/config/list
    GET  /acx/chatbot/recommend/list
    GET  /acx/user/users/cluster-user-detail
    GET  /acx/llm/account/config/status
    POST /acx/llm/account/config/authorize
    POST /acx/llm/api-key/createActivityApiKey
    GET  /api/llm/v1/models
    GET  /acx/chatbot/conversation/list
    GET  /acx/chatbot/v2/agent/conversation/<id>/history
    POST /acx/chatbot/v2/agent/stream      （SSE）
    POST /acx/chatbot/v2/agent/stop
    POST /api/llm/v1/chat/completions      （SSE）
    POST /acx/search/dolphin/{mcp,skills}/full-text
    POST /acx/aihub/selected/agent/list
    GET  /acx/chatbot/file/upload/url + PUT <任意>
"""
import json
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8080
MOCK_KEY = "sk-" + "m" * 40

# 一段带 Markdown 的回答，用来验渲染
ANSWER = """# 结论

**SCNet-Max** 是平台自营模型，不扣余额；其余 32 个是上游付费模型。

## 建议

1. 默认用 `SCNet-Max`
2. 需要更强能力时再切付费模型
3. 余额为 0 时网关会回 `402 Insufficient Balance`

| 集群 | 空闲核 | 队列 |
|---|---|---|
| 昆山 | 116/992 | kshdAI |
| 哈尔滨 | 47/256 | hades |

```bash
scancel 127537835
```

> 提醒：作业取消后额度不会自动退回。"""


def envelope(data, code="0", msg="success"):
    return {"code": code, "msg": msg, "data": data}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"  # 无 keep-alive，SSE 可以直接边写边刷

    def log_message(self, fmt, *args):
        print("[mock] %s %s" % (self.command, self.path))

    # ---------------- helpers ----------------
    def read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def stream_start(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

    def sse(self, payload, flush=True):
        data = ("data: " + payload + "\n\n").encode("utf-8")
        self.wfile.write(data)
        if flush:
            self.wfile.flush()

    # ---------------- routing ----------------
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/acx/user/users/current-user-info":
            self.send_json(envelope({"id": "1", "userName": "mockuser", "fullName": "张测试",
                                     "mobilephoneNum": "138****0000", "acctRole": "admin"}))
        elif path == "/acx/chatbot/config/list":
            self.send_json(envelope({
                "recommendQuestion": ["用三句话说明 SLURM 是做什么的",
                                      "帮我写一个提交 VASP 任务的 sbatch 脚本",
                                      "HPC 作业排队很久，有哪些常见原因？",
                                      "解释一下 MPI 和 OpenMP 的区别"],
                "defaultCluster": 1,
                "defaultIdentify": "aiagent-router",
                "vibeCodingScenes": [{"value": "general", "label": "平台助手"},
                                     {"value": "industry", "label": "材料计算"}],
                "recommendAD": []
            }))
        elif path == "/acx/chatbot/recommend/list":
            self.send_json(envelope([{
                "identify": "aiagent-router",
                "aiAssistantName": "AI助理",
                "modelId": "600",
                "description": "平台运行时",
                "question": [
                    {"name": "帮我解释一下 MPI 和 OpenMP 的区别", "enable": True,
                     "route": "aiAssistant", "scene": "general"},
                    {"name": "帮我写一个 SLURM 提交脚本", "enable": True,
                     "route": "aiAssistant", "scene": "general"},
                    {"name": "VASP 计算过渡态一般怎么设参数", "enable": True,
                     "route": "aiAssistant", "scene": "industry"},
                    {"name": "帮我检索一下电催化方向的综述", "enable": True,
                     "route": "aiAssistant", "scene": "general"}
                ]
            }]))
        elif path == "/acx/user/users/cluster-user-detail":
            self.send_json(envelope([
                {"clusterId": 1, "clusterName": "华东一区·昆山", "accountId": "427416191724683264",
                 "groupId": "9", "userId": "u1", "status": "active"},
                {"clusterId": 2, "clusterName": "华北二区·哈尔滨", "accountId": "427416191724683264",
                 "groupId": "9", "userId": "u1", "status": "inactive"}
            ]))
        elif path == "/acx/llm/account/config/status":
            self.send_json(envelope({"accountId": "427416191724683264",
                                     "modelServiceEnabled": 1, "unpaidStatus": 0,
                                     "accessibleModelScope": "ALL"}))
        elif path == "/api/llm/v1/models":
            self.send_json({"object": "list", "data": [
                {"id": "SCNet-Max"}, {"id": "GLM-5.3-Flash"}, {"id": "DeepSeek-V3"}]})
        elif path == "/acx/chatbot/conversation/list":
            self.send_json(envelope({"records": [
                {"id": "c1", "title": "SLURM 入门", "createTime": "2026-11-10 10:00",
                 "taskStatus": "done"},
                {"id": "c2", "title": "VASP 参数", "createTime": "2026-11-10 11:00",
                 "taskStatus": "done"}
            ], "end": 1}))
        elif path.startswith("/acx/chatbot/v2/agent/conversation/"):
            self.send_json(envelope({"conversationId": "c1", "taskStatus": "done",
                                     "messages": [
                                         {"role": "user", "text": "SLURM 是什么"},
                                         {"role": "assistant", "text": "SLURM 是作业调度器。"}
                                     ]}))
        elif path.startswith("/acx/chatbot/file/upload/url"):
            self.send_json(envelope({}))
        else:
            self.send_json(envelope({}))

    def do_PUT(self):
        # OSS 预签名直传：吞掉字节返回 200
        self.read_body()
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        body = self.read_body()

        if path == "/ac/api/auth/loginDesktopClient.action":
            self.send_json(envelope({"token": "mock-token", "accessToken": "mock-token"}))
        elif path == "/acx/llm/account/config/authorize":
            self.send_json(envelope({}))
        elif path == "/acx/llm/api-key/createActivityApiKey":
            self.send_json(envelope({
                "apiKey": MOCK_KEY,
                "baseUrl": "http://127.0.0.1:%d/api/llm/v1" % PORT,
                "model": "SCNet-Max",
            }))
        elif path == "/acx/chatbot/file/upload/url":
            self.send_json(envelope([{"fileName": "mock-upload.csv",
                                      "uploadUrl": "http://127.0.0.1:%d/oss/put" % PORT}]))
        elif path == "/acx/search/dolphin/mcp/full-text" or \
                path == "/acx/search/dolphin/skills/full-text":
            self.send_json(envelope({"total": 2, "pages": 1, "records": [
                {"id": "1", "nameCn": "必应搜索", "desc": "联网检索", "createUser": "scnet",
                 "browseCount": 1200, "downloadCount": 300, "updateTime": "2026-11-01",
                 "suggestType": "1", "tags": [{"nameCn": "检索"}]},
                {"id": "2", "nameCn": "MATLAB", "desc": "数值计算", "createUser": "scnet",
                 "browseCount": 800, "downloadCount": 120, "updateTime": "2026-10-01",
                 "tags": [{"nameCn": "计算"}]}
            ]}))
        elif path == "/acx/aihub/selected/agent/list":
            self.send_json(envelope([{"agentId": "a1", "nameCn": "文献洞察", "nameEn": "paper",
                                      "desc": "论文速读", "sourceType": "build",
                                      "createUser": "scnet"}]))
        elif path == "/acx/chatbot/v2/agent/stream":
            self.agent_stream()
        elif path == "/api/llm/v1/chat/completions":
            self.llm_stream(body)
        elif path == "/acx/chatbot/v2/agent/stop":
            self.send_json(envelope({}))
        else:
            self.send_json(envelope({}))

    # ---------------- SSE ----------------
    def agent_stream(self):
        self.stream_start()
        self.sse(json.dumps({"type": None, "conversationId": "c1"}, ensure_ascii=False))
        self.sse(json.dumps({"type": "start"}, ensure_ascii=False))
        self.sse(json.dumps({"type": "title_gen", "title": "mock 会话"}, ensure_ascii=False))
        self.sse(json.dumps({"type": "todolist", "progressText": "正在分析任务…"},
                            ensure_ascii=False))
        for chunk in [ANSWER[i:i + 24] for i in range(0, len(ANSWER), 24)]:
            self.sse(json.dumps({"type": "text-delta", "delta": chunk}, ensure_ascii=False))
            time.sleep(0.02)
        self.sse(json.dumps({"type": "finish"}, ensure_ascii=False))

    def llm_stream(self, body):
        self.stream_start()
        for chunk in [ANSWER[i:i + 24] for i in range(0, len(ANSWER), 24)]:
            payload = {"choices": [{"delta": {"content": chunk}}]}
            self.sse(json.dumps(payload, ensure_ascii=False))
            time.sleep(0.02)
        self.sse("[DONE]")


if __name__ == "__main__":
    print("[mock] listening on 0.0.0.0:%d" % PORT)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
