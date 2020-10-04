(use-package dap-mode
  :custom
  (dap-breakpoints-file (bison/expand-cache-file "dap-breakpoints"))
  (dap-auto-configure-features '(sessions locals controls tooltip)))
