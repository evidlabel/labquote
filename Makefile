# labquote — self-documenting makefile
# any target: `make <target>` · this overview: `make` or `make help`
.DEFAULT_GOAL := help
PDF := /tmp/opencode/labquote-main.pdf

help: ## show this overview
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: ## sync lib.typ into the local typst package cache
	./local_install.sh install

demo: ## compile the template demo (template/main.typ → PDF)
	@$(MAKE) --no-print-directory -s install
	typst compile --root . template/main.typ $(PDF)
	@echo "demo PDF: $(PDF)"

preview: ## compile demo + refresh preview.png (needs imagemagick)
	@$(MAKE) --no-print-directory -s install
	typst compile --root . template/main.typ template/main.pdf
	cd template && ./preview.sh && mv preview.png ../preview.png

check: ## run the full pre-commit suite (lint/build) on all files
	pre-commit run --all-files

hook: ## wire the pre-commit hook into .git/hooks
	pre-commit install

clean: ## remove build artefacts
	rm -f template/main.pdf
