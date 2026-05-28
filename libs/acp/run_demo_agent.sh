#!/bin/bash
# Wrapper script to run deepagents-acp with the deps in the script directory
# but with the current working directory preserved.
#
# Usage:
#   ./run_demo_agent.sh          # 默认启动（读取 .env）
#   ./run_demo_agent.sh 1        # 启动实例 1（读取 .env.1）
#   ./run_demo_agent.sh 2        # 启动实例 2（读取 .env.2）
SCRIPT_DIR="$(dirname "$0")"

# 支持传入实例后缀，加载对应的 .env.N 文件
if [ -n "$1" ]; then
    ENV_FILE="$SCRIPT_DIR/.env.$1"
    if [ -f "$ENV_FILE" ]; then
        echo "[INFO] Loading env file: $ENV_FILE"
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
    else
        echo "[WARN] Env file not found: $ENV_FILE" >&2
    fi
fi

uv run --project "$SCRIPT_DIR" python "$SCRIPT_DIR/examples/demo_agent.py"
