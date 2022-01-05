(use-package eshell
  :hook
  (eshell-mode
   . (lambda ()
	   (setq show-trailing-whitespace nil)

	   (eshell-cmpl-initialize)
	   (define-key eshell-mode-map [remap eshell-pcomplete] 'helm-esh-pcomplete)
	   (define-key eshell-mode-map (kbd "M-s f") 'helm-eshell-prompts-all)
	   (define-key eshell-mode-map (kbd "M-r") 'helm-eshell-history)))

  :config
  (let* ((eshell-cache-dir (bison/expand-cache-file "eshell/"))
	 (eshell-hist-file (expand-file-name "history" eshell-cache-dir))
	 (eshell-last-dir-file (expand-file-name "lastdir" eshell-cache-dir)))

    (bison/mkdir eshell-cache-dir #o700)
    (setq eshell-history-file-name eshell-hist-file)
    (setq eshell-last-dir-ring-file-name eshell-last-dir-file)))
