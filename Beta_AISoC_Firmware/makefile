.PHONY: sanitize
sanitize:
	@echo ">> Fix EOL, BOM, shebang cho script"
	@find . -type f -name "*.sh" -print0 | xargs -0 -I{} sh -c \
		'sed -i "s/\r$$//" "{}"; \
		 sed -i "1s/^\xEF\xBB\xBF//" "{}"; \
		 head -n1 "{}" | grep -q "^#!" || sed -i "1i #!/usr/bin/env bash" "{}"; \
		 chmod +x "{}"'
