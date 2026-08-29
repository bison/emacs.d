;;; bison-ui.el --- Theme, modeline, dashboard  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; Everything visual.  Icons come from nerd-icons, which needs a Nerd Font
;; on the terminal side in the VMs (Ghostty on the host provides it) and
;; `M-x nerd-icons-install-fonts' once for the macOS GUI.

;;; Code:

(require 'bison-lib)

(use-package doom-themes
  :demand t
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-gruvbox t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

(use-package nerd-icons
  :defer t)

(use-package doom-modeline
  :hook (emacs-startup . doom-modeline-mode)
  :custom
  (doom-modeline-height 28)
  (doom-modeline-buffer-file-name-style 'relative-to-project)
  (doom-modeline-vcs-max-length 24)
  (doom-modeline-check-simple-format t)
  (doom-modeline-buffer-encoding 'nondefault))

(use-package dashboard
  :demand t
  :custom
  (dashboard-startup-banner 'logo)
  (dashboard-banner-logo-title nil)
  (dashboard-center-content t)
  (dashboard-vertically-center-content t)
  (dashboard-projects-backend 'project-el)
  (dashboard-items '((recents . 8)
                     (projects . 8)
                     (bookmarks . 5)))
  (dashboard-item-shortcuts '((recents . "r")
                              (projects . "p")
                              (bookmarks . "m")))
  (dashboard-display-icons-p t)
  (dashboard-icon-type 'nerd-icons)
  (dashboard-set-heading-icons t)
  (dashboard-set-file-icons t)
  (dashboard-set-footer nil)
  :config
  ;; The startup hook covers `emacs' proper; the daemon needs
  ;; `initial-buffer-choice' so a bare `emacsclient -c' lands here too.
  (dashboard-setup-startup-hook)
  (setq initial-buffer-choice
        (lambda () (get-buffer-create dashboard-buffer-name))))

(use-package hl-line
  :straight (:type built-in)
  :hook ((prog-mode text-mode conf-mode) . hl-line-mode))

(use-package display-line-numbers
  :straight (:type built-in)
  :hook ((prog-mode conf-mode) . display-line-numbers-mode)
  :custom
  (display-line-numbers-width 3))

(use-package hl-todo
  :hook ((prog-mode conf-mode yaml-ts-mode) . hl-todo-mode))

(use-package which-key
  :straight (:type built-in)
  :hook (emacs-startup . which-key-mode)
  :custom
  (which-key-idle-delay 0.6))

(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-command]  . helpful-command)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)
         ([remap describe-symbol]   . helpful-symbol)))

(setq frame-title-format '("%b -- Emacs"))

(provide 'bison-ui)
;;; bison-ui.el ends here
