.PHONY: help install-dependencies create-artifact-bucket check test deploy

INPUT_TEMPLATE_FILE := default-sg-remediation.sam.yaml
OUTPUT_TEMPLATE_FILE := .aws-sam/default-sg-remediation-output.yaml
ARTIFACT_BUCKET := default-sg-remediation-artifacts
STACK_NAME := default-sg-remediation
SOURCE_FILES := $(shell find . -type f -path './src/*')
MANIFEST_FILE := ./src/requirements.txt

help: ## This help
	@grep -E -h "^[a-zA-Z_-]+:.*?## " $(MAKEFILE_LIST) \
	  | sort \
	  | awk -v width=36 'BEGIN {FS = ":.*?## "} {printf "\033[36m%-*s\033[0m %s\n", width, $$1, $$2}'

install-dependencies: ## Install pipenv and dependencies
	@echo '*** installing dependencies ***'
	pip3 install pipenv
	pipenv install --dev
	@echo '*** dependencies installed ***'

create-artifact-bucket:  ## Create bucket to upload stack to
	aws s3 mb s3://${ARTIFACT_BUCKET}

check: ## Run linters
	@echo '*** running checks ***'
	flake8
	yamllint -f parsable .
	cfn-lint -f parseable
	@echo '*** all checks passing ***'

test: check ## Run tests
	@echo '*** running tests ***'
	PYTHONPATH=./src pytest --cov=src --cov-branch --cov-report term-missing
	@echo '*** all tests passing ***'

.aws-sam/build/template.yaml: $(INPUT_TEMPLATE_FILE) $(SOURCE_FILES)  ## sam-build target and dependencies
	@echo '*** running SAM build ***'
	SAM_CLI_TELEMETRY=0 \
	sam build \
		--template-file $(INPUT_TEMPLATE_FILE) \
		--manifest $(MANIFEST_FILE) \
		--debug
	@echo '*** done SAM building ***'

$(OUTPUT_TEMPLATE_FILE): $(INPUT_TEMPLATE) .aws-sam/build/template.yaml
	@echo '*** running SAM package ***'
	SAM_CLI_TELEMETRY=0 \
	sam package \
		--s3-bucket $(ARTIFACT_BUCKET) \
		--output-template-file "$(OUTPUT_TEMPLATE_FILE)" \
		--debug
	@echo '*** done SAM packaging ***'

deploy: test $(OUTPUT_TEMPLATE_FILE) ## Deploy stack to AWS
	@echo '*** running SAM deploy ***'
	SAM_CLI_TELEMETRY=0 \
	sam deploy \
		--template-file $(OUTPUT_TEMPLATE_FILE) \
		--stack-name $(STACK_NAME) \
		--s3-bucket $(ARTIFACT_BUCKET) \
		--capabilities "CAPABILITY_IAM" \
		--no-fail-on-empty-changeset
	@echo '*** done SAM deploying ***'