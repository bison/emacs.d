;;; bison-util.el --- Utility functions  -*- lexical-binding: t; -*-
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

(eval-when-compile (require 'subr-x))

(defun bison/set-and-non-empty (var)
  "Return non-nil if VAR is bound and not an empty string."
  (and (boundp var) (not (string-blank-p (eval var)))))

(defun bison/var-or-default (var default)
  "Return value of VAR if it is non-empty, otherwise DEFAULT."
  (if (bison/set-and-non-empty var) (eval var) default))

(defconst bison/emacs-profile
  (bison/var-or-default 'chemacs-current-emacs-profile "default")
  "The name of the current Emacs profile.")

(defconst bison/emacs-cache-dir
  (expand-file-name bison/emacs-profile "~/.cache/emacs/")
  "The path to the current Emacs cache directory.")

(defun bison/load-directory (dir)
  "Load all Emacs Lisp files in DIR."
  (let ((load-from-dir (lambda (f)
                         (load-file (expand-file-name f dir)))))
    (mapc load-from-dir (directory-files dir nil "\\.elc?$"))))

(defun bison/mkdir (dir &optional mode)
  "Create DIR if it doesn't exist, and optionally set MODE."
  (unless (file-directory-p dir)
    (make-directory dir t)
    (when mode (chmod dir mode))))

(defun bison/expand-cache-file (file)
  "Expand FILE name within our Emacs cache directory."
  (expand-file-name file bison/emacs-cache-dir))

(provide 'bison-util)
;;; bison-util.el ends here
