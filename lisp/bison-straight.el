;;; bison-straight.el --- Bootstrap straight.el and use-package  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; straight.el rather than package.el because the lockfile matters: the
;; sandbox images clone this repo at build time, and versions/default.el
;; is what makes two builds a week apart produce the same Emacs.
;;
;; The repos, build products and lockfile symlink all live under the cache
;; directory, so `straight-base-dir' is the cache and the only thing in
;; ~/.emacs.d is this checkout.
;;
;; Every package is cloned from github.com: the recipe repositories are
;; there anyway, and the handful of packages whose canonical home is
;; GitLab, Codeberg or Savannah are taken from the emacsmirror
;; organisation instead (see the :straight overrides in the modules).
;; The exception is corfu-terminal (Codeberg, no mirror), which only
;; Emacs 30.2 needs.  So: github.com always, codeberg.org until the VMs
;; are on 31, and no dependence on Savannah's uptime.

;;; Code:

(require 'bison-lib)

(defvar bootstrap-version)

(defvar straight-base-dir bison-cache-dir)
(defvar straight-use-package-by-default t)

;; Checking every repo for local edits on startup is the slow part of
;; straight; this only checks repos that were edited inside Emacs.
(defvar straight-check-for-modifications '(check-on-save find-when-checking))

(defun bison-straight--link-versions-dir ()
  "Point straight's versions directory at the one in this checkout.
straight only reads lockfiles from `straight-base-dir'/straight/versions,
but the lockfile has to live in the repo to be tracked."
  (let ((target (expand-file-name "versions" user-emacs-directory))
        (link (expand-file-name "straight/versions" straight-base-dir)))
    (bison-mkdir (expand-file-name "straight" straight-base-dir))
    (cond
     ;; Already ours.
     ((and (file-symlink-p link)
           (string= (file-truename link) (file-truename target))))
     ;; A stale link, e.g. from a checkout that has since moved.
     ((file-symlink-p link)
      (delete-file link)
      (make-symbolic-link target link))
     ;; A real directory: keep whatever is in it out of the way.
     (t
      (when (file-directory-p link)
        (rename-file link (concat link ".orig")))
      (make-symbolic-link target link)))))

(defvar straight-repository-branch "develop")

(defun bison-straight-bootstrap ()
  "Clone straight.el if needed and load its bootstrap file.
This is what upstream install.el does after fetching itself, minus the
two HTTP round trips: git already knows how to reach GitHub,
including through a proxy, and nothing downloaded gets evaluated before
it is on disk in a repository straight manages."
  (bison-straight--link-versions-dir)
  (let* ((repo-dir (expand-file-name "straight/repos/straight.el/"
                                     straight-base-dir))
         (bootstrap-file (expand-file-name "bootstrap.el" repo-dir))
         (bootstrap-version 7))
    (unless (file-exists-p bootstrap-file)
      (bison-mkdir (file-name-directory (directory-file-name repo-dir)))
      (message "Bootstrapping straight.el...")
      (with-temp-buffer
        (unless (zerop (call-process "git" nil t nil "clone" "--origin" "origin"
                                     "--branch" straight-repository-branch
                                     "https://github.com/radian-software/straight.el.git"
                                     repo-dir))
          (error "Cloning straight.el failed: %s" (buffer-string)))))
    (load bootstrap-file nil 'nomessage)))

(bison-straight-bootstrap)

;; straight byte-compiles each package in a child `emacs -Q --batch', which
;; never loads this configuration: `startup-redirect-eln-cache' is a
;; variable and does not cross a process boundary, EMACSNATIVELOADPATH
;; would not help since startup pushes <user-emacs-directory>/eln-cache on
;; top of it, and the trampoline writer creates that directory when it is
;; missing.  So a child that has to synthesize a subr trampoline -- which
;; loading a package during byte-compilation makes it do -- writes .eln
;; files into ~/.emacs.d, this checkout.  The environment variable is read
;; by the child at startup and stops it writing them anywhere; the parent
;; already read its own value, so this only ever affects subprocesses.
(defun bison-straight--inhibit-child-eln (fn &rest args)
  "Apply FN to ARGS with subprocess native compilation inhibited."
  (let ((process-environment
         (cons "EMACS_INHIBIT_AUTOMATIC_NATIVE_COMPILATION=1"
               process-environment)))
    (apply fn args)))

(advice-add 'straight--build-compile :around
            #'bison-straight--inhibit-child-eln)

;; use-package ships with Emacs 29+; straight adds its :straight keyword
;; once use-package is loaded.
(require 'use-package)
(setq use-package-enable-imenu-support t
      use-package-verbose nil)

(provide 'bison-straight)
;;; bison-straight.el ends here
