;;; bison-org.el --- Org: journal capture and agenda  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; A stream-of-consciousness journal: `C-c c j' appends a timestamped
;; entry to today's file under ~/Notes/journal, `C-c j' visits that
;; file, and `C-c a' opens the agenda over the whole directory, where
;; the week and month views show what each day was about.  Plain org
;; only; org-journal is the upgrade if calendar navigation is wanted.
;;
;; Notes live in the host home so a capture in a VM lands in the same
;; day file as one on the host.

;;; Code:

(require 'bison-lib)

(defconst bison-notes-dir
  (let ((host (bison-host-home)))
    (expand-file-name "Notes"
                      ;; A sandbox mounts the host home read-only; the
                      ;; machine VMs mount it writable and get the shared
                      ;; notes.  The host itself has no virtiofs mounts.
                      (if (and host (file-writable-p host)) host "~")))
  "Root of the org notes: the host's ~/Notes when writable, else ~/Notes.")

(defconst bison-journal-dir
  (expand-file-name "journal" bison-notes-dir)
  "Directory of per-day journal files, named YYYY-MM-DD.org.")

(defun bison-journal-file (&optional time)
  "Return the journal file for TIME (default now), creating it if needed.
A new file gets a title line so it reads sensibly on its own."
  (let* ((day (format-time-string "%Y-%m-%d" time))
         (file (expand-file-name (concat day ".org") bison-journal-dir)))
    (unless (file-exists-p file)
      (bison-mkdir bison-journal-dir #o700)
      (with-temp-file file
        (insert "#+title: " (format-time-string "%A, %-d %B %Y" time) "\n\n")))
    file))

(defun bison-journal-today ()
  "Visit today's journal file."
  (interactive)
  (find-file (bison-journal-file))
  (goto-char (point-max)))

(use-package org
  :straight (:type built-in)
  :defer t
  :bind (("C-c a" . org-agenda)
         ("C-c c" . org-capture)
         ("C-c j" . bison-journal-today))
  :custom
  (org-directory bison-notes-dir)
  (org-agenda-files (list bison-journal-dir))
  (org-startup-indented t)
  (org-startup-folded 'showall)
  (org-log-done 'time)
  (org-return-follows-link t)
  (org-capture-templates
   '(("j" "Journal" entry (file bison-journal-file)
      "* %<%H:%M> %?\n%U\n"
      :empty-lines 1)))
  :config
  ;; Directories in `org-agenda-files' must exist or agenda errors out.
  (bison-mkdir bison-journal-dir #o700))

;; These live in org-agenda.el, which loads after org.el; use-package's
;; :custom defers values for not-yet-defined variables and, for this
;; file, never applies them.  Setting them once it is loaded is reliable.
(defvar org-agenda-include-inactive-timestamps)
(defvar org-agenda-span)
(defvar org-agenda-start-on-weekday)
(with-eval-after-load 'org-agenda
  ;; Journal entries carry inactive timestamps so they never look like
  ;; appointments; this is what makes the agenda show them regardless.
  (setq org-agenda-include-inactive-timestamps t
        org-agenda-span 'week
        org-agenda-start-on-weekday nil))

(provide 'bison-org)
;;; bison-org.el ends here
