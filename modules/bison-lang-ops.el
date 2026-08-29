;;; bison-lang-ops.el --- Infrastructure and config languages  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; The SRE side: YAML and Kubernetes manifests, Dockerfiles, Terraform,
;; Jsonnet, Nix, systemd units, Markdown, and the small formats in
;; between.  Built-in tree-sitter modes wherever one exists.

;;; Code:

(require 'bison-lib)
(require 'bison-lang)

(defun bison-lang-ops--yaml-setup ()
  "Buffer settings for YAML.
`yaml-ts-mode' derives from `text-mode', so the `prog-mode' hooks that
turn on diagnostics and line numbers elsewhere do not fire here."
  (setq-local tab-width 2
              indent-tabs-mode nil)
  (display-line-numbers-mode 1)
  (flymake-mode 1))

(use-package yaml-ts-mode
  :straight (:type built-in)
  :mode "\\.ya?ml\\'"
  :hook (yaml-ts-mode . bison-lang-ops--yaml-setup))

(use-package flymake-yamllint
  :hook (yaml-ts-mode . flymake-yamllint-setup))

(use-package dockerfile-ts-mode
  :straight (:type built-in)
  :mode ("/\\(?:Docker\\|Container\\)file\\(?:\\..*\\)?\\'" . dockerfile-ts-mode))

(use-package terraform-mode
  :mode ("\\.tf\\(?:vars\\)?\\'" . terraform-mode)
  :hook (terraform-mode . eglot-ensure)
  :hook (terraform-mode . bison-eglot-format-on-save))

(use-package jsonnet-mode
  :mode "\\.\\(?:jsonnet\\|libsonnet\\)\\'"
  :custom
  (jsonnet-use-smie t))

(use-package json-ts-mode
  :straight (:type built-in)
  :mode "\\.json\\'")

(use-package toml-ts-mode
  :straight (:type built-in)
  :mode "\\.toml\\'")

(use-package sh-script
  :straight (:type built-in)
  :mode ("\\.\\(?:ba\\|z\\)?sh\\'" . bash-ts-mode)
  :interpreter (("bash" . bash-ts-mode)
                ("sh" . bash-ts-mode)))

(use-package nix-mode
  :mode "\\.nix\\'")

(use-package systemd
  :defer t)

(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :custom
  (markdown-fontify-code-blocks-natively t)
  (markdown-command "markdown"))

(use-package protobuf-mode
  :mode "\\.proto\\'")

(provide 'bison-lang-ops)
;;; bison-lang-ops.el ends here
