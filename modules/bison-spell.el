;;; bison-spell.el --- Spell checking  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; jinx in place of flyspell: it checks only the visible part of the
;; buffer, checks every language in `jinx-languages' at once, and in
;; prog-mode restricts itself to comments, strings and docstrings.  It
;; talks to hunspell through enchant, and compiles a small module against
;; libenchant the first time it loads -- so enchant's headers have to be
;; installed.  Where they are not (yet), flyspell fills in.

;;; Code:

(require 'bison-lib)

;; hunspell dictionaries on macOS live where enchant already looks;
;; hunspell itself, used by the fallback, needs telling.
(when (eq system-type 'darwin)
  (setenv "DICPATH" (expand-file-name "~/Library/Spelling")))

(defun bison-spell-enchant-p ()
  "Return non-nil if jinx could build its module here."
  (and (executable-find "cc")
       (executable-find "pkg-config")
       (zerop (call-process "pkg-config" nil nil nil "--exists" "enchant-2"))))

(use-package jinx
  :if (bison-spell-enchant-p)
  :hook (emacs-startup . global-jinx-mode)
  :bind (("M-$"   . jinx-correct)
         ("C-M-$" . jinx-languages)
         ([f9]    . jinx-languages))
  :custom
  ;; Both at once; no dictionary cycling needed any more.
  (jinx-languages "en_US de_DE"))

;;; Fallback

(use-package ispell
  :straight (:type built-in)
  :unless (bison-spell-enchant-p)
  :defer t
  :custom
  (ispell-program-name "hunspell")
  (ispell-dictionary "en_US"))

(defvar bison-spell-dictionaries '("en_US" "de_DE")
  "Dictionaries `bison-spell-cycle-dictionary' rotates through.")

(defun bison-spell-cycle-dictionary ()
  "Switch to the next dictionary in `bison-spell-dictionaries'."
  (interactive)
  (let* ((current (or ispell-local-dictionary ispell-dictionary))
         (rest (cdr (member current bison-spell-dictionaries)))
         (next (or (car rest) (car bison-spell-dictionaries))))
    (ispell-change-dictionary next)))

(use-package flyspell
  :straight (:type built-in)
  :unless (bison-spell-enchant-p)
  :hook ((prog-mode . flyspell-prog-mode)
         (text-mode . flyspell-mode))
  :bind ([f9] . bison-spell-cycle-dictionary))

(provide 'bison-spell)
;;; bison-spell.el ends here
