(use-package exec-path-from-shell
  :config
  (when (or (memq window-system '(mac ns x)) (daemonp))
	(dolist (var '("SSH_AUTH_SOCK" "SSH_AGENT_PID" "GPG_AGENT_INFO" "LANG" "LC_CTYPE"))
	  (add-to-list 'exec-path-from-shell-variables var))
	(exec-path-from-shell-initialize)))
