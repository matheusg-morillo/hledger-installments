SCRIPT_NAME := hledger-parcela
INSTALL_DIR := $(HOME)/.local/bin

.PHONY: install uninstall

install:
	install -m 755 $(SCRIPT_NAME).hs $(INSTALL_DIR)/$(SCRIPT_NAME)

uninstall:
	rm -f $(INSTALL_DIR)/$(SCRIPT_NAME)
