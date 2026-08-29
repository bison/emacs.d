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

(provide 'bison-lib)
;;; bison-lib.el ends here
