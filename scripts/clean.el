;;; clean.el --- What the checkout is allowed to contain  -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by `make lint' and `make test'.  Both run from inside the
;; checkout, and the sandbox images clone it to ~/.emacs.d itself, so
;; anything that derives a path from `user-emacs-directory' before the
;; cache redirection applies -- or in a subprocess the redirection cannot
;; reach -- leaves its droppings right here.  Anything in the root that is
;; not checked in is such a leak.

;;; Code:

(defconst bison-clean-entries
  '("COPYING" "Makefile" "README.md" "docs" "early-init.el" "eshell"
    "init.el" "lisp" "modules" "scripts" "versions")
  "Every non-dot entry the checkout is supposed to have.")

(defun bison-clean-strays (root)
  "Return the entries in ROOT that are not part of the checkout.
Dot files are skipped: .git and .github belong here, and whatever else a
user keeps in a dot file is their business.  Emacs Lisp is skipped too,
since a new module is a file someone wrote rather than a leak."
  (let (strays)
    (dolist (entry (directory-files root nil "\\`[^.]") (nreverse strays))
      (unless (or (member entry bison-clean-entries)
                  (string-suffix-p ".el" entry))
        (push entry strays)))))

;;; clean.el ends here
