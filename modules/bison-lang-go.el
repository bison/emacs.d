;;; bison-lang-go.el --- Go  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; go-ts-mode with gopls through eglot.  gopls itself formats with
;; gofumpt and organises imports on save, so goimports is no longer a
;; hard dependency of the editor.

;;; Code:

(require 'bison-lib)
(require 'bison-lang)

(use-package go-ts-mode
  :straight (:type built-in)
  :mode (("\\.go\\'" . go-ts-mode)
         ("/go\\.mod\\'" . go-mod-ts-mode))
  :hook ((go-ts-mode go-mod-ts-mode) . eglot-ensure)
  :hook (go-ts-mode . bison-eglot-format-on-save)
  :custom
  (go-ts-mode-indent-offset 4)
  :config
  ;; gofmt output uses tabs; keep the buffer honest about it.
  (add-hook 'go-ts-mode-hook (lambda () (setq-local indent-tabs-mode t)))

  ;; go.work support arrived in 31; on 30.2 these files fall back to
  ;; go-mod-ts-mode, which is close enough.
  (add-to-list 'auto-mode-alist
               (cons "/go\\.work\\'" (if (fboundp 'go-work-ts-mode)
                                         'go-work-ts-mode
                                       'go-mod-ts-mode)))

  (with-eval-after-load 'eglot
    (setq-default eglot-workspace-configuration
                  (append eglot-workspace-configuration
                          '(:gopls (:gofumpt t
                                    :staticcheck t
                                    :usePlaceholders t
                                    :hints (:parameterNames t
                                            :assignVariableTypes t)))))))

(provide 'bison-lang-go)
;;; bison-lang-go.el ends here
