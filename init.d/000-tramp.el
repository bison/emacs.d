(use-package tramp
  :straight (tramp :type git :host github
				   :repo "bison/tramp" :branch "main")

  :config
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path)

  (add-to-list 'tramp-connection-properties
               (list (regexp-quote "/ssh:work:")
					 "remote-shell" "/usr/bin/zsh"))


  (setq tramp-terminal-type "tramp")
  (setq tramp-default-method "ssh")
  (setq tramp-encoding-shell "/bin/zsh")
  (setq tramp-use-ssh-controlmaster-options nil)
  (setq tramp-persistency-file-name (bison/expand-cache-file "tramp")))
