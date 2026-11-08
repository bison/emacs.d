;;; bison-spaces.el --- A tab per work stream: shell and Claude Code  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; A space is a project.el project -- a repository, or one of its
;; worktrees under <repo>/.worktrees/<branch> -- in a tab of its own.  A
;; new space opens with a shell on the left and Claude Code on the
;; right, both ghostel terminals rooted at the project.
;;
;; Nothing is registered here: project.el already knows every repo and
;; worktree (`bison-project-discover' plus the worktrunk hooks), so
;; `bison-space' only finds or makes the tab.  Run it from
;; `project-switch-project' (C-x p p ... s) or on the current project.
;;
;; The tab bar stays hidden.  Tabs are only the mechanism -- each keeps
;; its own window layout -- and the open spaces are listed instead in a
;; sidebar, as a tree of org, repo and worktree.  Each tab's saved
;; layout includes the sidebar or not, depending on how it was left, so
;; whether it shows is a frame parameter re-applied on every switch.

;;; Code:

(require 'bison-lib)
(require 'cl-lib)
(require 'project)                      ; `project-root' is not autoloaded
(require 'subr-x)

(declare-function ghostel "ghostel")
(declare-function ghostel-send-string "ghostel")
(declare-function nerd-icons-octicon "nerd-icons")
(declare-function doom-modeline-def-modeline "doom-modeline-core")
(declare-function doom-modeline-set-modeline "doom-modeline-core")
(defvar ghostel-buffer-name)

(use-package tab-bar
  :straight (:type built-in)
  :custom
  (tab-bar-show nil))

;;;; Naming

;; A tab's group is "ORG/REPO" and its name the worktree's directory, or
;; REPO for the main checkout.  That pair identifies the space, and the
;; sidebar reads its tree back out of it.

(defun bison-space--names (root)
  "Return (ORG REPO NAME) for the space at project ROOT.
ORG is the directory holding the repository under `bison-code-dir',
or \"other\" outside it.  NAME is the worktree's directory name, or
REPO for the main checkout."
  (let* ((dir (directory-file-name (expand-file-name root)))
         (name (file-name-nondirectory dir))
         (parent (directory-file-name (file-name-directory dir)))
         (repo-dir (if (equal (file-name-nondirectory parent) ".worktrees")
                       (directory-file-name (file-name-directory parent))
                     dir))
         (org-dir (directory-file-name (file-name-directory repo-dir))))
    (list (if (file-in-directory-p org-dir bison-code-dir)
              (file-name-nondirectory org-dir)
            "other")
          (file-name-nondirectory repo-dir)
          name)))

(defun bison-space--label (group name)
  "Return the label naming the buffers of space NAME in GROUP."
  (let ((repo (file-name-nondirectory group)))
    (if (equal repo name) repo (concat repo "/" name))))

(defvar bison-space--roots (make-hash-table :test #'equal)
  "Project root of each space opened this session, by (GROUP . NAME).")

(defun bison-space--tab-index (group name)
  "Return the index of the tab for space NAME in GROUP, or nil."
  (cl-position-if (lambda (tab)
                    (and (equal (alist-get 'group tab) group)
                         (equal (alist-get 'name tab) name)))
                  (funcall tab-bar-tabs-function)))

;;;; Opening and closing

(defun bison-space--terminal (name &optional command)
  "Show the ghostel buffer NAME in the selected window, creating it.
A new terminal is a shell; COMMAND, if non-nil, is typed into it, so
the shell is still there when the command exits.  Return the buffer."
  (let* ((fresh (not (get-buffer name)))
         (buffer (let ((ghostel-buffer-name name))
                   (ghostel))))
    (when (and fresh command)
      (with-current-buffer buffer
        ;; Typeahead: the pty holds it until zsh's line editor reads it.
        (ghostel-send-string (concat command "\r"))))
    buffer))

(defun bison-space--layout (root label command)
  "Lay out the selected tab as the space LABEL at ROOT.
One window with the shell, and to its right one with the agent
terminal, typing COMMAND into it if the terminal is new.  Terminals
that still exist are reused; missing ones are created."
  (let ((default-directory (file-name-as-directory root)))
    ;; `delete-other-windows' leaves the sidebar, a side window, alone,
    ;; but must not start from it.
    (when (window-parameter nil 'window-side)
      (select-window (get-mru-window nil nil t)))
    (delete-other-windows)
    ;; The surviving window may be the old agent window, still dedicated.
    (set-window-dedicated-p nil nil)
    (bison-space--terminal (format "*%s: shell*" label))
    (let ((window (split-window-right)))
      (select-window window)
      (bison-space--terminal (format "*%s: claude*" label) command)
      ;; Weakly dedicated: `display-buffer' (magit, help, compile) goes
      ;; elsewhere, but an explicit `switch-to-buffer' here still works.
      (set-window-dedicated-p window 'bison-space))))

(defun bison-space--open (root group name command)
  "Make the tab for space NAME in GROUP at ROOT, running COMMAND on the right."
  (puthash (cons group name) (file-name-as-directory root) bison-space--roots)
  ;; With the bar hidden, tab-bar narrates each of these steps.
  (let ((inhibit-message t))
    (tab-bar-new-tab)
    (tab-bar-rename-tab name)
    (tab-bar-change-tab-group group))
  (bison-space--layout root (bison-space--label group name) command))

(defun bison-space (&optional continue)
  "Switch to the current project's space, making it on first use.
The space is a tab with a shell on the left and Claude Code on the
right.  With prefix arg CONTINUE, a new space starts Claude with
--continue to resume its last conversation."
  (interactive "P")
  (pcase-let* ((`(,org ,repo ,name)
                (bison-space--names (project-root (project-current t))))
               (group (concat org "/" repo)))
    (if-let* ((index (bison-space--tab-index group name)))
        (tab-bar-select-tab (1+ index))
      (bison-space--open (project-root (project-current t)) group name
                         (if continue "claude --continue" "claude"))))
  (bison-space--sidebar-sync))

;; The space's terminals are found by name, its tab by group and name;
;; neither depends on the space being the selected one.
(defun bison-space--kill (group name)
  "Kill the terminals of space NAME in GROUP and close its tab."
  (let ((label (bison-space--label group name)))
    (dolist (kind '("shell" "claude"))
      (when-let* ((buffer (get-buffer (format "*%s: %s*" label kind))))
        (kill-buffer buffer)))
    (when-let* ((index (bison-space--tab-index group name)))
      (let ((inhibit-message t))
        ;; tab-bar keeps a sole tab open rather than close it.
        (when (= (length (funcall tab-bar-tabs-function)) 1)
          (tab-bar-new-tab)
          (switch-to-buffer "*scratch*"))
        (tab-bar-close-tab (1+ index))))
    (remhash (cons group name) bison-space--roots)
    (bison-space--sidebar-sync)))

(defun bison-space--context ()
  "Return (GROUP NAME ROOT) for the space a command should act on.
In the sidebar, the space on the line at point; elsewhere, the current
project, which need not have a space yet.  ROOT is nil for a sidebar
space opened before this session's `bison-space--roots' knew it."
  (if (derived-mode-p 'bison-space-sidebar-mode)
      (pcase-let ((`(,group . ,name) (bison-space--at-point)))
        (list group name (gethash (cons group name) bison-space--roots)))
    (pcase-let* ((root (project-root (project-current t)))
                 (`(,org ,repo ,name) (bison-space--names root)))
      (list (concat org "/" repo) name root))))

(defun bison-space-close ()
  "Close the current space's tab and kill its terminals.
In the sidebar, the space on the line at point."
  (interactive)
  (pcase-let ((`(,group ,name) (if (derived-mode-p 'bison-space-sidebar-mode)
                                   (bison-space--context)
                                 (let ((tab (tab-bar--current-tab)))
                                   (list (alist-get 'group tab)
                                         (alist-get 'name tab))))))
    (unless (and group (string-search "/" group))
      (user-error "Not in a space"))
    (when (yes-or-no-p (format "Kill the terminals of %s? "
                               (bison-space--label group name)))
      (bison-space--kill group name))))

(defun bison-space--current ()
  "Return (GROUP NAME) for the selected tab's space, or signal.
In the sidebar, switch to the space on the line at point first."
  (when (derived-mode-p 'bison-space-sidebar-mode)
    (bison-space-sidebar-select))
  (let* ((tab (tab-bar--current-tab))
         (group (alist-get 'group tab)))
    (unless (and group (string-search "/" group))
      (user-error "Not in a space"))
    (list group (alist-get 'name tab))))

(defun bison-space-reset ()
  "Put the current space back to its layout: shell left, Claude right.
Terminals that were killed are recreated; a new Claude terminal
resumes the space's last conversation with --continue."
  (interactive)
  (pcase-let* ((`(,group ,name) (bison-space--current))
               (root (or (gethash (cons group name) bison-space--roots)
                         (user-error "No root known for %s" name))))
    (bison-space--layout root (bison-space--label group name)
                         "claude --continue")
    (bison-space--sidebar-sync)))

(defun bison-space--key (group name)
  "Return the completion key for space NAME in GROUP: ORG/REPO[/NAME]."
  (if (equal (file-name-nondirectory group) name)
      group
    (concat group "/" name)))

(defun bison-space-switch ()
  "Switch to a space chosen with completion, open or not.
Open spaces are listed first; choosing any other known project opens
its space."
  (interactive)
  (let ((table (make-hash-table :test #'equal))
        open)
    (dolist (tab (funcall tab-bar-tabs-function))
      (when-let* ((group (alist-get 'group tab))
                  ((string-search "/" group)))
        (let ((key (bison-space--key group (alist-get 'name tab))))
          (push key open)
          (puthash key (list group (alist-get 'name tab) nil) table))))
    (dolist (root (project-known-project-roots))
      (pcase-let* ((`(,org ,repo ,name) (bison-space--names root))
                   (key (bison-space--key (concat org "/" repo) name)))
        (unless (gethash key table)
          (puthash key (list nil nil root) table))))
    (let* ((keys (append (sort open #'string<)
                         (sort (seq-remove (lambda (k) (member k open))
                                           (hash-table-keys table))
                               #'string<)))
           (choice (completing-read
                    "Space: "
                    (lambda (string pred action)
                      (if (eq action 'metadata)
                          `(metadata
                            (category . bison-space)
                            (display-sort-function . identity)
                            (group-function
                             . ,(lambda (key transform)
                                  (cond (transform key)
                                        ((member key open) "Open")
                                        (t "Projects")))))
                        (complete-with-action action keys string pred)))
                    nil t)))
      (pcase-let ((`(,group ,name ,root) (gethash choice table)))
        (if group
            (tab-bar-select-tab (1+ (bison-space--tab-index group name)))
          (let ((default-directory root))
            (bison-space)))))))

(defun bison-space--wt (args on-success)
  "Run wt with ARGS in `default-directory', asynchronously.
On success, call ON-SUCCESS with wt's JSON result as an alist, or nil
if it printed none.  On failure, show wt's report in *wt*.

The human-readable report goes to stderr, kept in *wt* for when it
fails; ARGS should ask for --format json, which goes to stdout.  No
--yes: a project hook still waiting for approval should fail here,
with stdin closed, rather than run unreviewed."
  (unless (executable-find "wt")
    (user-error "No wt on PATH"))
  (let ((out (generate-new-buffer " *wt-json*"))
        (log (get-buffer-create "*wt*")))
    (with-current-buffer log
      (let ((inhibit-read-only t))
        (erase-buffer)))
    (process-send-eof
     (make-process
      :name "wt"
      :buffer out
      :stderr log
      :connection-type 'pipe
      :command (cons "wt" args)
      :sentinel
      (lambda (proc _event)
        (unless (process-live-p proc)
          (unwind-protect
              (if (zerop (process-exit-status proc))
                  (funcall on-success
                           (with-current-buffer out
                             (goto-char (point-min))
                             (and (re-search-forward "[{[]" nil t)
                                  (progn (goto-char (match-beginning 0))
                                         (json-parse-buffer
                                          :object-type 'alist)))))
                (display-buffer log)
                (message "wt %s failed; see *wt*" (car args)))
            (kill-buffer out))))))))

(defun bison-space-new-worktree (branch &optional base)
  "Start a work stream on new BRANCH: a worktree from wt, in its own space.
The worktree belongs to the current project's repository, or in the
sidebar to the repository of the line at point.  With a prefix
argument, also read BASE, the branch to start from; wt defaults to
the repository's default branch."
  (interactive
   (list (read-string "New branch: ")
         (and current-prefix-arg (read-string "Base branch: "))))
  (when (string-empty-p branch)
    (user-error "No branch given"))
  (let ((default-directory (or (nth 2 (bison-space--context))
                               (user-error "Reopen this space first"))))
    (message "Creating a worktree for %s..." branch)
    ;; --no-cd: there is no shell to move.  The JSON says where the
    ;; worktree went; wt sanitizes the branch for the directory.
    (bison-space--wt
     `("switch" "--create" ,branch "--no-cd" "--format" "json"
       ,@(and base (list "--base" base)))
     (lambda (result)
       (let ((default-directory
              (file-name-as-directory (alist-get 'path result))))
         (bison-space))))))

(defun bison-space-remove-worktree (&optional force)
  "Remove the current space's worktree with wt, then close the space.
In the sidebar, the space on the line at point.  wt refuses a dirty
worktree and keeps an unmerged branch; with prefix argument FORCE,
it discards uncommitted changes and deletes the branch regardless.
The space stays open if wt fails."
  (interactive "P")
  (pcase-let* ((`(,group ,name ,root) (bison-space--context))
               (repo (file-name-nondirectory group)))
    (when (equal name repo)
      (user-error "%s is the main checkout, not a worktree" repo))
    (unless root
      (user-error "Reopen this space first"))
    (let* ((root (directory-file-name root))
           (label (bison-space--label group name))
           ;; Run from the main checkout, never from inside the worktree.
           (default-directory (file-name-directory
                               (directory-file-name
                                (file-name-directory root)))))
      (when (yes-or-no-p (format "%s worktree %s and close its space? "
                                 (if force "Force-remove" "Remove") label))
        (message "Removing worktree %s..." label)
        (bison-space--wt
         `("remove" "--foreground" "--format" "json"
           ,@(and force '("--force" "--force-delete"))
           ,root)
         (lambda (_result)
           (bison-space--kill group name)
           (message "Removed worktree %s" label)))))))

;;;; Sidebar

(defgroup bison-space nil
  "Spaces: a tab per work stream, listed in a sidebar."
  :group 'convenience)

(defcustom bison-space-sidebar-width 32
  "Width of the spaces sidebar, in columns of the frame's font."
  :type 'natnum)

(defcustom bison-space-sidebar-text-scale 0.9
  "Font height of the sidebar, relative to other buffers."
  :type 'number)

(defcustom bison-space-sidebar-line-spacing 0.4
  "Extra space around each sidebar row, as a fraction of its height.
Split evenly above and below, so the text sits centred in the row."
  :type 'number)

;; Colours are the doom-gruvbox palette, falling back to theme faces on
;; terminals with fewer colours.
(defface bison-space-sidebar
  '((((class color) (min-colors 88)) :background "#1d2021")
    (t))
  "Default face of the sidebar: a panel darker than the buffers.")

(defface bison-space-sidebar-header
  '((((class color) (min-colors 88)) :foreground "#665c54" :weight bold)
    (t :inherit shadow))
  "Face of the sidebar's header line.")

(defface bison-space-sidebar-header-line
  '((((class color) (min-colors 88))
     :background "#1d2021" :box (:line-width (1 . 8) :color "#1d2021"))
    (t))
  "Face of the sidebar's header line as a whole.
The box, in the background colour, pads it above and below; its
side width must be at least 1, and is invisible against the panel.")

(defface bison-space-sidebar-org
  '((((class color) (min-colors 88)) :foreground "#7c6f64")
    (t :inherit shadow))
  "Face of an org heading in the sidebar.")

(defface bison-space-sidebar-icon
  '((t :inherit shadow))
  "Face of the repo and worktree icons in the sidebar.")

(defface bison-space-sidebar-closed
  '((t :inherit shadow))
  "Face of a repo whose main checkout has no open space.")

(defface bison-space-sidebar-current
  '((((class color) (min-colors 88))
     :background "#3c3836" :weight bold :extend t)
    (t :inherit (bold highlight) :extend t))
  "Face of the current space's row.")

(defface bison-space-sidebar-hover
  '((((class color) (min-colors 88)) :background "#504945" :extend t)
    (t :inherit highlight :extend t))
  "Face of the row under the mouse.")

(defface bison-space-sidebar-hl-line
  '((((class color) (min-colors 88)) :background "#32302f" :extend t)
    (t :inherit hl-line))
  "Face of the line at point while the sidebar is selected.")

(defconst bison-space--sidebar-name "*spaces*")

(defvar-local bison-space--sidebar-count 0
  "Number of open spaces, for the header line.")

(defun bison-space--sidebar-window ()
  "Return the sidebar's window in the selected frame, or nil."
  (get-buffer-window bison-space--sidebar-name (selected-frame)))

(defun bison-space--tree ()
  "Return the open spaces of this frame as ((ORG (REPO SPACE...)...)...).
Each SPACE is (GROUP NAME CURRENT), sorted by name at every level."
  (let (tree)
    (dolist (tab (funcall tab-bar-tabs-function))
      (when-let* ((group (alist-get 'group tab))
                  ((string-search "/" group)))
        (let* ((org (substring (file-name-directory group) 0 -1))
               (repo (file-name-nondirectory group))
               (orgs (or (assoc org tree)
                         (car (push (list org) tree))))
               (repos (or (assoc repo (cdr orgs))
                          (car (push (list repo) (cdr orgs))))))
          (push (list group (alist-get 'name tab)
                      (eq (car tab) 'current-tab))
                (cdr repos)))))
    (let ((by-car (lambda (a b) (string< (car a) (car b))))
          (by-name (lambda (a b) (string< (cadr a) (cadr b)))))
      (mapcar (lambda (org)
                (cons (car org)
                      (mapcar (lambda (repo)
                                (cons (car repo) (sort (cdr repo) by-name)))
                              (sort (cdr org) by-car))))
              (sort tree by-car)))))

(defun bison-space--icon (name)
  "Return the octicon NAME and a space, or nothing without nerd-icons."
  (if (require 'nerd-icons nil t)
      (let ((icon (copy-sequence (nerd-icons-octicon name))))
        (add-face-text-property 0 (length icon) 'bison-space-sidebar-icon
                                t icon)
        (concat icon " "))
    ""))

(defvar bison-space--sidebar-row-padding nil
  "The (ABOVE . BELOW) pixels padding each row, bound while rendering.")

(defun bison-space--sidebar-newline ()
  "Return a newline ending a row padded per `bison-space-sidebar-line-spacing'.
Emacs puts `line-spacing' below a line only; a `line-height' taller
than the font adds the rest above it."
  (pcase-let ((`(,above . ,below) bison-space--sidebar-row-padding))
    (propertize "\n"
                'line-height (+ (default-font-height) above)
                'line-spacing below)))

(defun bison-space--sidebar-insert-row (space indent icon text)
  "Insert a row for SPACE at INDENT: ICON, then TEXT.
SPACE is (GROUP NAME CURRENT), or nil for a repo with no space open."
  (pcase-let ((`(,group ,name ,current) space)
              (start (point)))
    (insert (make-string indent ?\s) (bison-space--icon icon)
            (propertize text 'face (unless space 'bison-space-sidebar-closed))
            (bison-space--sidebar-newline))
    (when current
      (add-face-text-property start (point) 'bison-space-sidebar-current))
    (when space
      ;; Through the newline, so the hover face's :extend fills the row.
      ;; A fresh list per row: Emacs highlights the whole run of text
      ;; whose mouse-face is `eq', which would join adjacent rows.
      (add-text-properties start (point)
                           `(bison-space ,(cons group name)
                             mouse-face ,(list 'bison-space-sidebar-hover)
                             help-echo "mouse-1: switch to this space")))))

(defun bison-space--sidebar-render ()
  "Redraw the sidebar from the selected frame's tabs, if it exists.
Point stays on its line while the sidebar is selected, and otherwise
follows the current space, so it is there on the next visit."
  (when-let* ((buffer (get-buffer bison-space--sidebar-name)))
    (with-current-buffer buffer
      (let* ((inhibit-read-only t)
             (line (line-number-at-pos))
             (count 0)
             ;; In this buffer, so the height is that of its smaller font.
             (extra (round (* (default-font-height)
                              bison-space-sidebar-line-spacing)))
             (bison-space--sidebar-row-padding
              (cons (/ extra 2) (- extra (/ extra 2)))))
        (erase-buffer)
        (pcase-dolist (`(,org . ,repos) (bison-space--tree))
          (unless (bobp) (insert "\n"))
          (insert " " (propertize org 'face 'bison-space-sidebar-org)
                  (bison-space--sidebar-newline))
          (pcase-dolist (`(,repo . ,spaces) repos)
            ;; The main checkout is the repo row itself; worktrees are
            ;; listed under it.
            (let ((main (seq-find (lambda (s) (equal (cadr s) repo)) spaces)))
              (bison-space--sidebar-insert-row main 1 "nf-oct-repo" repo)
              (dolist (space (remq main spaces))
                (bison-space--sidebar-insert-row space 3 "nf-oct-git_branch"
                                                 (cadr space)))
              (setq count (+ count (length spaces))))))
        (setq bison-space--sidebar-count count)
        (when (bobp)
          (insert (propertize
                   (substitute-command-keys
                    " No open spaces.\n\n \\[bison-space-switch] opens one,\n \\[bison-space-help] lists the keys.")
                   'face 'shadow)))
        (goto-char (point-min))
        (if (eq (get-buffer-window buffer) (selected-window))
            (forward-line (1- line))
          (when-let* ((match (text-property-search-forward
                              'face 'bison-space-sidebar-current
                              (lambda (face faces)
                                (memq face (ensure-list faces))))))
            (goto-char (prop-match-beginning match)))
          ;; A window shows its own point, not the buffer's.
          (dolist (window (get-buffer-window-list buffer nil t))
            (set-window-point window (point))))
        (force-mode-line-update)))))

(defun bison-space--sidebar-fit (&optional frame)
  "Hold the sidebar in FRAME at `bison-space-sidebar-width' columns.
Runs from `window-size-change-functions': `preserve-size' keeps the
width when sibling windows change, but not when the frame itself is
resized, as on maximizing, which spreads the change proportionally."
  (when-let* ((window (get-buffer-window bison-space--sidebar-name
                                         (or frame (selected-frame))))
              (delta (- (* bison-space-sidebar-width
                           (frame-char-width (window-frame window)))
                        (window-pixel-width window)))
              ((not (zerop delta))))
    (window-preserve-size window t nil)
    ;; Pixelwise, else the resize rounds and the next check fires again.
    (let ((window-resize-pixelwise t))
      (ignore-errors (window-resize window delta t nil t)))
    (window-preserve-size window t t)))

(defun bison-space--sidebar-header ()
  "Return the sidebar's header line: a title and the count of spaces."
  (let ((count (number-to-string bison-space--sidebar-count)))
    (concat (propertize " Spaces" 'face 'bison-space-sidebar-header)
            (propertize " " 'display
                        `(space :align-to (- right ,(1+ (length count)))))
            (propertize count 'face 'bison-space-sidebar-header))))

(defun bison-space--sidebar-sync (&rest _)
  "Show or hide the sidebar per this frame's setting, then redraw it.
Takes and ignores any arguments, so it can run from tab-bar hooks."
  (let ((window (bison-space--sidebar-window)))
    (cond ((and (frame-parameter nil 'bison-space-sidebar) (not window))
           (set-window-fringes
            (display-buffer-in-side-window
             (bison-space--sidebar-buffer)
             `((side . left) (slot . 0)
               (window-width . ,bison-space-sidebar-width)
               (preserve-size . (t . nil))
               (dedicated . t)
               (window-parameters . ((no-other-window . t)
                                     (no-delete-other-windows . t)))))
            0 0))
          ((and window (not (frame-parameter nil 'bison-space-sidebar)))
           (delete-window window))))
  ;; `window-width' in the display action counts columns of the
  ;; sidebar's own, smaller font; fit to the frame's columns instead.
  (bison-space--sidebar-fit)
  (bison-space--sidebar-render))

(defun bison-space--sidebar-buffer ()
  "Return the sidebar buffer, creating it."
  (or (get-buffer bison-space--sidebar-name)
      (with-current-buffer (get-buffer-create bison-space--sidebar-name)
        (bison-space-sidebar-mode)
        (current-buffer))))

(defun bison-space-sidebar-toggle ()
  "Show the spaces sidebar and select it, or hide it if it is selected.
When the sidebar is shown but not selected, select it."
  (interactive)
  (let ((window (bison-space--sidebar-window)))
    (cond ((and window (eq window (selected-window)))
           (set-frame-parameter nil 'bison-space-sidebar nil)
           (bison-space--sidebar-sync))
          (t
           (set-frame-parameter nil 'bison-space-sidebar t)
           (bison-space--sidebar-sync)
           (select-window (bison-space--sidebar-window))))))

(defun bison-space--at-point ()
  "Return (GROUP . NAME) for the sidebar line at point, or signal."
  (or (get-text-property (line-beginning-position) 'bison-space)
      (user-error "No space on this line")))

(defun bison-space-sidebar-select ()
  "Switch to the space on this sidebar line."
  (interactive)
  (pcase-let ((`(,group . ,name) (bison-space--at-point)))
    (when-let* ((index (bison-space--tab-index group name)))
      (tab-bar-select-tab (1+ index)))))

(defun bison-space-sidebar-next (n)
  "Move to the Nth next space in the sidebar, skipping headings."
  (interactive "p")
  (let ((step (if (< n 0) -1 1))
        (target (point)))
    (save-excursion
      (dotimes (_ (abs n))
        (goto-char target)
        (let (found)
          (while (and (not found)
                      (zerop (forward-line step))
                      (not (eobp)))
            (when (get-text-property (point) 'bison-space)
              (setq found (point))))
          (when found
            (setq target found)))))
    (goto-char target)))

(defun bison-space-sidebar-previous (n)
  "Move to the Nth previous space in the sidebar, skipping headings."
  (interactive "p")
  (bison-space-sidebar-next (- n)))

(defvar-keymap bison-space-sidebar-mode-map
  "RET" #'bison-space-sidebar-select
  "<mouse-1>" #'bison-space-sidebar-select
  "/" #'bison-space-switch
  "r" #'bison-space-reset
  "k" #'bison-space-close
  "c" #'bison-space-new-worktree
  "D" #'bison-space-remove-worktree
  "n" #'bison-space-sidebar-next
  "p" #'bison-space-sidebar-previous
  "<down>" #'bison-space-sidebar-next
  "<up>" #'bison-space-sidebar-previous
  "?" #'bison-space-help
  "q" #'bison-space-sidebar-toggle)

(defun bison-space--sidebar-hints ()
  "Return the key hints shown in the sidebar's mode line."
  (propertize (substitute-command-keys
               "\\<bison-space-sidebar-mode-map>\\[bison-space-help] help   \\[bison-space-switch] search   \\[bison-space-sidebar-toggle] hide")
              'face 'bison-space-sidebar-header))

;; A mode line like every other window's, so the row above the echo
;; area runs unbroken across the frame.  doom-modeline's bar segment
;; gives it the same height as theirs.
(with-eval-after-load 'doom-modeline
  (doom-modeline-def-modeline 'bison-space-sidebar
    `(bar "  " ,(bison-space--sidebar-hints))))

(define-derived-mode bison-space-sidebar-mode special-mode "Spaces"
  "Major mode for the spaces sidebar.
\\{bison-space-sidebar-mode-map}"
  (setq-local cursor-type nil
              truncate-lines t
              header-line-format '(:eval (bison-space--sidebar-header))
              hl-line-sticky-flag nil)
  (unless (and (featurep 'doom-modeline)
               (doom-modeline-set-modeline 'bison-space-sidebar))
    (setq-local mode-line-format
                (list "  " (bison-space--sidebar-hints))))
  (face-remap-add-relative 'default 'bison-space-sidebar
                           :height bison-space-sidebar-text-scale)
  ;; The header line does not follow the remapped default's height.
  (face-remap-add-relative 'header-line 'bison-space-sidebar-header-line
                           :height bison-space-sidebar-text-scale
                           :underline nil :overline nil)
  (face-remap-add-relative 'fringe 'bison-space-sidebar)
  (face-remap-add-relative 'hl-line 'bison-space-sidebar-hl-line)
  (hl-line-mode 1))

;;;; Help

(defconst bison-space--help
  "Spaces

A space is a work stream: a repository's main checkout, or one of its
worktrees, in a tab of its own with a shell on the left and Claude
Code on the right.  The sidebar lists the open spaces by org and repo.

Everywhere

  \\[bison-space-switch]	Switch to a space, or open one for any project
  \\[bison-space]	Open or switch to the current project's space
	(\\[universal-argument] \\[bison-space]: start Claude with --continue)
  \\[bison-space-reset]	Reset this space's layout, recreating lost terminals
  \\[bison-space-close]	Close this space and kill its terminals
  \\[bison-space-new-worktree]	New worktree on a new branch, in a new space
	(\\[universal-argument] \\[bison-space-new-worktree]: also ask for the base branch)
  \\[bison-space-remove-worktree]	Remove this space's worktree, then close it
	(\\[universal-argument] \\[bison-space-remove-worktree]: even if dirty or unmerged)
  \\[bison-space-sidebar-toggle]	Show and focus the sidebar; again to hide it
  \\[bison-space-help]	This help

  From \\[project-switch-project], `s' opens the chosen project's space.

In the sidebar
\\<bison-space-sidebar-mode-map>
  \\[bison-space-sidebar-select]	Switch to the space at point
  \\[bison-space-switch]	Search all spaces and projects
  \\[bison-space-sidebar-next] \\[bison-space-sidebar-previous]	Next / previous space
  \\[bison-space-reset]	Reset the space at point
  \\[bison-space-close]	Close the space at point
  \\[bison-space-new-worktree]	New worktree of the repo at point
  \\[bison-space-remove-worktree]	Remove the worktree at point
  \\[bison-space-help]	This help
  \\[bison-space-sidebar-toggle]	Hide the sidebar

\\<global-map>Notes

  A space's terminals are named *REPO[/WORKTREE]: shell* and
  *...: claude*; \\[consult-buffer] finds them when the layout is gone.
  wt reports from the worktree commands land in *wt*.
  Spaces do not survive a restart: reopen them, with \\[universal-argument] to resume Claude.

Font size (everywhere)

  \\[bison-font-size-increase] \\[bison-font-size-decrease] \\[bison-font-size-reset]	Bigger / smaller / reset"
  "Text of `bison-space-help', with keys substituted when shown.")

(defun bison-space-help ()
  "Show the keys and concepts of spaces."
  (interactive)
  (with-help-window "*Spaces Help*"
    (princ (substitute-command-keys bison-space--help)))
  (with-current-buffer "*Spaces Help*"
    (let ((inhibit-read-only t))
      (goto-char (point-min))
      (put-text-property (point) (line-end-position) 'face 'bold)
      (while (re-search-forward "^\\(Everywhere\\|In the sidebar\\|Notes\\|Font size.*\\)$" nil t)
        (put-text-property (match-beginning 0) (match-end 0) 'face 'bold))
      (setq-local tab-width 24))))

;; Each tab's layout remembers the sidebar as it was; re-apply the
;; frame's setting after a switch.  Closing a tab has only a pre hook,
;; so redraw once it is gone.
(add-hook 'tab-bar-tab-post-select-functions #'bison-space--sidebar-sync)
(defun bison-space--sidebar-sync-later (&rest _)
  "Sync the sidebar once the current command, such as closing a tab, is done."
  (run-at-time 0 nil #'bison-space--sidebar-sync))

(add-hook 'tab-bar-tab-pre-close-functions #'bison-space--sidebar-sync-later)
(add-hook 'window-size-change-functions #'bison-space--sidebar-fit)

(global-set-key (kbd "C-c s") #'bison-space)
(global-set-key (kbd "C-c S") #'bison-space-close)
(global-set-key (kbd "C-c b") #'bison-space-sidebar-toggle)
(global-set-key (kbd "C-c N") #'bison-space-new-worktree)
(global-set-key (kbd "C-c D") #'bison-space-remove-worktree)
(global-set-key (kbd "C-c R") #'bison-space-reset)
(global-set-key (kbd "C-c f") #'bison-space-switch)
(global-set-key (kbd "C-c ?") #'bison-space-help)

(provide 'bison-spaces)
;;; bison-spaces.el ends here
