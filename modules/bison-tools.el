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

(defun bison-eshell-export-editor ()
  "Point $EDITOR and $VISUAL in this eshell at the current Emacs.
Both, because git consults $VISUAL first, so an inherited value
would silently shadow the $EDITOR export -- and `emacsclient -t'
cannot work inside eshell anyway."
  ;; `envrc--clear' kills the buffer-local `process-environment'
  ;; eshell created; without restoring it the setenv inside
  ;; `with-editor-export-editor' would leak the sleeping editor into
  ;; the global environment.
  (unless (local-variable-p 'process-environment)
    (setq-local process-environment (copy-sequence process-environment)))
  (let ((inhibit-message t))
    (with-editor-export-editor "EDITOR")
    (with-editor-export-editor "VISUAL")))

;; direnv: per-project env from .envrc, the same as the shell sees.
(use-package envrc
  :hook (emacs-startup . envrc-global-mode)
  :config
  ;; envrc-mode activates after `eshell-mode-hook' and rebuilds the
  ;; buffer-local `process-environment' -- then again on every eshell
  ;; `cd' -- discarding what `bison-eshell-export-editor' set.  The
  ;; preoutput filter with-editor installs is buffer-local and
  ;; survives, so re-exporting after each apply is enough.
  (define-advice envrc--apply (:after (buf &rest _) bison-reexport-editor)
    (with-current-buffer buf
      (when (derived-mode-p 'eshell-mode)
        (bison-eshell-export-editor)))))

(use-package eat
  :straight (eat :host github :repo "emacsmirror/eat")
  :bind (("C-c t" . eat-project)
         ("C-c T" . eat))
  ;; `git commit' inside eat opens in this Emacs.  with-editor handles
  ;; the process argument `eat-exec-hook' passes, and the function is
  ;; autoloaded, so this costs nothing until a terminal spawns.
  :hook ((eshell-load . eat-eshell-mode)
         (eat-exec . with-editor-export-editor))
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
  :hook ((eshell-mode . bison-eshell-export-editor)
         (eshell-mode . (lambda () (setq-local show-trailing-whitespace nil)))))

(provide 'bison-tools)
;;; bison-tools.el ends here
