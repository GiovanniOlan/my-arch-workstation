.PHONY: install install-claude uninstall status

AI := ai

# Crea (o reemplaza) un symlink en $(2) -> $(1), pero nunca pisa un archivo/carpeta real.
define link
	@if [ -L "$(2)" ] || [ ! -e "$(2)" ]; then \
		rm -rf "$(2)"; \
		mkdir -p "$$(dirname "$(2)")"; \
		ln -s "$(1)" "$(2)"; \
		echo "linked $(2) -> $(1)"; \
	else \
		echo "skip $(2): existe y no es un symlink (revisar a mano)"; \
	fi
endef

install: install-claude

install-claude:
	$(call link,../$(AI)/AGENTS.md,.claude/CLAUDE.md)
	$(call link,../$(AI)/commands,.claude/commands)
	$(call link,../$(AI)/skills,.claude/skills)

uninstall:
	rm -f .claude/CLAUDE.md .claude/commands .claude/skills

status:
	@for f in .claude/CLAUDE.md .claude/commands .claude/skills; do \
		if [ -L "$$f" ]; then \
			echo "$$f -> $$(readlink "$$f")"; \
		elif [ -e "$$f" ]; then \
			echo "$$f (no es symlink)"; \
		else \
			echo "$$f (no instalado)"; \
		fi; \
	done
