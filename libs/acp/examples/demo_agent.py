"""Demo coding agent using ACP."""

import asyncio
import os

from acp import (
    run_agent as run_acp_agent,
)
from acp.schema import (
    SessionMode,
    SessionModeState,
)
from deepagents import create_deep_agent
from deepagents.backends import CompositeBackend, LocalShellBackend, StateBackend
from dotenv import load_dotenv
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph.state import Checkpointer, CompiledStateGraph

from deepagents_acp.server import AgentServerACP, AgentSessionContext
from examples.custom_model_config import load_anthropic_model, load_custom_models
from examples.local_context import LocalContextMiddleware


def _get_interrupt_config(mode_id: str) -> dict:
    """Get interrupt configuration for a given mode."""
    mode_to_interrupt = {
        "ask_before_edits": {
            "edit_file": {"allowed_decisions": ["approve", "reject"]},
            "write_file": {"allowed_decisions": ["approve", "reject"]},
            "write_todos": {"allowed_decisions": ["approve", "reject"]},
            "execute": {"allowed_decisions": ["approve", "reject"]},
        },
        "accept_edits": {
            "write_todos": {"allowed_decisions": ["approve", "reject"]},
            "execute": {"allowed_decisions": ["approve", "reject"]},
        },
        "accept_everything": {},
    }
    return mode_to_interrupt.get(mode_id, {})


async def _serve_example_agent() -> None:
    """Run example agent from the root of the repository with ACP integration."""
    load_dotenv()

    checkpointer: Checkpointer = MemorySaver()

    def build_agent(context: AgentSessionContext) -> CompiledStateGraph:
        """Agent factory based in the given root directory."""
        _root_dir = context.cwd
        interrupt_config = _get_interrupt_config(context.mode)

        ephemeral_backend = StateBackend()
        shell_env = os.environ.copy()

        # Use CLIShellBackend for filesystem + shell execution.
        # Provides `execute` tool via FilesystemMiddleware with per-command
        # timeout support.
        shell_backend = LocalShellBackend(
            root_dir=_root_dir,
            inherit_env=True,
            env=shell_env,
        )
        backend = CompositeBackend(
            default=shell_backend,
            routes={
                "/memories/": ephemeral_backend,
                "/conversation_history/": ephemeral_backend,
            },
        )

        return create_deep_agent(
            # Falls back to Deep Agent default model if not provided
            model=context.model,
            checkpointer=checkpointer,
            backend=backend,
            interrupt_on=interrupt_config,
            middleware=[LocalContextMiddleware(backend=backend)],
        )

    modes = SessionModeState(
        current_mode_id="accept_edits",
        available_modes=[
            SessionMode(
                id="ask_before_edits",
                name="Ask before edits",
                description="Ask permission before edits, writes, shell commands, and plans",
            ),
            SessionMode(
                id="accept_edits",
                name="Accept edits",
                description="Auto-accept edit operations, but ask before shell commands and plans",
            ),
            SessionMode(
                id="accept_everything",
                name="Accept everything",
                description="Auto-accept all operations without asking permission",
            ),
        ],
    )

    # Define available models for dynamic switching
    # 从环境变量加载自定义模型
    # Anthropic 协议: ANTHROPIC_BASE_URL / API_KEY / MODEL（ChatAnthropic 自动读取 env）
    anthropic_models = load_anthropic_model()
    # OpenAI 兼容协议: CUSTOM_LLM_* 环境变量
    custom_models = load_custom_models()

    # 内置模型
    builtin_models = [
        {"value": "baseten:moonshotai/Kimi-K2.6", "name": "Kimi-K2.6"},
        {"value": "baseten:zai-org/GLM-5", "name": "GLM-5"},
        {"value": "anthropic:claude-opus-4-7", "name": "Claude Opus 4.7"},
        {"value": "anthropic:claude-sonnet-4-6", "name": "Claude Sonnet 4.6"},
        {"value": "anthropic:claude-haiku-4-5", "name": "Claude Haiku 4.5"},
        {"value": "openai:gpt-5.5", "name": "GPT-5.5"},
        {"value": "openai:gpt-5.4-pro", "name": "GPT-5.4 Pro"},
        {"value": "openai:gpt-5.3-codex", "name": "GPT-5.3 Codex"},
    ]

    # 合并: Anthropic 自定义 > OpenAI 兼容自定义 > 内置模型
    models = anthropic_models + custom_models + builtin_models

    acp_agent = AgentServerACP(agent=build_agent, modes=modes, models=models)
    await run_acp_agent(acp_agent)


def main() -> None:
    """Run the demo agent."""
    asyncio.run(_serve_example_agent())


if __name__ == "__main__":
    main()
