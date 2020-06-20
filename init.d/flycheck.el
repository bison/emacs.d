(use-package flycheck
  :init
  (global-flycheck-mode)

  :config
  (setq flycheck-emacs-lisp-load-path 'inherit)
  (setq flycheck-emacs-lisp-initialize-packages 'auto))
