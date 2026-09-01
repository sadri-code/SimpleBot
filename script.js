// ==UserScript==
// @name         YouTube Nonstop
// @namespace    https://github.com/
// @version      2.4
// @description  Disables "Video paused. Continue watching?", idle detection, auto-pause, focus-based pausing
// @author       You
// @match        *://*.youtube.com/*
// @match        *://*.youtube-nocookie.com/*
// @match        *://music.youtube.com/*
// @grant        none
// @run-at       document-start
// ==/UserScript==

(function() {
    'use strict';

    // ---------- State ----------
    let userPaused = false;          // true only when user explicitly paused
    let userClickedPause = false;    // transient flag for click detection
    let userClickedPlay = false;     // transient flag for click detection

    // ---------- Direct click tracking on play/pause button ----------
    function handleButtonClick(e) {
        const target = e.target.closest('button');
        if (!target) return;

        const label = (target.getAttribute('aria-label') || '').toLowerCase();
        const isPlayButton = target.classList.contains('ytp-play-button');

        // YouTube Music: button might have different classes, but label works
        if (label.includes('pause') || (isPlayButton && !label.includes('play'))) {
            // Pause button clicked
            userPaused = true;
            userClickedPause = true;
            setTimeout(() => { userClickedPause = false; }, 1000);
        } else if (label.includes('play') || (isPlayButton && label.includes('play'))) {
            // Play button clicked
            userPaused = false;
            userClickedPlay = true;
            setTimeout(() => { userClickedPlay = false; }, 1000);
        }
    }

    document.addEventListener('click', handleButtonClick, { capture: true });

    // Also listen for keyboard shortcuts (space, k) – they work on the video or document
    document.addEventListener('keydown', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
        const key = e.key;
        if (key === ' ' || key === 'k' || key === 'K') {
            const video = document.querySelector('video.html5-main-video');
            if (!video) return;
            // Toggle pause state
            if (video.paused) {
                // User wants to play
                userPaused = false;
                userClickedPlay = true;
                setTimeout(() => { userClickedPlay = false; }, 1000);
                video.play().catch(() => {});
            } else {
                // User wants to pause
                userPaused = true;
                userClickedPause = true;
                setTimeout(() => { userClickedPause = false; }, 1000);
                video.pause();
            }
            e.preventDefault();
        }
    }, { capture: true });

    // ---------- Resume on tab/window focus (only if NOT manually paused) ----------
    function resumeIfNeeded() {
        const video = document.querySelector('video.html5-main-video');
        if (video && video.paused && !userPaused) {
            video.play().catch(() => {});
            const player = document.querySelector('#movie_player');
            if (player && player.playVideo) player.playVideo();
        }
    }

    document.addEventListener('visibilitychange', (e) => {
        if (document.visibilityState === 'visible') resumeIfNeeded();
        e.stopImmediatePropagation();
    }, true);

    window.addEventListener('focus', (e) => {
        resumeIfNeeded();
        e.stopImmediatePropagation();
    }, true);

    // ---------- 1. Block EXPERIMENT_FLAGS ----------
    const idleFlags = {
        'html5_idle_rate_limit_ms': -1,
        'html5_check_for_idle_network_interval_ms': -1,
        'html5_autonav_cap_idle_secs': 0,
        'enable_premium_voluntary_pause': false,
        'web_player_mouse_idle_wait_time_ms': 86400000,
        'web_player_touch_idle_wait_time_ms': 86400000,
    };

    function patchYtConfig() {
        if (window.ytcfg?.set) {
            const origSet = window.ytcfg.set;
            window.ytcfg.set = function(key, val) {
                if (key === 'EXPERIMENT_FLAGS' && val) Object.assign(val, idleFlags);
                return origSet.apply(this, arguments);
            };
        }
        if (window.ytcfg?.data_?.EXPERIMENT_FLAGS) {
            Object.assign(window.ytcfg.data_.EXPERIMENT_FLAGS, idleFlags);
        }
    }
    patchYtConfig();
    let retries = 0;
    const cfgInterval = setInterval(() => {
        if (window.ytcfg) { patchYtConfig(); clearInterval(cfgInterval); }
        if (++retries > 20) clearInterval(cfgInterval);
    }, 200);

    // ---------- 2. Block visibility API ----------
    try {
        Object.defineProperty(document, 'hidden', { get: () => false, configurable: true });
        Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
        Object.defineProperty(document, 'hasFocus', { value: () => true, configurable: true, writable: true });
    } catch (_) {}

    ['visibilitychange', 'webkitvisibilitychange', 'focus', 'blur', 'focusin', 'focusout'].forEach(evt =>
        document.addEventListener(evt, e => e.stopImmediatePropagation(), true)
    );
    window.addEventListener('blur', e => e.stopImmediatePropagation(), true);
    window.addEventListener('focus', e => e.stopImmediatePropagation(), true);

    // ---------- 3. Block requestIdleCallback ----------
    window.requestIdleCallback = function(fn) {
        fn({ didTimeout: false, timeRemaining: () => 50 });
        return 0;
    };

    // ---------- 4. Block postMessage idle signals ----------
    const origAddEventListener = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function(type, listener, options) {
        if (type === 'message' && typeof listener === 'function') {
            const wrapped = function(e) {
                if (e.data && typeof e.data === 'string' &&
                    (e.data.includes('idle') || e.data.includes('heartbeat'))) {
                    return;
                }
                return listener.call(this, e);
            };
            return origAddEventListener.call(this, type, wrapped, options);
        }
        return origAddEventListener.call(this, type, listener, options);
    };

    // ---------- 5. Override HTMLMediaElement play ----------
    // Block any play attempt if userPaused is true, UNLESS the user explicitly clicked play (userClickedPlay flag)
    const origPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function() {
        if (userPaused && !userClickedPlay) {
            // User paused manually – block all automatic play attempts
            return Promise.reject(new Error('Play blocked by Nonstop Playback (user paused)'));
        }
        // If user clicked play, allow and reset flags
        if (userClickedPlay) {
            userPaused = false;
            userClickedPlay = false;
        }
        return origPlay.call(this);
    };

    // ---------- 6. Video event listeners ----------
    function setupVideoListeners(video) {
        if (video._np) return;
        video._np = true;

        video.addEventListener('pause', (e) => {
            // If the user clicked pause, we already set userPaused=true; do nothing else.
            // If it's an automatic pause (e.g., from YouTube), we resume immediately.
            if (!userClickedPause && !userPaused) {
                // Automatic pause – resume
                video.play().catch(() => {});
                const player = document.querySelector('#movie_player');
                if (player && player.playVideo) player.playVideo();
            }
            // If user clicked pause, userPaused is already true, so we allow the pause.
        }, true);

        video.addEventListener('play', (e) => {
            // If video starts playing, it's not paused by user anymore (unless we block play)
            // But we only get here if play succeeded; if userPaused was true and no userClickedPlay, the play was blocked.
            // So we can assume userPaused is already false if we allowed play.
            // Just ensure it's false.
            if (!userPaused) {
                // It's playing normally.
            }
        }, true);
    }

    // ---------- 7. Patch YouTube player object ----------
    function patchPlayerObject() {
        const player = document.querySelector('#movie_player, #player');
        if (!player) return;

        if (player.pauseVideo && !player._patchedPause) {
            const orig = player.pauseVideo;
            player.pauseVideo = function() {
                // If user clicked pause, allow; otherwise block
                if (userClickedPause) {
                    userPaused = true;
                    return orig.call(this);
                }
                // else block auto-pause
            };
            player._patchedPause = true;
        }

        if (player.playVideo && !player._patchedPlay) {
            const orig = player.playVideo;
            player.playVideo = function() {
                if (userPaused && !userClickedPlay) {
                    return; // block forced play
                }
                if (userClickedPlay) {
                    userPaused = false;
                    userClickedPlay = false;
                }
                return orig.call(this);
            };
            player._patchedPlay = true;
        }
    }

    // ---------- 8. Periodic resume (every 3s, only if not manually paused) ----------
    function ensurePlaying() {
        const video = document.querySelector('video.html5-main-video');
        if (video && video.paused && !userPaused) {
            video.play().catch(() => {});
            const player = document.querySelector('#movie_player');
            if (player && player.playVideo) player.playVideo();
        }
    }
    setInterval(ensurePlaying, 3000);

    // ---------- 9. Auto‑click "Yes" dialogs & hide overlays ----------
    const dialogSelectors = [
        'ytmusic-you-there-renderer',
        'ytmusic-notification-action-renderer',
        'tp-yt-paper-dialog[prevent-autonav]',
        'yt-confirm-dialog-renderer',
        '[aria-label*="Continue watching" i]',
        '.ytmusic-popup-container tp-yt-paper-dialog'
    ];

    function handleDialogs() {
        dialogSelectors.forEach(sel =>
            document.querySelectorAll(sel).forEach(el => {
                const d = el.closest('tp-yt-paper-dialog') || el;
                if (d && (d.open || d.style.display !== 'none')) {
                    const yesBtn = d.querySelector('yt-button-renderer#action-button button, [aria-label="Yes" i], button[aria-label*="Yes" i]');
                    yesBtn?.click();
                    d.close?.();
                    d.remove?.();
                    d.style.display = 'none';
                }
            })
        );
    }

    const observer = new MutationObserver(() => {
        document.querySelectorAll('video.html5-main-video').forEach(setupVideoListeners);
        patchPlayerObject();
        handleDialogs();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });

    setInterval(handleDialogs, 2000);

    // ---------- 10. CSS hide all pause/idle overlays ----------
    const style = document.createElement('style');
    style.textContent = `
        ytmusic-you-there-renderer,
        ytmusic-notification-action-renderer,
        tp-yt-paper-dialog[prevent-autonav],
        .ytmusic-popup-container tp-yt-paper-dialog,
        yt-confirm-dialog-renderer,
        [aria-label*="Continue watching" i],
        .ytp-dim-overlay,
        .ytp-backdrop,
        tp-yt-iron-overlay-backdrop,
        .ytp-pause-overlay,
        .html5-pause-overlay,
        .ytp-autonav-countdown,
        .ytp-autonav-endcountdown,
        .ytp-autonav-mode-indicator,
        yt-notification-action-renderer {
            display: none !important;
        }
    `;
    (document.head || document.documentElement).appendChild(style);

    // ---------- 11. Block fetch/XHR to idle/heartbeat endpoints ----------
    const origFetch = window.fetch;
    window.fetch = function(url, options) {
        const u = url.toString();
        if (u.includes('/heartbeat') || u.includes('/idle') || u.includes('/get_midroll_info')) {
            return Promise.resolve(new Response('{}', { status: 200 }));
        }
        return origFetch.call(this, url, options);
    };

    const origXHROpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
        if (url.includes('/heartbeat') || url.includes('/idle')) {
            this._blocked = true;
        }
        return origXHROpen.apply(this, arguments);
    };
    const origXHRSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function() {
        if (this._blocked) {
            this.status = 200;
            this.readyState = 4;
            this.responseText = '{}';
            setTimeout(() => this.onload?.({}), 0);
            return;
        }
        return origXHRSend.apply(this, arguments);
    };

    // ---------- 12. Initial setup ----------
    document.querySelectorAll('video.html5-main-video').forEach(setupVideoListeners);
    patchPlayerObject();

})();
