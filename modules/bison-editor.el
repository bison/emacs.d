;;; bison-editor.el --- Editing conveniences  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; Small packages that change how text is edited, independent of language.

;;; Code:

(require 'bison-lib)

;; Trims trailing whitespace only on lines this session touched, so a
;; one-line fix never turns into a whitespace diff across the file.
;; Emacs 31 adds `delete-trailing-whitespace-mode', but that is the
;; whole-buffer behaviour, which is exactly what this avoids.
(use-package ws-butler
  :straight (ws-butler :host github :repo "emacsmirror/ws-butler" :branch "master")
  :hook ((prog-mode text-mode conf-mode) . ws-butler-mode))

(use-package whitespace
  :straight (:type built-in)
  :hook ((prog-mode conf-mode) . whitespace-mode)
  :custom
  (whitespace-style '(face trailing tabs tab-mark)))

(use-package avy
  :bind (("C-:" . avy-goto-char-timer)
         ("M-g w" . avy-goto-word-1)
         ("M-g l" . avy-goto-line)))

(use-package expand-region
  :bind ("C-=" . er/expand-region))

(use-package vundo
  :bind ("C-x u" . vundo)
  :custom
  (vundo-glyph-alist vundo-unicode-symbols))

(use-package multiple-cursors
  :bind (("C->" . mc/mark-next-like-this)
         ("C-<" . mc/mark-previous-like-this)
         ("C-c C-<" . mc/mark-all-like-this)))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package paren
  :straight (:type built-in)
  :custom
  (show-paren-delay 0)
  (show-paren-context-when-offscreen 'overlay)
  :config
  (show-paren-mode 1))

(use-package subword
  :straight (:type built-in)
  :hook (prog-mode . subword-mode))

(provide 'bison-editor)
;;; bison-editor.el ends here
