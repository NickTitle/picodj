(() => {
  const appShell = document.querySelector('#app-shell');
  const helpToggle = document.querySelector('#help-toggle');
  const helpDialog = document.querySelector('#help-dialog');
  if (!appShell || !helpToggle || !helpDialog) return;

  const focusSelector = 'button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';
  let returnFocus = null;
  let priorInert = false;
  let active = false;

  function focusableControls() {
    return Array.from(helpDialog.querySelectorAll(focusSelector));
  }

  function restoreBackground() {
    if (!active) return;
    active = false;
    appShell.inert = priorInert;
    helpToggle.setAttribute('aria-expanded', 'false');
    const target = returnFocus;
    returnFocus = null;
    const refocus = () => {
      const connectedTarget = target && target.isConnected !== false ? target : helpToggle;
      if (typeof connectedTarget.focus === 'function') connectedTarget.focus();
    };
    if (typeof requestAnimationFrame === 'function') requestAnimationFrame(refocus);
    else refocus();
  }

  function openHelp(opener = document.activeElement) {
    if (active) return;
    returnFocus = opener && opener.isConnected !== false ? opener : helpToggle;
    priorInert = Boolean(appShell.inert);
    appShell.inert = true;
    helpToggle.setAttribute('aria-expanded', 'true');
    active = true;
    try {
      if (typeof helpDialog.showModal === 'function') helpDialog.showModal();
      else helpDialog.setAttribute('open', '');
    } catch (error) {
      restoreBackground();
      throw error;
    }
    const target = helpDialog.querySelector('[autofocus]') || focusableControls()[0] || helpDialog;
    if (typeof target.focus === 'function') target.focus();
  }

  function closeHelp() {
    if (!active) return;
    if (typeof helpDialog.close === 'function') helpDialog.close();
    else {
      helpDialog.removeAttribute('open');
      restoreBackground();
    }
  }

  helpToggle.addEventListener('click', () => openHelp(helpToggle));
  helpDialog.addEventListener('click', (event) => {
    if (event.target.closest?.('[data-help-close]')) closeHelp();
  });
  helpDialog.addEventListener('cancel', (event) => {
    event.preventDefault();
    closeHelp();
  });
  helpDialog.addEventListener('close', restoreBackground);
  helpDialog.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      closeHelp();
      return;
    }
    if (event.key !== 'Tab') return;
    const controls = focusableControls();
    if (!controls.length) {
      event.preventDefault();
      helpDialog.focus();
      return;
    }
    const first = controls[0];
    const last = controls[controls.length - 1];
    if (event.shiftKey && (document.activeElement === first || !helpDialog.contains(document.activeElement))) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && (document.activeElement === last || !helpDialog.contains(document.activeElement))) {
      event.preventDefault();
      first.focus();
    }
  });

})();
