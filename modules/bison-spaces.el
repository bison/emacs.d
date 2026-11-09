;;; bison-spaces.el --- A tab per work stream: a shell and its agents  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; A space is a project.el project -- a repository, or one of its
;; worktrees under <repo>/.worktrees/<branch> -- in a tab of its own.
;; It holds one shell, on the left, and any number of agents -- Claude
;; Code, Codex, or whatever `bison-space-harnesses' lists -- shown one
;; at a time in the agent window on the right.  A space with no agent
;; shows a launcher there instead, so starting one is a keystroke.
;;
;; Nothing is registered here: project.el already knows every repo and
;; worktree (`bison-project-discover' plus the worktrunk hooks), so
;; `bison-space' only finds or makes the tab.  Run it from
;; `project-switch-project' (C-x p p ... s) or on the current project.
;;
;; The shell runs tmux by default, in a session named per
;; `bison-space-tmux-session', which outlives Emacs: reopening the space
;; reattaches.  Agents stay outside tmux, where they can report their
;; status to ghostel.
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
(declare-function ghostel-exec "ghostel")
(declare-function nerd-icons-octicon "nerd-icons")
(declare-function doom-modeline-def-modeline "doom-modeline-core")
(declare-function doom-modeline-set-modeline "doom-modeline-core")
(defvar ghostel-buffer-name)
(defvar ghostel-program-status)
(defvar ghostel-query-before-killing)
(defvar ghostel-kill-buffer-on-exit)
(defvar ghostel--process)
(defvar ghostel-status-mode-line-labels)

(use-package tab-bar
  :straight (:type built-in)
  :custom
  (tab-bar-show nil))
;;;; Settings

(defgroup bison-space nil
  "Spaces: a tab per work stream, listed in a sidebar."
  :group 'convenience)

(defcustom bison-space-harnesses
  '((claude :name "Claude Code" :command "claude"
            :resume "claude --continue" :key ?c)
    (codex :name "Codex" :command "codex"
           :resume "codex resume --last" :key ?x))
  "Agent harnesses a space can start, as (SYMBOL . PLIST).
:name is shown in the launcher, :command starts a new session,
:resume continues the last one in the directory, and :key starts it
from the launcher."
  :type '(alist :key-type symbol :value-type plist))

(defcustom bison-space-default-harness 'claude
  "The harness offered first, and started by \[universal-argument] \[bison-space]."
  :type 'symbol)

(defcustom bison-space-shell 'tmux
  "What a space's shell runs: `tmux', or nil for the plain login shell.
tmux attaches to the session `bison-space-tmux-session' names,
creating it, so a space's shell survives Emacs: reopening the space
reattaches."
  :type '(choice (const :tag "tmux session" tmux)
                 (const :tag "Plain shell" nil)))

(defcustom bison-space-tmux-session "emacs-%s"
  "Template for a space's tmux session name, for `format-spec'.
%s is the repo, or repo-worktree for a worktree; %o the org, %r the
repo and %n the worktree, or the repo for the main checkout.
Characters tmux does not allow become dashes."
  :type 'string)

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

;;;; Terminals

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

(defun bison-space--tmux-name (string)
  "Return STRING with runs of characters tmux disallows as single dashes."
  (string-trim (replace-regexp-in-string "[^[:alnum:]_-]+" "-" string)
               "-+" "-+"))

(defun bison-space--tmux-session (group name)
  "Return the tmux session name of space NAME in GROUP."
  (let* ((org (bison-space--tmux-name (car (split-string group "/"))))
         (repo (bison-space--tmux-name (file-name-nondirectory group)))
         (name* (bison-space--tmux-name name))
         (both (if (equal repo name*) repo (concat repo "-" name*))))
    (bison-space--tmux-name
     (format-spec bison-space-tmux-session
                  `((?s . ,both) (?o . ,org) (?r . ,repo) (?n . ,name*))))))

(defun bison-space--shell-command (group name)
  "Return the command typed into the shell of space NAME in GROUP, or nil."
  (when (and (eq bison-space-shell 'tmux) (executable-find "tmux"))
    ;; A session takes its environment from the tmux server, which may
    ;; have been started outside Emacs; hand it this terminal's editor,
    ;; and INSIDE_EMACS so the shell rc keeps that editor.  The shell
    ;; expands them.  An existing session keeps what it was made with.
    (format "tmux new-session -A -s %s -e \"EDITOR=$EDITOR\" -e \"VISUAL=$VISUAL\" -e \"INSIDE_EMACS=$INSIDE_EMACS\""
            (shell-quote-argument (bison-space--tmux-session group name)))))

(defun bison-space--kill-tmux-session (group name)
  "Kill the tmux session of space NAME in GROUP, if it has one."
  (when (and (eq bison-space-shell 'tmux) (executable-find "tmux"))
    (call-process "tmux" nil 0 nil "kill-session" "-t"
                  (concat "=" (bison-space--tmux-session group name)))))

;;;; Agents

;; An agent is a ghostel terminal running its harness as the program
;; itself, through a login shell for its environment: when the harness
;; exits, so does the terminal, and the agent window moves on to the
;; space's next agent or the launcher.  It records its space and harness
;; in `bison-space-agent', so a space finds its agents by asking the
;; buffers, not by parsing their names.

(defvar-local bison-space-agent nil
  "In an agent terminal: (GROUP NAME HARNESS SERIAL COMMAND).
HARNESS is a key of `bison-space-harnesses', or `other'; SERIAL orders
a space's agents by creation; COMMAND is what it runs.")
(put 'bison-space-agent 'permanent-local t)

(defvar bison-space--agent-serial 0)

(defun bison-space--agents (group name)
  "Return the live agent terminals of space NAME in GROUP, oldest first."
  (sort (seq-filter (lambda (buffer)
                      (let ((agent (buffer-local-value 'bison-space-agent buffer)))
                        (and agent
                             (equal (nth 0 agent) group)
                             (equal (nth 1 agent) name))))
                    (buffer-list))
        (lambda (a b)
          (< (nth 3 (buffer-local-value 'bison-space-agent a))
             (nth 3 (buffer-local-value 'bison-space-agent b))))))

(defun bison-space--agent-window ()
  "Return the selected tab's agent window, or nil.
It is the window weakly dedicated to `bison-space': `display-buffer'
\(magit, help, compile) goes elsewhere, but an explicit
`switch-to-buffer' there still works."
  (seq-find (lambda (window) (eq (window-dedicated-p window) 'bison-space))
            (window-list nil 'nomini)))

(defun bison-space--show-agent (buffer)
  "Show BUFFER in the agent window and select it."
  (let ((window (or (bison-space--agent-window)
                    (user-error "This space has no agent window; reset it with %s"
                                (substitute-command-keys "\\[bison-space-reset]")))))
    (select-window window)
    (set-window-dedicated-p window nil)
    (switch-to-buffer buffer nil t)
    (set-window-dedicated-p window 'bison-space)))

(defun bison-space--fresh-name (label tag)
  "Return an unused agent buffer name for TAG in space LABEL."
  (let ((base (format "*%s: %s*" label tag))
        (n 1)
        name)
    (setq name base)
    (while (get-buffer name)
      (setq n (1+ n)
            name (format "*%s: %s<%d>*" label tag n)))
    name))

(defun bison-space--start-agent (group name root harness command)
  "Start an agent typing COMMAND in space NAME in GROUP at ROOT.
HARNESS is its key of `bison-space-harnesses', or `other'.  The new
terminal is shown in the agent window; return it."
  (let* ((default-directory (file-name-as-directory root))
         (tag (if (eq harness 'other)
                  (file-name-nondirectory (car (split-string-shell-command command)))
                (symbol-name harness)))
         (window (or (bison-space--agent-window)
                     (user-error "This space has no agent window; reset it with %s"
                                 (substitute-command-keys "\\[bison-space-reset]"))))
         buffer)
    (select-window window)
    (set-window-dedicated-p window nil)
    (setq buffer (get-buffer-create
                  (bison-space--fresh-name (bison-space--label group name) tag)))
    (with-current-buffer buffer
      (setq default-directory (file-name-as-directory root)))
    ;; Shown first: `ghostel-exec' sizes the terminal to its window.
    (switch-to-buffer buffer nil t)
    (set-window-dedicated-p window 'bison-space)
    (ghostel-exec buffer (or (getenv "SHELL") "/bin/zsh")
                  (list "-l" "-i" "-c" command))
    (with-current-buffer buffer
      (setq bison-space-agent
            (list group name harness (cl-incf bison-space--agent-serial) command))
      (add-hook 'kill-buffer-hook #'bison-space--agent-killed nil t)
      (bison-space-agent-mode 1))
    (bison-space--sidebar-render)
    buffer))

(defun bison-space--harness-command (harness resume)
  "Return the command starting HARNESS, or resuming it if RESUME."
  (let ((spec (or (alist-get harness bison-space-harnesses)
                  (user-error "No harness %s in `bison-space-harnesses'" harness))))
    (or (and resume (plist-get spec :resume))
        (plist-get spec :command))))

(defun bison-space--read-harness ()
  "Read a harness, default first; return its symbol or a command string."
  (let* ((names (mapcar (lambda (entry) (symbol-name (car entry)))
                        bison-space-harnesses))
         (default (symbol-name bison-space-default-harness))
         (choices (append (cons default (delete default names))
                          '("other command...")))
         (choice (completing-read "Start agent: " choices nil t nil nil default)))
    (if (equal choice "other command...")
        (read-shell-command "Command: ")
      (intern choice))))

(defun bison-space-add-agent (harness &optional resume)
  "Start a HARNESS agent in the current space's agent window.
Read the harness, or any command, from the minibuffer.  With a prefix
argument RESUME, start it with its :resume command, continuing its
last session in this directory.  Other agents keep running; cycle
between them with \\<bison-space-agent-mode-map>\\[bison-space-agent-next] \
and \\[bison-space-agent-previous]."
  (interactive (list (bison-space--read-harness) current-prefix-arg))
  (pcase-let* ((`(,group ,name) (bison-space--current))
               (root (or (gethash (cons group name) bison-space--roots)
                         (user-error "No root known for %s" name))))
    (if (stringp harness)
        (bison-space--start-agent group name root 'other harness)
      (bison-space--start-agent group name root harness
                                (bison-space--harness-command harness resume)))))

(defun bison-space-agent-next (n)
  "Show the Nth next agent of this space in the agent window."
  (interactive "p")
  (pcase-let* ((`(,group ,name) (bison-space--current))
               (agents (or (bison-space--agents group name)
                           (user-error "No agents in this space")))
               (window (bison-space--agent-window))
               (index (or (and window (seq-position agents (window-buffer window)))
                          -1)))
    (if (and (= (length agents) 1) (>= index 0))
        (message "%s is the only agent here" (buffer-name (car agents)))
      (bison-space--show-agent
       (nth (mod (+ index n) (length agents)) agents)))))

(defun bison-space-agent-previous (n)
  "Show the Nth previous agent of this space in the agent window."
  (interactive "p")
  (bison-space-agent-next (- n)))

(defvar-keymap bison-space-agent-mode-map
  "M-n" #'bison-space-agent-next
  "M-p" #'bison-space-agent-previous)

;; A minor mode: its map outranks ghostel's, which is the buffer's local
;; map and would otherwise send M-n and M-p to the program.
(define-minor-mode bison-space-agent-mode
  "Keys for moving between a space's agents, in agent terminals.
\\{bison-space-agent-mode-map}"
  :lighter nil)

(defun bison-space--agent-running-p (buffer)
  "Return non-nil if agent terminal BUFFER's harness is still running."
  (process-live-p (buffer-local-value 'ghostel--process buffer)))

(defun bison-space--agent-exited (buffer event)
  "Keep agent BUFFER open if its harness failed, per EVENT.
A member of `ghostel-exit-functions'.  A clean exit, or one by Ctrl-C
or a hangup, lets ghostel kill the buffer; any other leaves it showing
the harness's last words, until you kill it."
  (when (buffer-local-value 'bison-space-agent buffer)
    (let ((code (if (string-match "code \\([0-9]+\\)" event)
                    (string-to-number (match-string 1 event))
                  0)))
      ;; 128+N: killed by signal N -- 1 hangup, 2 interrupt, 15 term.
      (unless (memq code '(0 129 130 143))
        (with-current-buffer buffer
          (setq-local ghostel-kill-buffer-on-exit nil))
        (message "%s exited with code %d" (buffer-name buffer) code)))
    (bison-space--status-changed nil nil nil)))

(defvar bison-space--killing nil
  "Non-nil while a whole space is being killed.")

(defun bison-space--successor (buffer)
  "Return what the agent window should show once agent BUFFER is gone.
The space's next agent, wrapping around, or its launcher."
  (pcase-let* ((`(,group ,name ,_ ,serial) (buffer-local-value 'bison-space-agent buffer))
               (others (remq buffer (bison-space--agents group name))))
    (or (seq-find (lambda (other)
                    (> (nth 3 (buffer-local-value 'bison-space-agent other)) serial))
                  others)
        (car others)
        (bison-space--launcher group name
                               (or (gethash (cons group name) bison-space--roots)
                                   default-directory)))))

(defun bison-space--agent-killed ()
  "Move agent windows showing this agent on, before it goes.
In `kill-buffer-hook' of agent terminals.  Before the kill, because
Emacs deletes a dedicated window when its buffer dies: switched away
first, the agent window stays."
  (unless bison-space--killing
    (let ((windows (seq-filter (lambda (window)
                                 (eq (window-dedicated-p window) 'bison-space))
                               (get-buffer-window-list (current-buffer) nil t))))
      (when windows
        (let ((next (bison-space--successor (current-buffer))))
          (dolist (window windows)
            (set-window-dedicated-p window nil)
            (set-window-buffer window next)
            (set-window-dedicated-p window 'bison-space)))))
    (run-at-time 0 nil #'bison-space--status-changed nil nil nil)))

(defun bison-space--repair-agent-window (&rest _)
  "Point the selected tab's agent window at an agent or the launcher.
After a switch to a tab whose agent was killed while it was out of
view, the window shows whatever Emacs picked instead."
  (when-let* ((window (bison-space--agent-window))
              (tab (tab-bar--current-tab))
              (group (alist-get 'group tab))
              ((string-search "/" group)))
    (let* ((name (alist-get 'name tab))
           (shown (window-buffer window))
           (agents (bison-space--agents group name)))
      (unless (or (memq shown agents)
                  (eq (buffer-local-value 'major-mode shown)
                      'bison-space-launcher-mode))
        (set-window-dedicated-p window nil)
        (set-window-buffer
         window (or (car agents)
                    (bison-space--launcher
                     group name (or (gethash (cons group name) bison-space--roots)
                                    default-directory))))
        (set-window-dedicated-p window 'bison-space)))))

(with-eval-after-load 'ghostel
  (add-hook 'ghostel-exit-functions #'bison-space--agent-exited))
(add-hook 'tab-bar-tab-post-select-functions #'bison-space--repair-agent-window)

;;;; Launcher

(defvar-local bison-space--launcher-space nil
  "In a launcher: (GROUP NAME ROOT) of its space.")

(defface bison-space-launcher-title
  '((((class color) (min-colors 88)) :foreground "#a89984" :weight bold)
    (t :inherit bold))
  "Face of the launcher's title.")

(defface bison-space-launcher-key
  '((((class color) (min-colors 88)) :foreground "#fabd2f" :weight bold)
    (t :inherit help-key-binding))
  "Face of the launcher's keys.")

(defun bison-space--launcher (group name root)
  "Return the launcher of space NAME in GROUP at ROOT, creating it."
  (let ((buffer-name (format "*%s: agents*" (bison-space--label group name))))
    (or (get-buffer buffer-name)
        (with-current-buffer (get-buffer-create buffer-name)
          (bison-space-launcher-mode)
          (setq bison-space--launcher-space (list group name root)
                default-directory (file-name-as-directory root))
          (bison-space--launcher-render)
          (current-buffer)))))

(defun bison-space--launcher-render ()
  "Draw the launcher and bind its harness keys."
  (pcase-let ((`(,group ,name ,_) bison-space--launcher-space)
              (map (make-sparse-keymap))
              (inhibit-read-only t))
    (set-keymap-parent map bison-space-launcher-mode-map)
    (erase-buffer)
    (insert "\n  " (propertize (format "Start an agent in %s"
                                       (bison-space--label group name))
                               'face 'bison-space-launcher-title)
            "\n\n")
    (pcase-dolist (`(,harness . ,spec) bison-space-harnesses)
      (when-let* ((key (plist-get spec :key)))
        (keymap-set map (char-to-string key)
                    (lambda (resume)
                      (interactive "P")
                      (bison-space--launch harness resume)))
        (insert (format "  %5s   %-14s %s\n"
                        (propertize (char-to-string key)
                                    'face 'bison-space-launcher-key)
                        (plist-get spec :name)
                        (propertize (plist-get spec :command) 'face 'shadow)))))
    (insert (format "  %5s   %s\n"
                    (propertize "RET" 'face 'bison-space-launcher-key)
                    "Another command")
            "\n  "
            (propertize
             (substitute-command-keys
              "\\[universal-argument] first resumes the last session.  \\[bison-space-help] for all keys.")
             'face 'shadow)
            "\n")
    (use-local-map map)
    (goto-char (point-min))))

(defun bison-space--launch (harness resume)
  "Start HARNESS from the launcher, resuming if RESUME; or a command string."
  (pcase-let ((`(,group ,name ,root) bison-space--launcher-space))
    (if (stringp harness)
        (bison-space--start-agent group name root 'other harness)
      (bison-space--start-agent group name root harness
                                (bison-space--harness-command harness resume)))))

(defun bison-space-launcher-command (command)
  "Start an agent running any shell COMMAND, from the launcher."
  (interactive (list (read-shell-command "Command: ")))
  (bison-space--launch command nil))

(defvar-keymap bison-space-launcher-mode-map
  "RET" #'bison-space-launcher-command
  "M-n" #'bison-space-agent-next
  "M-p" #'bison-space-agent-previous)

(define-derived-mode bison-space-launcher-mode special-mode "Agents"
  "The agent window of a space with no agents running in view.
\\{bison-space-launcher-mode-map}"
  (setq-local cursor-type nil
              truncate-lines t))

;;;; Opening and closing

(defun bison-space--layout (group name root)
  "Lay out the selected tab as space NAME in GROUP at ROOT.
The shell on the left and, on the right, the agent window: the agent
most recently in view, or the launcher when there is none.  Terminals
that still exist are reused; a missing shell is recreated."
  (let ((default-directory (file-name-as-directory root))
        (label (bison-space--label group name)))
    ;; `delete-other-windows' leaves the sidebar, a side window, alone,
    ;; but must not start from it.
    (when (window-parameter nil 'window-side)
      (select-window (get-mru-window nil nil t)))
    (delete-other-windows)
    ;; The surviving window may be the old agent window, still dedicated.
    (set-window-dedicated-p nil nil)
    (bison-space--terminal (format "*%s: shell*" label)
                           (bison-space--shell-command group name))
    (let ((window (split-window-right))
          (agents (bison-space--agents group name)))
      (select-window window)
      (switch-to-buffer
       (or (seq-find (lambda (buffer) (memq buffer agents)) (buffer-list))
           (bison-space--launcher group name root))
       nil t)
      (set-window-dedicated-p window 'bison-space))))

(defun bison-space--open (root group name)
  "Make the tab for space NAME in GROUP at ROOT."
  (puthash (cons group name) (file-name-as-directory root) bison-space--roots)
  ;; With the bar hidden, tab-bar narrates each of these steps.
  (let ((inhibit-message t))
    (tab-bar-new-tab)
    (tab-bar-rename-tab name)
    (tab-bar-change-tab-group group))
  (bison-space--layout group name root))

(defun bison-space (&optional resume)
  "Switch to the current project's space, making it on first use.
The space is a tab with the shell on the left and the agent window,
showing the launcher, on the right.  With prefix arg RESUME, a new
space starts `bison-space-default-harness' resuming its last session
instead of showing the launcher."
  (interactive "P")
  (pcase-let* ((root (project-root (project-current t)))
               (`(,org ,repo ,name) (bison-space--names root))
               (group (concat org "/" repo)))
    (if-let* ((index (bison-space--tab-index group name)))
        (tab-bar-select-tab (1+ index))
      (bison-space--open root group name)
      (when resume
        (bison-space--start-agent
         group name root bison-space-default-harness
         (bison-space--harness-command bison-space-default-harness t)))))
  (bison-space--sidebar-sync))

;; The space's terminals are found by name and by `bison-space-agent',
;; its tab by group and name; none depends on it being selected.
(defun bison-space--kill (group name)
  "Kill the terminals of space NAME in GROUP and close its tab.
A tmux session is left running, to reattach to later."
  (let ((label (bison-space--label group name))
        ;; The callers asked already; ghostel would ask again for each
        ;; terminal still running something -- tmux, an agent.
        (ghostel-query-before-killing nil)
        (bison-space--killing t))
    (dolist (buffer (append (bison-space--agents group name)
                            (delq nil (list (get-buffer (format "*%s: shell*" label))
                                            (get-buffer (format "*%s: agents*" label))))))
      (kill-buffer buffer))
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
In the sidebar, the space on the line at point.  Its tmux session
keeps running, so reopening the space reattaches."
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
  "Put the current space back to its layout: shell left, agent window right.
A killed shell is recreated, reattaching to its tmux session; the
agent window shows the agent last in view, or the launcher."
  (interactive)
  (pcase-let* ((`(,group ,name) (bison-space--current))
               (root (or (gethash (cons group name) bison-space--roots)
                         (user-error "No root known for %s" name))))
    (bison-space--layout group name root)
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
           ;; Its directory is gone; a shell there has nothing to do.
           (bison-space--kill-tmux-session group name)
           (message "Removed worktree %s" label)))))))

;;;; Sidebar

(defcustom bison-space-sidebar-width 32
  "Width of the spaces sidebar, in columns of the frame's font."
  :type 'natnum)

(defcustom bison-space-sidebar-text-scale 0.9
  "Font height of the sidebar, relative to other buffers."
  :type 'number)

(defcustom bison-space-sidebar-right-padding 10
  "Pixels between the status glyphs and the sidebar's right edge.
At least the width of a space, which the line's newline needs: a
newline pushed out into the fringe no longer carries the row's
`line-height' and `line-spacing', and the row padding is lost."
  :type 'natnum)

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

;;;; Agent status

;; Claude Code reports its state to the terminal (OSC 7501) and ghostel
;; keeps it per buffer in `ghostel-program-status'; a row shows the
;; state of its space's Claude terminal, and a repo row the most urgent
;; of its spaces.  `done' and `error' last until you type into that
;; terminal (`ghostel-status-auto-acknowledge').

(defface bison-space-status-working
  '((((class color) (min-colors 88)) :foreground "#fabd2f")
    (t :inherit warning))
  "Face of the working status glyph.")

(defface bison-space-status-blocked
  '((((class color) (min-colors 88)) :foreground "#fe8019" :weight bold)
    (t :inherit error))
  "Face of the needs-you status glyph.")

(defface bison-space-status-done
  '((((class color) (min-colors 88)) :foreground "#b8bb26")
    (t :inherit success))
  "Face of the done status glyph.")

(defface bison-space-status-error
  '((((class color) (min-colors 88)) :foreground "#fb4934")
    (t :inherit error))
  "Face of the error status glyph.")

(defface bison-space-status-idle
  '((((class color) (min-colors 88)) :foreground "#665c54")
    (t :inherit shadow))
  "Face of the idle status glyph.")

(defcustom bison-space-done-seconds 3
  "Seconds the sidebar shows a finished turn before the idle dot.
Only the sidebar: ghostel keeps the `done' record, and the mode-line
counter with it, until you type into the terminal."
  :type 'number)

(defvar bison-space--done-since (make-hash-table :test #'eq :weakness 'key)
  "When each Claude terminal's turn last finished, by buffer.")

(defconst bison-space--urgency '(blocked error done working idle)
  "Agent states, most urgent first.")

(defun bison-space--most-urgent (records)
  "Return the most urgent of the status plists RECORDS, or nil."
  (car (seq-sort-by (lambda (record)
                      (or (seq-position bison-space--urgency
                                        (plist-get record :state))
                          99))
                    #'< records)))

(defun bison-space--agent-status (buffer)
  "Return the status plist of agent terminal BUFFER, or nil.
The program's own record, unless one of its background agents needs
you or failed: a background agent finishing while the program works
on is not news, but one waiting on a permission is.  It carries the
agent's buffer as :agent, for the hover text."
  (let* ((records (buffer-local-value 'ghostel-program-status buffer))
         (status (bison-space--fade-done
                  buffer
                  (bison-space--most-urgent
                   (delq nil
                         (cons (alist-get "" records nil nil #'equal)
                               (mapcar (lambda (entry)
                                         (and (not (equal (car entry) ""))
                                              (memq (plist-get (cdr entry) :state)
                                                    '(blocked error))
                                              (cdr entry)))
                                       records)))))))
    (cond (status (append (list :agent buffer) status))
          ;; Running but silent: a harness that reports no status.
          ((bison-space--agent-running-p buffer)
           (list :agent buffer :state 'idle)))))

(defun bison-space--status (group name)
  "Return the most urgent status among the agents of space NAME in GROUP."
  (bison-space--most-urgent
   (delq nil (mapcar #'bison-space--agent-status
                     (bison-space--agents group name)))))

(defun bison-space--fade-done (buffer status)
  "Return STATUS of BUFFER, shown as idle once its `done' is stale.
Stale is older than `bison-space-done-seconds', or of unknown age."
  (let ((since (gethash buffer bison-space--done-since)))
    (if (and (eq (plist-get status :state) 'done)
             (not (and since (< (- (float-time) since)
                                bison-space-done-seconds))))
        (list :state 'idle :app (plist-get status :app))
      status)))

(defun bison-space--repo-status (repo spaces)
  "Return the most urgent status among SPACES of REPO, or nil.
A status from a worktree carries its name as :space, for the hover text."
  (bison-space--most-urgent
   (delq nil
         (mapcar (lambda (space)
                   (when-let* ((status (bison-space--status (car space)
                                                            (cadr space))))
                     (if (equal (cadr space) repo)
                         status
                       (append (list :space (cadr space)) status))))
                 spaces))))

(defun bison-space--status-describe (record)
  "Return a one-line description of the status plist RECORD."
  (let ((state (plist-get record :state))
        (kind (plist-get record :kind))
        (msg (or (plist-get record :msg) (plist-get record :title))))
    (concat (if-let* ((buffer (plist-get record :agent))
                      ((buffer-live-p buffer)))
                ;; The tag after the space's label: "claude", "codex<2>".
                (string-remove-suffix
                 "*" (car (last (split-string (buffer-name buffer) ": "))))
              "Agent")
            (if-let* ((space (plist-get record :space)))
                (format " in %s: " space)
              ": ")
            (pcase state
              ('blocked "needs you")
              (_ (symbol-name state)))
            (and kind (format " (%s)" kind))
            (and msg (concat " -- " msg)))))

(defun bison-space--status-glyph (record)
  "Return the glyph for the status plist RECORD, or an empty string."
  (pcase-let* ((state (plist-get record :state))
               (progress (plist-get record :progress))
               (`(,icon ,char)
                (pcase state
                  ('working '("nf-oct-sync" "↻"))
                  ('blocked (pcase (plist-get record :kind)
                              ('permission '("nf-oct-lock" "!"))
                              ('question '("nf-oct-question" "?"))
                              ('auth '("nf-oct-key" "!"))
                              (_ '("nf-oct-alert" "!"))))
                  ('done '("nf-oct-check" "✓"))
                  ('error '("nf-oct-x" "✗"))
                  ('idle '("nf-oct-dot" "·"))))
               (face (intern-soft (format "bison-space-status-%s" state))))
    (cond ((not icon) "")
          ((and (eq state 'working) progress)
           (propertize (format "%d%%" progress) 'face face))
          ((require 'nerd-icons nil t)
           (let ((glyph (copy-sequence (nerd-icons-octicon icon))))
             (add-face-text-property 0 (length glyph) face t glyph)
             glyph))
          (t (propertize char 'face face)))))

(defvar bison-space--status-timer nil
  "Pending sidebar redraw after a status change, or nil.")

(defun bison-space--status-changed (id _old new)
  "Note a status change; a member of `ghostel-program-status-functions'.
Runs in the terminal buffer with the record ID and its NEW plist.
Times a finished turn for `bison-space--fade-done' -- here rather
than at redraw, so it holds while the sidebar is hidden -- and
redraws the sidebar shortly.  The hook runs on the terminal output
path, so changes in quick succession share one redraw, and none
happens while the sidebar is hidden."
  (when (equal id "")
    (if (eq (plist-get new :state) 'done)
        (unless (gethash (current-buffer) bison-space--done-since)
          (puthash (current-buffer) (float-time) bison-space--done-since)
          (run-with-timer (+ bison-space-done-seconds 0.1) nil
                          #'bison-space--sidebar-render))
      (remhash (current-buffer) bison-space--done-since)))
  (when (and (not bison-space--status-timer)
             (get-buffer-window bison-space--sidebar-name t))
    (setq bison-space--status-timer
          (run-with-timer 0.1 nil
                          (lambda ()
                            (setq bison-space--status-timer nil)
                            (bison-space--sidebar-render))))))

(defun bison-space--status-labels ()
  "Return `ghostel-status-mode-line-labels' drawn from the sidebar's glyphs."
  (append
   (mapcar (lambda (state)
             (cons state (concat (bison-space--status-glyph
                                  (list :state state))
                                 "%c")))
           '(working blocked done error))
   (mapcar (lambda (kind)
             (cons kind (concat (bison-space--status-glyph
                                 (list :state 'blocked :kind kind))
                                "%c")))
           '(permission question auth))
   `((progress . ,(propertize "%p%%%c" 'face 'bison-space-status-working)))))

;; Not before ghostel-status defines the hook: `add-hook' on an unbound
;; variable would create it, and its defcustom would then skip ghostel's
;; own default members.
(with-eval-after-load 'ghostel-status
  (add-hook 'ghostel-program-status-functions #'bison-space--status-changed)
  ;; The counter `ghostel-status-indicator-mode' puts in every mode line
  ;; already includes a terminal's own state, so its own label in
  ;; `mode-line-process' only doubled it -- at the far right edge, where
  ;; doom-modeline puts the process segment.
  (remove-hook 'ghostel-program-status-functions #'ghostel-status-mode-line)
  ;; The counter uses the sidebar's glyphs rather than ghostel's emoji.
  (setq ghostel-status-mode-line-labels (bison-space--status-labels)))

(defun bison-space--pixel-width (string)
  "Return the width of STRING in pixels as the current buffer draws it."
  (if (string-empty-p string)
      0
    (string-pixel-width string (current-buffer))))

(defun bison-space--right-gap ()
  "Return the pixels to leave right of the status glyphs."
  (max bison-space-sidebar-right-padding
       (bison-space--pixel-width " ")))

(defun bison-space--sidebar-insert-row (space indent icon text &optional status)
  "Insert a row for SPACE at INDENT: ICON, then TEXT.
SPACE is (GROUP NAME CURRENT), or nil for a repo with no space open.
STATUS, a status plist, is shown at the right edge."
  (pcase-let ((`(,group ,name ,current) space)
              (start (point))
              (glyph (if status (bison-space--status-glyph status) "")))
    (insert (make-string indent ?\s) (bison-space--icon icon)
            (propertize text 'face (unless space 'bison-space-sidebar-closed))
            ;; In pixels, as this buffer draws the glyph: columns would
            ;; count the frame's larger font, not the sidebar's smaller
            ;; one or the icon font's.
            (propertize " " 'display
                        `(space :align-to
                                (- right (,(+ (bison-space--pixel-width glyph)
                                                (bison-space--right-gap))))))
            glyph
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
                             help-echo ,(concat
                                         (and status
                                              (concat (bison-space--status-describe
                                                       status)
                                                      "\n"))
                                         "mouse-1: switch to this space"))))))

;;;; Sidebar: agents

;; Below the spaces, every running agent in sections by state, as the
;; Herdr app's agents list does by default: Needs you, Done, Working,
;; Idle; within a section the most recent change first, with how long
;; ago it was.  An agent whose harness has exited is not listed.

(defconst bison-space--agent-sections
  '(("Needs you" blocked error) ("Done" done) ("Working" working) ("Idle" idle))
  "Agent sections in order, each a heading and the states it holds.")

(defvar bison-space--agent-since (make-hash-table :test #'eq :weakness 'key)
  "Each agent terminal's last shown state and when it began, by buffer.")

(defun bison-space--agent-since (buffer state)
  "Return when agent BUFFER entered STATE, noting it now if it just did."
  (let ((seen (gethash buffer bison-space--agent-since)))
    (if (eq (car seen) state)
        (cdr seen)
      (puthash buffer (cons state (float-time)) bison-space--agent-since)
      (float-time))))

(defun bison-space--duration (seconds)
  "Return SECONDS as Herdr shows an age: <1m, 5m, 2h, 3d."
  (let ((minutes (floor seconds 60)))
    (cond ((< minutes 1) "<1m")
          ((< minutes 60) (format "%dm" minutes))
          ((< minutes 1440) (format "%dh" (floor minutes 60)))
          (t (format "%dd" (floor minutes 1440))))))

(defun bison-space--sidebar-agents ()
  "Return the running agents as ((HEADING (BUFFER STATUS AGE)...)...).
Sections in `bison-space--agent-sections' order, empty ones left out;
AGE is the seconds since the agent's state last changed."
  (let ((now (float-time))
        rows)
    (dolist (buffer (buffer-list))
      (when-let* (((buffer-local-value 'bison-space-agent buffer))
                  (status (bison-space--agent-status buffer)))
        (push (list buffer status
                    (- now (bison-space--agent-since
                            buffer (plist-get status :state))))
              rows)))
    (delq nil
          (mapcar (lambda (section)
                    (when-let* ((in (seq-filter
                                     (lambda (row)
                                       (memq (plist-get (nth 1 row) :state)
                                             (cdr section)))
                                     rows)))
                      (cons (car section)
                            (seq-sort-by (lambda (row) (nth 2 row)) #'< in))))
                  bison-space--agent-sections))))

(defun bison-space--agent-label (buffer)
  "Return \"SPACE · TAG\" for agent terminal BUFFER."
  (pcase-let ((`(,group ,name) (buffer-local-value 'bison-space-agent buffer)))
    (concat (bison-space--label group name) " · "
            (string-remove-suffix
             "*" (car (last (split-string (buffer-name buffer) ": ")))))))

(defun bison-space--sidebar-insert-agent (buffer status age current)
  "Insert the row of agent BUFFER with STATUS, AGE seconds in it.
CURRENT non-nil marks the agent in view in the selected space."
  (let* ((start (point))
         (glyph (bison-space--status-glyph status))
         (right (concat (propertize (bison-space--duration age)
                                    'face 'bison-space-sidebar-header)
                        " " glyph))
         (gap (+ (bison-space--pixel-width right) (bison-space--right-gap)))
         (room (- (if-let* ((window (get-buffer-window (current-buffer) t)))
                      (window-body-width window t)
                    (* bison-space-sidebar-width (frame-char-width)))
                  gap
                  (bison-space--pixel-width "    ")))
         (label (truncate-string-pixelwise (bison-space--agent-label buffer)
                                           room (current-buffer) "…")))
    (insert "  " label
            (propertize " " 'display `(space :align-to (- right (,gap))))
            right
            (bison-space--sidebar-newline))
    (when current
      (add-face-text-property start (point) 'bison-space-sidebar-current))
    (add-text-properties start (point)
                         `(bison-space-agent-row ,buffer
                           mouse-face ,(list 'bison-space-sidebar-hover)
                           help-echo ,(concat (bison-space--status-describe status)
                                              "\nmouse-1: show this agent")))))

(defun bison-space--sidebar-insert-agents ()
  "Insert the agents section, if any agent is running."
  (when-let* ((sections (bison-space--sidebar-agents)))
    (let* ((window (bison-space--agent-window))
           (current (and window (window-buffer window)))
           (count (number-to-string
                   (apply #'+ (mapcar (lambda (s) (length (cdr s))) sections)))))
      (insert "\n " (propertize "Agents" 'face 'bison-space-sidebar-header)
              (propertize " " 'display
                          `(space :align-to
                                  (- right (,(+ (bison-space--pixel-width count)
                                                (bison-space--right-gap))))))
              (propertize count 'face 'bison-space-sidebar-header)
              (bison-space--sidebar-newline))
      (pcase-dolist (`(,heading . ,rows) sections)
        (insert " " (propertize heading 'face 'bison-space-sidebar-org)
                (bison-space--sidebar-newline))
        (pcase-dolist (`(,buffer ,status ,age) rows)
          (bison-space--sidebar-insert-agent buffer status age
                                             (eq buffer current)))))))

(defvar bison-space--sidebar-clock nil
  "Timer refreshing the agents' ages while the sidebar shows.")

(defun bison-space--sidebar-tick ()
  "Redraw the sidebar for the agents' ages, if it shows anywhere."
  (when (get-buffer-window bison-space--sidebar-name t)
    (bison-space--sidebar-render)))

(unless bison-space--sidebar-clock
  (setq bison-space--sidebar-clock
        (run-with-timer 30 30 #'bison-space--sidebar-tick)))

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
              ;; The repo row shows the most urgent state of all of its
              ;; spaces, its own main checkout's included.
              (bison-space--sidebar-insert-row
               main 1 "nf-oct-repo" repo
               (bison-space--repo-status repo spaces))
              (dolist (space (remq main spaces))
                (bison-space--sidebar-insert-row
                 space 3 "nf-oct-git_branch" (cadr space)
                 (bison-space--status (car space) (cadr space))))
              (setq count (+ count (length spaces))))))
        (setq bison-space--sidebar-count count)
        (unless (bobp)
          (bison-space--sidebar-insert-agents))
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
            ;; Any right fringe at all: without one Emacs keeps the
            ;; last column free for its `$' truncation mark.  The
            ;; padding itself is left by the row layout.
            0 1))
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
  "Return (GROUP . NAME) for the sidebar line at point, or signal.
On an agent's row, the agent's space."
  (or (get-text-property (line-beginning-position) 'bison-space)
      (when-let* ((agent (get-text-property (line-beginning-position)
                                            'bison-space-agent-row)))
        (let ((space (buffer-local-value 'bison-space-agent agent)))
          (cons (nth 0 space) (nth 1 space))))
      (user-error "No space on this line")))

(defun bison-space-sidebar-select ()
  "Switch to the space on this sidebar line, or show the agent on it."
  (interactive)
  (if-let* ((agent (get-text-property (line-beginning-position)
                                      'bison-space-agent-row)))
      (pcase-let ((`(,group ,name) (buffer-local-value 'bison-space-agent agent)))
        (tab-bar-select-tab
         (1+ (or (bison-space--tab-index group name)
                 (user-error "No open space for %s" (buffer-name agent)))))
        (bison-space--show-agent agent))
    (pcase-let ((`(,group . ,name) (bison-space--at-point)))
      (when-let* ((index (bison-space--tab-index group name)))
        (tab-bar-select-tab (1+ index))))))

(defun bison-space-sidebar-next (n)
  "Move to the Nth next space or agent in the sidebar, skipping headings."
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
            (when (or (get-text-property (point) 'bison-space)
                      (get-text-property (point) 'bison-space-agent-row))
              (setq found (point))))
          (when found
            (setq target found)))))
    (goto-char target)))

(defun bison-space-sidebar-previous (n)
  "Move to the Nth previous space or agent in the sidebar, skipping headings."
  (interactive "p")
  (bison-space-sidebar-next (- n)))

(defvar-keymap bison-space-sidebar-mode-map
  "RET" #'bison-space-sidebar-select
  "<mouse-1>" #'bison-space-sidebar-select
  "/" #'bison-space-switch
  "r" #'bison-space-reset
  "k" #'bison-space-close
  "a" #'bison-space-add-agent
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
              hl-line-sticky-flag nil
              ;; Rows never overflow; keep the 1px fringe free of arrows.
              fringe-indicator-alist
              (cons '(truncation nil nil)
                    (default-value 'fringe-indicator-alist)))
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
worktrees, in a tab of its own.  The shell is on the left, running tmux
in a session that outlives Emacs; the agent window is on the right,
showing one agent at a time, or the launcher while there is none.
When an agent exits, the window moves on to the next one, or back to
the launcher; one that fails stays open to show why.
The sidebar lists the open spaces by org and repo.

Everywhere

  \\[bison-space-switch]	Switch to a space, or open one for any project
  \\[bison-space]	Open or switch to the current project's space
	(\\[universal-argument] \\[bison-space]: open it resuming the default agent)
  \\[bison-space-add-agent]	Start an agent: Claude, Codex, or any command
	(\\[universal-argument] \\[bison-space-add-agent]: resume its last session)
  \\[bison-space-reset]	Reset this space's layout
  \\[bison-space-close]	Close this space and kill its terminals
  \\[bison-space-new-worktree]	New worktree on a new branch, in a new space
	(\\[universal-argument] \\[bison-space-new-worktree]: also ask for the base branch)
  \\[bison-space-remove-worktree]	Remove this space's worktree, then close it
	(\\[universal-argument] \\[bison-space-remove-worktree]: even if dirty or unmerged)
  \\[bison-space-sidebar-toggle]	Show and focus the sidebar; again to hide it
  \\[bison-space-help]	This help

  From \\[project-switch-project], `s' opens the chosen project's space.

In an agent or the launcher
\\<bison-space-agent-mode-map>
  \\[bison-space-agent-next] \\[bison-space-agent-previous]	Next / previous agent of this space
\\<bison-space-launcher-mode-map>
  RET	(launcher) Start any command as an agent; harness keys as listed

In the sidebar
\\<bison-space-sidebar-mode-map>
  \\[bison-space-sidebar-select]	Switch to the space, or show the agent, at point
  \\[bison-space-switch]	Search all spaces and projects
  \\[bison-space-sidebar-next] \\[bison-space-sidebar-previous]	Next / previous space or agent
  \\[bison-space-add-agent]	Start an agent in the space at point
  \\[bison-space-reset]	Reset the space at point
  \\[bison-space-close]	Close the space at point
  \\[bison-space-new-worktree]	New worktree of the repo at point
  \\[bison-space-remove-worktree]	Remove the worktree at point
  \\[bison-space-help]	This help
  \\[bison-space-sidebar-toggle]	Hide the sidebar

Agent status (right edge of a row)

  Each space shows the most urgent state of its agents; a repo row the
  most urgent of its spaces.  Below the spaces, the Agents section lists
  every running agent under Needs you, Done, Working and Idle, the most
  recent change first, with how long ago it was.  Hover for details.
    working      busy (or a percentage)
    needs you    a permission prompt, question or login is waiting
    done         a turn finished; back to idle after a few seconds
    error        the last turn failed
    idle         running, nothing happening
  A harness that reports no status shows idle while it runs.  The mode
  line counts terminals needing attention, a finished turn until you
  type into it; click it, or M-x ghostel-status-next, to visit them.

\\<global-map>Notes

  Terminals are named *REPO[/WORKTREE]: shell*, *...: claude*,
  *...: codex<2>*; \\[consult-buffer] finds them when the layout is gone.
  Harnesses and the tmux session name are customizable:
  M-x customize-group RET bison-space.
  Closing a space leaves its tmux session running; removing the
  worktree ends it.  wt reports land in *wt*.

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
      (while (re-search-forward "^\\(Everywhere\\|In an agent.*\\|In the sidebar\\|Notes\\|Agent status.*\\|Font size.*\\)$" nil t)
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
(global-set-key (kbd "C-c a") #'bison-space-add-agent)

(provide 'bison-spaces)
;;; bison-spaces.el ends here
