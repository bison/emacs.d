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
  ;; `global-git-commit-mode' is on by default but inert until the
  ;; git-commit library is loaded, and magit refuses to autoload it, so
  ;; without this the first `git commit' after a restart lands in
  ;; fundamental-mode.  emacs-startup-hook runs before the daemon
  ;; accepts clients, so emacsclient can never win that race.
  :init
  (unless noninteractive
    (add-hook 'emacs-startup-hook (lambda () (require 'magit))))
  :custom
  (magit-diff-refine-hunk t)
  (magit-save-repository-buffers 'dontask)
  (magit-display-buffer-function
   #'magit-display-buffer-same-window-except-diff-v1))

;; forge resolves its API token through auth-source (machine
;; api.github.com, login "<user>^forge").  Answer that query from the
;; gh CLI's existing login instead of minting a second credential --
;; the same delegation the gitconfig makes for git itself with
;; `gh auth git-credential'.  The backend claims only api.github.com,
;; so every other auth-source query falls through to the usual files.
;; auth-source caches results (`auth-source-cache-expiry'), so the gh
;; subprocess runs once per expiry, not once per API request.
(require 'auth-source)

(defun bison-auth-source-gh-search (&rest spec)
  "Answer an auth-source SPEC for api.github.com with the gh CLI's token.
Return nil when the host does not match, gh is not installed, or gh
has no login, so the query falls through to the other `auth-sources'."
  (when-let* ((host (plist-get spec :host))
              ((member "api.github.com" (ensure-list host)))
              ((executable-find "gh"))
              (token (with-temp-buffer
                       (when (zerop (call-process "gh" nil t nil "auth" "token"))
                         (string-trim (buffer-string)))))
              ((not (equal token ""))))
    (list (list :host "api.github.com"
                :user (car (ensure-list (plist-get spec :user)))
                :secret (lambda () token)))))

(defun bison-auth-source-gh-backend-parse (entry)
  "Parse ENTRY, claiming the symbol `gh' in `auth-sources'."
  (when (eq entry 'gh)
    (auth-source-backend :source "gh"
                         :type 'gh
                         :search-function #'bison-auth-source-gh-search)))

(add-hook 'auth-source-backend-parser-functions
          #'bison-auth-source-gh-backend-parse)
(add-to-list 'auth-sources 'gh)

;; PRs and issues inside magit.  The token comes from the gh backend
;; above; the github.user git config forge also needs comes from the
;; config repo's gitconfig.
(use-package forge
  :after magit
  :custom
  (forge-database-file (bison-cache-file "forge-database.sqlite")))

;; browse-at-remote builds forge URLs without any credential, but its
;; mode dispatch does not know magit-blame: in a blamed buffer it would
;; open the file at point, not the chunk's commit.  The jump from a
;; blame chunk to its commit page is a small command on top of its URL
;; builder instead.
(use-package browse-at-remote
  :defer t)

(declare-function magit-current-blame-chunk "magit-blame")
(declare-function browse-at-remote--commit-url "browse-at-remote")

(defun bison-blame-browse-commit ()
  "Browse the commit of the blame chunk at point on its forge."
  (interactive)
  (require 'browse-at-remote)
  (let ((rev (oref (or (magit-current-blame-chunk)
                       (user-error "No blame chunk at point"))
                   orig-rev)))
    (when (string-match-p "\\`0+\\'" rev)
      (user-error "Not yet committed"))
    (browse-url (browse-at-remote--commit-url rev))))

(with-eval-after-load 'magit-blame
  (keymap-set magit-blame-read-only-mode-map "o" #'bison-blame-browse-commit))

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
