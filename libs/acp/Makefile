.PHONY: lint format type typecheck test help test_watch toad install uninstall run

.DEFAULT_GOAL := help

######################
# TESTING AND COVERAGE
######################

# Define a variable for the test file path.
TEST_FILE ?= tests/
PYTEST_EXTRA ?=

test: ## Run unit tests with coverage
	uv run pytest $(PYTEST_EXTRA) --disable-socket --allow-unix-socket $(TEST_FILE) --timeout 10 --cov=deepagents_acp --cov-report=term-missing --cov-report=xml

test_watch: ## Run tests in watch mode
	uv run ptw . -- $(TEST_FILE)

toad: ## Run toad ACP server
	uv run toad acp 'bash ./run.sh'


######################
# INSTALL / RUN
######################

install: ## Install package locally (editable mode + CLI command)
	uv sync --group examples
	@echo ""
	@echo "✓ Installed. CLI command available in venv:"
	@echo "    uv run deepagents-acp"
	@echo ""
	@echo "  Zed ACP config (macOS/Linux):"
	@echo '    "command": "uv", "args": ["run", "--project", "'$$(pwd)'", "deepagents-acp"]'
	@echo ""
	@echo "  Zed ACP config (Windows):"
	@echo '    "command": "uv", "args": ["run", "--project", "C:\\path\\to\\libs\\acp", "deepagents-acp"]'

uninstall: ## Uninstall package from venv
	uv pip uninstall deepagents-acp

run: ## Run demo agent (within venv)
	uv run deepagents-acp


######################
# LINTING AND FORMATTING
######################

# Define a variable for Python and notebook files.
lint format: PYTHON_FILES=deepagents_acp/ tests/
lint_diff format_diff: PYTHON_FILES=$(shell git diff --relative=. --name-only --diff-filter=d main | grep -E '\.py$$|\.ipynb$$')

lint: ## Run linters and type checker
lint lint_diff:
	[ "$(PYTHON_FILES)" = "" ] ||	uv run --group test ruff format $(PYTHON_FILES) --diff
	[ "$(PYTHON_FILES)" = "" ] ||	uv run --group test ruff check $(PYTHON_FILES)
	$(MAKE) type

type: ## Run type checker
type typecheck:
	uv run --group test ty check deepagents_acp

format: ## Run code formatters
format format_diff:
	[ "$(PYTHON_FILES)" = "" ] || uv run --group test ruff format $(PYTHON_FILES)
	[ "$(PYTHON_FILES)" = "" ] || uv run --group test ruff check --fix $(PYTHON_FILES)

######################
# HELP
######################

help: ## Show this help message
	@echo "Usage: make [target] [TEST_FILE=path/to/tests/]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
