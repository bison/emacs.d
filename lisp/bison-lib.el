;;; bison-lib.el --- Helpers shared by early-init and the modules  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; Nothing here loads a package.  This file is required from early-init,
;; so it has to stay free of anything that assumes a running frame or an
;; initialised package system.

;;; Code:

(defconst bison-cache-dir
  (file-name-as-directory
   (or (getenv "BISON_EMACS_CACHE_DIR")
       (expand-file-name "emacs/default"
                         (if (eq system-type 'darwin)
                             "~/Library/Caches/"
                           (or (getenv "XDG_CACHE_HOME") "~/.cache/")))))
  "Directory for everything Emacs writes at runtime.

The trailing `default' segment is the profile name left over from the
chemacs days; it stays because ~/.zshrc and the launchd plists in the
config repo derive the server socket path from it.  BISON_EMACS_CACHE_DIR
overrides the whole path, which is what `make test' uses to keep a
throwaway run away from the real cache.")

(defun bison-cache-file (file)
  "Expand FILE relative to `bison-cache-dir'."
  (expand-file-name file bison-cache-dir))

(defun bison-mkdir (dir &optional mode)
  "Create DIR and its parents unless it exists, then chmod it to MODE."
  (unless (file-directory-p dir)
    (make-directory dir t)
    (when mode (set-file-modes dir mode))))

(bison-mkdir bison-cache-dir #o700)

;; no-littering reads these when it loads, and it can load earlier than
;; bison-defaults sets things up: byte-compiling a use-package form
;; requires the package at compile time, before any :init runs.  Set
;; here, they hold wherever no-littering ends up loading from.
(defvar no-littering-etc-directory (bison-cache-file "etc/"))
(defvar no-littering-var-directory (bison-cache-file "var/"))

;; Native-compiled files go with the rest of the cache.  Done here rather
;; than in early-init so that every entry point -- the batch lint and test
;; scripts included -- redirects before anything gets compiled; otherwise
;; a `make lint' from inside ~/.emacs.d leaves an eln-cache/ in the checkout.
(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache (bison-cache-file "eln-cache/")))

(defun bison-host-home ()
  "Return the macOS host home when running in a guest, else nil.
Both `container machine' VMs and Docker Sandboxes mount host directories
at their host-absolute paths over virtiofs: the machine mounts the home
itself, a sandbox mounts the org directory and the worktree under it.
The mount source is an opaque tag in both, so the target is the handle:
the shortest virtiofs mount under /Users/ gives the home.  There is no
/proc/mounts on the host, which is what makes this return nil there."
  (when (file-readable-p "/proc/mounts")
    (let (home)
      (dolist (line (split-string (with-temp-buffer
                                    (insert-file-contents "/proc/mounts")
                                    (buffer-string))
                                  "\n" t))
        (pcase-let ((`(,_src ,target ,fstype . ,_) (split-string line)))
          (when (and (equal fstype "virtiofs")
                     (string-match "\\`/Users/[^/]+" target))
            (let ((candidate (match-string 0 target)))
              (when (or (null home) (< (length candidate) (length home)))
                (setq home candidate))))))
      home)))

(defconst bison-code-dir
  (let ((host (bison-host-home)))
    (if (and host (file-directory-p (expand-file-name "Code" host)))
        (expand-file-name "Code" host)
      (expand-file-name "~/Code")))
  "Directory holding <org>/<repo> checkouts: the host's in a guest, else ~/Code.")

(provide 'bison-lib)
;;; bison-lib.el ends here
