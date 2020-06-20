(use-package lsp-mode
  :hook
  (go-mode . lsp-deferred)

  :custom
  (lsp-enable-links nil)
  (lsp-session-file (bison/expand-cache-file "lsp-session-v1")))
