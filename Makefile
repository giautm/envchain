BINARY_NAME=envchain
PREFIX=/usr/local
BIN_PATH=$(PREFIX)/bin/$(BINARY_NAME)
ARCH=$(shell uname -m)
OS=$(shell uname -s)
DIST_DIR=dist

ifeq ($(OS),Linux)
	TRIPLE=$(ARCH)-linux-gnu
	SHA_CMD=sha256sum
else
	TRIPLE=$(ARCH)-apple-darwin
	SHA_CMD=shasum -a 256
endif

TARBALL=$(DIST_DIR)/$(BINARY_NAME)-$(TRIPLE).tar.gz
all:
	swift build -c release

build:
	swift build

test:
ifeq ($(OS),Linux)
	eval "$$(dbus-launch --sh-syntax)" && echo "" | gnome-keyring-daemon --unlock --components=secrets && swift test
else
	swift test
endif

package: all
	mkdir -p $(DIST_DIR)
	cp .build/release/$(BINARY_NAME) $(DIST_DIR)/$(BINARY_NAME)
	cd $(DIST_DIR) && tar czf $(BINARY_NAME)-$(TRIPLE).tar.gz $(BINARY_NAME)
	cd $(DIST_DIR) && $(SHA_CMD) $(BINARY_NAME)-$(TRIPLE).tar.gz > $(BINARY_NAME)-$(TRIPLE).tar.gz.sha256
	rm $(DIST_DIR)/$(BINARY_NAME)

install: all
	@echo "Installing to $(BIN_PATH) (may require sudo)"
	sudo install -m 755 .build/release/$(BINARY_NAME) $(BIN_PATH)

clean:
	swift package clean
	rm -rf $(DIST_DIR)
