;;; bison-lang-ops.el --- Infrastructure and config languages  -*- lexical-binding: t; -*-

;; Copyright (c) 2020-2026 Brad Ison
;; Author: Brad Ison <bison@xvdf.io>

;;; Commentary:

;; The SRE side: YAML and Kubernetes manifests, Dockerfiles, Terraform,
;; Jsonnet, Nix, systemd units, Markdown, and the small formats in
;; between.  Built-in tree-sitter modes wherever one exists.

;;; Code:

(require 'bison-lib)
(require 'bison-lang)

(defun bison-lang-ops--yaml-setup ()
  "Buffer settings for YAML.
`yaml-ts-mode' derives from `text-mode', so the `prog-mode' hooks that
turn on diagnostics and line numbers elsewhere do not fire here."
  (setq-local tab-width 2
              indent-tabs-mode nil)
  (display-line-numbers-mode 1)
  (flymake-mode 1))

(use-package yaml-ts-mode
  :straight (:type built-in)
  :mode "\\.ya?ml\\'"
  :hook (yaml-ts-mode . bison-lang-ops--yaml-setup))

(use-package flymake-yamllint
  :straight (flymake-yamllint :host github :repo "emacsmirror/flymake-yamllint")
  :hook (yaml-ts-mode . flymake-yamllint-setup))

(use-package dockerfile-ts-mode
  :straight (:type built-in)
  :mode ("/\\(?:Docker\\|Container\\)file\\(?:\\..*\\)?\\'" . dockerfile-ts-mode))

(use-package terraform-mode
  :mode ("\\.tf\\(?:vars\\)?\\'" . terraform-mode)
  :hook (terraform-mode . eglot-ensure)
  :hook (terraform-mode . bison-eglot-format-on-save))

(use-package jsonnet-mode
  :mode "\\.\\(?:jsonnet\\|libsonnet\\)\\'"
  :custom
  (jsonnet-use-smie t))

(use-package json-ts-mode
  :straight (:type built-in)
  :mode "\\.json\\'")

(use-package toml-ts-mode
  :straight (:type built-in)
  :mode "\\.toml\\'")

(use-package sh-script
  :straight (:type built-in)
  :mode ("\\.\\(?:ba\\|z\\)?sh\\'" . bash-ts-mode)
  :interpreter (("bash" . bash-ts-mode)
                ("sh" . bash-ts-mode)))

(use-package nix-mode
  :mode "\\.nix\\'")

(use-package systemd
  :defer t)

;; Two unrelated linters answer to the name markdownlint: Node's
;; markdownlint-cli (Homebrew, macOS) and Ruby's mdl (Debian's
;; `markdownlint' package, the VMs).  The flymake-markdownlint package
;; only speaks the first one's JSON, so this backend parses the plain
;; output both produce: "file:LINE[:COL] [error] MDnnn... text" from
;; markdownlint-cli, "(stdin):LINE: MDnnn text" from mdl.

(defvar-local bison-markdownlint--process nil)

(defun bison-markdownlint--command ()
  "Return the linter command line reading Markdown from stdin, or nil."
  (cond ((executable-find "markdownlint") '("markdownlint" "--stdin"))
        ((executable-find "mdl") '("mdl"))))

(defun bison-markdownlint--parse (source)
  "Return flymake diagnostics for SOURCE from the linter output in this buffer."
  (let (diags)
    (goto-char (point-min))
    (while (re-search-forward
            (rx bol (+ (not ":")) ":" (group (+ digit))
                (? ":" (group (+ digit))) (? ":")
                (+ " ") (? "error" (+ " "))
                (group "MD" (+ digit)) (* (not " ")) (+ " ")
                (group (+ nonl)))
            nil t)
      (let* ((line (string-to-number (match-string 1)))
             (col (and (match-string 2) (string-to-number (match-string 2))))
             (text (format "%s: %s" (match-string 3) (match-string 4)))
             (region (flymake-diag-region source line col)))
        (push (flymake-make-diagnostic source (car region) (cdr region)
                                       :warning text)
              diags)))
    (nreverse diags)))

(defun bison-markdownlint (report-fn &rest _args)
  "Flymake backend running markdownlint or mdl on the buffer.
Calls REPORT-FN with the diagnostics."
  (when-let* ((command (bison-markdownlint--command)))
    (when (process-live-p bison-markdownlint--process)
      (kill-process bison-markdownlint--process))
    (let ((source (current-buffer)))
      (save-restriction
        (widen)
        (setq bison-markdownlint--process
              (make-process
               :name "bison-markdownlint" :noquery t :connection-type 'pipe
               :buffer (generate-new-buffer " *bison-markdownlint*")
               :command command
               :sentinel
               (lambda (proc _event)
                 (when (memq (process-status proc) '(exit signal))
                   (unwind-protect
                       (when (and (buffer-live-p source)
                                  (eq proc (buffer-local-value
                                            'bison-markdownlint--process source)))
                         (with-current-buffer (process-buffer proc)
                           (funcall report-fn (bison-markdownlint--parse source))))
                     (kill-buffer (process-buffer proc)))))))
        (process-send-region bison-markdownlint--process (point-min) (point-max))
        (process-send-eof bison-markdownlint--process)))))

(defun bison-markdownlint-setup ()
  "Enable flymake with the markdownlint backend in this buffer."
  (add-hook 'flymake-diagnostic-functions #'bison-markdownlint nil t)
  (flymake-mode 1))

(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :hook (markdown-mode . bison-markdownlint-setup)
  :custom
  (markdown-fontify-code-blocks-natively t)
  (markdown-command "markdown"))

(use-package protobuf-mode
  :mode "\\.proto\\'")

(provide 'bison-lang-ops)
;;; bison-lang-ops.el ends here
