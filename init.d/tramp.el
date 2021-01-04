(use-package tramp
  :config
  (setq tramp-use-ssh-controlmaster-options nil)
  (setq tramp-persistency-file-name (bison/expand-cache-file "tramp")))
