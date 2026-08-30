;;; bison-completion.el --- Minibuffer and in-buffer completion  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; The vertico stack replacing helm: vertico shows candidates, orderless
;; matches them, marginalia annotates, consult supplies the commands,
;; embark acts on whatever is selected.  corfu + cape do the same for
;; in-buffer completion in place of company.

;;; Code:

(require 'bison-lib)

(use-package vertico
  :hook (emacs-startup . vertico-mode)
  :custom
  (vertico-cycle t)
  (vertico-count 15)
  :bind (:map vertico-map
              ("RET"   . vertico-directory-enter)
              ("DEL"   . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  :config
  (require 'vertico-directory)
  (add-hook 'rfn-eshadow-update-overlay-hook #'vertico-directory-tidy))

(use-package orderless
  :demand t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides
   '((file (styles partial-completion))
     (eglot (styles orderless))
     (eglot-capf (styles orderless)))))

(use-package marginalia
  :hook (emacs-startup . marginalia-mode))

(use-package nerd-icons-completion
  :after marginalia
  :config
  (nerd-icons-completion-mode)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package consult
  :bind (("C-x b"    . consult-buffer)
         ("C-x 4 b"  . consult-buffer-other-window)
         ("C-x p b"  . consult-project-buffer)
         ("C-x r b"  . consult-bookmark)
         ([f10]      . consult-buffer)
         ([S-f10]    . consult-recent-file)
         ("M-y"      . consult-yank-pop)
         ("M-g g"    . consult-goto-line)
         ("M-g M-g"  . consult-goto-line)
         ("M-g i"    . consult-imenu)
         ("M-g I"    . consult-imenu-multi)
         ("M-g m"    . consult-mark)
         ("M-g o"    . consult-outline)
         ("M-s l"    . consult-line)
         ("M-s L"    . consult-line-multi)
         ("M-s g"    . consult-ripgrep)
         ("M-s f"    . consult-fd)
         ("M-s r"    . consult-ripgrep)
         ;; Successor to helm-projectile-ag on the same key.
         ("C-<return>" . consult-ripgrep)
         :map minibuffer-local-map
         ("M-s" . consult-history)
         ("M-r" . consult-history))
  :custom
  (consult-narrow-key "<")
  (consult-preview-key '(:debounce 0.2 any))
  (xref-show-xrefs-function #'consult-xref)
  (xref-show-definitions-function #'consult-xref)
  :config
  ;; Match the rgv alias from ~/.zshrc: vendor trees are noise.
  (setq consult-ripgrep-args
        (concat consult-ripgrep-args " --iglob=!vendor/")))

(use-package embark
  :bind (("C-."   . embark-act)
         ("C-;"   . embark-dwim)
         ("C-h B" . embark-bindings))
  :custom
  (prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package wgrep
  :defer t
  :custom
  (wgrep-auto-save-buffer t))

(use-package corfu
  :hook (emacs-startup . global-corfu-mode)
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.1)
  (corfu-auto-prefix 2)
  (corfu-cycle t)
  (corfu-preselect 'prompt)
  (corfu-quit-no-match 'separator)
  :bind (:map corfu-map
              ("TAB"     . corfu-next)
              ([tab]     . corfu-next)
              ("S-TAB"   . corfu-previous)
              ([backtab] . corfu-previous))
  :config
  (require 'corfu-popupinfo)
  (corfu-popupinfo-mode 1)
  (require 'corfu-history)
  (corfu-history-mode 1)
  (with-eval-after-load 'savehist
    (add-to-list 'savehist-additional-variables 'corfu-history)))

;; Emacs 31 draws child frames on TTYs, so corfu works in the VMs as-is.
;; 30.2 needs corfu-terminal, which repaints the popup with overlays.
;; Drop this block once the VMs are on 31.
(declare-function corfu-terminal-mode "corfu-terminal")
(unless (featurep 'tty-child-frames)
  (use-package corfu-terminal
    :after corfu
    :config (corfu-terminal-mode 1)))

(use-package nerd-icons-corfu
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package cape
  :init
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-dabbrev))

(provide 'bison-completion)
;;; bison-completion.el ends here
