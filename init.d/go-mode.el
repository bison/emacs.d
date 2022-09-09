(use-package go-mode
  :hook
  (before-save . gofmt-before-save)

  :config
  (setq gofmt-command "goimports -local"))
