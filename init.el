;;; init.el --- My Emacs configuration  -*- lexical-binding: t; -*-
;;
;; Copyright (c) 2020 Brad Ison
;;
;; Author: Brad Ison <bison@xvdf.io>
;; URL: http://github.com/bison/emacs.d
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:

;;; Code:

(setq user-full-name "Brad Ison")
(setq user-mail-address "bison@xvdf.io")

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

(require 'ring)
(require 'server)
(require 'ispell)
(require 'recentf)
(require 'bison-util)
(require 'bison-straight.el)

;; Create the cache directory.
(bison/mkdir bison/emacs-cache-dir #o700)

;; Backup and auto-save settings.
(let ((backups-dir    (bison/expand-cache-file "backups/"))
      (auto-saves-dir (bison/expand-cache-file "auto-saves/")))

  (bison/mkdir auto-saves-dir #o700)
  (bison/mkdir backups-dir #o700)

  (setq auto-save-file-name-transforms `((".*" ,auto-saves-dir t))
        auto-save-list-file-prefix auto-saves-dir
        auto-save-visited-mode t)

  (setq backup-directory-alist `(("." . ,backups-dir))
        backup-by-copying t
        delete-old-versions t
        version-control t
        kept-new-versions 6
        kept-old-versions 3))

;; Location for the emacs server socket.
(setq server-socket-dir bison/emacs-cache-dir)
(setq server-name (bison/expand-cache-file "server"))

;; Basic settings.
(setq-default inhibit-startup-screen t)
(setq-default truncate-lines t)
(setq-default require-final-newline t)
(setq-default show-trailing-whitespace t)
(setq-default linum-format " %3d ")
(setq-default tab-width 4)

(size-indication-mode t)
(column-number-mode t)
(line-number-mode t)

;; Set the default font.
(cond ((eq system-type 'darwin)
	   (set-face-attribute
		'default nil
		:family "Monaco" :height 160)

	   (eq system-type 'gnu/linux)
		(set-face-attribute
		 'default nil
		 :family "Source Code Pro" :height 140)))

;; Window hopping shortcuts.
(global-set-key (kbd "M-o")   (lambda () (interactive) (other-window  1)))
(global-set-key (kbd "M-O")   (lambda () (interactive) (other-window -1)))
(global-set-key (kbd "C-x O") (lambda () (interactive) (other-window -1)))

;; Disable scroll bar, tool bar, and menu bar.
(if (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(if (fboundp 'tool-bar-mode)   (tool-bar-mode   -1))
(if (fboundp 'menu-bar-mode)   (menu-bar-mode   -1))

;; Bootstrap straight.el package manager.
(bison/bootstrap-straight.el)

;; Install and/or initialize all packages.
(bison/load-directory (expand-file-name "init.d" user-emacs-directory))

;; Load customizations.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(if (file-exists-p custom-file) (load custom-file))

;; Save recently opened files list to the cache directory.
(setq recentf-save-file (bison/expand-cache-file "recentf"))

;; Quick cycle through ispell dictionaries.
(let* ((dicts '("en_US" "de_DE"))
       (bison/dict-ring (make-ring (length dicts))))

  (setq ispell-program-name "hunspell")
  (setq ispell-dictionary (car dicts))
  (dolist (elem dicts) (ring-insert bison/dict-ring elem))

  (defun bison/cycle-ispell-languages ()
    (interactive)
    (let ((dict (ring-ref bison/dict-ring -1)))
      (ring-insert bison/dict-ring dict)
      (ispell-change-dictionary dict)))

  (global-set-key [f9] 'bison/cycle-ispell-languages))

;; Enable flyspell for source code comments.
(add-hook 'prog-mode-hook 'flyspell-prog-mode)
(add-hook 'prog-mode-hook 'linum-mode)

;;; init.el ends here
