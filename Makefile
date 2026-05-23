BINARY_NAME=envchain
PREFIX=/usr/local
BIN_PATH=$(PREFIX)/bin/$(BINARY_NAME)
ARCH=$(shell uname -m)
DIST_DIR=dist
TARBALL=$(DIST_DIR)/$(BINARY_NAME)-$(ARCH)-apple-darwin.tar.gz
all:
	swift build -c release

build:
	swift build

test:
	eval "$$(dbus-launch --sh-syntax)" && echo "" | gnome-keyring-daemon --unlock --components=secrets && swift test

package: all
	mkdir -p $(DIST_DIR)
	cp .build/release/$(BINARY_NAME) $(DIST_DIR)/$(BINARY_NAME)
	cd $(DIST_DIR) && tar czf $(BINARY_NAME)-$(ARCH)-apple-darwin.tar.gz $(BINARY_NAME)
	cd $(DIST_DIR) && shasum -a 256 $(BINARY_NAME)-$(ARCH)-apple-darwin.tar.gz > $(BINARY_NAME)-$(ARCH)-apple-darwin.tar.gz.sha256
	rm $(DIST_DIR)/$(BINARY_NAME)

install: all
	@echo "Installing to $(BIN_PATH) (may require sudo)"
	sudo install -m 755 .build/release/$(BINARY_NAME) $(BIN_PATH)

clean:
	swift package clean
	rm -rf $(DIST_DIR)
