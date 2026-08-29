;;; init.el --- Brad Ison's Emacs configuration  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>
;; URL: https://github.com/bison/emacs.d

;;; Commentary:

;; Layout, loosely after Doom:
;;
;;   early-init.el  frame chrome, GC, cache paths (runs first)
;;   lisp/          bootstrap helpers, no package configuration
;;   modules/       one file per concern, loaded in the order below
;;   versions/      straight.el lockfile (`make lock' regenerates it)
;;
;; Targets Emacs 31.1 but must keep working on 30.2 for a while; anything
;; version-dependent is guarded rather than assumed, and the guard says
;; which side is the 30.2 fallback.

;;; Code:

(setq user-full-name "Brad Ison"
      user-mail-address "bison@xvdf.io")

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path (expand-file-name "modules" user-emacs-directory))

(require 'bison-lib)
(require 'bison-straight)

;; Order matters: defaults sets paths every later module relies on, and
;; completion has to come before the modules that bind consult commands.
(require 'bison-defaults)
(require 'bison-ui)
(require 'bison-completion)
(require 'bison-editor)
(require 'bison-spell)
(require 'bison-project)
(require 'bison-tools)
(require 'bison-lang)
(require 'bison-lang-go)
(require 'bison-lang-ops)

;; Customize writes here; the file is gitignored and loaded if present.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(load custom-file 'noerror 'nomessage)

;;; init.el ends here
