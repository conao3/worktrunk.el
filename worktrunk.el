;;; worktrunk.el --- Worktrunk integration  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Naoya Yamashita

;; Author: Naoya Yamashita <conao3@gmail.com>
;; Version: 0.0.1
;; Keywords: convenience
;; Package-Requires: ((emacs "26.1"))
;; URL: https://github.com/conao3/worktrunk.el

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Worktrunk integration.

;; This package wraps the `wt' command-line tool from worktrunk
;; (https://github.com/max-sixty/worktrunk).  Interactive subcommands
;; run inside an Emacs terminal buffer; the backend is selectable via
;; `worktrunk-terminal-backend' and defaults to `shell-mode'.


;;; Code:

(require 'comint)
(require 'json)
(require 'subr-x)
(require 'tabulated-list)

(declare-function make-term "term"
                  (name program &optional startfile &rest switches))
(declare-function term-mode "term" ())
(declare-function term-char-mode "term" ())
(declare-function vterm "vterm" (&optional buffer-name))
(declare-function vterm-send-string "vterm" (string &optional paste-p))
(declare-function vterm-send-return "vterm" ())
(declare-function eat "eat" (&optional program arg))

(defvar vterm-buffer-name)
(defvar eat-buffer-name)

(defgroup worktrunk nil
  "Worktrunk integration."
  :group 'convenience
  :link '(url-link :tag "Github" "https://github.com/conao3/worktrunk.el"))

(defcustom worktrunk-executable "wt"
  "Path to the `wt' executable."
  :group 'worktrunk
  :type 'string)

(defcustom worktrunk-terminal-backend 'shell
  "Terminal backend used to run interactive `wt' subcommands.

The chosen backend opens a buffer in the corresponding mode and
sends the assembled `wt' command line for execution.  Backends
that depend on third-party packages (`vterm', `eat') are loaded
on demand and signal an error when unavailable."
  :group 'worktrunk
  :type '(choice (const :tag "shell-mode" shell)
                 (const :tag "term-mode" term)
                 (const :tag "vterm-mode" vterm)
                 (const :tag "eat-mode" eat)))

(defcustom worktrunk-buffer-name-function
  #'worktrunk-default-buffer-name
  "Function returning the terminal buffer name for a subcommand.
Called with one string argument: the `wt' subcommand."
  :group 'worktrunk
  :type 'function)

(defun worktrunk-default-buffer-name (subcommand)
  "Return the default terminal buffer name for SUBCOMMAND."
  (format "*worktrunk %s*" subcommand))

(defun worktrunk--call (&rest args)
  "Run `wt' synchronously with ARGS and return stdout.
Signal an error when the process exits with a non-zero status."
  (with-temp-buffer
    (let ((status (apply #'call-process worktrunk-executable nil
                         (current-buffer) nil args)))
      (unless (eq status 0)
        (error "Failed to run wt %s (exit %S): %s"
               (mapconcat #'identity args " ")
               status
               (string-trim (buffer-string))))
      (buffer-string))))

(defun worktrunk--call-json (&rest args)
  "Run `wt' with ARGS and parse stdout as JSON."
  (let ((json-array-type 'list)
        (json-object-type 'alist)
        (json-key-type 'symbol))
    (json-read-from-string (apply #'worktrunk--call args))))

(defun worktrunk--build-command (args)
  "Assemble a shell command line from `worktrunk-executable' and ARGS."
  (mapconcat #'shell-quote-argument
             (cons worktrunk-executable args)
             " "))

(defun worktrunk--run-in-terminal (subcommand &rest args)
  "Run `wt SUBCOMMAND ARGS...' through `worktrunk-terminal-backend'."
  (let* ((buffer-name (funcall worktrunk-buffer-name-function subcommand))
         (command (worktrunk--build-command (cons subcommand args)))
         (handler (intern (format "worktrunk--run-%s"
                                  worktrunk-terminal-backend))))
    (unless (fboundp handler)
      (error "Unknown `worktrunk-terminal-backend': %S"
             worktrunk-terminal-backend))
    (funcall handler buffer-name command)))

(defun worktrunk--run-shell (buffer-name command)
  "Run COMMAND in a fresh `shell-mode' buffer named BUFFER-NAME."
  (require 'shell)
  (let* ((name (generate-new-buffer-name buffer-name))
         (buffer (get-buffer-create name)))
    (shell buffer)
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert command)
      (comint-send-input))
    (pop-to-buffer buffer)))

(defun worktrunk--run-term (buffer-name command)
  "Run COMMAND in a fresh `term-mode' buffer named BUFFER-NAME."
  (require 'term)
  (let* ((short (replace-regexp-in-string "\\`\\*\\|\\*\\'" "" buffer-name))
         (program (or (bound-and-true-p explicit-shell-file-name)
                      (getenv "SHELL")
                      "/bin/sh"))
         (buffer (make-term (generate-new-buffer-name short)
                            program nil "-c" command)))
    (with-current-buffer buffer
      (term-mode)
      (term-char-mode))
    (pop-to-buffer buffer)))

(defun worktrunk--run-vterm (buffer-name command)
  "Run COMMAND in a `vterm-mode' buffer named BUFFER-NAME."
  (unless (require 'vterm nil t)
    (error "Package `vterm' is not available"))
  (let* ((vterm-buffer-name (generate-new-buffer-name buffer-name))
         (buffer (vterm vterm-buffer-name)))
    (with-current-buffer buffer
      (vterm-send-string command)
      (vterm-send-return))
    (pop-to-buffer buffer)))

(defun worktrunk--run-eat (buffer-name command)
  "Run COMMAND in an `eat-mode' buffer named BUFFER-NAME."
  (unless (require 'eat nil t)
    (error "Package `eat' is not available"))
  (let ((eat-buffer-name (generate-new-buffer-name buffer-name)))
    (eat command)))

(defun worktrunk--worktrees (&optional with-branches with-remotes)
  "Return parsed `wt list --format=json' data.
With WITH-BRANCHES, include branches without worktrees.  With
WITH-REMOTES, include remote-only branches."
  (let ((args (list "list" "--format=json")))
    (when with-branches (setq args (append args '("--branches"))))
    (when with-remotes  (setq args (append args '("--remotes"))))
    (apply #'worktrunk--call-json args)))

(defun worktrunk--branch-names (&optional with-branches with-remotes)
  "Return branch names reported by `wt list'.
WITH-BRANCHES and WITH-REMOTES are forwarded to `worktrunk--worktrees'."
  (delq nil
        (mapcar (lambda (entry) (alist-get 'branch entry))
                (worktrunk--worktrees with-branches with-remotes))))

(defun worktrunk--read-branch (prompt &optional with-branches with-remotes default)
  "Read a branch name with completion using PROMPT.
WITH-BRANCHES and WITH-REMOTES toggle additional listings.  DEFAULT
is offered as the initial input."
  (completing-read prompt
                   (worktrunk--branch-names with-branches with-remotes)
                   nil nil nil nil default))

;;;###autoload
(defun worktrunk-switch (branch &optional create base)
  "Switch to BRANCH worktree, creating it when CREATE is non-nil.
BASE selects the base branch when creating; nil means use the
default branch."
  (interactive
   (let* ((create (and current-prefix-arg t))
          (branch (if create
                      (read-string "New branch: ")
                    (worktrunk--read-branch "Switch to branch: " t t)))
          (base (when create
                  (let ((b (worktrunk--read-branch
                            "Base branch (empty for default): " nil nil "")))
                    (and (not (string-empty-p b)) b)))))
     (list branch create base)))
  (let ((args (list branch)))
    (when base (setq args (cons (format "--base=%s" base) args)))
    (when create (setq args (cons "--create" args)))
    (apply #'worktrunk--run-in-terminal "switch" args)))

;;;###autoload
(defun worktrunk-create (branch &optional base)
  "Create new BRANCH and worktree.  Optional BASE picks a base branch."
  (interactive
   (list (read-string "New branch: ")
         (let ((b (worktrunk--read-branch
                   "Base branch (empty for default): " nil nil "")))
           (and (not (string-empty-p b)) b))))
  (worktrunk-switch branch t base))

;;;###autoload
(defun worktrunk-remove (branch &optional force)
  "Remove the worktree for BRANCH.
With prefix arg or non-nil FORCE, pass `--force'."
  (interactive
   (list (worktrunk--read-branch "Remove branch: ")
         current-prefix-arg))
  (let ((args (list branch)))
    (when force (setq args (cons "--force" args)))
    (apply #'worktrunk--run-in-terminal "remove" args)))

;;;###autoload
(defun worktrunk-merge (&optional target)
  "Merge the current branch into TARGET.
TARGET defaults to the repository's default branch."
  (interactive
   (list (let ((b (worktrunk--read-branch
                   "Merge into (empty for default): " nil nil "")))
           (and (not (string-empty-p b)) b))))
  (apply #'worktrunk--run-in-terminal
         "merge"
         (when target (list target))))

;;;###autoload
(defun worktrunk-step-commit ()
  "Run `wt step commit'."
  (interactive)
  (worktrunk--run-in-terminal "step" "commit"))

;;;###autoload
(defun worktrunk-step-squash ()
  "Run `wt step squash'."
  (interactive)
  (worktrunk--run-in-terminal "step" "squash"))

;;;###autoload
(defun worktrunk-step-rebase ()
  "Run `wt step rebase'."
  (interactive)
  (worktrunk--run-in-terminal "step" "rebase"))

;;;###autoload
(defun worktrunk-step-push ()
  "Run `wt step push'."
  (interactive)
  (worktrunk--run-in-terminal "step" "push"))

;;;###autoload
(defun worktrunk-step-diff ()
  "Run `wt step diff'."
  (interactive)
  (worktrunk--run-in-terminal "step" "diff"))

(defvar worktrunk-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'worktrunk-list-find-file)
    (define-key map (kbd "s") #'worktrunk-list-switch)
    (define-key map (kbd "c") #'worktrunk-create)
    (define-key map (kbd "D") #'worktrunk-list-remove)
    (define-key map (kbd "m") #'worktrunk-list-merge)
    (define-key map (kbd "g") #'worktrunk-list-refresh)
    map)
  "Keymap for `worktrunk-list-mode'.")

(define-derived-mode worktrunk-list-mode tabulated-list-mode "Worktrunk"
  "Major mode for browsing wt worktrees."
  (setq tabulated-list-format
        [("Branch" 28 t)
         ("Cur" 3 nil)
         ("HEAD" 10 nil)
         ("Path" 50 t)
         ("Message" 0 t)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header))

(defun worktrunk-list--entry (item)
  "Convert ITEM (a parsed JSON record) to a `tabulated-list' entry."
  (let* ((branch (or (alist-get 'branch item) "(detached)"))
         (path (or (alist-get 'path item) ""))
         (commit (alist-get 'commit item))
         (short (or (alist-get 'short_sha commit) ""))
         (message (or (alist-get 'message commit) ""))
         (current (if (eq (alist-get 'is_current item) t) "*" "")))
    (list branch (vector branch current short path message))))

(defun worktrunk-list-refresh ()
  "Reload the worktree list."
  (interactive)
  (setq tabulated-list-entries
        (mapcar #'worktrunk-list--entry (worktrunk--worktrees)))
  (tabulated-list-print t))

(defun worktrunk-list--current-branch ()
  "Return the branch name on the current `worktrunk-list-mode' line."
  (or (tabulated-list-get-id)
      (user-error "No worktree at point")))

(defun worktrunk-list--current-path ()
  "Return the worktree path on the current line, if any."
  (let ((entry (tabulated-list-get-entry)))
    (and entry (aref entry 3))))

(defun worktrunk-list-switch ()
  "Switch to the worktree on the current line."
  (interactive)
  (worktrunk--run-in-terminal "switch" (worktrunk-list--current-branch)))

(defun worktrunk-list-find-file ()
  "Open the worktree on the current line in `dired'.
Falls back to `worktrunk-list-switch' when no path is recorded."
  (interactive)
  (let ((path (worktrunk-list--current-path)))
    (if (and path (not (string-empty-p path)))
        (dired path)
      (worktrunk-list-switch))))

(defun worktrunk-list-remove ()
  "Remove the worktree on the current line."
  (interactive)
  (let ((branch (worktrunk-list--current-branch)))
    (when (yes-or-no-p (format "Remove worktree for `%s'? " branch))
      (worktrunk--run-in-terminal "remove" branch))))

(defun worktrunk-list-merge ()
  "Merge the worktree on the current line into the default branch."
  (interactive)
  (let* ((branch (worktrunk-list--current-branch))
         (path (worktrunk-list--current-path)))
    (when (yes-or-no-p (format "Merge `%s' into default branch? " branch))
      (let ((default-directory (if (and path (not (string-empty-p path)))
                                   (file-name-as-directory path)
                                 default-directory)))
        (worktrunk--run-in-terminal "merge")))))

;;;###autoload
(defun worktrunk-list ()
  "Display the worktrunk worktree list."
  (interactive)
  (let ((buffer (get-buffer-create "*worktrunk-list*")))
    (with-current-buffer buffer
      (worktrunk-list-mode)
      (worktrunk-list-refresh))
    (pop-to-buffer buffer)))

(provide 'worktrunk)

;;; worktrunk.el ends here
