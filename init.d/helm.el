(use-package helm
  :bind
  (("M-x"     . helm-M-x)
   ("C-c x"   . helm-M-x)
   ("M-y"     . helm-show-kill-ring)
   ("M-<f5>"  . helm-find-files)
   ("C-x C-f" . helm-find-files)
   ("C-x C-b" . helm-buffers-list)
   ([f10]     . helm-buffers-list)
   ([S-f10]   . helm-recentf)
   :map helm-map
   ([tab]     . helm-execute-persistent-action))

  :init
  (setq-default helm-split-window-inside-p nil)

  :config
  (helm-mode 1))
