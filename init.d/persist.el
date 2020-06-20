(use-package persist
  :config
  (setq persist--directory-location (bison/expand-cache-file "persist")))
