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
(bison-test--assert (featurep 'bison-org) "org module loaded")
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


;; Nothing may write into the checkout.  Every variable here names a file
;; or directory some package writes at runtime; load what defines them
;; and check each resolves under the cache directory.
(dolist (lib '(tramp transient recentf savehist bookmark eshell em-hist url nsm
               project dape multiple-cursors org-id auto-save))
  (require lib nil t))

(dolist (var (append (and (boundp 'native-comp-eln-load-path)
                          '(native-comp-eln-load-path))
             '(auto-save-list-file-prefix
               backup-directory-alist
               auto-save-file-name-transforms
               bookmark-default-file
               dape-default-breakpoints-file
               eshell-directory-name
               eshell-history-file-name
               mc/list-file
               nsm-settings-file
               org-id-locations-file
               project-list-file
               recentf-save-file
               savehist-file
               server-socket-dir
               straight-base-dir
               tramp-auto-save-directory
               tramp-persistency-file-name
               transient-history-file
               transient-levels-file
               transient-values-file
               url-configuration-directory
               url-cookie-file)))
  (let* ((value (symbol-value var))
         (path (pcase var
                 ('native-comp-eln-load-path (car value))
                 ;; Catch-all entries; /tmp exceptions come before them.
                 ('backup-directory-alist (cdr (assoc "." value)))
                 ('auto-save-file-name-transforms (cadr (assoc ".*" value)))
                 (_ value))))
    (bison-test--assert
     (and (stringp path)
          (string-prefix-p bison-cache-dir (expand-file-name path)))
     (format "%s stays in the cache (%s)" var path))))

;; The grammar installer must target the cache too, not the default
;; <user-emacs-directory>/tree-sitter.
(bison-test--assert
 (string-prefix-p bison-cache-dir (car treesit-extra-load-path))
 "tree-sitter grammars install into the cache")

(message "test: ok on Emacs %s" emacs-version)

;;; test.el ends here
