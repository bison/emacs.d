(use-package ediff
  :custom
  (ediff-custom-diff-options "-U3")
  (ediff-split-window-function 'split-window-horizontally)
  (ediff-window-setup-function 'ediff-setup-windows-plain)

  :hook
  (ediff-startup . ediff-toggle-wide-display)
  (ediff-cleanup . ediff-toggle-wide-display)
  (ediff-suspend . ediff-toggle-wide-display))
