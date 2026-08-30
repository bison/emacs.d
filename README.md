# emacs.d

My Emacs configuration.

## Layout

| Path             | What                                                      |
| ---------------- | --------------------------------------------------------- |
| `early-init.el`  | GC, frame chrome, cache paths -- runs before packages     |
| `init.el`        | Loads `lisp/` then the `modules/` in order                |
| `lisp/`          | Bootstrap helpers (cache dir, straight.el)                |
| `modules/`       | One file per concern: defaults, ui, completion, ... lang  |
| `versions/`      | straight.el lockfile                                      |
| `scripts/`       | Batch entry points used by the Makefile                   |

## Make targets

    make lint      # checkdoc + byte-compile, warnings are errors
    make test      # load the whole config in batch, check invariants
    make lock      # write versions/default.el from the checked-out repos
    make thaw      # check out what the lockfile says
    make update    # pull all packages, then lock
    make grammars  # compile missing tree-sitter grammars into the cache

`make test CACHE=/tmp/x` runs against an empty cache, installing everything
from scratch.
