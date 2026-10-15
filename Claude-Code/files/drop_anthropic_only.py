"""LiteLLM callback: drop Anthropic-only fields the upstream rejects.

Why this exists
---------------
Claude Code >= 2.1.169 always sends

    thinking: {"type": "adaptive", "display": "omitted"}

Adaptive thinking is an Anthropic 4.6+ feature. LiteLLM decides whether to
strip that field using its own model cost map, and our upstream is registered
as `openai/deepseek-ai/DeepSeek-V4.1-Flash` — a name that map does not know.
So the field passes straight through to the OpenAI-style upstream, which
answers

    400 {"message": "Invalid request", "type": "Bad Request", "code": 400}

`drop_params: true` does not help: it only removes parameters LiteLLM has
already classified as foreign, and it considers `thinking` its own.
`additional_drop_params` on the model entry does not help either — the
`/v1/messages` route never reads it from the config.

Verified by bisection against the live gateway: the full real payload from
the CLI returns 400; the same payload with only `thinking` removed returns
200.

What it does
------------
`async_pre_call_hook` runs on the proxy before the request leaves, so the
upstream never sees these fields. Dropping is safe here: the upstream is a
reasoning model that emits its reasoning in a separate `reasoning_content`
field regardless, so no capability is lost — only a field the upstream would
have rejected anyway.

Note this is the same class of fix as `websearch_interception` in the config:
both compensate for an upstream that is not Anthropic-shaped.
"""

from typing import Any

from litellm.integrations.custom_logger import CustomLogger

# Anthropic-only request fields our upstream rejects with HTTP 400.
# `thinking` is the one observed in practice; the other two ride along in the
# same payload from the CLI and are equally meaningless to an OpenAI backend,
# so they go too rather than waiting for them to break something later.
ANTHROPIC_ONLY_FIELDS = ("thinking", "context_management", "output_config")


class DropAnthropicOnlyParams(CustomLogger):
    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict,
        call_type: Any,
    ) -> dict | None:
        if not isinstance(data, dict):
            return None

        dropped = [field for field in ANTHROPIC_ONLY_FIELDS if field in data]
        for field in dropped:
            data.pop(field, None)

        if dropped:
            print(f"[drop-anthropic-only] removed {dropped} before upstream call")

        return data


proxy_handler_instance = DropAnthropicOnlyParams()
