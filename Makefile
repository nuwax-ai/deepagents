###############################################################################
# nuwax-deepagents — 项目根目录 Makefile
#
# 用法:
#   make help            # 查看所有可用命令
#   make install         # 安装 ACP agent 到本地
#   make run             # 启动 ACP agent
#   make build           # 构建所有包
#   make test            # 运行所有测试
#
###############################################################################

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ACP_DIR      := $(MAKEFILE_DIR)libs/acp
BUILD_SCRIPT := $(MAKEFILE_DIR)scripts/build.sh

# 所有含 Makefile 的 lib 子包
LIB_DIRS := $(sort $(patsubst %/,%,$(dir $(wildcard $(MAKEFILE_DIR)libs/*/Makefile))))

.PHONY: help install uninstall run build test lint format clean

.DEFAULT_GOAL := help

######################
# ACP AGENT
######################

install: ## 安装 ACP agent 到本地（editable 模式 + CLI 命令）
	@$(MAKE) -C "$(ACP_DIR)" install

uninstall: ## 卸载 ACP agent
	@$(MAKE) -C "$(ACP_DIR)" uninstall

run: ## 启动 ACP agent
	@$(MAKE) -C "$(ACP_DIR)" run

######################
# BUILD / TEST
######################

PKG ?= all

build: ## 构建包（PKG=acp|code|deepagents|cli|evals|all，默认 all）
	@bash "$(BUILD_SCRIPT)" build $(PKG)

test: ## 运行测试（PKG=acp|code|deepagents|cli|evals|all，默认 all）
	@bash "$(BUILD_SCRIPT)" test $(PKG)

######################
# LINT / FORMAT
######################

lint: ## 代码检查所有包
	@$(MAKE) -C "$(MAKEFILE_DIR)libs" lint

format: ## 格式化所有包
	@$(MAKE) -C "$(MAKEFILE_DIR)libs" format

######################
# CLEAN
######################

clean: ## 清理构建产物
	@rm -rf "$(MAKEFILE_DIR)nuwax-dist"
	@echo "✓ 已清理 nuwax-dist/"

######################
# HELP
######################

help: ## 显示帮助信息
	@echo ""
	@echo "nuwax-deepagents — 项目根目录"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "ACP Agent:"
	@echo "  make install        安装 ACP agent 到本地"
	@echo "  make uninstall      卸载 ACP agent"
	@echo "  make run            启动 ACP agent"
	@echo ""
	@echo "Build / Test:"
	@echo "  make build          构建所有包（PKG=acp|code|...|all）"
	@echo "  make test           运行所有测试（PKG=acp|code|...|all）"
	@echo "  make lint           代码检查"
	@echo "  make format         代码格式化"
	@echo ""
	@echo "Other:"
	@echo "  make clean          清理构建产物"
	@echo ""
	@echo "Examples:"
	@echo "  make install                    # 安装 ACP agent"
	@echo "  make build PKG=acp              # 只构建 ACP"
	@echo "  make test PKG=acp               # 只测试 ACP"
	@echo ""
