;;; early-init.el --- Pre-package-system setup  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>
;; URL: https://github.com/bison/emacs.d

;;; Commentary:

;; Runs before the package system and before the first frame.  Only
;; things that must happen that early belong here: GC tuning for the
;; duration of startup, disabling package.el (straight.el owns packages),
;; frame chrome, and pointing the native-compilation cache at the cache
;; directory so ~/.emacs.d stays a clean checkout.

;;; Code:

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(require 'bison-lib)

;; Defer GC during startup; bison-defaults restores a sane threshold.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; straight.el manages packages; keep package.el out of the way.
(setq package-enable-at-startup nil)

;; Keep native-compiled files with the rest of the cache.
(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache (bison-cache-file "eln-cache/")))

;; Frame chrome, set here so the first frame is never drawn with it.
;; macOS keeps the menu bar: it lives in the system bar, costs nothing.
;; TTY frames drop it in `bison-defaults--setup-frame' regardless.
(unless (eq system-type 'darwin)
  (push '(menu-bar-lines . 0) default-frame-alist))
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq frame-inhibit-implied-resize t
      frame-resize-pixelwise t
      inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name
      initial-scratch-message nil)

;; Font is per-frame so the daemon's TTY and GUI frames both get it right.
(push (cons 'font (if (eq system-type 'darwin)
                      "JetBrains Mono-16"
                    "JetBrains Mono-12"))
      default-frame-alist)

(defvar ns-use-proxy-icon)
(when (eq system-type 'darwin)
  (setq ns-use-proxy-icon nil)
  (push '(internal-border-width . 0) default-frame-alist)
  (push '(ns-transparent-titlebar . t) default-frame-alist)
  (push '(ns-appearance . dark) default-frame-alist))

;;; early-init.el ends here
