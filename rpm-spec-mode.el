;;; rpm-spec-mode.el --- RPM spec mode for Emacs/XEmacs -*- lexical-binding:t -*-

;; Copyright (C) 1997-2015 Stig Bjørlykke, <stig@bjorlykke.org>

;; Author:   Stig Bjørlykke, <stig@bjorlykke.org>
;;	Tore Olsen <toreo@tihlde.org>
;;	Steve Sanbeg <sanbeg@dset.com>
;;	Tim Powers <timp@redhat.com>
;;	Trond Eivind Glomsrød <teg@redhat.com>
;;	Chmouel Boudjnah <chmouel@mandrakesoft.com>
;;	Ville Skyttä <ville.skytta@iki.fi>
;;	Adam Spiers <elisp@adamspiers.org>
;; Maintainer: Björn Bidar <bjorn.bidar@thaodan.de>

;; Keywords: unix languages rpm
;; Version:  0.16
;; URL: https://github.com/Thaodan/rpm-spec-mode/
;; Package-Requires: ((emacs "29.0.90"))

;; This file was part of XEmacs.
;; RPM-Spec-Mode is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; RPM-Spec-Mode is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with RPM-Spec-Mode; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301 USA.

;;; Synched up with: not in GNU Emacs.

;;; Thanx to:

;;     Tore Olsen <toreo@tihlde.org> for some general fixes.
;;     Steve Sanbeg <sanbeg@dset.com> for navigation functions and
;;          some Emacs fixes.
;;     Tim Powers <timp@redhat.com> and Trond Eivind Glomsrød
;;          <teg@redhat.com> for Red Hat adaptions and some fixes.
;;     Chmouel Boudjnah <chmouel@mandrakesoft.com> for Mandrake fixes.
;;     Ville Skyttä  <ville.skytta@iki.fi> for some fixes.
;;     Adam Spiers <elisp@adamspiers.org> for GNU emacs compilation
;;          and other misc fixes.

;;; ToDo:

;; - rewrite function names.
;; - autofill changelog entries.
;; - customize rpm-tags-list, rpm-obsolete-tags-list and rpm-group-tags-list.
;; - get values from `rpm --showrc'.
;; - ssh/rsh for compile.
;; - finish integrating the new navigation functions in with existing stuff.
;; - use a single prefix consistently (internal)

;;; Commentary:

;; This mode is used for editing spec files used for building RPM packages.
;;
;; Most recent version is available from:
;;  <https://github.com/bjorlykke/rpm-spec-mode>
;;
;; Put this in your .emacs file to enable autoloading of rpm-spec-mode,
;; and auto-recognition of ".spec" files:
;;
;;  (autoload 'rpm-spec-mode "rpm-spec-mode.el" "RPM spec mode." t)
;;  (setq auto-mode-alist (append '(("\\.spec" . rpm-spec-mode))
;;                                auto-mode-alist))
;;------------------------------------------------------------
;;

;;; Code:
(require 'compile)
(require 'sh-script)
(require 'cc-mode)
(require 'easymenu)

(declare-function lm-version "lisp-mnt")
(declare-function lm-maintainers "lisp-mnt")

(defconst rpm-spec-mode-version "0.16" "Version of `rpm-spec-mode'.")

(defgroup rpm-spec nil
  "RPM spec mode with Emacs enhancements."
  :prefix "rpm-spec-"
  :group 'languages)

(defcustom rpm-spec-build-command "rpmbuild"
  "Command for building an RPM package."
  :type 'string
  :group 'rpm-spec)

(defcustom rpm-spec-add-attr nil
  "Add \"%attr\" entry for file listings or not."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-short-circuit nil
  "Skip straight to specified stage.
\(ie, skip all stages leading up to the specified stage).  Only valid
in \"%build\" and \"%install\" stage."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-timecheck "0"
  "Set the \"timecheck\" age (0 to disable).
The timecheck value expresses, in seconds, the maximum age of a file
being packaged.  Warnings will be printed for all files beyond the
timecheck age."
  :type 'integer
  :group 'rpm-spec)

(defcustom rpm-spec-buildroot ""
  "When building, override the BuildRoot tag with directory <dir>."
  :type 'string
  :group 'rpm-spec)

(defcustom rpm-spec-target ""
  "Interpret given string as `arch-vendor-os'.
Set the macros _target, _target_arch and _target_os accordingly"
  :type 'string
  :group 'rpm-spec)

(define-obsolete-variable-alias
  'rpm-completion-ignore-case 'rpm-spec-completion-ignore-case "0.12")

(defcustom rpm-spec-completion-ignore-case t
  "*Non-nil means that case differences are ignored during completion.
A value of nil means that case is significant.
This is used during Tempo template completion."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-clean nil
  "Remove the build tree after the packages are made."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-rmsource nil
  "Remove the source and spec file after the packages are made."
  :type 'boolean
  :group 'rpm-spec)

(define-obsolete-variable-alias
  'rpm-spec-test 'rpm-spec-nobuild "0.12")

(defcustom rpm-spec-nobuild nil
  "Do not execute any build stages.  Useful for testing out spec files."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-quiet nil
  "Print as little as possible.
Normally only error messages will be displayed."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-sign-gpg nil
  "Embed a GPG signature in the package.
This signature can be used to verify the integrity and the origin of
the package."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-nodeps nil
  "Do not verify build dependencies."
  :type 'boolean
  :group 'rpm-spec)

(define-obsolete-variable-alias
  'rpm-initialize-sections 'rpm-spec-initialize-sections "0.12")

(defcustom rpm-spec-initialize-sections t
  "Automatically add empty section headings to new spec files."
  :type 'boolean
  :group 'rpm-spec)

(define-obsolete-variable-alias
  'rpm-insert-version 'rpm-spec-insert-changelog-version "0.12")

(defcustom rpm-spec-insert-changelog-version t
  "Automatically add version in a new change log entry."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-user-full-name user-full-name
  "Full name of the user in the change log and Packager tag.
Can be either a string or a function."
  :type '(choice function
				 string)
  :group 'rpm-spec)

(defcustom rpm-spec-user-mail-address user-mail-address
  "Email address of the user used in the change log and the Packager tag.
Can be either a string or a function."
  :type '(choice function
                 string)
  :group 'rpm-spec)

(defcustom rpm-spec-indent-heading-values nil
  "*Indent values for all tags in the \"heading\" of the spec file."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-spec-default-release "1"
  "*Default value for the Release tag in new spec files."
  :type 'string
  :group 'rpm-spec)

(defcustom rpm-spec-default-epoch nil
  "*If non-nil, default value for the Epoch tag in new spec files."
  :type '(choice (const :tag "No Epoch" nil) integer)
  :group 'rpm-spec)

(defcustom rpm-spec-default-buildroot
  "%{_tmppath}/%{name}-%{version}-%{release}-root"
  "*Default value for the BuildRoot tag in new spec files."
  :type 'integer
  :group 'rpm-spec)

(defcustom rpm-spec-default-build-section ""
  "*Default %build section in new spec files."
  :type 'string
  :group 'rpm-spec)

(defcustom rpm-spec-default-install-section "rm -rf $RPM_BUILD_ROOT\n"
  "*Default %install section in new spec files."
  :type 'string
  :group 'rpm-spec)

(defcustom rpm-spec-default-clean-section "rm -rf $RPM_BUILD_ROOT\n"
  "*Default %clean section in new spec files."
  :type 'string
  :group 'rpm-spec)

(defcustom rpm-spec-auto-topdir nil
  "*Automatically detect an rpm build directory tree and define _topdir."
  :type 'boolean
  :group 'rpm-spec)

(defcustom rpm-build-topdir "~/rpmbuild"
  "Rpm _topdir directory to be used when calling rpmbuild."
  :type 'directory
  :safe t
  :package-version '(rpm-spec . 0.17.0)
  :group 'rpm-spec)

(defgroup rpm-spec-faces nil
  "Font lock faces for `rpm-spec-mode'."
  :prefix "rpm-spec-"
  :group 'rpm-spec
  :group 'faces)

;;------------------------------------------------------------
;; variables used by navigation functions.

(defconst rpm-sections
  '("preamble"
    "description"
    "prep"
    "generate_buildrequires"
    "conf"
    "build"
    "install"
    "check"
    "clean"
    "files"
    "changelog")
  "Partial list of section names.")
(defconst rpm-scripts
  ;; trigger, filetrigger, transfiletrigger no found in build/parseScript.c
  '("pre"
    "post"
    "preun"
    "postun"
    "trigger"
    "triggerin"
    "triggerprein"
    "triggerun"
    "triggerpostun"
    "pretrans"
    "posttrans"
    "preuntrans"
    "postuntrans"
    "verifyscript"
    "filetriggerin"
    "filetrigger"
    "filetriggerun"
    "filetriggerpostun"
    "transfiletriggerin"
    "transfiletrigger"
    "transfiletriggerun"
    "transfiletriggerpostun")
  "List of rpm scripts.")
(defconst rpm-section-seperate "^%\\(\\w+\\)\\s-")
(defconst rpm-section-regexp
  (eval-when-compile
    (concat "^%"
            (regexp-opt
             ;; From RPM 4.20.0 sources, file build/parseSpec.c: partList[].
             '("package"
               "prep"
               "generate_buildrequires"
               "conf"
               "build"
               "install"
               "check"
               "clean"
               "preun"
               "postun"
               "pretrans"
               "posttrans"
               "preuntrans"
               "postuntrans"
               "pre"
               "post"
               "files"
               "changelog"
               "description"
               "triggerpostun"
               "triggerprein"
               "triggerun"
               "triggerin"
               "trigger"
               "verifyscript"
               "sepolicy"
               "filetriggerin"
               "filetrigger"
               "filetriggerun"
               "filetriggerpostun"
               "transfiletriggerin"
               "transfiletrigger"
               "transfiletriggerun"
               "transfiletriggerpostun"
               "end"
               "patchlist"
               "sourcelist")
             t)
            "\\b"))
  "Regular expression to match beginning of a section.")

;;------------------------------------------------------------

(defface rpm-spec-tag-face
  '((t (:inherit font-lock-keyword-face)))
  "*Face for tags."
  :group 'rpm-spec-faces)

(defface rpm-spec-obsolete-tag-face
  '((t (:inherit font-lock-warning-face)))
  "*Face for obsolete tags."
  :group 'rpm-spec-faces)

(defface rpm-spec-macro-face
  '((t (:inherit font-lock-preprocessor-face)))
  "*Face for RPM macros and variables."
  :group 'rpm-spec-faces)

(defface rpm-spec-var-face
  '((t (:inherit font-lock-variable-name-face)))
  "*Face for environment variables."
  :group 'rpm-spec-faces)

(defface rpm-spec-doc-face
  '((t (:inherit font-lock-doc-face)))
  "*Face for %doc and %license entries in %files."
  :group 'rpm-spec-faces)

(defface rpm-spec-dir-face
  '((t (:inherit font-lock-string-face)))
  "*Face for %dir entries in %files."
  :group 'rpm-spec-faces)

(defface rpm-spec-package-face
  '((t (:inherit font-lock-function-name-face)))
  "*Face for package tag."
  :group 'rpm-spec-faces)

(defface rpm-spec-ghost-face
  '((t (:inherit font-lock-string-face)))
  "*Face for %ghost and %config entries in %files."
  :group 'rpm-spec-faces)

(defface rpm-spec-section-face
  '((t (:inherit font-lock-function-name-face)))
  "*Face for section markers."
  :group 'rpm-spec-faces)

;;; GNU emacs font-lock needs these...
(defvar rpm-spec-macro-face
  'rpm-spec-macro-face "*Face for RPM macros and variables.")
(defvar rpm-spec-var-face
  'rpm-spec-var-face "*Face for environment variables.")
(defvar rpm-spec-tag-face
  'rpm-spec-tag-face "*Face for tags.")
(defvar rpm-spec-obsolete-tag-face
  'rpm-spec-tag-face "*Face for obsolete tags.")
(defvar rpm-spec-package-face
  'rpm-spec-package-face "*Face for package tag.")
(defvar rpm-spec-dir-face
  'rpm-spec-dir-face "*Face for %dir entries in %files.")
(defvar rpm-spec-doc-face
  'rpm-spec-doc-face "*Face for %doc and %license entries in %files.")
(defvar rpm-spec-ghost-face
  'rpm-spec-ghost-face "*Face for %ghost and %config entries in %files.")
(defvar rpm-spec-section-face
  'rpm-spec-section-face "*Face for section markers.")

(defvar rpm-default-umask "-"
  "*Default umask for files, specified with \"%attr\".")
(defvar rpm-default-owner "root"
  "*Default owner for files, specified with \"%attr\".")
(defvar rpm-default-group "root"
  "*Default group for files, specified with \"%attr\".")

;;------------------------------------------------------------

(defvar rpm-no-gpg nil "Tell rpm not to sign package.")
(defvar rpm-spec-nobuild-option "--nobuild" "Option for no build.")

(defvar rpm-tags-list
  ;; From RPM 4.20.0 sources, file build/parsePreamble.c: preambleList[]:
  '(("Name")
    ("Version")
    ("Release")
    ("Epoch")
    ("Summary")
    ("License")
    ("SourceLicense")
    ("Distribution")
    ("DistURL")
    ("Vendor")
    ("Group")
    ("Packager")
    ("URL")
    ("VCS")
    ("Source")
    ("Patch")
    ("NoSource")
    ("NoPatch")
    ("ExcludeArch")
    ("ExclusiveArch")
    ("ExcludeOS")
    ("ExclusiveOS")
    ("Icon")
    ("Provides")
    ("Requires")
    ("Recommends")
    ("Suggests")
    ("Supplements")
    ("Enhances")
    ("PreReq")
    ("Conflicts")
    ("Obsoletes")
    ("Prefixes")
    ("Prefix")
    ("BuildRoot")
    ("BuildArchitectures")
    ("BuildArch")
    ("BuildConflicts")
    ("BuildOption")
    ("BuildPreReq")
    ("BuildRequires")
    ("BuildSystem")
    ("AutoReqProv")
    ("AutoReq")
    ("AutoProv")
    ("DocDir")
    ("DistTag")
    ("BugURL")
    ("TranslationURL")
    ("UpstreamReleases")
    ("OrderWithRequires")
    ("RemovePathPostFixes")
    ("ModularityLabel")
    ;; ...plus some from rpm5.org:
    ("CVSId")
    ("SVNId")
    ("BuildSuggests")
    ("BuildEnhances")
    ("Variants")
    ("Variant")
    ("XMajor")
    ("XMinor")
    ("RepoTag")
    ("Keywords")
    ("Keyword")
    ("BuildPlatforms")
    ;; ...plus a few macros that aren't tags but useful here.
    ("%description")
    ("%files")
    ("%ifarch")
    ("%package")
    )
  "List of elements that are valid tags.")

(defvar rpm-tags-regexp
  (concat "\\(\\<" (regexp-opt (mapcar 'car rpm-tags-list))
	  "\\|\\(Patch\\|Source\\)[0-9]+\\>\\)")
  "Regular expression for matching valid tags.")

(defvar rpm-obsolete-tags-list
  ;; From RPM sources, file build/parsePreamble.c: preambleList[].
  '(("Copyright")    ;; 4.4.2
    ("RHNPlatform")  ;; 4.4.2, 4.4.9
    ("Serial")       ;; 4.4.2, 4.4.9
    )
  "List of elements that are obsolete tags in some versions of rpm.")

(defvar rpm-obsolete-tags-regexp
  (regexp-opt (mapcar 'car rpm-obsolete-tags-list) 'words)
  "Regular expression for matching obsolete tags.")

(defvar rpm-group-tags-list
  ;; From RPM 4.4.9 sources, file GROUPS.
  '(("Amusements/Games")
    ("Amusements/Graphics")
    ("Applications/Archiving")
    ("Applications/Communications")
    ("Applications/Databases")
    ("Applications/Editors")
    ("Applications/Emulators")
    ("Applications/Engineering")
    ("Applications/File")
    ("Applications/Internet")
    ("Applications/Multimedia")
    ("Applications/Productivity")
    ("Applications/Publishing")
    ("Applications/System")
    ("Applications/Text")
    ("Development/Debuggers")
    ("Development/Languages")
    ("Development/Libraries")
    ("Development/System")
    ("Development/Tools")
    ("Documentation")
    ("System Environment/Base")
    ("System Environment/Daemons")
    ("System Environment/Kernel")
    ("System Environment/Libraries")
    ("System Environment/Shells")
    ("User Interface/Desktops")
    ("User Interface/X")
    ("User Interface/X Hardware Support")
    )
  "List of elements that are valid group tags.")

(defvar rpm-spec-mode-syntax-table nil
  "Syntax table in use in `rpm-spec-mode' buffers.")
(unless rpm-spec-mode-syntax-table
  (setq rpm-spec-mode-syntax-table (make-syntax-table))
  (modify-syntax-entry ?\\ "\\" rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?\n ">   " rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?\f ">   " rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?\# "<   " rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?/ "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?* "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?+ "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?- "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?= "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?% "_" rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?< "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?> "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?& "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?| "." rpm-spec-mode-syntax-table)
  (modify-syntax-entry ?\' "." rpm-spec-mode-syntax-table))

(defvar-keymap rpm-spec-mode-map
  :doc  "Keymap used in `rpm-spec-mode'."
  "C-c C-c"  #'rpm-change-tag
  "C-c C-e"  #'rpm-add-change-log-entry
  "C-c C-w"  #'rpm-goto-add-change-log-entry
  "C-c C-i"  #'rpm-insert-tag
  "C-c C-n"  #'rpm-forward-section
  "C-c C-o"  #'rpm-goto-section
  "C-c C-p"  #'rpm-backward-section
  "C-c C-r"  #'rpm-increase-release-tag
  "C-c C-u"  #'rpm-insert-true-prefix
  "C-c C-b a" #'rpm-build-all
  "C-c C-b b" #'rpm-build-binary
  "C-c C-b c" #'rpm-build-compile
  "C-c C-b i" #'rpm-build-install
  "C-c C-b l" #'rpm-list-check
  "C-c C-b p" #'rpm-build-prepare
  "C-c C-b s" #'rpm-build-source
  "C-c C-d d" #'rpm-insert-dir
  "C-c C-d o" #'rpm-insert-docdir
  "C-c C-f c" #'rpm-insert-config
  "C-c C-f d" #'rpm-insert-doc
  "C-c C-f f" #'rpm-insert-file
  "C-c C-f g" #'rpm-insert-ghost
  "C-c C-x a" #'rpm-toggle-add-attr
  "C-c C-x b" #'rpm-change-buildroot-option
  "C-c C-x c" #'rpm-toggle-clean
  "C-c C-x d" #'rpm-toggle-nodeps
  "C-c C-x f" #'rpm-files-group
  "C-c C-x g" #'rpm-toggle-sign-gpg
  "C-c C-x i" #'rpm-change-timecheck-option
  "C-c C-x n" #'rpm-toggle-nobuild
  "C-c C-x o" #'rpm-files-owner
  "C-c C-x r" #'rpm-toggle-rmsource
  "C-c C-x q" #'rpm-toggle-quiet
  "C-c C-x s" #'rpm-toggle-short-circuit
  "C-c C-x t" #'rpm-change-target-option
  "C-c C-x u" #'rpm-files-umask
  ;;(define-key rpm-spec-mode-map "C-q" #'indent-spec-exp)
  ;;(define-key rpm-spec-mode-map "\t" #'sh-indent-line)
  )

(easy-menu-define rpm-spec-mode-menu rpm-spec-mode-map
  "Post menu for `rpm-spec-mode'."
  '("RPM spec"
    ["Insert Tag..."           rpm-insert-tag                t]
    ["Change Tag..."           rpm-change-tag                t]
    "---"
    ["Go to section..."        rpm-mouse-goto-section  :keys "C-c C-o"]
    ["Forward section"         rpm-forward-section           t]
    ["Backward section"        rpm-backward-section          t]
    "---"
    ["Add change log entry..." rpm-add-change-log-entry      t]
    ["Increase release tag"    rpm-increase-release-tag      t]
    "---"
    ("Add file entry"
     ["Regular file..."        rpm-insert-file               t]
     ["Config file..."         rpm-insert-config             t]
     ["Document file..."       rpm-insert-doc                t]
     ["Ghost file..."          rpm-insert-ghost              t]
     "---"
     ["Directory..."           rpm-insert-dir                t]
     ["Document directory..."  rpm-insert-docdir             t]
     "---"
     ["Insert %{prefix}"       rpm-insert-true-prefix        t]
     "---"
     ["Default add \"%attr\" entry" rpm-toggle-add-attr
      :style toggle :selected rpm-spec-add-attr]
     ["Change default umask for files..."  rpm-files-umask   t]
     ["Change default owner for files..."  rpm-files-owner   t]
     ["Change default group for files..."  rpm-files-group   t])
    ("Build Options"
     ["Short circuit" rpm-toggle-short-circuit
      :style toggle :selected rpm-spec-short-circuit]
     ["Remove source" rpm-toggle-rmsource
      :style toggle :selected rpm-spec-rmsource]
     ["Clean"         rpm-toggle-clean
      :style toggle :selected rpm-spec-clean]
     ["No build"      rpm-toggle-nobuild
      :style toggle :selected rpm-spec-nobuild]
     ["Quiet"         rpm-toggle-quiet
      :style toggle :selected rpm-spec-quiet]
     ["GPG sign"      rpm-toggle-sign-gpg
      :style toggle :selected rpm-spec-sign-gpg]
     ["Ignore dependencies" rpm-toggle-nodeps
      :style toggle :selected rpm-spec-nodeps]
     "---"
     ["Change timecheck value..."  rpm-change-timecheck-option   t]
     ["Change buildroot value..."  rpm-change-buildroot-option   t]
     ["Change target value..."     rpm-change-target-option      t])
    ("RPM Build"
     ["Execute \"%prep\" stage"    rpm-build-prepare             t]
     ["Do a \"list check\""        rpm-list-check                t]
     ["Do the \"%build\" stage"    rpm-build-compile             t]
     ["Do the \"%install\" stage"  rpm-build-install             t]
     "---"
     ["Build binary package"       rpm-build-binary              t]
     ["Build source package"       rpm-build-source              t]
     ["Build binary and source"    rpm-build-all                 t])
    "---"
    ["About rpm-spec-mode"         rpm-about-rpm-spec-mode       t]))


(defvar rpm-spec-font-lock-keywords
  (list
   (cons rpm-section-regexp rpm-spec-section-face)
   '("%[a-zA-Z0-9_]+" 0 rpm-spec-macro-face)
   (cons (concat "^" rpm-obsolete-tags-regexp "\\(\([a-zA-Z0-9,_]+\)\\)[ \t]*:")
         '((1 'rpm-spec-obsolete-tag-face)
           (2 'rpm-spec-ghost-face)))
   (cons (concat "^" rpm-tags-regexp "\\(\([a-zA-Z0-9,_]+\)\\)[ \t]*:")
         '((1 'rpm-spec-tag-face)
           (3 'rpm-spec-ghost-face)))
   (cons (concat "^" rpm-obsolete-tags-regexp "[ \t]*:")
         '(1 'rpm-spec-obsolete-tag-face))
   (cons (concat "^" rpm-tags-regexp "[ \t]*:")
         '(1 'rpm-spec-tag-face))
   '("%\\(de\\(fine\\|scription\\)\\|files\\|global\\|package\\)[ \t]+\\([^-][^ \t\n]*\\)"
     (3 rpm-spec-package-face))
   '("^%p\\(ost\\|re\\)\\(un\\|trans\\)?[ \t]+\\([^-][^ \t\n]*\\)"
     (3 rpm-spec-package-face))
   '("%configure " 0 rpm-spec-macro-face)
   '("%dir[ \t]+\\([^ \t\n]+\\)[ \t]*" 1 rpm-spec-dir-face)
   '("%\\(doc\\(dir\\)?\\|license\\)[ \t]+\\(.*\\)\n" 3 rpm-spec-doc-face)
   '("%\\(ghost\\|config\\([ \t]*(.*)\\)?\\)[ \t]+\\(.*\\)\n"
     3 rpm-spec-ghost-face)
   '("^%.+-[a-zA-Z][ \t]+\\([a-zA-Z0-9\.-]+\\)" 1 rpm-spec-doc-face)
   '("^\\(.+\\)(\\([a-zA-Z]\\{2,2\\}\\)):"
     (1 rpm-spec-tag-face)
     (2 rpm-spec-doc-face))
   '("^\\*\\(.*[0-9] \\)\\(.*\\)<\\(.*\\)>\\(.*\\)\n"
     (1 rpm-spec-dir-face)
     (2 rpm-spec-package-face)
     (3 rpm-spec-tag-face)
     (4 rpm-spec-ghost-face))
   '("%{[^{}]*}" 0 rpm-spec-macro-face)
   '("$[a-zA-Z0-9_]+" 0 rpm-spec-var-face)
   '("${[a-zA-Z0-9_]+}" 0 rpm-spec-var-face))
  "Additional expressions to highlight in `rpm-spec-mode'.")


(defun rpm-spec-mode-comment-region (beg end &optional arg)
  "Comment each line between BEG ... END region.
But also escape the % character by duplicating it to prevent macro expansion.
ARG is passed on to `comment-region-default'."
  (comment-region-default beg
                          (+ end (replace-string-in-region "%" "%%" beg end))
                          arg))

(defun rpm-spec-mode-uncomment-region (beg end &optional arg)
  "Uncomment each line between the BEG .. END region.
But also revert the escape of the % character by deduplicating it which
reenables macro expansion.
ARG is passed on to `uncomment-region-default'."
  (uncomment-region-default beg
                            (- end (replace-string-in-region "%%" "%" beg end))
                            arg))


(defvar rpm-spec-mode-abbrev-table nil
  "Abbrev table in use in `rpm-spec-mode' buffers.")
(define-abbrev-table 'rpm-spec-mode-abbrev-table ())

;;------------------------------------------------------------
;; Imenu support
(defun rpm-spec-mode-imenu-setup ()
  "An all-in-one setup function to add `imenu' support to `rpm-spec-mode'."
  (setq imenu-create-index-function
        #'rpm-spec-mode-imenu-create-index-function))

(defun rpm-spec-mode-imenu-create-index-function ()
  "Creating a buffer index for `rpm-spec-mode'.
The function should take no arguments, and return an index alist for the
current buffer.  It is called within `save-excursion', so where it
leaves point makes no difference."
  (goto-char (point-min))
  (let (rpm-imenu-index
        (sub-package-name-regexp "[[:space:]]+-n[[:space:]]+\\([-_[:alnum:]]+\\)")
        section
        pos-marker
        subpkg-name
        submenu
        new-index)
    (while (re-search-forward rpm-section-regexp nil t)
      (setq pos-marker (point-marker))
      (setq section (match-string-no-properties 1))
      ;; try to extract sub package name
      (if (re-search-forward sub-package-name-regexp
                             (line-end-position) t)
          (setq subpkg-name (match-string-no-properties 1))
        (setq subpkg-name "__default"))
      ;; create/add the matched item to the index list
      (setq new-index (cons subpkg-name pos-marker))
      (if (setq submenu (assoc section rpm-imenu-index))
          (setf (cdr submenu)
                (cons new-index (cdr submenu)))
        (push (list section new-index) rpm-imenu-index)))
    rpm-imenu-index))

;;------------------------------------------------------------
(add-hook 'rpm-spec-mode-new-file-hook 'rpm-spec-initialize)

;;;###autoload
(define-derived-mode rpm-spec-mode shell-script-mode "RPM"
  "Major mode for editing RPM spec files.
This is much like C mode except for the syntax of comments.  It uses
the same keymap as C mode and has the same variables for customizing
indentation.  It has its own abbrev table and its own syntax table.

Turning on RPM spec mode calls the value of the variable `rpm-spec-mode-hook'
with no args, if that value is non-nil."
  (rpm-update-mode-name)

  (if (and (= (buffer-size) 0) rpm-spec-initialize-sections)
      (run-hooks 'rpm-spec-mode-new-file-hook))

  (if (not (executable-find "rpmbuild"))
      (progn
	(setq rpm-spec-build-command "rpm")
	(setq rpm-spec-nobuild-option "--test")))
  
  (setq-local paragraph-start (concat "$\\|" page-delimiter))
  (setq-local paragraph-separate paragraph-start)
  (setq-local paragraph-ignore-fill-prefix t)
;  (setq-local indent-line-function 'c-indent-line)
  (setq-local require-final-newline t)
  (setq-local comment-start "# ")
  (setq-local comment-end "")
  (setq-local comment-column 32)
  (setq-local comment-start-skip "#+ *")
;  (setq-local comment-indent-function 'c-comment-indent)
  (setq-local comment-region-function #'rpm-spec-mode-comment-region)
  (setq-local uncomment-region-function #'rpm-spec-mode-uncomment-region)
  ;;Initialize font lock for GNU emacs.
  (make-local-variable 'font-lock-defaults)
  (font-lock-add-keywords nil rpm-spec-font-lock-keywords)
  ;; shell-script-mode would try to detect the shell type to accommodate
  ;; to the target shell. The shell type should always be RPM in this
  ;; instance
  ;; FIXME: set `sh-ancestors' list based on '%_buildshell'.
  ;; call a custom version of `sh--guess-shell' which compares against
  ;; the macro.
  (sh-set-shell "rpm" nil nil)
  (rpm-spec-mode-imenu-setup))

(defun rpm-command-filter (process string)
  "Filter to PROCESS normal output.  Add STRING as starting boundary."
  (with-current-buffer (process-buffer process)
    (save-excursion
      (goto-char (process-mark process))
      (insert-before-markers string)
      (set-marker (process-mark process) (point)))))

;;------------------------------------------------------------

(defvar rpm-change-log-uses-utc nil
  "*If non-nil, \\[rpm-add-change-log-entry] will use Universal time (UTC).
If this is nil, it uses local time as returned by `current-time'.

This variable is global by default, but you can make it buffer-local.")

(defsubst rpm-change-log-date-string ()
  "Return the date string for today, inserted by \\[rpm-add-change-log-entry].
If `rpm-change-log-uses-utc' is nil, \"today\" means the local time zone."
  (format-time-string "%a %b %d %Y" nil rpm-change-log-uses-utc))

(defun rpm-goto-add-change-log-header ()
  "Find change log and add header (if needed) for today."
  (rpm-goto-section "changelog")
  (let* ((address (if (functionp rpm-spec-user-mail-address)
                      (funcall rpm-spec-user-mail-address)
					rpm-spec-user-mail-address))
         (fullname (if (functionp rpm-spec-user-full-name)
					   (funcall rpm-spec-user-full-name)
					 rpm-spec-user-full-name))
         (system-time-locale "C")
         (change-log-header (format "* %s %s  <%s> - %s"
                                    (rpm-change-log-date-string)
                                    fullname
                                    address
                                    (rpm-find-spec-version t))))
    (if (not (search-forward change-log-header nil t))
        (insert "\n" change-log-header "\n")
      (forward-line 2))))

(defun rpm-add-change-log-entry (&optional change-log-entry)
  "Find change log and add an entry for today.
CHANGE-LOG-ENTRY will be used if provided."
  (interactive "sChange log entry: ")
  (save-excursion
    (rpm-goto-add-change-log-header)
      (while (looking-at "^-")
             (forward-line))
      (insert "- " change-log-entry "\n")))

(defun rpm-goto-add-change-log-entry ()
  "Goto change log and add an header for today (if needed)."
  (interactive)
  (rpm-goto-add-change-log-header)
  (while (looking-at "^-")
         (forward-line))
  (insert "- \n")
  (end-of-line '0))

;;------------------------------------------------------------

(defun rpm-insert-f (&optional filetype filename)
  "Insert new \"%files\" entry.
If FILENAME is 1 or is not provided, it will be prompted for
using FILETYPE to prompt the user."
  (save-excursion
    (and (rpm-goto-section "files") (rpm-end-of-section))
    (if (or (eq filename 1) (not filename))
        (insert (read-file-name
                 (concat filetype "filename: ") "" "" nil) "\n")
      (insert filename "\n"))
    (forward-line -1)
    (if rpm-spec-add-attr
        (let ((rpm-default-mode rpm-default-umask))
          (insert "%attr(" rpm-default-mode ", " rpm-default-owner ", "
                  rpm-default-group ") ")))
    (insert filetype)))

(defun rpm-insert-file (filename)
  "Insert file FILENAME."
  (interactive "FFilename: ")
  (rpm-insert-f "" filename))

(defun rpm-insert-config (filename)
  "Insert config file FILENAME."
  (interactive "FFilename: ")
  (rpm-insert-f "%config " filename))

(defun rpm-insert-doc (filename)
  "Insert doc file FILENAME."
  (interactive "FFilename: ")
  (rpm-insert-f "%doc " filename))

(defun rpm-insert-ghost (filename)
  "Insert ghost file FILENAME."
  (interactive "FFilename: ")
  (rpm-insert-f "%ghost " filename))

(defun rpm-insert-dir (dirname)
  "Insert directory DIRNAME."
  (interactive "GDirectory: ")
  (rpm-insert-f "%dir " dirname))

(defun rpm-insert-docdir (dirname)
  "Insert doc directory DIRNAME."
  (interactive "GDirectory: ")
  (rpm-insert-f "%docdir " dirname))

(defun rpm-completing-read (prompt collection &optional predicate
                                   require-match initial-input hist)
  "Take `rpm-spec-completion-ignore-case' into account call `completion-read'.
Forward all arguments i.e. PROMPT, COLLECTION, PREDICATE, REQUIRE-MATCH,
INITIAL-INPUT and HIST to `completing-read'."
  (let ((completion-ignore-case rpm-spec-completion-ignore-case))
    (completing-read prompt collection predicate
                     require-match initial-input hist)))

(defun rpm-insert (&optional what file-completion)
  "Insert given tag.  Use FILE-COMPLETION if argument is t.
WHAT is the tag used."
  (beginning-of-line)
  (if (not what)
      (setq what (rpm-completing-read "Tag: " rpm-tags-list)))
  (let (read-text insert-text)
    (if (string-match "^%" what)
        (setq read-text (format "Packagename for %s: " what)
              insert-text (concat what " "))
      (setq read-text (concat what ": ")
            insert-text (concat what ": ")))
    (cond
     ((string-equal what "Group")
      (call-interactively 'rpm-insert-group))
     ((string-equal what "Source")
      (rpm-insert-n "Source"))
     ((string-equal what "Patch")
      (rpm-insert-n "Patch"))
     (t
      (if file-completion
          (insert insert-text (read-file-name (concat read-text) "" "" nil) "\n")
        (insert insert-text (read-from-minibuffer (concat read-text)) "\n"))))))

(defun rpm--topdir ()
  "Try user environment for rpmbuild topdir or default to custom setting."
  (let ((rpm-envdir (or (getenv "RPM")
                         (getenv "rpm"))))
    (if (file-directory-p rpm-envdir)
        rpm-envdir
      rpm-build-topdir)))

(defun rpm-insert-n (what)
  "Insert given tag (WHAT) with possible number."
  (save-excursion
    (goto-char (point-max))
    (if (search-backward-regexp (concat "^" what "\\([0-9]*\\):") nil t)
        (let ((release (1+ (string-to-number (match-string 1)))))
          (forward-line 1)
          (let ((default-directory (expand-file-name "/SOURCES/" (rpm--topdir))))
            (insert what (int-to-string release) ": "
                    (read-file-name (concat what "file: ") "" "" nil) "\n")))
      (goto-char (point-min))
      (rpm-end-of-section)
      (insert what ": " (read-from-minibuffer (concat what "file: ")) "\n"))))

(defun rpm-change (&optional what)
  "Update given tag (WHAT)."
  (save-excursion
    (if (not what)
		;; interactive
        (setq what (rpm-completing-read "Tag: " rpm-tags-list)))
    (cond
     ((string-equal what "Group")
      (rpm-change-group))
     ((string-equal what "Source")
      (rpm-change-n "Source"))
     ((string-equal what "Patch")
      (rpm-change-n "Patch"))
     (t
      (goto-char (point-min))
      (if (search-forward-regexp (concat "^" what ":\\s-*\\(.*\\)$") nil t)
          (replace-match
           (concat what ": " (read-from-minibuffer
                              (format "New %s:"  what) (match-string 1))))
        (message "%s tag not found..." what))))))

(defun rpm-change-n (tag)
  "Change given tag TAG with possible number."
  (save-excursion
    (goto-char (point-min))
    (let ((number (read-from-minibuffer (concat tag " number: "))))
      (if (search-forward-regexp
           (concat "^" tag number ":\\s-*\\(.*\\)") nil t)
          (let ((default-directory (concat (rpm--topdir) "/SOURCES/")))
            (replace-match
             (concat tag number ": "
                     (read-file-name (format "New %s%i file: " tag number)
                                     "" "" nil (match-string 1)))))
        (message "%s number \"%s\" not found..." tag number)))))

(defun rpm-insert-group (group)
  "Insert GROUP tag."
  (interactive (list (rpm-completing-read "Group: " rpm-group-tags-list)))
  (beginning-of-line)
  (insert "Group: " group "\n"))

(defun rpm-change-group ()
  "Update Group tag."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (if (search-forward-regexp "^Group: \\(.*\\)$" nil t)
        (replace-match
         (concat "Group: "
                 (insert (rpm-completing-read "Group: " rpm-group-tags-list
                                              nil nil (match-string 1)))))
      (message "Group tag not found..."))))

(defun rpm-insert-tag (tag)
  "Insert or change a TAG.
With a prefix argument, change an existing tag."
  (interactive (list (completing-read "Tag: " rpm-tags-list)))
  (if current-prefix-arg
      (rpm-change tag)
    (rpm-insert tag)))

(defun rpm-change-tag (tag)
  "Change an existing tag."
  (interactive (list (completing-read "Tag: " rpm-tags-list)))
  (rpm-change tag))

(defun rpm-insert-packager ()
  "Insert Packager tag."
  (interactive)
  (beginning-of-line)
  (insert (format "Packager: %s <%s>\n"
                  (if (functionp rpm-spec-user-full-name)
					  (funcall rpm-spec-user-full-name)
					rpm-spec-user-full-name)
                  (if (functionp rpm-spec-user-mail-address)
                      (funcall rpm-spec-user-mail-address)
					rpm-spec-user-mail-address))))

(defun rpm-change-packager ()
  "Update Packager tag."
  (interactive)
  (rpm-change "Packager"))

;;------------------------------------------------------------

(defun rpm-current-section nil
  "Get the current section."
  (interactive)
  (save-excursion
    (rpm-forward-section)
    (rpm-backward-section)
    (if (bobp) "preamble"
      (buffer-substring (match-beginning 1) (match-end 1)))))

(defun rpm-backward-section nil
  "Move backward to the beginning of the previous section.
Go to beginning of previous section."
  (interactive)
  (or (re-search-backward rpm-section-regexp nil t)
      (goto-char (point-min))))

(defun rpm-beginning-of-section nil
  "Move backward to the beginning of the current section.
Go to beginning of current section."
  (interactive)
  (or (and (looking-at rpm-section-regexp) (point))
      (re-search-backward rpm-section-regexp nil t)
      (goto-char (point-min))))

(defun rpm-forward-section nil
  "Move forward to the beginning of the next section."
  (interactive)
  (forward-char)
  (if (re-search-forward rpm-section-regexp nil t)
      (progn (forward-line 0) (point))
    (goto-char (point-max))))

(defun rpm-end-of-section nil
  "Move forward to the end of this section."
  (interactive)
  (forward-char)
  (if (re-search-forward rpm-section-regexp nil t)
      (forward-line -1)
    (goto-char (point-max)))
;;  (while (or (looking-at paragraph-separate) (looking-at "^\\s-*#"))
  (while (looking-at "^\\s-*\\($\\|#\\)")
    (forward-line -1))
  (forward-line 1)
  (point))

(defun rpm-goto-section (section)
  "Move point to the beginning of the specified SECTION.
leave point at previous location."
  (interactive (list (rpm-completing-read "Section: " rpm-sections)))
  (push-mark)
  (goto-char (point-min))
  (or
   (equal section "preamble")
   (re-search-forward (concat "^%" section "\\b") nil t)
   (let ((s (cdr rpm-sections)))
     (while (not (equal section (car s)))
       (re-search-forward (concat "^%" (car s) "\\b") nil t)
       (setq s (cdr s)))
     (if (re-search-forward rpm-section-regexp nil t)
         (forward-line -1) (goto-char (point-max)))
     (insert "\n%" section "\n"))))

(defun rpm-mouse-goto-section (&optional section)
  "Go to SECTION."
  (interactive
   (x-popup-menu
    nil
    (list "sections"
          (cons "Sections" (mapcar (lambda (e) (list e e)) rpm-sections))
          (cons "Scripts" (mapcar (lambda (e) (list e e)) rpm-scripts))
          )))
  ;; If user doesn't pick a section, exit quietly.
  (and section
       (if (member section rpm-sections)
           (rpm-goto-section section)
         (goto-char (point-min))
         (or (re-search-forward (concat "^%" section "\\b") nil t)
             (and (re-search-forward "^%files\\b" nil t) (forward-line -1))
             (goto-char (point-max))))))

(defun rpm-insert-true-prefix ()
  "Insert %{prefix}."
  (interactive)
  (insert "%{prefix}"))

;;------------------------------------------------------------

(defun rpm-build (buildoptions)
  "Build this RPM package with BUILDOPTIONS."
  (if (and (buffer-modified-p)
           (y-or-n-p (format "Buffer %s modified, save it? " (buffer-name))))
      (save-buffer))
  (let ((rpm-buffer-name
         (format "* %s %s %s*"
                 rpm-spec-build-command
                 buildoptions
                 (file-name-nondirectory buffer-file-name))))
    (rpm-process-check rpm-buffer-name)
    (if (get-buffer rpm-buffer-name)
        (kill-buffer rpm-buffer-name))
    (create-file-buffer rpm-buffer-name)
    (display-buffer rpm-buffer-name))
  (setq buildoptions (list buildoptions buffer-file-name))
  (if (or rpm-spec-short-circuit rpm-spec-nobuild)
      (setq rpm-no-gpg t))
  (if rpm-spec-rmsource
      (setq buildoptions (cons "--rmsource" buildoptions)))
  (if rpm-spec-clean
      (setq buildoptions (cons "--clean" buildoptions)))
  (if rpm-spec-short-circuit
      (setq buildoptions (cons "--short-circuit" buildoptions)))
  (if (and (not (equal rpm-spec-timecheck "0"))
           (not (equal rpm-spec-timecheck "")))
      (setq buildoptions (cons "--timecheck" (cons rpm-spec-timecheck
                                                   buildoptions))))
  (if (not (equal rpm-spec-buildroot ""))
      (setq buildoptions (cons "--buildroot" (cons rpm-spec-buildroot
                                                   buildoptions))))
  (if (not (equal rpm-spec-target ""))
      (setq buildoptions (cons "--target" (cons rpm-spec-target
                                                buildoptions))))
  (if rpm-spec-nobuild
      (setq buildoptions (cons rpm-spec-nobuild-option buildoptions)))
  (if rpm-spec-quiet
      (setq buildoptions (cons "--quiet" buildoptions)))
  (if rpm-spec-nodeps
      (setq buildoptions (cons "--nodeps" buildoptions)))
  (if (and rpm-spec-sign-gpg (not rpm-no-gpg))
      (setq buildoptions (cons "--sign" buildoptions)))

  (if rpm-spec-auto-topdir
      (if (string-match ".*/SPECS/$" default-directory)
	  (let ((topdir (expand-file-name default-directory)))
	    (setq buildoptions
		  (cons
		   (concat "--define \"_topdir "
			   (replace-regexp-in-string "/SPECS/$" "" topdir)
			   "\"")
		   buildoptions)))))

  (compilation-start (mapconcat #'identity (cons rpm-spec-build-command buildoptions) " ") 'rpmbuild-mode)

  (if (and rpm-spec-sign-gpg (not rpm-no-gpg))
      (let ((build-proc (get-buffer-process
			 (get-buffer
			  (compilation-buffer-name "rpmbuild" nil nil))))
	    (rpm-passwd-cache (read-passwd "GPG passphrase: ")))
	(process-send-string build-proc (concat rpm-passwd-cache "\n")))))

(defun rpm-build-prepare ()
  "Run a `rpmbuild -bp'."
  (interactive)
  (if rpm-spec-short-circuit
      (message "Cannot run `%s -bp' with --short-circuit"
	       rpm-spec-build-command)
    (setq rpm-no-gpg t)
    (rpm-build "-bp")))

(defun rpm-list-check ()
  "Run a `rpmbuild -bl'."
  (interactive)
  (if rpm-spec-short-circuit
      (message "Cannot run `%s -bl' with --short-circuit"
	       rpm-spec-build-command)
    (setq rpm-no-gpg t)
    (rpm-build "-bl")))

(defun rpm-build-compile ()
  "Run a `rpmbuild -bc'."
  (interactive)
  (setq rpm-no-gpg t)
  (rpm-build "-bc"))

(defun rpm-build-install ()
  "Run a `rpmbuild -bi'."
  (interactive)
  (setq rpm-no-gpg t)
  (rpm-build "-bi"))

(defun rpm-build-binary ()
  "Run a `rpmbuild -bb'."
  (interactive)
  (if rpm-spec-short-circuit
      (message "Cannot run `%s -bb' with --short-circuit"
	       rpm-spec-build-command)
    (setq rpm-no-gpg nil)
    (rpm-build "-bb")))

(defun rpm-build-source ()
  "Run a `rpmbuild -bs'."
  (interactive)
  (if rpm-spec-short-circuit
      (message "Cannot run `%s -bs' with --short-circuit"
	       rpm-spec-build-command)
    (setq rpm-no-gpg nil)
    (rpm-build "-bs")))

(defun rpm-build-all ()
  "Run a `rpmbuild -ba'."
  (interactive)
  (if rpm-spec-short-circuit
      (message "Cannot run `%s -ba' with --short-circuit"
	       rpm-spec-build-command)
    (setq rpm-no-gpg nil)
    (rpm-build "-ba")))

(defun rpm-process-check (buffer)
  "Check if BUFFER has a running process.
If so, give the user the choice of aborting the process or the current
command."
  (let ((process (get-buffer-process (get-buffer buffer))))
    (if (and process (eq (process-status process) 'run))
        (if (yes-or-no-p (format "Process `%s' running.  Kill it?"
                                 (process-name process)))
            (delete-process process)
          (error "Cannot run two simultaneous processes")))))

;;------------------------------------------------------------

(defun rpm-toggle-short-circuit ()
  "Toggle `rpm-spec-short-circuit'."
  (interactive)
  (setq rpm-spec-short-circuit (not rpm-spec-short-circuit))
  (rpm-update-mode-name)
  (message (format "Turned `--short-circuit' %s."
                   (if rpm-spec-short-circuit "on" "off"))))

(defun rpm-toggle-rmsource ()
  "Toggle `rpm-spec-rmsource'."
  (interactive)
  (setq rpm-spec-rmsource (not rpm-spec-rmsource))
  (rpm-update-mode-name)
  (message (format "Turned `--rmsource' %s."
                   (if rpm-spec-rmsource "on" "off"))))

(defun rpm-toggle-clean ()
  "Toggle `rpm-spec-clean'."
  (interactive)
  (setq rpm-spec-clean (not rpm-spec-clean))
  (rpm-update-mode-name)
  (message (format "Turned `--clean' %s."
                   (if rpm-spec-clean "on" "off"))))

(defun rpm-toggle-nobuild ()
  "Toggle `rpm-spec-nobuild'."
  (interactive)
  (setq rpm-spec-nobuild (not rpm-spec-nobuild))
  (rpm-update-mode-name)
  (message (format "Turned `%s' %s."
                   rpm-spec-nobuild-option
                   (if rpm-spec-nobuild "on" "off"))))

(defun rpm-toggle-quiet ()
  "Toggle `rpm-spec-quiet'."
  (interactive)
  (setq rpm-spec-quiet (not rpm-spec-quiet))
  (rpm-update-mode-name)
  (message (format "Turned `--quiet' %s."
                   (if rpm-spec-quiet "on" "off"))))

(defun rpm-toggle-sign-gpg ()
  "Toggle `rpm-spec-sign-gpg'."
  (interactive)
  (setq rpm-spec-sign-gpg (not rpm-spec-sign-gpg))
  (rpm-update-mode-name)
  (message (format "Turned `--sign' %s."
                   (if rpm-spec-sign-gpg "on" "off"))))

(defun rpm-toggle-add-attr ()
  "Toggle `rpm-spec-add-attr'."
  (interactive)
  (setq rpm-spec-add-attr (not rpm-spec-add-attr))
  (rpm-update-mode-name)
  (message (format "Default add \"attr\" entry turned %s."
                   (if rpm-spec-add-attr "on" "off"))))

(defun rpm-toggle-nodeps ()
  "Toggle `rpm-spec-nodeps'."
  (interactive)
  (setq rpm-spec-nodeps (not rpm-spec-nodeps))
  (rpm-update-mode-name)
  (message (format "Turned `--nodeps' %s."
                   (if rpm-spec-nodeps "on" "off"))))

(defun rpm-update-mode-name ()
  "Update `mode-name' according to values set."
  (setq mode-name "RPM-SPEC")
  (let ((modes (concat (if rpm-spec-add-attr      "A")
                       (if rpm-spec-clean         "C")
                       (if rpm-spec-nodeps        "D")
                       (if rpm-spec-sign-gpg      "G")
                       (if rpm-spec-nobuild       "N")
                       (if rpm-spec-rmsource      "R")
                       (if rpm-spec-short-circuit "S")
                       (if rpm-spec-quiet         "Q")
                       )))
    (if (not (equal modes ""))
        (setq mode-name (concat mode-name ":" modes)))))

;;------------------------------------------------------------

(defun rpm-change-timecheck-option ()
  "Change the value for timecheck."
  (interactive)
  (setq rpm-spec-timecheck
        (read-from-minibuffer "New timecheck: " rpm-spec-timecheck)))

(defun rpm-change-buildroot-option ()
  "Change the value for buildroot."
  (interactive)
  (setq rpm-spec-buildroot
        (read-from-minibuffer "New buildroot: " rpm-spec-buildroot)))

(defun rpm-change-target-option ()
  "Change the value for target."
  (interactive)
  (setq rpm-spec-target
        (read-from-minibuffer "New target: " rpm-spec-target)))

(defun rpm-files-umask ()
  "Change the default umask for files."
  (interactive)
  (setq rpm-default-umask
        (read-from-minibuffer "Default file umask: " rpm-default-umask)))

(defun rpm-files-owner ()
  "Change the default owner for files."
  (interactive)
  (setq rpm-default-owner
        (read-from-minibuffer "Default file owner: " rpm-default-owner)))

(defun rpm-files-group ()
  "Change the source directory."
  (interactive)
  (setq rpm-default-group
        (read-from-minibuffer "Default file group: " rpm-default-group)))

(defun rpm-increase-release-tag (&optional arg)
  "Increase the release tag by ARG or 1 if ARG is nil."
  (interactive "p")
  (let ((arg (or arg 1)))
  (save-excursion
    (goto-char (point-min))
    (if (search-forward-regexp
         ;; Try to find the last digit-only group of a dot-separated release string
         (concat "^\\(Release[ \t]*:[ \t]*\\)"
                 "\\(.*[ \t\\.}]\\)\\([0-9]+\\)\\([ \t\\.%].*\\|$\\)") nil t)
        (let ((release (+ arg (string-to-number (match-string 3)))))
          (setq release
                (concat (match-string 2) (int-to-string release) (match-string 4)))
          (replace-match (concat (match-string 1) release))
          (message "Release tag changed to %s." release))
      (if (search-forward-regexp "^Release[ \t]*:[ \t]*%{?\\([^}]*\\)}?$" nil t)
          (rpm-increase-release-with-macros)
        (message "No Release tag to increase found..."))))))

;;------------------------------------------------------------

(defun rpm-spec-field-value (field max)
  "Get the value of FIELD, searching up to buffer position MAX.
See `search-forward-regexp'."
  (save-excursion
    (ignore-errors
      (let ((str
             (progn
               (goto-char (point-min))
               (search-forward-regexp
                (concat "^" field ":[ \t]*\\(.*?\\)[ \t]*$") max)
               (match-string 1))))
        ;; Try to expand macros
        (if (string-match "\\(%{?\\(\\?\\)?\\)\\([a-zA-Z0-9_]*\\)\\(}?\\)" str)
            (let ((start-string (substring str 0 (match-beginning 1)))
                  (end-string (substring str (match-end 4))))
              (if (progn
                    (goto-char (point-min))
                    (search-forward-regexp
                     (concat "%\\(define\\|global\\)[ \t]+"
                             (match-string 3 str)
                             "[ \t]+\\(.*\\)") nil t))
                  ;; Got it - replace.
                  (concat start-string (match-string 2) end-string)
                (if (match-string 2 str)
                    ;; Conditionally evaluated macro - remove it.
                    (concat start-string end-string)
                  ;; Leave as is.
                  str)))
          str)))))

(defun rpm-find-spec-version (&optional with-epoch)
  "Get the version string.
If WITH-EPOCH is non-nil, the string contains the Epoch/Serial value,
if one is present in the file."
  (save-excursion
    (goto-char (point-min))
    (let* ((max (search-forward-regexp rpm-section-regexp))
           (version (rpm-spec-field-value "Version" max))
           (release (rpm-spec-field-value "Release" max))
           (epoch   (rpm-spec-field-value "Epoch"   max)) )
      (when (and version (< 0 (length version)))
        (unless epoch (setq epoch (rpm-spec-field-value "Serial" max)))
        (concat (and with-epoch epoch (concat epoch ":"))
                version
                (and release (concat "-" release)))))))

(defun rpm-increase-release-with-macros (&optional increment)
  "Increase release in spec.
Either by INCREMENT or 1 if not given."
  (let ((increment (or increment 1)))
  (save-excursion
    (let ((str
           (progn
             (goto-char (point-min))
             (search-forward-regexp "^Release[ \t]*:[ \t]*\\(.+\\).*$" nil)
             (match-string 1))))
      (let ((inrel
             (if (string-match "%{?\\([^}]*\\)}?$" str)
                 (progn
                   (goto-char (point-min))
                   (let ((macros (substring str (match-beginning 1)
                                            (match-end 1))))
                     (search-forward-regexp
                      (concat "%define[ \t]+" macros
                              "[ \t]+\\(\\([0-9]\\|\\.\\)+\\)\\(.*\\)"))
                     (concat macros " " (int-to-string (+ increment (string-to-number
                                                            (match-string 1))))
                             (match-string 3))))
               str)))
        (let ((dinrel inrel))
          (replace-match (concat "%define " dinrel))
          (message "Release tag changed to %s." dinrel)))))))

;;------------------------------------------------------------

(defun rpm-spec-initialize ()
  "Create a default spec file if one does not exist or is empty."
  (let (file name version (release rpm-spec-default-release))
    (setq file (if (buffer-file-name)
                   (file-name-nondirectory (buffer-file-name))
                 (buffer-name)))
    (cond
     ((eq (string-match "\\(.*\\)-\\([^-]*\\)-\\([^-]*\\).spec" file) 0)
      (setq name (match-string 1 file))
      (setq version (match-string 2 file))
      (setq release (match-string 3 file)))
     ((eq (string-match "\\(.*\\)-\\([^-]*\\).spec" file) 0)
      (setq name (match-string 1 file))
      (setq version (match-string 2 file)))
     ((eq (string-match "\\(.*\\).spec" file) 0)
      (setq name (match-string 1 file))))

    (if rpm-spec-indent-heading-values
	(insert
	 "Summary:        "
	 "\nName:           " (or name "")
	 "\nVersion:        " (or version "")
	 "\nRelease:        " (or release "")
	 (if rpm-spec-default-epoch
	     (concat "\nEpoch:          "
		     (int-to-string rpm-spec-default-epoch))
	   "")
	 "\nLicense:        "
	 "\nGroup:          "
	 "\nURL:            "
	 "\nSource0:        %{name}-%{version}.tar.gz"
	 "\nBuildRoot:      " rpm-spec-default-buildroot)
      (insert
       "Summary: "
       "\nName: " (or name "")
       "\nVersion: " (or version "")
       "\nRelease: " (or release "")
       (if rpm-spec-default-epoch
	   (concat "\nEpoch: " (int-to-string rpm-spec-default-epoch))
	 "")
       "\nLicense: "
       "\nGroup: "
       "\nURL: "
       "\nSource0: %{name}-%{version}.tar.gz"
       "\nBuildRoot: " rpm-spec-default-buildroot))

    (insert
     "\n\n%description\n"
     "\n%prep"
     "\n%setup -q"
     "\n\n%build\n"
     (or rpm-spec-default-build-section "")
     "\n%install\n"
     (or rpm-spec-default-install-section "")
     "\n%clean\n"
     (or rpm-spec-default-clean-section "")
     "\n\n%files"
     "\n%defattr(-,root,root,-)"
     "\n%doc\n"
     "\n\n%changelog\n")

    (end-of-line 1)
    (rpm-add-change-log-entry "Initial build.")))

;;------------------------------------------------------------

(defun rpm-about-rpm-spec-mode ()
  "About `rpm-spec-mode'."
  (interactive)
  (let* ((file (or (macroexp-file-name) buffer-file-name))
         (package-version (lm-version file))
         (package-maintainer (car (lm-maintainers file))))
  (message
   (format "rpm-spec-mode version %s by %s <%s>"
           package-version
           (car package-maintainer)
           (cdr package-maintainer)))))

;;;###autoload(add-to-list 'auto-mode-alist '("\\.spec\\(\\.in\\)?$" . rpm-spec-mode))

(provide 'rpm-spec-mode)
;;;###autoload
(define-compilation-mode rpmbuild-mode "RPM build"
  (setq-local compilation-disable-input t))

;;; rpm-spec-mode.el ends here
