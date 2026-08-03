"""
Zero-code-instrumented demo LLM app.

This app is a deliberately "boring" chatbot/RAG endpoint. It knows nothing
about observability. All GenAI telemetry (tokens, cost, latency, model name,
prompt/response span events) is captured OUTSIDE this file:

  - by the LiteLLM Proxy it talks to (acts as a transparent OpenAI-compatible
    gateway), and
  - by OpenLIT, which either instruments this process via `openlit.init()`
    (see the OPENLIT_ZERO_CODE toggle below) or is configured purely on the
    LiteLLM side, so this file can stay 100% untouched if you want a true
    zero-code story.

Env vars:
  LITELLM_BASE_URL   default http://litellm-proxy.monitoring:4000/v1
  LITELLM_API_KEY    default "sk-demo" (LiteLLM proxy virtual key)
  DEFAULT_MODEL      default "local-llama"
  OPENLIT_ZERO_CODE  "true"/"false" - if true, imports openlit and calls
                     openlit.init() at startup (2 lines of "instrumentation").
                     If false, we rely entirely on LiteLLM-side OTel export
                     and this app truly never imports anything observability
                     related.
"""

import os
import time
import uuid

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from openai import OpenAI

LITELLM_BASE_URL = os.getenv("LITELLM_BASE_URL", "http://litellm-proxy.monitoring:4000/v1")
LITELLM_API_KEY = os.getenv("LITELLM_API_KEY", "sk-demo")
DEFAULT_MODEL = os.getenv("DEFAULT_MODEL", "local-llama")
OPENLIT_ZERO_CODE = os.getenv("OPENLIT_ZERO_CODE", "true").lower() == "true"

if OPENLIT_ZERO_CODE:
    try:
        import openlit
        openlit.init(
            otlp_endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT",
                                     "http://otel-gateway.monitoring:4318"),
            application_name="llm-demo",
            environment=os.getenv("ENVIRONMENT", "demo"),
            disable_batch=True,
        )
    except Exception as e:  # pragma: no cover - never break the app on telemetry issues
        print(f"[llm-demo] OpenLIT init skipped/failed: {e}")

app = FastAPI(title="LLM Observability Demo App")

client = OpenAI(base_url=LITELLM_BASE_URL, api_key=LITELLM_API_KEY)

# --- tiny in-memory "RAG" store, just to make the demo more than a bare chat call ---
FAKE_DOCS = [
    "The SRE observability platform ingests metrics, logs and traces via an "
    "OpenTelemetry Collector running as an agent DaemonSet plus a gateway Deployment.",
    "LiteLLM Proxy exposes an OpenAI-compatible API and can route requests to "
    "OpenAI, Anthropic, or a self-hosted Ollama model based on a model_list.",
    "OpenLIT emits OTel GenAI semantic-convention spans and metrics: "
    "gen_ai.client.token.usage and gen_ai.client.operation.duration.",
]


def retrieve_context(query: str, k: int = 2) -> str:
    """Extremely naive keyword-overlap retriever -- good enough for a demo."""
    scored = sorted(
        FAKE_DOCS,
        key=lambda d: len(set(query.lower().split()) & set(d.lower().split())),
        reverse=True,
    )
    return "\n".join(scored[:k])


class ChatRequest(BaseModel):
    message: str
    model: str | None = None
    use_rag: bool = False


class ChatResponse(BaseModel):
    request_id: str
    model: str
    reply: str
    latency_ms: float


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    model = req.model or DEFAULT_MODEL
    request_id = str(uuid.uuid4())
    start = time.time()

    messages = []
    if req.use_rag:
        context = retrieve_context(req.message)
        messages.append({
            "role": "system",
            "content": f"Answer using this context if relevant:\n{context}",
        })
    messages.append({"role": "user", "content": req.message})

    try:
        completion = client.chat.completions.create(
            model=model,
            messages=messages,
            extra_headers={"x-request-id": request_id},
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"upstream LLM call failed: {e}")

    latency_ms = (time.time() - start) * 1000
    reply = completion.choices[0].message.content

    return ChatResponse(
        request_id=request_id,
        model=model,
        reply=reply,
        latency_ms=round(latency_ms, 2),
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
