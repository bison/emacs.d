(use-package forge
  :after magit
  :custom
  (forge-database-file (bison/expand-cache-file "forge-database.sqlite")))
