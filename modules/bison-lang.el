;;; bison-lang.el --- Tree-sitter, LSP, diagnostics, debugging  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; Language-independent code intelligence, all built in since Emacs 29:
;; tree-sitter major modes, eglot as the LSP client, flymake for
;; diagnostics (eglot feeds it), eldoc for signatures.  dape is the one
;; external package, standing in for dap-mode.

;;; Code:

(require 'bison-lib)

;;; Tree-sitter

(use-package treesit
  :straight (:type built-in)
  :custom
  (treesit-font-lock-level 4)
  :config
  ;; Grammars compile into the cache, not ~/.emacs.d/tree-sitter.
  (add-to-list 'treesit-extra-load-path (bison-cache-file "tree-sitter/"))

  ;; Pinned to tags so a rebuilt image compiles the same grammar.  The
  ;; positional form works on 30.2; 31 also accepts keyword arguments.
  (setq treesit-language-source-alist
        '((bash       "https://github.com/tree-sitter/tree-sitter-bash" "v0.23.3")
          (dockerfile "https://github.com/camdencheek/tree-sitter-dockerfile" "v0.2.0")
          (go         "https://github.com/tree-sitter/tree-sitter-go" "v0.23.4")
          (gomod      "https://github.com/camdencheek/tree-sitter-go-mod" "v1.1.0")
          (gowork     "https://github.com/omertuc/tree-sitter-go-work")
          (json       "https://github.com/tree-sitter/tree-sitter-json" "v0.24.8")
          (toml       "https://github.com/tree-sitter-grammars/tree-sitter-toml" "v0.7.0")
          (yaml       "https://github.com/tree-sitter-grammars/tree-sitter-yaml" "v0.7.1")))

  ;; Emacs 31 can install grammars on demand; 30.2 relies on
  ;; `bison-treesit-install-grammars', run from startup below.
  (when (boundp 'treesit-auto-install-grammar)
    (setq treesit-auto-install-grammar 'always))

  ;; `treesit-enabled-modes' is 31-only, and mode packages register
  ;; themselves there, whereas this list works on both.
  (dolist (remap '((sh-mode         . bash-ts-mode)
                   (dockerfile-mode . dockerfile-ts-mode)
                   (go-mode         . go-ts-mode)
                   (go-dot-mod-mode . go-mod-ts-mode)
                   (js-json-mode    . json-ts-mode)
                   (conf-toml-mode  . toml-ts-mode)
                   (yaml-mode       . yaml-ts-mode)))
    (add-to-list 'major-mode-remap-alist remap)))

(defun bison-treesit-install-grammars ()
  "Compile every grammar in `treesit-language-source-alist' not yet installed.
Interactively, or from `make grammars'; startup also calls it so a fresh
sandbox builds what it needs on first launch."
  (interactive)
  (let ((dir (bison-cache-file "tree-sitter/")))
    (bison-mkdir dir)
    (dolist (entry treesit-language-source-alist)
      (let ((lang (car entry)))
        (unless (treesit-language-available-p lang)
          (condition-case err
              (progn
                (message "Installing tree-sitter grammar for %s..." lang)
                (treesit-install-language-grammar lang dir))
            (error
             (display-warning 'bison "grammar %s: %s" lang
                              (error-message-string err)))))))))

;; Only worth doing when there is a compiler; skip in batch so lint and
;; test runs stay fast, `make grammars' handles those explicitly.
(unless noninteractive
  (add-hook 'emacs-startup-hook #'bison-treesit-install-grammars))

;;; LSP

(use-package eglot
  :straight (:type built-in)
  :defer t
  :bind (:map eglot-mode-map
              ("C-c l r" . eglot-rename)
              ("C-c l a" . eglot-code-actions)
              ("C-c l o" . eglot-code-action-organize-imports)
              ("C-c l f" . eglot-format)
              ("C-c l h" . eldoc)
              ("C-c l d" . xref-find-definitions)
              ("C-c l R" . xref-find-references)
              ("C-c l i" . eglot-find-implementation)
              ("C-c l t" . eglot-find-typeDefinition)
              ("C-c l =" . eglot-format-buffer)
              ("C-c l q" . eglot-shutdown)
              ("C-c l Q" . eglot-reconnect))
  :custom
  (eglot-autoshutdown t)
  (eglot-extend-to-xref t)
  (eglot-report-progress nil)
  ;; The events buffer is a debugging aid and a memory sink otherwise.
  (eglot-events-buffer-config '(:size 0 :format full))
  (eglot-ignored-server-capabilities '(:inlayHintProvider))
  :config
  (add-to-list 'eglot-server-programs
               '(terraform-mode . ("terraform-ls" "serve")))
  (add-to-list 'eglot-server-programs
               '(jsonnet-mode . ("jsonnet-language-server")))
  ;; yaml-language-server does Kubernetes schemas; only attach when it
  ;; is on PATH, which today is nowhere.
  (add-to-list 'eglot-server-programs
               '(yaml-ts-mode . ("yaml-language-server" "--stdio"))))

(use-package consult-eglot
  :after (consult eglot)
  :bind (:map eglot-mode-map
              ("C-c l s" . consult-eglot-symbols)))

(defun bison-eglot-format-on-save ()
  "Format the buffer and organise imports through eglot before saving.
Buffer-local, so it only ever applies to buffers with a live server."
  (add-hook 'before-save-hook #'eglot-format-buffer -10 t)
  (add-hook 'before-save-hook #'bison-eglot--organize-imports nil t))

(defun bison-eglot--organize-imports ()
  "Run the organizeImports code action without prompting."
  (when (eglot-managed-p)
    (ignore-errors
      (eglot-code-actions nil nil "source.organizeImports" t))))

;;; Diagnostics

(use-package flymake
  :straight (:type built-in)
  :hook (prog-mode . flymake-mode)
  :bind (:map flymake-mode-map
              ("M-n"     . flymake-goto-next-error)
              ("M-p"     . flymake-goto-prev-error)
              ("C-c ! l" . flymake-show-buffer-diagnostics)
              ("C-c ! L" . flymake-show-project-diagnostics))
  :custom
  (flymake-no-changes-timeout 0.5)
  (flymake-show-diagnostics-at-end-of-line nil)
  (flymake-fringe-indicator-position 'right-fringe)
  (flymake-margin-indicator-position 'right-margin))

(use-package eldoc
  :straight (:type built-in)
  :custom
  (eldoc-echo-area-use-multiline-p 3)
  (eldoc-echo-area-prefer-doc-buffer t))

;;; Debugging

(use-package dape
  :defer t
  :custom
  (dape-buffer-window-arrangement 'right)
  (dape-inlay-hints t)
  :config
  (dape-breakpoint-global-mode 1)
  (add-hook 'dape-compile-hook #'kill-buffer))

(provide 'bison-lang)
;;; bison-lang.el ends here
