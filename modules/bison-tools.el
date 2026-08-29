;;; bison-tools.el --- Shells, environment, and external tools  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; eat replaces vterm: pure elisp, so no libvterm in the images, and it
;; runs the shell on the remote side of a TRAMP connection.

;;; Code:

(require 'bison-lib)

;; The launchd plist gives the daemon a sane PATH, but GOPATH/bin and
;; the SSH/GPG sockets still only exist in a login shell.
(use-package exec-path-from-shell
  :if (or (memq window-system '(mac ns)) (daemonp))
  :custom
  (exec-path-from-shell-variables
   '("PATH" "MANPATH" "GOPATH" "SSH_AUTH_SOCK" "SSH_AGENT_PID"
     "GPG_AGENT_INFO" "LANG" "LC_CTYPE" "EMACS_SOCKET_NAME"))
  :config
  (exec-path-from-shell-initialize))

;; direnv: per-project env from .envrc, the same as the shell sees.
(use-package envrc
  :hook (emacs-startup . envrc-global-mode))

(use-package eat
  :bind (("C-c t" . eat-project)
         ("C-c T" . eat))
  :hook (eshell-load . eat-eshell-mode)
  :custom
  (eat-kill-buffer-on-exit t)
  (eat-enable-mouse t))

(use-package eshell
  :straight (:type built-in)
  :defer t
  :custom
  (eshell-aliases-file (expand-file-name "eshell/alias" user-emacs-directory))
  (eshell-hist-ignoredups t)
  (eshell-scroll-to-bottom-on-input 'this)
  :hook (eshell-mode . (lambda () (setq-local show-trailing-whitespace nil))))

(provide 'bison-tools)
;;; bison-tools.el ends here
