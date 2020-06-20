(use-package eshell
  :config
  (let* ((eshell-cache-dir (bison/expand-cache-file "eshell/"))
	 (eshell-hist-file (expand-file-name "history" eshell-cache-dir))
	 (eshell-last-dir-file (expand-file-name "lastdir" eshell-cache-dir)))

    (bison/mkdir eshell-cache-dir #o700)
    (setq eshell-history-file-name eshell-hist-file)
    (setq eshell-last-dir-ring-file-name eshell-last-dir-file)))
