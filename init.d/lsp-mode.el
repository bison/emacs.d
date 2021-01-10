(use-package lsp-mode
  :hook
  (go-mode . lsp-deferred)

  :commands
  (lsp lsp-deferred)

  :custom
  (lsp-enable-links nil)
  (lsp-file-watch-threshold 10000)
  (lsp-session-file (bison/expand-cache-file "lsp-session-v1"))

  :config
  (lsp-register-client
   (make-lsp-client :new-connection (lsp-tramp-connection
									 (lambda () (cons lsp-go-gopls-server-path
													  lsp-go-gopls-server-args)))
					:major-modes '(go-mode go-dot-mod-mode)
					:remote? t
					:language-id "go"
					:priority 0
					:server-id 'gopls-remote
					:completion-in-comments? t
					:library-folders-fn #'lsp-go--library-default-directories
					:after-open-fn (lambda ()
									 ;; https://github.com/golang/tools/commit/b2d8b0336
									 (setq-local lsp-completion-filter-on-incomplete nil)))))
