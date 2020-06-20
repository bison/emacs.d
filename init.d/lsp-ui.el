(use-package lsp-ui
  :bind
  ("C-?" . lsp-ui-doc-glance)

  :custom
  (lsp-ui-doc-enable nil)

  :config
  (lsp-ui-mode 1))
