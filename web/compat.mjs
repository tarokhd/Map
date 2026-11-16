// Small standards-compatible shims for mobile WebViews that predate AbortSignal.any.
if (!AbortSignal.timeout) AbortSignal.timeout = milliseconds => {
  const controller = new AbortController();
  setTimeout(() => controller.abort(new DOMException('Timed out', 'TimeoutError')), milliseconds);
  return controller.signal;
};
if (!AbortSignal.any) AbortSignal.any = signals => {
  const controller = new AbortController(), attached = [];
  const cleanup = () => attached.forEach(([signal, listener]) => signal.removeEventListener('abort', listener));
  for (const signal of signals) {
    if (signal.aborted) { controller.abort(signal.reason); break; }
    const listener = () => {controller.abort(signal.reason); cleanup();};
    signal.addEventListener('abort', listener, {once: true});
    attached.push([signal, listener]);
  }
  if (controller.signal.aborted) cleanup();
  return controller.signal;
};
