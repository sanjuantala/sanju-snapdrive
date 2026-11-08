'use strict';
// Blobs stay in the extension's local origin and survive worker suspension.
(function(root) {
  const MAX_BYTES = 40 * 1024 * 1024;
  const TOTAL_BYTES = 80 * 1024 * 1024;
  const TTL = 30 * 60 * 1000;
  const CAPACITY = 5;

  function expire(records, now) {
    let count = 0, bytes = 0;
    return [...records].sort((a,b) => b.created - a.created).filter(entry => {
      const size = entry.blob.size;
      if (now - entry.created >= TTL || size > MAX_BYTES || count >= CAPACITY || bytes + size > TOTAL_BYTES) return true;
      count++; bytes += size; return false;
    }).map(entry => entry.id);
  }

  async function database() {
    return new Promise((resolve,reject) => {
      const request = indexedDB.open('snapdrive-captures', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('captures', {keyPath:'id'});
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async function transact(entry, id) {
    const db = await database();
    try {
      return await new Promise((resolve,reject) => {
        const tx = db.transaction('captures', 'readwrite');
        const store = tx.objectStore('captures');
        let selected = null;
        if (entry) store.put(entry);
        const request = store.getAll();
        request.onsuccess = () => {
          const records = request.result;
          const removed = new Set(expire(records, Date.now()));
          removed.forEach(key => store.delete(key));
          const valid = records.filter(record => !removed.has(record.id));
          selected = id ? valid.find(record => record.id === id) : valid.sort((a,b) => b.created - a.created)[0];
        };
        tx.oncomplete = () => resolve(selected ?? null);
        tx.onabort = tx.onerror = () => reject(tx.error ?? new Error('Chrome could not save the capture locally.'));
      });
    } finally { db.close(); }
  }

  async function put(blob, mode) {
    if (!(blob instanceof Blob) || blob.type !== 'image/png' || !blob.size || blob.size > MAX_BYTES) throw new Error('Capture is not a PNG under 40 MB.');
    const entry = {id:crypto.randomUUID(), blob, mode, created:Date.now()};
    await transact(entry);
    return entry.id;
  }

  root.SnapCaptureStore = {put, get:id => transact(null, id), latest:() => transact(), expire, MAX_BYTES};
})(globalThis);
