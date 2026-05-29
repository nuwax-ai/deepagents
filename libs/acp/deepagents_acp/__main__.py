"""Entry point for running the ACP server as a module."""

import asyncio

from deepagents_acp.server import _serve_test_agent


def main() -> None:
    """Run the test ACP agent server."""
    asyncio.run(_serve_test_agent())


def run() -> None:
    """Run the demo coding agent with custom model support.

    Entry point for the ``deepagents-acp`` CLI command (registered via
    ``[project.scripts]`` in pyproject.toml).
    """
    from deepagents_acp.agent import main as agent_main

    agent_main()


if __name__ == "__main__":
    main()
