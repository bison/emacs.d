(use-package treemacs
  :bind
  (("C-c t" . treemacs))

  :config
  (setq treemacs-persist-file (bison/expand-cache-file "persist/treemacs")))
