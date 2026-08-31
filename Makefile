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

# Daemon control. Darwin runs the daemon from a launchd agent, Linux
# from an emacs.service systemd user unit.
.PHONY: emacs-start emacs-stop emacs-restart emacs-reload

ifeq ($(shell uname -s),Darwin)

EMACS_LABEL  := io.xvdf.emacs
EMACS_DOMAIN := gui/$(shell id -u)
EMACS_PLIST  := $(HOME)/Library/LaunchAgents/$(EMACS_LABEL).plist

emacs-start:
	launchctl bootstrap $(EMACS_DOMAIN) $(EMACS_PLIST)

# KeepAlive means launchd respawns the daemon after a plain `launchctl kill`,
# so stopping it for real means unloading the job.
emacs-stop:
	launchctl bootout $(EMACS_DOMAIN)/$(EMACS_LABEL)

# Restarts the process only -- launchd keeps the plist it parsed at bootstrap
# time, so plist edits need emacs-reload.
emacs-restart:
	launchctl kickstart -k $(EMACS_DOMAIN)/$(EMACS_LABEL)

# bootout returns before the job is fully gone, and bootstrapping over one on
# its way out fails with a bare "Input/output error", so wait for the job to
# disappear first. The `|| true` covers reloading when nothing is loaded yet.
emacs-reload:
	launchctl bootout $(EMACS_DOMAIN)/$(EMACS_LABEL) 2>/dev/null || true
	while launchctl print $(EMACS_DOMAIN)/$(EMACS_LABEL) >/dev/null 2>&1; do sleep 0.2; done
	launchctl bootstrap $(EMACS_DOMAIN) $(EMACS_PLIST)

else

EMACS_UNIT := emacs.service

emacs-start:
	systemctl --user start $(EMACS_UNIT)

emacs-stop:
	systemctl --user stop $(EMACS_UNIT)

emacs-restart:
	systemctl --user restart $(EMACS_UNIT)

# The systemd analog of re-parsing the plist: pick up unit file edits,
# then restart the daemon on the new definition.
emacs-reload:
	systemctl --user daemon-reload
	systemctl --user restart $(EMACS_UNIT)

endif
