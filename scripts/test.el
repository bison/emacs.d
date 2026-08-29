;;; test.el --- Load the whole configuration in batch  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run by `make test'.  Loads early-init.el and init.el exactly as Emacs
;; would, with `debug-on-error' so any failure prints a backtrace and
;; exits non-zero, then checks a few invariants that would otherwise only
;; show up on the next interactive launch.

;;; Code:

(defvar bison-test--root (file-name-directory
                          (directory-file-name
                           (file-name-directory load-file-name))))

(setq debug-on-error t
      user-emacs-directory bison-test--root)

(load (expand-file-name "early-init.el" bison-test--root))
(load (expand-file-name "init.el" bison-test--root))

(defun bison-test--assert (ok what)
  "Print WHAT and fail unless OK is non-nil."
  (message "%s %s" (if ok "ok  " "FAIL") what)
  (unless ok (kill-emacs 1)))

(bison-test--assert (featurep 'straight) "straight bootstrapped")
(bison-test--assert (featurep 'bison-lang-ops) "all modules loaded")
(bison-test--assert (equal server-name (bison-cache-file "server"))
                    "server socket path matches the config repo")
(bison-test--assert (string-prefix-p bison-cache-dir
                                     (file-truename straight-base-dir))
                    "straight lives in the cache dir")
(bison-test--assert (file-symlink-p
                     (expand-file-name "straight/versions" straight-base-dir))
                    "lockfile symlink in place")
(bison-test--assert (eq (cdr (assq 'go-mode major-mode-remap-alist)) 'go-ts-mode)
                    "tree-sitter remaps registered")
(bison-test--assert
 (equal (cdr (assoc "\\.go\\'" auto-mode-alist)) 'go-ts-mode)
 "go files open in go-ts-mode")

(message "test: ok on Emacs %s" emacs-version)

;;; test.el ends here
