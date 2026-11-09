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
  (doom-themes-org-config)

  ;; The theme's modeline background #37302f has no close neighbour in
  ;; the xterm-256 palette: Emacs approximates it to color-58, an olive
  ;; green.  Terminals without truecolour -- tmux, the VMs over ssh --
  ;; get an exact palette grey instead.  A display-conditional spec so
  ;; a daemon serving both GUI and TTY frames renders each correctly.
  (custom-set-faces
   '(mode-line ((((class color) (min-colors 16777216))
                 :background "#37302f" :foreground "#dfd2b8")
                (t :background "#303030" :foreground "#d5c4a1")))
   '(mode-line-active ((t :inherit mode-line)))))

(use-package nerd-icons
  :defer t)

;; doom-modeline pulls shrink-path from GitLab; take the GitHub mirror so
;; github.com is the only host this config ever clones from.
(use-package shrink-path
  :straight (shrink-path :host github :repo "emacsmirror/shrink-path")
  :defer t)

(use-package doom-modeline
  :hook (emacs-startup . doom-modeline-mode)
  :custom
  (doom-modeline-height 28)
  (doom-modeline-buffer-file-name-style 'relative-to-project)
  (doom-modeline-vcs-max-length 24)
  (doom-modeline-check-simple-format t)
  (doom-modeline-buffer-encoding 'nondefault)
  :config
  ;; doom-gruvbox paints the buffer path and major mode bright green,
  ;; which with `relative-to-project' paths is most of the modeline.
  ;; These are gruvbox's own fg2 and fg4 neutrals instead; the yellow
  ;; modified marker and cyan project directory stay as the accents.
  ;; Not `:custom-face': that sets the defface spec, which a theme
  ;; spec replaces wholesale; `custom-set-faces' layers on top.
  (custom-set-faces
   '(doom-modeline-buffer-path ((t :inherit bold :foreground "#d5c4a1")))
   '(doom-modeline-buffer-major-mode ((t :inherit bold :foreground "#a89984")))))

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

;; Claude Code marks recaps and notes with ※ (U+203B).  JetBrains Mono
;; has no glyph for it, and the automatic fallback lands on Arial Unicode
;; MS, which is proportional; Monaco is the installed monospace font that
;; has it.  One code point, not a range: a fontset entry wins over the
;; frame's font, so a range would also take over punctuation JetBrains
;; Mono draws itself.  Builds without a window system (CI's) lack
;; `set-fontset-font' altogether.
(when (fboundp 'set-fontset-font)
  (set-fontset-font t #x203B (font-spec :family "Monaco") nil 'prepend))

;; Font size for every buffer and frame at once, on the keys Ghostty and
;; most macOS apps use; the stock s-= family scales one buffer only.
;; `global-text-scale-adjust' picks its direction from the key that
;; invoked it, and ghostel advises it to refit its terminals.  It also
;; arms a transient map so a following bare -, = or 0 adjusts again --
;; dropped here, so that text typed right after goes where it should.
(defun bison-font-size--adjust (key)
  "Adjust the global font size as `global-text-scale-adjust' does for KEY."
  (let ((last-command-event key))
    (cl-letf (((symbol-function 'set-transient-map) #'ignore))
      (global-text-scale-adjust 1))))

(defun bison-font-size-increase ()
  "Increase the font size everywhere."
  (interactive)
  (bison-font-size--adjust ?=))

(defun bison-font-size-decrease ()
  "Decrease the font size everywhere."
  (interactive)
  (bison-font-size--adjust ?-))

(defun bison-font-size-reset ()
  "Reset the font size everywhere."
  (interactive)
  (bison-font-size--adjust ?0))

(global-set-key (kbd "s-=") #'bison-font-size-increase)
(global-set-key (kbd "s-+") #'bison-font-size-increase)
(global-set-key (kbd "s--") #'bison-font-size-decrease)
(global-set-key (kbd "s-0") #'bison-font-size-reset)

(provide 'bison-ui)
;;; bison-ui.el ends here
