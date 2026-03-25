BINARY_NAME := hledger-add-installments
BIN_DIR := bin
INSTALL_DIR := $(HOME)/.local/bin

.PHONY: build install clean

build:
	go build -o $(BIN_DIR)/$(BINARY_NAME) main.go

install: build
	cp $(BIN_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	chmod +x $(INSTALL_DIR)/$(BINARY_NAME)

clean:
	rm -rf $(BIN_DIR)
