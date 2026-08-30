;;; bison-defaults.el --- Built-in behaviour and file locations  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; Settings for things that ship with Emacs.  Loaded first because
;; no-littering has to be in place before any other package computes a
;; file path.

;;; Code:

(require 'bison-lib)

;; Sends every package's state file to <cache>/var and <cache>/etc, so
;; the per-package `-file' settings the old config carried are gone.
(use-package no-littering
  :demand t                             ; directories are set in bison-lib
  :config
  (no-littering-theme-backups))

;; The server socket path is part of the contract with the config repo:
;; ~/.zshrc exports EMACS_SOCKET_NAME=<cache>/server and the launchd env
;; plist repeats it, so this cannot follow no-littering into var/.
(use-package server
  :straight (:type built-in)
  :custom
  (server-name (bison-cache-file "server"))
  :config
  ;; A defvar, not a defcustom, so :custom would silently not apply.
  (setq server-socket-dir bison-cache-dir))

;; Restore GC after startup; early-init raised it to speed up loading.
(use-package gcmh
  :straight (gcmh :host github :repo "emacsmirror/gcmh")
  :hook (emacs-startup . gcmh-mode)
  :custom
  (gcmh-idle-delay 'auto)
  (gcmh-high-cons-threshold (* 64 1024 1024)))

;;; Files

(setq backup-by-copying t
      delete-old-versions t
      version-control t
      kept-new-versions 6
      kept-old-versions 3
      auto-save-default t
      create-lockfiles nil
      require-final-newline t)

(auto-save-visited-mode 1)
(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t
      auto-revert-verbose nil)

(use-package recentf
  :straight (:type built-in)
  :hook (emacs-startup . recentf-mode)
  :custom
  (recentf-max-saved-items 200)
  (recentf-auto-cleanup 'never)
  :config
  ;; Do not remember the cache dir or straight's repos as recent files.
  (add-to-list 'recentf-exclude (regexp-quote bison-cache-dir)))

(use-package savehist
  :straight (:type built-in)
  :hook (emacs-startup . savehist-mode)
  :custom
  (savehist-additional-variables '(kill-ring search-ring regexp-search-ring)))

(use-package saveplace
  :straight (:type built-in)
  :hook (emacs-startup . save-place-mode))

;;; Editing

(setq-default tab-width 4
              indent-tabs-mode nil
              truncate-lines t
              fill-column 80)

(setq sentence-end-double-space nil
      use-short-answers t
      confirm-kill-processes nil
      enable-recursive-minibuffers t
      read-extended-command-predicate #'command-completion-default-include-p
      minibuffer-prompt-properties
      '(read-only t cursor-intangible t face minibuffer-prompt)
      completion-ignore-case t
      read-buffer-completion-ignore-case t
      read-file-name-completion-ignore-case t
      kill-do-not-save-duplicates t
      scroll-conservatively 101
      scroll-margin 2
      ring-bell-function #'ignore)

(delete-selection-mode 1)
(electric-pair-mode 1)
(column-number-mode 1)
(size-indication-mode 1)
(winner-mode 1)
(repeat-mode 1)
(minibuffer-depth-indicate-mode 1)

;; Frame-type specific setup, done at frame creation so the daemon
;; serves either kind: pixel scrolling in the GUI; mouse support and no
;; menu bar in the TTY (the macOS GUI keeps its menu bar, see early-init).
(defun bison-defaults--setup-frame (frame)
  "Enable frame-type specific modes for FRAME."
  (with-selected-frame frame
    (if (display-graphic-p)
        (pixel-scroll-precision-mode 1)
      (set-frame-parameter frame 'menu-bar-lines 0)
      (xterm-mouse-mode 1))))
(add-hook 'after-make-frame-functions #'bison-defaults--setup-frame)
(add-hook 'emacs-startup-hook
          (lambda () (bison-defaults--setup-frame (selected-frame))))

;; Window hopping.  M-o is the one binding from the old config worth
;; keeping as-is; everything else moved to the modules.
(global-set-key (kbd "M-o") #'other-window)
(global-set-key (kbd "M-O") (lambda () (interactive) (other-window -1)))
(global-set-key (kbd "C-x O") (lambda () (interactive) (other-window -1)))

;;; Remote files

(use-package tramp
  :straight (:type built-in)
  :defer t
  :custom
  (tramp-default-method "ssh")
  (tramp-verbose 1)
  :config
  ;; VC probing over TRAMP is what makes remote buffers feel slow.
  (setq vc-ignore-dir-regexp
        (format "\\(%s\\)\\|\\(%s\\)" vc-ignore-dir-regexp
                tramp-file-name-regexp)))

(use-package ediff
  :straight (:type built-in)
  :defer t
  :custom
  (ediff-custom-diff-options "-U3")
  (ediff-split-window-function #'split-window-horizontally)
  (ediff-window-setup-function #'ediff-setup-windows-plain)
  :hook
  ((ediff-startup ediff-cleanup ediff-suspend) . ediff-toggle-wide-display))

(provide 'bison-defaults)
;;; bison-defaults.el ends here
