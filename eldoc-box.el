;;; eldoc-box.el --- Display documentation in childframe      -*- lexical-binding: t; -*-

;; Copyright (C) 2017-2018 Sebastien Chapuis, 2018 Yuan Fu

;; Version: 1.4

;; Author: Sebastien Chapuis <sebastien@chapu.is>
;; Maintainer: Yuan Fu <casouri@gmail.com>
;; URL: https://github.com/casouri/eldoc-box
;; Package-Requires: ((emacs "26.1"))

;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; This file is NOT part of GNU Emacs

;;; Commentary:
;;
;;  Made a lot of change to use it for ElDoc

;;; Code:
;;

(require 'cl-lib)

;;;; Userland
;;;;; Variable
(defgroup eldoc-box nil
  "Display Eldoc docs in a pretty child frame."
  :prefix "eldoc-box-"
  :group 'eldoc)

(defface eldoc-box-border '((((background dark)) . (:background "white"))
                            (((background light)) . (:background "black")))
  "The border color used in childframe.")

(defface eldoc-box-body '((t . (:background nil)))
  "Body face used in eglot doc childframe. Only :background is used.")

(defvar eldoc-box-only-multi-line nil
  "If non-nil, only use childframe when there are more than one line.")

(defvar eldoc-box-frame-parameters
  '(
    ;; (left . -1)
    (no-accept-focus . t)
    (no-focus-on-map . t)
    (min-width  . 0)
    ;; (width  . 0)
    (min-height  . 0)
    ;; (height  . 0)
    (internal-border-width . 1)
    (vertical-scroll-bars . nil)
    (horizontal-scroll-bars . nil)
    (right-fringe . 0)
    (menu-bar-lines . 0)
    (tool-bar-lines . 0)
    (line-spacing . 0)
    (unsplittable . t)
    (undecorated . t)
    ;; (top . -1)
    (visibility . nil)
    (mouse-wheel-frame . nil)
    (no-other-frame . t)
    (cursor-type . nil)
    (inhibit-double-buffering . t)
    (drag-internal-border . t)
    (no-special-glyphs . t)
    (desktop-dont-save . t))
  "Frame parameters used to create the frame.")

(defvar eldoc-box-max-pixel-width 800
  "Maximum width of doc childframw in pixel.
Consider your machine's screen's resolution when setting this variable.")

(defvar eldoc-box-max-pixel-height 700
  "Maximum height of doc childframw in pixel.
Consider your machine's screen's resolution when setting this variable.")

;;;;; Function
(defvar eldoc-box--frame nil ;; A backstage variable
  "The frame to display doc.")

(defun eldoc-box-quit-frame ()
  "Hide childframe used by eglot doc."
  (interactive)
  (when eldoc-box--frame
    (make-frame-invisible eldoc-box--frame t)))

;;;###autoload
(define-minor-mode eldoc-box-hover-mode
  "Displays hover documentations in a childframe. This mode is buffer local."
  :lighter " ELDOC-BOX"
  (if eldoc-box-hover-mode
      (add-function :before-until (local 'eldoc-message-function)
                    #'eldoc-box--eldoc-message-function)
    (remove-function (local 'eldoc-message-function) #'eldoc-box--eldoc-message-function)
    ;; if minor mode is turned off when childframe is visible
    ;; hide it
    (when eldoc-box--frame
      (delete-frame eldoc-box--frame)
      (setq eldoc-box--frame nil))))

;;;; Backstage
;;;;; Variable
(defvar eldoc-box--buffer " *eldoc-box*"
  "The buffer used to display eglot doc.")

;;;;; Function

(defvar eldoc-box--display-frame-timer nil)

(defun eldoc-box--display (str)
  "Display STR in childframe."
  (let ((doc-buffer (get-buffer-create eldoc-box--buffer)))
    (with-current-buffer doc-buffer
      (setq mode-line-format nil)
      ;; without this, clicking childframe will make doc buffer the current buffer
      ;; and `eldoc-box--maybe-cleanup' in `eldoc-box--cleanup-timer' will clear the childframe
      (setq eldoc-box-hover-mode t)
      (erase-buffer)
      (insert str)
      ;; Instead of showing the frame immediately, which is slow, wait
      ;; a little bit to see if any more requests come in, and cancel
      ;; any obsolete requests. If the user is moving rapidly, this
      ;; helps.
      (when (timerp eldoc-box--display-frame-timer)
        (cancel-timer eldoc-box--display-frame-timer))
      (setq eldoc-box--display-frame-timer
            (run-with-idle-timer 1 nil
                                 (lambda ()
                                   (eldoc-box--get-frame doc-buffer)
                                   (setq eldoc-box--display-frame-timer nil)))))))

(defun eldoc-box--window-side ()
  "Return 'left if the selected window is on the left,
'right if on the right. Return 'left if there is only one window."
  (let ((left-window(window-at 0 0)))
    (if (eq left-window (selected-window))
        'left
      'right)))

(defun eldoc-box--get-frame (buffer)
  "Return a childframe displaying BUFFER.
Checkout `lsp-ui-doc--make-frame', `lsp-ui-doc--move-frame'."
  (let* ((after-make-frame-functions nil)
         (before-make-frame-hook nil)
         (parameter (append eldoc-box-frame-parameters
                            `((default-minibuffer-frame . ,(selected-frame))
                              (minibuffer . ,(minibuffer-window))
                              (left-fringe . ,(frame-char-width)))))
         (window (or (and eldoc-box--frame (frame-selected-window eldoc-box--frame))
                     (display-buffer-in-child-frame
                      buffer
                      `((child-frame-parameters . ,parameter)))))
         (frame (window-frame window))
         (main-frame (selected-frame)))
    (make-frame-visible frame)
    (set-window-dedicated-p window t)
    (redirect-frame-focus frame (frame-parent frame))
    (set-face-attribute 'internal-border frame :inherit 'eldoc-box-border)
    (set-face-attribute 'default frame :background (face-attribute 'eldoc-box-body :background main-frame))
    ;; set size
    (let* ((size
            (window-text-pixel-size
             window nil nil
             eldoc-box-max-pixel-width
             eldoc-box-max-pixel-height t))
           (width (car size))
           (height (cdr size))
           (width (+ width (frame-char-width frame))) ; add margin
           (frame-resize-pixelwise t))
      (set-frame-size frame width height t)
      ;; move position
      (set-frame-position frame (pcase (eldoc-box--window-side) ; x position + a little padding (16)
                                  ;; display doc on right
                                  ('left (- (frame-outer-width main-frame) width 16))
                                  ;; display doc on left
                                  ('right 16))
                          ;; y position + a little padding (16)
                          16))
    (setq eldoc-box--frame frame)))

;;;;; ElDoc

(defvar eldoc-box--cleanup-timer nil
  "The timer used to cleanup childframe after ElDoc.")

(defvar eldoc-box--last-point 0
  ;; used in `eldoc-box--maybe-cleanup'
  "Last point when eldoc-box showed childframe.")

(defun eldoc-box--maybe-cleanup ()
  "Clean up after ElDoc."
  ;; timer is global, so this function will be called outside
  ;; the buffer with `eldoc-box-hover-mode' enabled
  (if (and (frame-parameter eldoc-box--frame 'visibility)
           (or (and (not eldoc-last-message) ; 1
                    (not (eq (point) eldoc-box--last-point)) ; 2
                    (not (eq (current-buffer) (get-buffer eldoc-box--buffer)))) ; 3
               (not eldoc-box-hover-mode))) ; 4
      ;; 1. Obviously, last-message nil means we are not on a valid symbol anymore.
      ;; 2. Or are we? If you scroll the childframe with mouse wheel
      ;; `eldoc-pre-command-refresh-echo-area' will set `eldoc-last-message' to nil.
      ;; Without the point test, this function, called by `eldoc-box--cleanup-timer'
      ;; will clear the doc frame, not good
      ;; 3. If scrolling can't satisfy you and you clicked the childframe
      ;; both 1. and 2. are satisfied. 3. is the last hope to prevent this function
      ;; from clearing your precious childframe. There is another safety pin in
      ;; `eldoc-box--display' that works with 3.
      ;; 4. Sometimes you switched buffer when childframe is on.
      ;; it wouldn't go away unless you goes back and let eldoc shut it off.
      ;; So if we are not in `eldoc-box-hover-mode', clear childframe
      (eldoc-box-quit-frame)
    ;; so you didn't clear the doc frame this time, and the last timer has ran out
    ;; setup another one to make sure the doc frame is cleared
    ;; once the condition above it met
    (setq eldoc-box--cleanup-timer
          (run-with-timer 1 nil #'eldoc-box--maybe-cleanup))))

(defun eldoc-box--eldoc-message-function (str &rest args)
  "Front-end for eldoc. Display STR in childframe and ARGS works like `message'."
  (if (stringp str)
      (let ((doc (apply #'format str args)))
        (unless (and eldoc-box-only-multi-line (eq (cl-count ?\n doc) 0))
          (eldoc-box--display doc)
          (setq eldoc-box--last-point (point))
          ;; Why a timer? ElDoc is mainly used in minibuffer,
          ;; where the text is constantly being flushed by other commands
          ;; so ElDoc doesn't try very hard to cleanup
          (when eldoc-box--cleanup-timer (cancel-timer eldoc-box--cleanup-timer))
          ;; this function is also called by `eldoc-pre-command-refresh-echo-area'
          ;; in `pre-command-hook', which means the timer is reset before every
          ;; command if `eldoc-box-hover-mode' is on and `eldoc-last-message' is not nil.
          (setq eldoc-box--cleanup-timer
                (run-with-timer 1 nil #'eldoc-box--maybe-cleanup))))
    (eldoc-box-quit-frame)
    t))

(provide 'eldoc-box)

;;; eldoc-box.el ends here
