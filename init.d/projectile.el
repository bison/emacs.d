(use-package projectile
  :bind
  (:map projectile-mode-map
	("C-c p" . projectile-command-map))

  :custom
  (projectile-known-projects-file
   (bison/expand-cache-file "projectile-bookmarks.eld"))

  :config
  (projectile-mode))
