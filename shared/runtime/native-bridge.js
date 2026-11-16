/* Native mobile GPS; only the bundled application can call either host. */
(() => {
  const native = window.AndroidWorld || (window.webkit?.messageHandlers?.world ? {
    requestLocation(id, once, timeout) { window.webkit.messageHandlers.world.postMessage({action: 'request', id, once, timeout}); },
    cancelLocation(id) { window.webkit.messageHandlers.world.postMessage({action: 'cancel', id}); }
  } : null);
  if (!native) return;
  window.NativeWorld = native;
  let sequence = 0;
  const listeners = new Map();
  function request(success, failure, options, once) {
    if (typeof success !== 'function') throw new TypeError('A position callback is required');
    const id = ++sequence;
    listeners.set(id, {success, failure, once});
    const timeout = Math.min(60000, Math.max(1000, Number(options?.timeout) || 15000));
    native.requestLocation(String(id), once, timeout);
    return id;
  }
  window.__nativeLocation = window.__androidLocation = (id, position, error) => {
    const listener = listeners.get(id);
    if (!listener) return;
    if (listener.once) listeners.delete(id);
    if (error) listener.failure?.(error);
    else listener.success(position);
  };
  const geolocation = {
    getCurrentPosition(success, failure, options) {request(success, failure, options, true);},
    watchPosition(success, failure, options) {return request(success, failure, options, false);},
    clearWatch(id) {listeners.delete(id); native.cancelLocation(String(id));}
  };
  Object.defineProperty(navigator, 'geolocation', {configurable: true, value: geolocation});
})();
