"""从环境变量加载自定义大模型配置。

支持通过环境变量配置任意大模型（智谱 GLM、MiniMax、通义千问、DeepSeek 等），
自动注册 ProviderProfile 并构建 ACP 下拉框模型列表。

支持两种协议:
    - OpenAI 兼容 API (默认): 通过 ``ChatOpenAI`` + 自定义 ``base_url``
    - Anthropic 兼容 API: 通过 ``ChatAnthropic`` + 自定义 ``base_url``

环境变量命名:
    单模型: CUSTOM_LLM_BASE_URL / API_KEY / MODEL / NAME / PROTOCOL
    多模型: CUSTOM_LLM_1_BASE_URL / API_KEY / MODEL / NAME / PROTOCOL (编号 1~9)

    PROTOCOL 可选值: "openai" (默认) 或 "anthropic"
"""

from __future__ import annotations

import logging
import os

from deepagents import ProviderProfile, register_provider_profile

logger = logging.getLogger(__name__)


def _read_single(prefix: str) -> dict[str, str] | None:
    """读取单组 CUSTOM_LLM_* 或 CUSTOM_LLM_N_* 环境变量。

    Args:
        prefix: 环境变量前缀，如 "CUSTOM_LLM" 或 "CUSTOM_LLM_1"。

    Returns:
        包含 base_url / api_key / model / name / protocol 的字典，缺少必填项时返回 None。
    """
    base_url = os.environ.get(f"{prefix}_BASE_URL", "").strip()
    api_key = os.environ.get(f"{prefix}_API_KEY", "").strip()
    model = os.environ.get(f"{prefix}_MODEL", "").strip()
    name = os.environ.get(f"{prefix}_NAME", "").strip()
    # 协议: "openai" (默认) 或 "anthropic"
    protocol = os.environ.get(f"{prefix}_PROTOCOL", "openai").strip().lower()

    if not base_url or not model:
        return None

    if protocol not in ("openai", "anthropic"):
        logger.warning(
            "Unsupported protocol %r for %s, falling back to 'openai'",
            protocol,
            prefix,
        )
        protocol = "openai"

    return {
        "base_url": base_url,
        "api_key": api_key,
        "model": model,
        "name": name or model,
        "protocol": protocol,
    }


def load_custom_models() -> list[dict[str, str]]:
    """解析环境变量，注册 ProviderProfile，返回 ACP 下拉框模型列表。

    支持:
      - CUSTOM_LLM_BASE_URL / API_KEY / MODEL / NAME / PROTOCOL (单模型)
      - CUSTOM_LLM_1_*, CUSTOM_LLM_2_* ... (多模型，编号 1~9)

    PROTOCOL 决定使用哪种协议接入:
      - ``"openai"`` (默认): 通过 ``ChatOpenAI`` + 自定义 ``base_url``，
        适用于提供 OpenAI 兼容 API 的厂商（智谱、MiniMax、通义千问、DeepSeek 等）。
      - ``"anthropic"``: 通过 ``ChatAnthropic`` + 自定义 ``base_url``，
        适用于提供 Anthropic 兼容 API 的厂商。

    Returns:
        ACP models 列表，如 ``[{"value": "openai:glm-4-flash", "name": "智谱 GLM-4"}]``。
        未配置任何自定义模型时返回空列表。
    """
    configs: list[dict[str, str]] = []

    # 1. 读取无编号配置 (CUSTOM_LLM_*)
    cfg = _read_single("CUSTOM_LLM")
    if cfg is not None:
        configs.append(cfg)

    # 2. 读取编号配置 (CUSTOM_LLM_1_* ~ CUSTOM_LLM_9_*)
    for i in range(1, 10):
        cfg = _read_single(f"CUSTOM_LLM_{i}")
        if cfg is not None:
            configs.append(cfg)

    if not configs:
        return []

    # 3. 注册 ProviderProfile — 仅注册精确匹配的 per-model key
    #    使用 "<protocol>:<model_name>" 而非 provider-wide key，
    #    避免覆盖内置 OpenAI/Anthropic 配置，
    #    确保下拉框中的 GPT-5.5 / Claude 等内置模型不受影响。
    #
    #    解析优先级 (get_provider_profile):
    #      1. 精确匹配 "openai:glm-4-flash"     ← 自定义模型命中
    #      2. 前缀匹配 "openai"                  ← 内置 OpenAI 配置
    #    自定义模型走路径 1，内置模型走路径 2，互不干扰。
    for c in configs:
        protocol = c["protocol"]
        init_kwargs: dict[str, object] = {
            "base_url": c["base_url"],
            "api_key": c["api_key"],
        }
        if protocol == "openai":
            # 覆盖内置 OpenAI 的 use_responses_api=True，
            # 非 OpenAI 端点通常不支持 responses API。
            init_kwargs["use_responses_api"] = False

        register_provider_profile(
            f"{protocol}:{c['model']}",
            ProviderProfile(init_kwargs=init_kwargs),
        )
        logger.info(
            "Registered custom LLM model: %s:%s → %s (protocol: %s)",
            protocol,
            c["model"],
            c["base_url"],
            protocol,
        )

    # 4. 构建 ACP 下拉框列表
    return [
        {"value": f"{c['protocol']}:{c['model']}", "name": c["name"]} for c in configs
    ]


def load_anthropic_model() -> list[dict[str, str]]:
    """从 ANTHROPIC_MODEL 环境变量加载自定义 Anthropic 协议模型。

    ChatAnthropic 已自动从环境变量读取 ANTHROPIC_BASE_URL 和 ANTHROPIC_API_KEY，
    无需注册 ProviderProfile。此函数只需读取 ANTHROPIC_MODEL 并返回下拉框列表。

    环境变量:
        ANTHROPIC_BASE_URL  — API 地址（ChatAnthropic 自动读取）
        ANTHROPIC_API_KEY   — API 密钥（ChatAnthropic 自动读取）
        ANTHROPIC_MODEL     — 模型名称（由此函数读取，加入 ACP 下拉框）
        ANTHROPIC_MODEL_NAME — 可选，ACP 下拉框显示名（默认同 MODEL）

    Returns:
        ACP models 列表，如 ``[{"value": "anthropic:glm-4-flash", "name": "智谱 GLM-4"}]``。
        未配置 ANTHROPIC_MODEL 时返回空列表。
    """
    model = os.environ.get("ANTHROPIC_MODEL", "").strip()
    if not model:
        return []
    name = os.environ.get("ANTHROPIC_MODEL_NAME", "").strip() or model
    logger.info("Custom Anthropic model from env: anthropic:%s", model)
    return [{"value": f"anthropic:{model}", "name": name}]
