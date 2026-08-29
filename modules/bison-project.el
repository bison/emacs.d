;;; bison-project.el --- Projects and version control  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; project.el replaces projectile.  Projects are discovered from the
;; <org>/<repo> layout under `bison-code-dir' at every startup, so the
;; mr and worktrunk hooks in the config repo that used to call
;; `projectile-add-known-project' can call `project-remember-projects-under'
;; or simply `bison-project-discover' (see the docs/scratch report).

;;; Code:

(require 'bison-lib)

(defun bison-project-discover ()
  "Register every repository under `bison-code-dir' with project.el.
The layout is <org>/<repo>, with worktrees at <repo>/.worktrees/<branch>,
so this looks exactly there rather than walking whole repositories the
way `project-remember-projects-under' would -- which over a virtiofs
mount is the difference between instant and minutes."
  (interactive)
  (let ((count 0))
    (dolist (org (bison-project--subdirs bison-code-dir))
      (dolist (repo (bison-project--subdirs org))
        (dolist (dir (cons repo (bison-project--subdirs
                                 (expand-file-name ".worktrees" repo))))
          (when-let* ((project (project-current nil dir)))
            (project-remember-project project 'no-write)
            (setq count (1+ count))))))
    (project--write-project-list)
    (when (called-interactively-p 'interactive)
      (message "%d projects under %s" count bison-code-dir))
    count))

(defun bison-project--subdirs (dir)
  "Non-hidden subdirectories of DIR, or nil if DIR does not exist."
  (when (file-directory-p dir)
    (seq-filter #'file-directory-p
                (directory-files dir t "\\`[^.]" t))))

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
  :bind ("C-x p D" . bison-project-discover))

;; Runs before dashboard draws (hooks added later run first) so the
;; project list on it is current from the very first frame.
(unless noninteractive
  (add-hook 'emacs-startup-hook #'bison-project-discover))

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
