;;; bison-project.el --- Projects and version control  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; project.el replaces projectile.  The one external caller that noticed
;; is the mr post_checkout hook in the config repo, which used
;; `projectile-add-known-project'; the equivalent is
;; `project-remember-projects-under' (see docs/scratch report).

;;; Code:

(require 'bison-lib)

(use-package project
  :straight (:type built-in)
  :defer t
  :custom
  (project-vc-extra-root-markers '("go.work" ".project"))
  (project-switch-commands
   '((project-find-file "Find file" ?f)
     (consult-ripgrep "Ripgrep" ?g)
     (project-find-dir "Find dir" ?d)
     (magit-project-status "Magit" ?m)
     (eat-project "Terminal" ?t)
     (project-eshell "Eshell" ?e)))
  :config
  ;; Registers every worktree under ~/Code the first time the project
  ;; list is empty, so a fresh cache still gets a populated dashboard.
  (unless (file-exists-p project-list-file)
    (when (file-directory-p "~/Code")
      (project-remember-projects-under "~/Code" t))))

(use-package magit
  :bind (([f12] . magit-status)
         ("C-x g" . magit-status)
         ("C-c g" . magit-file-dispatch))
  :custom
  (magit-diff-refine-hunk t)
  (magit-save-repository-buffers 'dontask)
  (magit-display-buffer-function
   #'magit-display-buffer-same-window-except-diff-v1))

(use-package git-modes
  :defer t)

(use-package diff-hl
  :hook ((emacs-startup . global-diff-hl-mode)
         (dired-mode . diff-hl-dired-mode))
  :config
  (diff-hl-flydiff-mode 1)
  ;; No fringe in the terminal; draw in the margin there instead.
  (unless (display-graphic-p)
    (diff-hl-margin-mode 1)))

(provide 'bison-project)
;;; bison-project.el ends here
