;;; lint.el --- Byte-compile and checkdoc every file  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run by `make lint'.  Bootstraps straight so use-package forms expand
;; against the real packages (use-package installs on compile through
;; straight's ensure function), then byte-compiles every file with
;; warnings promoted to errors and runs checkdoc over it.  Output files go
;; to a scratch directory so the checkout stays clean.

;;; Code:

(require 'checkdoc)
(require 'bytecomp)

(defvar bison-lint--root (file-name-directory
                          (directory-file-name
                           (file-name-directory load-file-name))))

(defvar bison-lint--files
  (append (list (expand-file-name "early-init.el" bison-lint--root)
                (expand-file-name "init.el" bison-lint--root))
          (directory-files (expand-file-name "lisp" bison-lint--root) t "\\.el\\'")
          (directory-files (expand-file-name "modules" bison-lint--root) t "\\.el\\'")
          (directory-files (expand-file-name "scripts" bison-lint--root) t "\\.el\\'")))

(defvar bison-lint--failures 0)

(setq user-emacs-directory bison-lint--root)
(add-to-list 'load-path (expand-file-name "lisp" bison-lint--root))
(add-to-list 'load-path (expand-file-name "modules" bison-lint--root))
(require 'bison-lib)
(require 'bison-straight)

(defun bison-lint--checkdoc (file)
  "Run checkdoc over FILE, counting each complaint as a failure."
  (let ((checkdoc-create-error-function
         (lambda (text start _end &optional _unfixable)
           (setq bison-lint--failures (1+ bison-lint--failures))
           (message "%s:%d: checkdoc: %s" file
                    (with-current-buffer (find-file-noselect file)
                      (line-number-at-pos start))
                    text)
           nil)))
    ;; Modules are loaded by then (compiling init.el requires them), so
    ;; keep their prog-mode hooks -- flyspell, eglot -- out of a lint run.
    (let ((prog-mode-hook nil)
          (emacs-lisp-mode-hook nil)
          (after-change-major-mode-hook nil))
      (with-current-buffer (find-file-noselect file)
        (checkdoc-current-buffer t)))))

(defun bison-lint--compile (file)
  "Byte-compile FILE with warnings as errors."
  (let ((byte-compile-error-on-warn t)
        (byte-compile-warnings t)
        (byte-compile-dest-file-function
         (lambda (f) (expand-file-name (concat (file-name-nondirectory f) "c")
                                       temporary-file-directory))))
    (unless (byte-compile-file file)
      (setq bison-lint--failures (1+ bison-lint--failures)))))

(dolist (file bison-lint--files)
  (message "lint: %s" (file-relative-name file bison-lint--root))
  (bison-lint--checkdoc file)
  (bison-lint--compile file))

;; Compiling loads packages, and a package -- or a subprocess straight
;; runs to build one -- that computes a path before the cache redirection
;; applies writes into the checkout.  Anything new in the root that git
;; does not know about is such a leak.
(declare-function bison-clean-strays "clean" (root))
(load (expand-file-name "scripts/clean.el" bison-lint--root) nil t)

(dolist (entry (bison-clean-strays bison-lint--root))
  (setq bison-lint--failures (1+ bison-lint--failures))
  (message "lint: unexpected %s in the checkout (written during compile?)"
           entry))

(if (zerop bison-lint--failures)
    (message "lint: ok (%d files)" (length bison-lint--files))
  (message "lint: %d failure(s)" bison-lint--failures)
  (kill-emacs 1))

;;; lint.el ends here
