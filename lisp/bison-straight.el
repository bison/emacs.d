;;; bison-straight.el --- Bootstrap straight.el  -*- lexical-binding: t; -*-
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

(require 'bison-util)

(defun bison/setup-straight-versions-dir (base-dir)
  "Create link to versions directory in BASE-DIR."
  (let ((target (expand-file-name "versions" user-emacs-directory))
		(link (expand-file-name "straight/versions" base-dir)))
	(bison/mkdir (expand-file-name "straight" base-dir))
	(make-symbolic-link target link t)))

(defun bison/bootstrap-straight.el ()
  "Bootstrap straight.el package manager."

  (defconst straight.el-install-url
    "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el")

  (defvar straight-base-dir bison/emacs-cache-dir)
  (defvar straight-use-package-by-default t)

  (bison/setup-straight-versions-dir straight-base-dir)

  (defvar bootstrap-version nil "Boostrap version for straight.el package.")

  (let ((bootstrap-file
	 (expand-file-name
	  "straight/repos/straight.el/bootstrap.el" straight-base-dir))
	(bootstrap-version 5))
    (unless (file-exists-p bootstrap-file)
      (with-current-buffer
          (url-retrieve-synchronously
	   straight.el-install-url 'silent 'inhibit-cookies)
        (goto-char (point-max))
        (eval-print-last-sexp)))
    (load bootstrap-file nil 'nomessage))

  (declare-function straight-use-package 'straight)
  (straight-use-package 'use-package))

(provide 'bison-straight.el)
;;; bison-straight.el ends here
