EMACS ?= emacs

# Everything Emacs writes at runtime (straight repos, eln cache, grammars)
# goes under this. Defaults to the real cache so lint and test share the
# packages the interactive session uses; point it elsewhere for a clean
# room run: make test CACHE=/tmp/emacs-scratch
CACHE ?=

ifneq ($(CACHE),)
export BISON_EMACS_CACHE_DIR := $(CACHE)
endif

# hunspell refuses to start without a locale, and batch Emacs has none.
export LANG ?= en_US.UTF-8

BATCH := $(EMACS) --batch -Q

.PHONY: all
all: lint test

# checkdoc + byte-compile with warnings as errors. Installs any missing
# package on first run, since use-package ensures at compile time.
.PHONY: lint
lint:
	$(BATCH) -l scripts/lint.el

# Loads the config the way a real session would and checks invariants.
.PHONY: test
test:
	$(BATCH) -l scripts/test.el

# Regenerate versions/default.el from what is currently checked out.
.PHONY: lock
lock:
	$(BATCH) -l scripts/test.el --eval '(straight-freeze-versions t)'

# Check out exactly what the lockfile says.
.PHONY: thaw
thaw:
	$(BATCH) -l scripts/test.el --eval '(straight-thaw-versions)'

# Pull every package to its latest upstream, then re-lock.
.PHONY: update
update:
	$(BATCH) -l scripts/test.el --eval '(straight-pull-all)' --eval '(straight-freeze-versions t)'

# Compile tree-sitter grammars that are missing from the cache.
.PHONY: grammars
grammars:
	$(BATCH) -l scripts/test.el --eval '(bison-treesit-install-grammars)'

.PHONY: clean
clean:
	find . -name '*.elc' -not -path './.git/*' -delete
