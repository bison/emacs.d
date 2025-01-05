(use-package org
  :straight (:type built-in)
  :custom
  (org-id-locations-file (bison/expand-cache-file "org-id-locations")))
