;;; worktrunk-tests.el --- Test definitions for worktrunk  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Naoya Yamashita

;; Author: Naoya Yamashita <conao3@gmail.com>
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

;; Test definitions for `worktrunk'.


;;; Code:

(require 'cort)
(require 'worktrunk)

(cort-deftest worktrunk/build-command
  '((:string=
     (worktrunk--build-command '("switch" "feature"))
     "wt switch feature")
    (:string=
     (worktrunk--build-command '("list" "--format=json"))
     "wt list --format\\=json")
    (:string=
     (worktrunk--build-command '("switch" "--create" "foo bar"))
     "wt switch --create foo\\ bar")))

(cort-deftest worktrunk/default-buffer-name
  '((:string=
     (worktrunk-default-buffer-name "switch")
     "*worktrunk switch*")
    (:string=
     (worktrunk-default-buffer-name "merge")
     "*worktrunk merge*")))

(cort-deftest worktrunk/list-entry
  '((:equal
     (worktrunk-list--entry
      '((branch . "master")
        (path . "/tmp/foo")
        (commit (short_sha . "abc1234") (message . "init"))
        (is_current . t)))
     '("master" ["master" "*" "abc1234" "/tmp/foo" "init"]))
    (:equal
     (worktrunk-list--entry
      '((branch . "feature")
        (path . "/tmp/feature")
        (commit (short_sha . "deadbee") (message . "wip"))
        (is_current . :json-false)))
     '("feature" ["feature" "" "deadbee" "/tmp/feature" "wip"]))
    (:equal
     (worktrunk-list--entry
      '((branch)
        (path)
        (commit)
        (is_current . :json-false)))
     '("(detached)" ["(detached)" "" "" "" ""]))))

(cort-deftest worktrunk/known-backend-handlers
  '((:eq (fboundp 'worktrunk--run-shell) t)
    (:eq (fboundp 'worktrunk--run-term) t)
    (:eq (fboundp 'worktrunk--run-vterm) t)
    (:eq (fboundp 'worktrunk--run-eat) t)))

;; (provide 'worktrunk-tests)

;;; worktrunk-tests.el ends here
