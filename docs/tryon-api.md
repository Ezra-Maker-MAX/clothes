# 虚拟试衣 · 自部署模型接口约定（tryon-api）

> 版本 v1（2026-10）。App 侧实现：`app/lib/services/tryon_service.dart`。
> 定位：模型服务**由你自行部署**（本地电脑 / 局域网 / 自有服务器），App 只是直连客户端。
> 试衣图片只从手机直发这个地址——不经过衣念的 Vercel 服务端、不写入 Turso / Vercel Blob，配置只存手机本地。

## 1. 网络要求

| 项 | 要求 |
|---|---|
| 监听 | 服务监听 `0.0.0.0`（而不是 127.0.0.1），否则手机连不上 |
| 网络 | 手机与服务器同一局域网（WiFi）；或部署到有公网 IP 的自有服务器 |
| 防火墙 | 放行服务端口 |
| 协议 | 支持 `http://`（Android 已允许明文流量；iOS 需在 Info.plist 加 NSAppTransportSecurity → NSAllowsArbitraryLoads） |
| 地址 | 设置页填 `http://<服务器IP>:<端口>`，例如 `http://192.168.1.5:8000` |

## 2. 两个接口

### 2.1 连接测试

```
GET {baseUrl}/health
```

- 返回任意 2xx 即视为在线（body 随意，推荐 `{"ok": true}`）。

### 2.2 生成试穿

```
POST {baseUrl}{path}        # path 在设置页可配，默认 /tryon
Content-Type: application/json
X-API-Key: <你在设置页填的 key，若填了>
```

请求体：

```json
{
  "personImages": ["<base64>", "base64..."],   // 1~5 张人像，必填
  "garmentImage": "<base64>",                  // 服装平铺图，必填
  "poseImage": "<base64>" | null,              // 姿势参考图，可选
  "body": {                                    // 身体数据，可选（用户填了才发）
    "heightCm": 165, "weightKg": 52,
    "bust": 84, "waist": 66, "hips": 90
  },
  "prompt": "string | null",                   // 补充描述，可选
  "options": { ... }                           // 自定义透传字段，App 原样转发
}
```

响应（三选一，App 自动兼容）：

```json
// a) 返回 base64
{"image": "<base64>"}

// b) 返回 URL（服务自己把图放哪都行，本地 http 也可以）
{"imageUrl": "http://192.168.1.5:8000/results/xxx.png"}

// c) 直接回图片二进制（Content-Type: image/png 等）
```

错误约定：非 2xx 时响应体里带 `{"error": "人话原因"}` 最好，App 会透出这行字。

超时：App 侧等待 **180 秒**；本地扩散模型 30s~3min 出图都正常。

## 3. 适配层示例（Python · FastAPI）

App 发的是上述简单 JSON。若你的模型是 ComfyUI / SD WebUI / 自研管线，写一个薄适配层把请求翻译过去即可，骨架如下（`pip install fastapi uvicorn pillow`）：

```python
from base64 import b64decode, b64encode
from io import BytesIO
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse, Response

app = FastAPI()

@app.get("/health")
def health():
    return {"ok": True}

@app.post("/tryon")
async def tryon(req: Request):
    d = await req.json()
    # 1. 解图
    person = [b64decode(x) for x in d["personImages"]]
    garment = b64decode(d["garmentImage"])
    pose = b64decode(d["poseImage"]) if d.get("poseImage") else None
    body, options = d.get("body") or {}, d.get("options") or {}

    # 2. 调你的模型（伪代码，替换为 ComfyUI workflow 提交 / SD WebUI /api/v1 调用等）
    #    - 人像作为 init image / 人体重建参考
    #    - garment 走 tryon 模型（如 IDM-VTON、CatVTON 类）或 inpainting
    #    - pose 转 openpose 条件；body 数据拼进 prompt 或反推
    result_bytes = run_your_model(person, garment, pose, body, options)

    # 3. 回传（base64 方式最简单）
    return {"image": b64encode(result_bytes).decode()}

@app.exception_handler(Exception)
async def boom(req, e):
    return JSONResponse(status_code=500, content={"error": str(e)})
```

启动：`uvicorn server:app --host 0.0.0.0 --port 8000`，设置页填 `http://<电脑IP>:8000`。

## 4. 设计取舍说明

- **为什么协议这么薄**：不绑定任何具体试衣模型。ComfyUI、SD WebUI、自研管线都能用几十行适配层接进来；`options` 字段透传，模型侧想加什么参数（采样步数、强度、蒙版…）App 不用改。
- **为什么人像支持多张**：多角度照提升分身还原度（正面/侧面各来一张即可，无需裸露照——试衣模型内建人体先验）。
- **隐私边界**：图片不出你的设备与你的服务；`usesCleartextTraffic` 仅为局域网 http 放开，若服务部署公网请配 https。**请仅使用成年人本人的照片，且生成内容勿对外传播** —— 这是使用者的责任边界。
