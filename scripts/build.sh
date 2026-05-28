#!/usr/bin/env bash
# ============================================================================
# build.sh — Deep Agents 项目一键构建脚本
# ============================================================================
#
# 所有包均为纯 Python (py3-none-any)，本地构建一次即可在以下平台通用:
#   macOS   (amd64 / arm64)
#   Linux   (amd64 / arm64 / musl)
#   Windows (amd64 / arm64)
#
# 项目结构:
#   libs/deepagents  (core)  — 核心框架        setuptools   Python >=3.11
#   libs/cli         (cli)   — CLI 部署工具    hatchling    Python >=3.11
#   libs/code        (code)  — 终端编码智能体  hatchling    Python >=3.11
#   libs/acp         (acp)   — ACP 服务器      hatchling    Python >=3.11
#   libs/evals       (evals) — 评测套件        setuptools   Python >=3.12,<3.14
#   libs/partners/*          — 沙箱/运行时插件 (editable 依赖)
#   libs/cli/frontend        — React/Vite 前端
#
# 用法:
#   scripts/build.sh [命令] [参数]
#
# 示例:
#   scripts/build.sh                      # 交互式菜单
#   scripts/build.sh all                  # 构建所有包 (wheel + sdist)
#   scripts/build.sh code                 # 只构建 deepagents-code
#   scripts/build.sh dist                 # 完整分发构建 (前端 + Python 包)
#   scripts/build.sh install code         # 本地 editable 安装 dcode
#   scripts/build.sh test code            # 测试 deepagents-code
#   scripts/build.sh check                # CI 预检: lint + test
#   scripts/build.sh verify               # 校验产物跨平台兼容性
#
# 环境变量:
#   PYTHON_VERSION     Python 版本       (默认: 3.12)
#   DIST_DIR           产物输出目录      (默认: ./nuwax-dist)
#   UV_BIN             uv 二进制路径     (自动检测)
#   FORCE_COLOR        强制彩色输出      (默认: 0)
#
# ============================================================================

set -euo pipefail

# ============================================================================
# 全局常量
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_DIR
DIST_DIR="${DIST_DIR:-${SCRIPT_DIR}/nuwax-dist}"
readonly DIST_DIR
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
readonly PYTHON_VERSION
UV_BIN="${UV_BIN:-uv}"

# 子包注册表: key → 路径 | 构建后端 | Python 版本要求
declare -A PKG_REGISTRY=(
  [core]="libs/deepagents|setuptools|>=3.11"
  [cli]="libs/cli|hatchling|>=3.11"
  [code]="libs/code|hatchling|>=3.11"
  [acp]="libs/acp|hatchling|>=3.11"
  [evals]="libs/evals|setuptools|>=3.12,<3.14"
)

# 依赖拓扑排序: core → (cli, code, acp) → evals
readonly BUILD_ORDER=(core cli code acp evals)

# ============================================================================
# 终端 UI
# ============================================================================
if [ -t 1 ] || [ "${FORCE_COLOR:-}" = "1" ]; then
  readonly C_RED='\033[0;31m'
  readonly C_GREEN='\033[0;32m'
  readonly C_YELLOW='\033[0;33m'
  readonly C_BLUE='\033[0;34m'
  readonly C_CYAN='\033[0;36m'
  readonly C_BOLD='\033[1m'
  readonly C_DIM='\033[2m'
  readonly C_NC='\033[0m'
else
  readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
  readonly C_CYAN='' C_BOLD='' C_DIM='' C_NC=''
fi

log_info()    { printf '%s' "${C_CYAN}"; printf '[INFO]  %s' "$*"; printf '%s\n' "${C_NC}"; }
log_ok()      { printf '%s' "${C_GREEN}"; printf '[ OK ]  %s' "$*"; printf '%s\n' "${C_NC}"; }
log_warn()    { printf '%s' "${C_YELLOW}" >&2; printf '[WARN]  %s' "$*" >&2; printf '%s\n' "${C_NC}" >&2; }
log_err()     { printf '%s' "${C_RED}" >&2; printf '[ERR ]  %s' "$*" >&2; printf '%s\n' "${C_NC}" >&2; }
log_step()    { printf '\n%s%s' "${C_BLUE}" "${C_BOLD}"; printf '━━━ %s ━━━' "$*"; printf '%s\n' "${C_NC}"; }
log_pkg()     { printf '  %s' "${C_DIM}"; printf '[%-5s]' "$1"; printf '%s' "${C_NC}"; printf ' %s\n' "$2"; }
log_time()    { printf '  %s' "${C_DIM}"; printf '耗时: %s' "$1"; printf '%s\n' "${C_NC}"; }

# ============================================================================
# 平台检测
# ============================================================================
detect_platform() {
  OS="$(uname -s)"
  ARCH="$(uname -m)"

  case "$OS" in
    Darwin)
      PLATFORM="macos"
      [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]] && ARCH="arm64"
      ;;
    Linux)
      PLATFORM="linux"
      [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
      [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      PLATFORM="windows"
      [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
      [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && ARCH="arm64"
      ;;
    *)
      PLATFORM="unknown"
      ;;
  esac

  PLATFORM_TAG="${PLATFORM}-${ARCH}"
}
detect_platform

# ============================================================================
# 前置依赖检查 (Fail Fast)
# ============================================================================
check_prereqs() {
  local fatal=0

  if ! command -v "$UV_BIN" &>/dev/null; then
    if command -v uv &>/dev/null; then
      UV_BIN="uv"
    else
      log_err "uv 未安装"
      log_err "  安装: curl -LsSf https://astral.sh/uv/install.sh | sh"
      fatal=1
    fi
  fi

  if ! command -v python3 &>/dev/null; then
    log_err "python3 未安装"
    fatal=1
  fi

  if [ "$fatal" -eq 1 ]; then
    exit 1
  fi

  command -v node &>/dev/null || log_warn "node 未安装 → 前端构建将被跳过"
  command -v npm &>/dev/null  || log_warn "npm 未安装 → 前端构建将被跳过"
}

# ============================================================================
# 工具函数
# ============================================================================
get_version() {
  local toml="${SCRIPT_DIR}/$1/pyproject.toml"
  [ -f "$toml" ] && grep -m1 '^version' "$toml" | sed 's/.*"\(.*\)"/\1/' || echo "unknown"
}

get_name() {
  local toml="${SCRIPT_DIR}/$1/pyproject.toml"
  [ -f "$toml" ] && grep -m1 '^name' "$toml" | sed 's/.*"\(.*\)"/\1/' || echo "unknown"
}

get_pkg_path() {
  echo "${PKG_REGISTRY[$1]}" | cut -d'|' -f1
}

get_pkg_backend() {
  echo "${PKG_REGISTRY[$1]}" | cut -d'|' -f2
}

get_pkg_pyver() {
  echo "${PKG_REGISTRY[$1]}" | cut -d'|' -f3
}

resolve_python_version() {
  local key="$1"
  local constraint
  constraint=$(get_pkg_pyver "$key")
  case "$constraint" in
    ">=3.14")
      echo "3.14"
      ;;
    ">=3.12,<3.14")
      # evals 要求 >=3.12,<3.14; 自动 clamp 到有效范围
      case "$PYTHON_VERSION" in
        3.11)  echo "3.12" ;;
        3.14|3.15|3.16|4.*) echo "3.13" ;;
        *)     echo "$PYTHON_VERSION" ;;
      esac
      ;;
    *)
      echo "$PYTHON_VERSION"
      ;;
  esac
}

resolve_pkg_key() {
  local input="$1"
  case "$input" in
    core|deepagents)              echo "core" ;;
    cli|deepagents-cli)           echo "cli" ;;
    code|deepagents-code|dcode)   echo "code" ;;
    acp|deepagents-acp)           echo "acp" ;;
    evals|deepagents-evals)       echo "evals" ;;
    all)                          echo "all" ;;
    *)
      log_err "未知包: $input"
      log_err "可选: core, cli, code, acp, evals, all"
      return 1
      ;;
  esac
}

_timer=0
timer_start() { _timer=$(date +%s); }
timer_elapsed() {
  local now
  now=$(date +%s)
  local d=$((now - _timer))
  printf "%dm%02ds" $((d / 60)) $((d % 60))
}

# ============================================================================
# lock — 锁定依赖
# ============================================================================
cmd_lock() {
  log_step "锁定所有包依赖 (uv lock)"
  timer_start

  for key in "${BUILD_ORDER[@]}"; do
    local pkg_path
    pkg_path=$(get_pkg_path "$key")
    local pyver
    pyver=$(resolve_python_version "$key")
    log_pkg "$key" "uv lock --python ${pyver}"
    (cd "${SCRIPT_DIR}/${pkg_path}" && "$UV_BIN" lock --python "$pyver")
  done

  log_ok "依赖锁定完成"
  log_time "$(timer_elapsed)"
}

# ============================================================================
# build — 构建 wheel + sdist
# ============================================================================
_build_single() {
  local key="$1"
  local pkg_path
  pkg_path=$(get_pkg_path "$key")
  local name
  name=$(get_name "$pkg_path")
  local ver
  ver=$(get_version "$pkg_path")

  log_pkg "$key" "构建 ${name} v${ver} ($(get_pkg_backend "$key"))"

  # 记录构建前已有产物，用于后续仅展示本次新增
  local _before
  _before=$(find "$DIST_DIR" -maxdepth 1 \( -name '*.whl' -o -name '*.tar.gz' \) -exec basename {} \; 2>/dev/null)

  (cd "${SCRIPT_DIR}/${pkg_path}" && "$UV_BIN" build --out-dir "${DIST_DIR}")

  local _after
  _after=$(find "$DIST_DIR" -maxdepth 1 \( -name '*.whl' -o -name '*.tar.gz' \) -exec basename {} \; 2>/dev/null)

  # 筛选出本次新增的产物
  local _new
  _new=$(comm -13 <(echo "$_before" | sort) <(echo "$_after" | sort))
  if [ -n "$_new" ]; then
    while IFS= read -r line; do
      _LAST_BUILD_ARTIFACTS+=("$line")
    done <<< "$_new"
  fi
}

cmd_build() {
  local target="${1:-all}"
  local key
  key=$(resolve_pkg_key "$target")

  log_step "构建 Python 包 → ${DIST_DIR}"
  timer_start
  mkdir -p "$DIST_DIR"

  _LAST_BUILD_ARTIFACTS=()

  if [ "$key" = "all" ]; then
    for k in "${BUILD_ORDER[@]}"; do
      _build_single "$k"
    done
  else
    _build_single "$key"
  fi

  log_ok "构建完成"
  log_time "$(timer_elapsed)"

  if [ ${#_LAST_BUILD_ARTIFACTS[@]} -gt 0 ]; then
    echo ""
    log_info "本次产物:"
    local f
    for f in "${_LAST_BUILD_ARTIFACTS[@]}"; do
      [ -f "${DIST_DIR}/${f}" ] && printf '  %-55s %s\n' "$f" "$(du -h "${DIST_DIR}/${f}" | cut -f1)"
    done
  fi
}

# ============================================================================
# frontend — 构建 React/Vite 前端
# ============================================================================
cmd_frontend() {
  local src="libs/cli/frontend"
  local dest="libs/cli/deepagents_cli/deploy/frontend_dist"

  log_step "构建 CLI 前端 (Vite + React)"
  timer_start

  if ! command -v npm &>/dev/null; then
    log_err "npm 未安装，无法构建前端"
    log_err "  安装: https://nodejs.org/"
    return 1
  fi

  (cd "${SCRIPT_DIR}/${src}" && npm ci && npm run build)

  rm -rf "${SCRIPT_DIR:?}/${dest}"
  mkdir -p "${SCRIPT_DIR:?}/${dest}"
  cp -R "${SCRIPT_DIR:?}/${src}/dist/." "${SCRIPT_DIR:?}/${dest}/"

  log_ok "前端构建完成 → ${dest}"
  log_time "$(timer_elapsed)"
}

# ============================================================================
# dist — 完整分发构建 (前端 + 所有 Python 包)
# ============================================================================
cmd_dist() {
  local target="${1:-all}"

  log_step "完整分发构建 (前端 + Python 包)"
  timer_start

  # 1. 前端
  if command -v npm &>/dev/null; then
    cmd_frontend
  else
    log_warn "跳过前端构建 (npm 未安装)"
  fi

  # 2. Python 包
  cmd_build "$target"

  # 3. twine 校验 — 收集实际存在的文件，避免 glob 未展开传给 twine 字面量
  local _twine_files=()
  for _f in "${DIST_DIR}"/*.whl "${DIST_DIR}"/*.tar.gz; do
    [ -f "$_f" ] && _twine_files+=("$_f")
  done
  if [ ${#_twine_files[@]} -gt 0 ]; then
    if "$UV_BIN" run --with twine twine check "${_twine_files[@]}" 2>/dev/null; then
      log_ok "twine check 通过"
    else
      log_warn "twine 校验失败或 twine 未安装 (pip install twine)"
    fi
  else
    log_warn "无产物文件，跳过 twine 校验"
  fi

  log_ok "分发构建全部完成"
  log_time "$(timer_elapsed)"
}

# ============================================================================
# verify — 校验产物跨平台兼容性
# ============================================================================
cmd_verify() {
  log_step "校验产物跨平台兼容性"
  timer_start

  local _has_whl=false
  for _f in "${DIST_DIR}"/*.whl; do
    [ -f "$_f" ] && _has_whl=true && break
  done
  if [ "$_has_whl" = false ]; then
    log_err "nuwax-dist/ 目录为空，请先执行构建: scripts/build.sh all"
    return 1
  fi

  local all_ok=true
  local total=0
  local universal=0

  for f in "${DIST_DIR}"/*.whl; do
    [ -f "$f" ] || continue
    total=$((total + 1))
    local name
    name=$(basename "$f")

    # wheel 命名规范: {name}-{ver}-{python}-{abi}-{platform}.whl
    # py3-none-any = 纯 Python, 全平台通用
    if echo "$name" | grep -q 'py3-none-any\.whl$'; then
      universal=$((universal + 1))
      printf '  %s✓%s %-55s 全平台通用\n' "${C_GREEN}" "${C_NC}" "$name"
    elif echo "$name" | grep -q 'py2\.py3-none-any\.whl$'; then
      universal=$((universal + 1))
      printf '  %s✓%s %-55s 全平台通用\n' "${C_GREEN}" "${C_NC}" "$name"
    else
      all_ok=false
      printf '  %s!%s %-55s 平台相关\n' "${C_YELLOW}" "${C_NC}" "$name"
    fi
  done

  echo ""
  log_info "总计: ${total} 个 wheel, 其中 ${universal} 个全平台通用"

  # 列出兼容的目标平台
  if [ "$universal" -gt 0 ]; then
    echo ""
    log_info "py3-none-any wheel 可在以下平台直接安装:"
    printf '  %s%s%s\n' "${C_DIM}" \
      "macOS   — amd64 (Intel), arm64 (Apple Silicon)" "${C_NC}"
    printf '  %s%s%s\n' "${C_DIM}" \
      "Linux   — amd64, arm64, musl (Alpine)" "${C_NC}"
    printf '  %s%s%s\n' "${C_DIM}" \
      "Windows — amd64, arm64" "${C_NC}"
  fi

  # 检查 sdist
  local sdist_count
  sdist_count=$(find "$DIST_DIR" -maxdepth 1 -name "*.tar.gz" | wc -l | tr -d ' ')
  if [ "$sdist_count" -gt 0 ]; then
    echo ""
    log_info "源码分发包 (sdist): ${sdist_count} 个"
    for f in "${DIST_DIR}"/*.tar.gz; do
      [ -f "$f" ] && printf "  %-55s %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
    done
  fi

  if [ "$all_ok" = true ]; then
    log_ok "所有产物均为全平台通用"
  else
    log_warn "存在平台相关产物，需要按平台分别构建"
  fi

  log_time "$(timer_elapsed)"
}

# ============================================================================
# install — 本地 editable 安装
# ============================================================================
cmd_install() {
  local target="${1:-code}"
  local key
  key=$(resolve_pkg_key "$target")

  log_step "本地 editable 安装 (uv tool install -e)"
  timer_start

  _install_single() {
    local k="$1"
    local pkg_path
    pkg_path=$(get_pkg_path "$k")
    local pyver
    pyver=$(resolve_python_version "$k")
    log_pkg "$k" "uv tool install --python ${pyver} -e ."
    (cd "${SCRIPT_DIR}/${pkg_path}" && "$UV_BIN" tool install --reinstall --python "$pyver" -e .)
  }

  if [ "$key" = "all" ]; then
    for k in "${BUILD_ORDER[@]}"; do
      _install_single "$k"
    done
  else
    _install_single "$key"
  fi

  log_ok "安装完成"
  log_time "$(timer_elapsed)"
}

# ============================================================================
# test — 运行测试
# ============================================================================
cmd_test() {
  local target="${1:-all}"
  local key
  key=$(resolve_pkg_key "$target")

  log_step "运行测试 (pytest)"
  timer_start

  _test_single() {
    local k="$1"
    local pkg_path
    pkg_path=$(get_pkg_path "$k")
    local full="${SCRIPT_DIR}/${pkg_path}"
    local pytest_args=(--disable-socket --allow-unix-socket)

    # pytest-xdist (-n auto) 仅在包声明了该依赖时使用
    if grep -q 'pytest-xdist' "${full}/pyproject.toml" 2>/dev/null; then
      pytest_args+=(-n auto)
      log_pkg "$k" "pytest -n auto"
    else
      log_pkg "$k" "pytest (无 xdist, 串行)"
    fi

    (cd "$full" && \
      UV_FROZEN=true "$UV_BIN" run --group test \
        pytest "${pytest_args[@]}" tests/) || return 1
  }

  local failed=()
  if [ "$key" = "all" ]; then
    for k in "${BUILD_ORDER[@]}"; do
      _test_single "$k" || failed+=("$k")
    done
  else
    _test_single "$key" || failed+=("$key")
  fi

  if [ ${#failed[@]} -gt 0 ]; then
    log_err "测试失败: ${failed[*]}"
    return 1
  fi

  log_ok "测试全部通过"
  log_time "$(timer_elapsed)"
}

# ============================================================================
# lint — 代码检查
# ============================================================================
cmd_lint() {
  local target="${1:-all}"
  local key
  key=$(resolve_pkg_key "$target")

  log_step "代码检查 (ruff + ty)"
  timer_start

  _lint_single() {
    local k="$1"
    local pkg_path
    pkg_path=$(get_pkg_path "$k")
    log_pkg "$k" "ruff check + ruff format --diff + ty check"
    (cd "${SCRIPT_DIR}/${pkg_path}" && \
      UV_FROZEN=true "$UV_BIN" run --group test ruff check . && \
      UV_FROZEN=true "$UV_BIN" run --group test ruff format . --diff && \
      UV_FROZEN=true "$UV_BIN" run --group test ty check .) || return 1
  }

  local failed=()
  if [ "$key" = "all" ]; then
    for k in "${BUILD_ORDER[@]}"; do
      _lint_single "$k" || failed+=("$k")
    done
  else
    _lint_single "$key" || failed+=("$key")
  fi

  if [ ${#failed[@]} -gt 0 ]; then
    log_err "lint 失败: ${failed[*]}"
    return 1
  fi

  log_ok "lint 通过"
  log_time "$(timer_elapsed)"
}

# ============================================================================
# format — 自动格式化
# ============================================================================
cmd_format() {
  local target="${1:-all}"
  local key
  key=$(resolve_pkg_key "$target")

  log_step "代码格式化 (ruff format + ruff check --fix)"
  timer_start

  _format_single() {
    local k="$1"
    local pkg_path
    pkg_path=$(get_pkg_path "$k")
    log_pkg "$k" "ruff format + ruff check --fix"
    (cd "${SCRIPT_DIR}/${pkg_path}" && \
      UV_FROZEN=true "$UV_BIN" run --group test ruff format . && \
      UV_FROZEN=true "$UV_BIN" run --group test ruff check --fix .) || return 1
  }

  local failed=()
  if [ "$key" = "all" ]; then
    for k in "${BUILD_ORDER[@]}"; do
      _format_single "$k" || failed+=("$k")
    done
  else
    _format_single "$key" || failed+=("$key")
  fi

  if [ ${#failed[@]} -gt 0 ]; then
    log_err "格式化失败: ${failed[*]}"
    return 1
  fi

  log_ok "格式化完成"
  log_time "$(timer_elapsed)"
}

# ============================================================================
# check — CI 预检 (lint + test)
# ============================================================================
cmd_check() {
  local target="${1:-all}"

  log_step "CI 预检: lint + test"
  local _check_start
  _check_start=$(date +%s)

  cmd_lint "$target"
  cmd_test "$target"

  local _check_end
  _check_end=$(date +%s)
  local _check_elapsed=$(( _check_end - _check_start ))
  log_ok "CI 预检全部通过"
  printf '  %s耗时: %dm%02ds%s\n' "${C_DIM}" $((_check_elapsed / 60)) $((_check_elapsed % 60)) "${C_NC}"
}

# ============================================================================
# clean — 清理构建产物
# ============================================================================
cmd_clean() {
  log_step "清理构建产物"

  rm -rf "${DIST_DIR:?}"
  log_info "✓ ${DIST_DIR}"

  for key in "${BUILD_ORDER[@]}"; do
    local pkg_path
    pkg_path=$(get_pkg_path "$key")
    local full="${SCRIPT_DIR:?}/${pkg_path}"
    rm -rf "${full}/dist" "${full}/build"
    rm -rf "${full}/"*.egg-info
    find "$full" -type d \( \
      -name "__pycache__" -o \
      -name ".mypy_cache" -o \
      -name ".pytest_cache" -o \
      -name ".ruff_cache" -o \
      -name ".ty" \
    \) -exec rm -rf {} + 2>/dev/null || true
  done
  log_info "✓ 各包 dist/build/__pycache__/缓存"

  rm -rf "${SCRIPT_DIR:?}/libs/cli/frontend/dist"
  rm -rf "${SCRIPT_DIR:?}/libs/cli/frontend/node_modules"
  rm -rf "${SCRIPT_DIR:?}/libs/cli/deepagents_cli/deploy/frontend_dist"
  log_info "✓ 前端 dist/node_modules/frontend_dist"

  rm -rf "${SCRIPT_DIR:?}/.build"
  log_info "✓ .build 临时目录"

  log_ok "清理完成"
}

# ============================================================================
# status — 项目状态总览
# ============================================================================
cmd_status() {
  log_step "项目状态"

  echo ""
  printf '  %s%-6s  %-22s  %-8s  %-12s  %s%s\n' "${C_BOLD}" "别名" "包名" "版本" "构建后端" "路径" "${C_NC}"
  printf '  %-6s  %-22s  %-8s  %-12s  %s\n' "────" "────────────────────" "──────" "─────────" "──────────────"

  for key in "${BUILD_ORDER[@]}"; do
    local pkg_path
    pkg_path=$(get_pkg_path "$key")
    printf "  %-6s  %-22s  %-8s  %-12s  %s\n" \
      "$key" \
      "$(get_name "$pkg_path")" \
      "v$(get_version "$pkg_path")" \
      "$(get_pkg_backend "$key")" \
      "$pkg_path"
  done

  echo ""
  log_info "当前平台:  ${PLATFORM_TAG}"
  log_info "Python:    ${PYTHON_VERSION}"
  log_info "uv:        $("${UV_BIN}" --version 2>/dev/null || echo '未安装')"
  log_info "node:      $(node --version 2>/dev/null || echo '未安装')"
  log_info "npm:       $(npm --version 2>/dev/null || echo '未安装')"

  if [ -d "${SCRIPT_DIR}/.git" ]; then
    local branch
    branch=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null || echo "detached")
    local dirty=""
    [ -n "$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null)" ] && dirty=" ${C_YELLOW}(dirty)${C_NC}"
    log_info "git:       ${branch}${dirty}"
  fi
}

# ============================================================================
# run — 快速启动
# ============================================================================
cmd_run() {
  local target="${1:-code}"
  local key
  key=$(resolve_pkg_key "$target") || return 1

  # 提前校验: run 仅支持 code 和 cli
  if [[ "$key" != "code" && "$key" != "cli" ]]; then
    log_err "run 命令仅支持 code 和 cli (当前: $target)"
    return 1
  fi

  shift 2>/dev/null || true

  local pkg_path
  pkg_path=$(get_pkg_path "$key")

  case "$key" in
    code)
      log_info "启动 deepagents-code (dcode)..."
      (cd "${SCRIPT_DIR}/${pkg_path}" && UV_FROZEN=true "$UV_BIN" run deepagents-code "$@")
      ;;
    cli)
      log_info "启动 deepagents-cli..."
      (cd "${SCRIPT_DIR}/${pkg_path}" && UV_FROZEN=true "$UV_BIN" run deepagents "$@")
      ;;
  esac
}

# ============================================================================
# 交互式菜单
# ============================================================================
interactive_menu() {
  echo ""
  printf '%sDeep Agents 构建工具%s' "${C_BOLD}" "${C_NC}"
  printf '  [%s]  Python %s\n' "${PLATFORM_TAG}" "${PYTHON_VERSION}"
  echo ""
  echo "  ┌─ 构建 ─────────────────────────────┐"
  echo "  │  1) all       构建所有包            │"
  echo "  │  2) code      deepagents-code       │"
  echo "  │  3) cli       deepagents-cli        │"
  echo "  │  4) core      deepagents (核心)     │"
  echo "  │  5) acp       deepagents-acp        │"
  echo "  │  6) evals     deepagents-evals      │"
  echo "  │  7) dist      完整分发 (前端+包)    │"
  echo "  │  8) frontend  构建前端              │"
  echo "  └─────────────────────────────────────┘"
  echo ""
  echo "  ┌─ 开发 ─────────────────────────────┐"
  echo "  │  9) install   本地 editable 安装    │"
  echo "  │  a) test      运行测试              │"
  echo "  │  b) lint      代码检查              │"
  echo "  │  c) format    代码格式化            │"
  echo "  │  d) lock      锁定依赖              │"
  echo "  │  k) check     CI 预检 (lint+test)   │"
  echo "  │  r) run       快速启动              │"
  echo "  └─────────────────────────────────────┘"
  echo ""
  echo "  ┌─ 其他 ─────────────────────────────┐"
  echo "  │  v) verify    校验跨平台兼容性      │"
  echo "  │  s) status    项目状态              │"
  echo "  │  !) clean     清理产物              │"
  echo "  │  q) quit      退出                  │"
  echo "  └─────────────────────────────────────┘"
  echo ""

  printf '%s选择:%s ' "${C_BOLD}" "${C_NC}"
  local choice
  read -r choice

  case "$choice" in
    1) cmd_build all ;;
    2) cmd_build code ;;
    3) cmd_build cli ;;
    4) cmd_build core ;;
    5) cmd_build acp ;;
    6) cmd_build evals ;;
    7) cmd_dist all ;;
    8) cmd_frontend ;;
    9) cmd_install code ;;
    a|A) cmd_test all ;;
    b|B) cmd_lint all ;;
    c|C) cmd_format all ;;
    d|D) cmd_lock ;;
    k|K) cmd_check all ;;
    r|R) cmd_run code ;;
    v|V) cmd_verify ;;
    s|S) cmd_status ;;
    !)   cmd_clean ;;
    q|Q) exit 0 ;;
    *)   log_err "无效选择: $choice"; return 1 ;;
  esac
}

# ============================================================================
# help
# ============================================================================
show_help() {
  cat <<'HELP'

  Deep Agents 一键构建脚本
  ═══════════════════════

  所有包均为纯 Python (py3-none-any)，本地构建一次即可在
  macOS / Linux / Windows (amd64 + arm64) 全平台通用。

  用法: scripts/build.sh <命令> [参数]

  构建命令:
    all [包]            构建所有/指定包 (wheel + sdist)
    dist [包]           完整分发构建 (前端 + Python 包 + twine 校验)
    frontend            构建 CLI 前端 (Vite + React)

  开发命令:
    install [包]        本地 editable 安装 (默认: code)
    test [包]           运行 pytest
    lint [包]           代码检查 (ruff + ty)
    format [包]         代码格式化 (ruff format + ruff check --fix)
    lock                锁定所有包依赖
    check [包]          CI 预检 (lint + test)
    run [code|cli]      快速启动 (默认: code)

  其他:
    verify              校验产物跨平台兼容性
    clean               清理所有构建产物
    status              项目状态总览
    help                显示此帮助

  包名别名:
    core / deepagents         核心框架      libs/deepagents
    cli  / deepagents-cli     CLI 部署工具  libs/cli
    code / dcode              终端编码智能体 libs/code
    acp  / deepagents-acp     ACP 服务器    libs/acp
    evals / deepagents-evals  评测套件      libs/evals
    all                       所有包

  环境变量:
    PYTHON_VERSION=3.12       Python 版本 (默认 3.12)
    DIST_DIR=./nuwax-dist       产物输出目录
    FORCE_COLOR=1             强制彩色输出

  示例:
    scripts/build.sh                        # 交互式菜单
    scripts/build.sh all                    # 构建所有包
    scripts/build.sh code                   # 只构建 deepagents-code
    scripts/build.sh dist                   # 完整分发构建
    scripts/build.sh verify                 # 校验跨平台兼容性
    scripts/build.sh test code              # 测试 deepagents-code
    PYTHON_VERSION=3.13 scripts/build.sh all  # 指定 Python 版本

HELP
}

# ============================================================================
# 主入口
# ============================================================================
main() {
  check_prereqs

  local cmd="${1:-}"

  case "$cmd" in
    "")             interactive_menu ;;
    help|--help|-h) show_help ;;
    all|build)      shift; cmd_build "${1:-all}" ;;
    dist)           shift; cmd_dist "${1:-all}" ;;
    frontend)       cmd_frontend ;;
    install)        shift; cmd_install "${1:-code}" ;;
    test)           shift; cmd_test "${1:-all}" ;;
    lint)           shift; cmd_lint "${1:-all}" ;;
    format)         shift; cmd_format "${1:-all}" ;;
    lock)           cmd_lock ;;
    check)          shift; cmd_check "${1:-all}" ;;
    run)            shift; cmd_run "$@" ;;
    verify)         cmd_verify ;;
    clean)          cmd_clean ;;
    status)         cmd_status ;;
    *)
      if resolve_pkg_key "$cmd" &>/dev/null; then
        cmd_build "$cmd"
      else
        log_err "未知命令: $cmd"
        show_help
        exit 1
      fi
      ;;
  esac
}

main "$@"
